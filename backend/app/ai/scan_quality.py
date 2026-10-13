"""Scan mesh quality validation + 3D preview sampling (PLY / STL / OBJ).

Heuristics calibrated against synthetic Medit-like PLY fixtures in
references/scans/. STL/OBJ use the same vertex-based checks after parsing.
"""

from __future__ import annotations

import math
import struct
from collections import deque
from pathlib import Path
from typing import Any

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

# Bump whenever the checks or thresholds change: stored results with an older
# version are re-validated the next time the scan is opened.
QUALITY_VERSION = 2


def _parse_ply_ascii(text: str) -> dict[str, Any]:
    lines = text.splitlines()
    vertex_count = 0
    header_end = 0
    props: list[str] = []
    for i, line in enumerate(lines):
        if line.startswith("element vertex"):
            vertex_count = int(line.split()[-1])
        if line.startswith("property"):
            props.append(line.split()[-1])
        if line.strip() == "end_header":
            header_end = i + 1
            break
    verts: list[tuple[float, float, float]] = []
    for line in lines[header_end : header_end + vertex_count]:
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            verts.append((float(parts[0]), float(parts[1]), float(parts[2])))
        except ValueError:
            continue
    return {"vertex_count": len(verts), "vertices": verts, "format": "ascii"}


_PLY_PROP_SIZES = {
    "char": 1,
    "uchar": 1,
    "int8": 1,
    "uint8": 1,
    "short": 2,
    "ushort": 2,
    "int16": 2,
    "uint16": 2,
    "int": 4,
    "uint": 4,
    "int32": 4,
    "uint32": 4,
    "float": 4,
    "float32": 4,
    "double": 8,
    "float64": 8,
}


def _parse_ply_binary_little(data: bytes) -> dict[str, Any]:
    """Binary little-endian PLY parser — respects vertex property stride (Exocad-safe)."""
    header_end = data.find(b"end_header\n")
    if header_end < 0:
        header_end = data.find(b"end_header\r\n")
        if header_end < 0:
            return {"vertex_count": 0, "vertices": [], "format": "binary"}
        header_end += len(b"end_header\r\n")
    else:
        header_end += len(b"end_header\n")

    header = data[:header_end].decode("utf-8", errors="ignore")
    vertex_count = 0
    props: list[tuple[str, str]] = []  # (type, name)
    in_vertex = False
    for line in header.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "element":
            in_vertex = len(parts) >= 3 and parts[1] == "vertex"
            if in_vertex:
                try:
                    vertex_count = int(parts[2])
                except ValueError:
                    vertex_count = 0
            continue
        if in_vertex and parts[0] == "property" and len(parts) >= 3:
            # skip list properties for stride estimate (rare on vertices)
            if parts[1] == "list":
                continue
            props.append((parts[1].lower(), parts[-1].lower()))

    if vertex_count <= 0:
        return {"vertex_count": 0, "vertices": [], "format": "binary"}

    # Locate xyz offsets within the vertex record
    stride = 0
    xyz_off = {"x": None, "y": None, "z": None}
    xyz_type = {"x": "float", "y": "float", "z": "float"}
    for ptype, pname in props:
        size = _PLY_PROP_SIZES.get(ptype)
        if size is None:
            # Unknown type — fall back to classic xyz float layout
            stride = 0
            break
        if pname in xyz_off and xyz_off[pname] is None:
            xyz_off[pname] = stride
            xyz_type[pname] = ptype
        stride += size

    if stride <= 0 or any(xyz_off[k] is None for k in ("x", "y", "z")):
        # Fallback: first three floats
        stride = 12
        xyz_off = {"x": 0, "y": 4, "z": 8}
        xyz_type = {"x": "float", "y": "float", "z": "float"}

    body = data[header_end:]
    need = vertex_count * stride
    if len(body) < need:
        return {"vertex_count": 0, "vertices": [], "format": "binary"}

    def _read_num(buf: bytes, off: int, ptype: str) -> float:
        if ptype in ("double", "float64"):
            return struct.unpack_from("<d", buf, off)[0]
        if ptype in ("float", "float32"):
            return struct.unpack_from("<f", buf, off)[0]
        if ptype in ("int", "int32"):
            return float(struct.unpack_from("<i", buf, off)[0])
        if ptype in ("uint", "uint32"):
            return float(struct.unpack_from("<I", buf, off)[0])
        if ptype in ("short", "int16"):
            return float(struct.unpack_from("<h", buf, off)[0])
        if ptype in ("ushort", "uint16"):
            return float(struct.unpack_from("<H", buf, off)[0])
        if ptype in ("char", "int8"):
            return float(struct.unpack_from("<b", buf, off)[0])
        if ptype in ("uchar", "uint8"):
            return float(struct.unpack_from("<B", buf, off)[0])
        return struct.unpack_from("<f", buf, off)[0]

    verts: list[tuple[float, float, float]] = []
    step = max(1, vertex_count // 50000)
    ox, oy, oz = xyz_off["x"], xyz_off["y"], xyz_off["z"]
    assert ox is not None and oy is not None and oz is not None
    for i in range(0, vertex_count, step):
        base = i * stride
        x = _read_num(body, base + ox, xyz_type["x"])
        y = _read_num(body, base + oy, xyz_type["y"])
        z = _read_num(body, base + oz, xyz_type["z"])
        if not (math.isfinite(x) and math.isfinite(y) and math.isfinite(z)):
            continue
        verts.append((x, y, z))
    return {
        "vertex_count": vertex_count,
        "vertices": verts,
        "format": "binary",
        "sampled": len(verts),
        "stride": stride,
    }


def _finite_verts(
    verts: list[tuple[float, float, float]],
) -> list[tuple[float, float, float]]:
    out: list[tuple[float, float, float]] = []
    for v in verts:
        if len(v) < 3:
            continue
        x, y, z = float(v[0]), float(v[1]), float(v[2])
        if math.isfinite(x) and math.isfinite(y) and math.isfinite(z):
            out.append((x, y, z))
    return out


def _stats(verts: list[tuple[float, float, float]]) -> dict[str, float]:
    """Shape descriptors for a point cloud.

    Everything used for scoring is **scale- and orientation-invariant** so the
    same thresholds hold whether the export is in millimetres or centimetres and
    regardless of how the mesh is oriented in space:

    - ``planarity``  = λ₂ / (λ₀+λ₁+λ₂) from the covariance eigenvalues. ~0 means
      the cloud collapses to a plane (missing arch depth / bad export); a real
      arch has genuine 3-D relief.
    - ``elongation`` = 1 − λ₁/λ₀. ~1 means a sliver / partial fragment.

    ``span_*`` is reported for context only; the physical extent is not scored
    (volumetric density on a thin surface scan is meaningless).
    """
    verts = _finite_verts(verts)
    arr = np.asarray(verts, dtype=np.float64)
    if arr.shape[0] == 0:
        return {
            "span_x": 0.0, "span_y": 0.0, "span_z": 0.0,
            "planarity": 0.0, "elongation": 0.0,
        }
    spans = arr.max(axis=0) - arr.min(axis=0)

    # PCA on centred points → eigenvalues (variance along principal axes).
    planarity = 0.0
    elongation = 0.0
    if arr.shape[0] >= 3:
        centred = arr - arr.mean(axis=0)
        cov = (centred.T @ centred) / max(arr.shape[0] - 1, 1)
        evals = np.clip(np.linalg.eigvalsh(cov)[::-1], 0.0, None)  # λ₀ ≥ λ₁ ≥ λ₂
        total = float(evals.sum())
        if total > 1e-12:
            planarity = float(evals[2] / total)
        if evals[0] > 1e-12:
            elongation = float(1.0 - evals[1] / evals[0])

    return {
        "span_x": float(spans[0]) if math.isfinite(spans[0]) else 0.0,
        "span_y": float(spans[1]) if math.isfinite(spans[1]) else 0.0,
        "span_z": float(spans[2]) if math.isfinite(spans[2]) else 0.0,
        "planarity": planarity if math.isfinite(planarity) else 0.0,
        "elongation": elongation if math.isfinite(elongation) else 0.0,
    }


def _coverage_gaps(verts: list[tuple[float, float, float]]) -> dict[str, float]:
    """Detect missing sectors and enclosed holes on a dental arch.

    A U-shaped arch has empty tongue space that touches the bounding-box
    border — that is *not* a scan hole. Interior empty pockets (missing
    enamel patches) and angular gaps between populated sectors (missing
    teeth / dropped frames) are.

    Returns scale- and orientation-invariant fractions in ``[0, 1]``.
    """
    arr = np.asarray(_finite_verts(verts), dtype=np.float64)
    n = int(arr.shape[0])
    empty = {"angular_gap": 0.0, "enclosed_hole": 0.0, "gap_bins": 0.0}
    if n < 200:
        return empty

    centred = arr - arr.mean(axis=0)
    cov = (centred.T @ centred) / max(n - 1, 1)
    evals, evecs = np.linalg.eigh(cov)  # ascending
    if not np.all(np.isfinite(evals)):
        return empty
    axis0 = evecs[:, 2]
    axis1 = evecs[:, 1]
    uv = np.column_stack((centred @ axis0, centred @ axis1))
    if not np.all(np.isfinite(uv)):
        return empty

    n_bins = 72
    ang = np.arctan2(uv[:, 1], uv[:, 0])
    bins = np.floor((ang + math.pi) / (2 * math.pi) * n_bins).astype(np.int32)
    bins = np.clip(bins, 0, n_bins - 1)
    counts = np.bincount(bins, minlength=n_bins).astype(np.float64)
    positive = counts[counts > 0]
    if positive.size < 6:
        return empty
    med = float(np.median(positive))
    occupied = counts >= max(med * 0.30, 4.0)
    occ_idx = np.flatnonzero(occupied)
    angular_gap = 0.0
    gap_bins = 0.0
    if occ_idx.size >= 3:
        gap_lengths: list[int] = []
        for i, a in enumerate(occ_idx):
            b = int(occ_idx[(i + 1) % occ_idx.size])
            if i + 1 < occ_idx.size:
                length = int(b - a - 1)
            else:
                length = int(b + n_bins - a - 1)
            gap_lengths.append(max(0, length))
        gap_lengths.sort(reverse=True)
        opening = gap_lengths[0]
        # Closed 360° scans have only tiny residual gaps — count them all.
        # Skip length-0; count 1-bin dips so a missing tooth still flags.
        if opening < 0.18 * n_bins:
            interior = sum(g for g in gap_lengths if g >= 1)
        else:
            interior = sum(g for g in gap_lengths[1:] if g >= 1)
        span = max(n_bins - opening, 1)
        angular_gap = float(interior) / float(span)
        gap_bins = float(interior)

    gs = 64
    mn = uv.min(axis=0)
    span_uv = np.maximum(uv.max(axis=0) - mn, 1e-9)
    ij = np.floor((uv - mn) / span_uv * (gs - 1.000001)).astype(np.int32)
    ij = np.clip(ij, 0, gs - 1)
    grid = np.zeros((gs, gs), dtype=np.uint8)
    grid[ij[:, 1], ij[:, 0]] = 1
    # Dilate occupancy to seal 1-cell leaks into tongue space and fill
    # sampling specks. Measure holes on the same map so a U-arch opening
    # stays connected to the border. A 64² grid keeps millimetre-scale
    # occlusal voids after that 1-cell close.
    dilated = grid.copy()
    if gs >= 3:
        dilated[1:, :] |= grid[:-1, :]
        dilated[:-1, :] |= grid[1:, :]
        dilated[:, 1:] |= grid[:, :-1]
        dilated[:, :-1] |= grid[:, 1:]

    reached = np.zeros_like(dilated, dtype=bool)
    q: deque[tuple[int, int]] = deque()

    def _push(y: int, x: int) -> None:
        if dilated[y, x] == 0 and not reached[y, x]:
            reached[y, x] = True
            q.append((y, x))

    for x in range(gs):
        _push(0, x)
        _push(gs - 1, x)
    for y in range(gs):
        _push(y, 0)
        _push(y, gs - 1)
    while q:
        y, x = q.popleft()
        if y > 0:
            _push(y - 1, x)
        if y + 1 < gs:
            _push(y + 1, x)
        if x > 0:
            _push(y, x - 1)
        if x + 1 < gs:
            _push(y, x + 1)

    enclosed = (dilated == 0) & (~reached)
    enclosed = _filter_tiny_components(enclosed, min_size=2)
    hole_cells = int(enclosed.sum())
    occ_cells = int(dilated.sum())
    enclosed_frac = hole_cells / max(occ_cells, 1)
    return {
        "angular_gap": angular_gap if math.isfinite(angular_gap) else 0.0,
        "enclosed_hole": enclosed_frac if math.isfinite(enclosed_frac) else 0.0,
        "gap_bins": gap_bins,
    }


def _filter_tiny_components(mask: np.ndarray, min_size: int = 2) -> np.ndarray:
    """Keep enclosed blobs of at least [min_size] cells (drop sampling specks)."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    keep = np.zeros_like(mask, dtype=bool)
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or seen[y, x]:
                continue
            stack = [(y, x)]
            seen[y, x] = True
            cells = [(y, x)]
            while stack:
                cy, cx = stack.pop()
                for ny, nx in (
                    (cy - 1, cx),
                    (cy + 1, cx),
                    (cy, cx - 1),
                    (cy, cx + 1),
                ):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
                        cells.append((ny, nx))
            if len(cells) >= min_size:
                for cy, cx in cells:
                    keep[cy, cx] = True
    return keep


def detect_mesh_format(data: bytes, filename: str = "") -> str:
    """Return ply | stl | obj | unknown from filename + content sniff."""
    name = (filename or "").removesuffix(".enc")
    ext = Path(name).suffix.lower().lstrip(".")
    if ext in ("ply", "stl", "obj"):
        return ext

    head = data[:256]
    text_head = head.decode("utf-8", errors="ignore").lstrip().lower()
    if text_head.startswith("ply") or b"end_header" in head:
        return "ply"
    if text_head.startswith("solid") and (b"facet" in data[:4096] or b"vertex" in data[:4096]):
        return "stl"
    if text_head.startswith("v ") or "\nv " in text_head or text_head.startswith("#"):
        # OBJ often starts with comments or vertex lines
        sample = data[:8192].decode("utf-8", errors="ignore")
        if any(line.startswith("v ") for line in sample.splitlines()):
            return "obj"

    # Binary STL: 80-byte header + uint32 count + 50 bytes/triangle
    if len(data) >= 84:
        try:
            tri_count = struct.unpack_from("<I", data, 80)[0]
            expected = 84 + tri_count * 50
            if tri_count > 0 and abs(expected - len(data)) <= 2:
                return "stl"
        except struct.error:
            pass
    return "unknown"


def _parse_stl_ascii(text: str, max_points: int | None = None) -> dict[str, Any]:
    verts: list[tuple[float, float, float]] = []
    for line in text.splitlines():
        parts = line.strip().split()
        if len(parts) >= 4 and parts[0].lower() == "vertex":
            try:
                verts.append((float(parts[1]), float(parts[2]), float(parts[3])))
            except ValueError:
                continue
    total = len(verts)
    if max_points and total > max_points:
        step = max(1, total // max_points)
        verts = verts[::step][:max_points]
    return {"vertex_count": total, "vertices": verts, "format": "stl_ascii"}


def _parse_stl_binary(data: bytes, max_points: int | None = None) -> dict[str, Any]:
    if len(data) < 84:
        return {"vertex_count": 0, "vertices": [], "format": "stl_binary"}
    tri_count = struct.unpack_from("<I", data, 80)[0]
    need = 84 + tri_count * 50
    if tri_count <= 0 or len(data) < need - 2:
        return {"vertex_count": 0, "vertices": [], "format": "stl_binary"}

    # 3 vertices per triangle
    total_verts = tri_count * 3
    step_tri = 1
    if max_points and total_verts > max_points:
        # Sample triangles so we stay near max_points vertices
        step_tri = max(1, total_verts // max_points)

    verts: list[tuple[float, float, float]] = []
    for i in range(0, tri_count, step_tri):
        off = 84 + i * 50
        # skip normal (3 floats), read 3 vertices
        x1, y1, z1, x2, y2, z2, x3, y3, z3 = struct.unpack_from("<9f", data, off + 12)
        verts.extend([(x1, y1, z1), (x2, y2, z2), (x3, y3, z3)])
        if max_points and len(verts) >= max_points:
            verts = verts[:max_points]
            break
    return {
        "vertex_count": total_verts,
        "vertices": verts,
        "format": "stl_binary",
        "triangle_count": tri_count,
    }


def _parse_obj_ascii(text: str, max_points: int | None = None) -> dict[str, Any]:
    verts: list[tuple[float, float, float]] = []
    for line in text.splitlines():
        if not line.startswith("v "):
            continue
        parts = line.split()
        if len(parts) < 4:
            continue
        try:
            verts.append((float(parts[1]), float(parts[2]), float(parts[3])))
        except ValueError:
            continue
    total = len(verts)
    if max_points and total > max_points:
        step = max(1, total // max_points)
        verts = verts[::step][:max_points]
    return {"vertex_count": total, "vertices": verts, "format": "obj"}


def _parse_ply_ascii_sampled(text: str, max_points: int) -> dict[str, Any]:
    """ASCII PLY reader that samples while streaming (safe for large Exocad exports)."""
    lines = text.splitlines()
    vertex_count = 0
    header_end = 0
    for i, line in enumerate(lines):
        if line.startswith("element vertex"):
            try:
                vertex_count = int(line.split()[-1])
            except ValueError:
                vertex_count = 0
        if line.strip() == "end_header":
            header_end = i + 1
            break

    step = max(1, vertex_count // max_points) if vertex_count > 0 else 1
    verts: list[tuple[float, float, float]] = []
    for i, line in enumerate(lines[header_end : header_end + max(vertex_count, 0)]):
        if i % step != 0:
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            verts.append((float(parts[0]), float(parts[1]), float(parts[2])))
        except ValueError:
            continue
        if len(verts) >= max_points:
            break
    return {
        "vertex_count": vertex_count or len(verts),
        "vertices": verts,
        "format": "ply_ascii",
    }


def load_mesh_vertices(
    data: bytes,
    filename: str = "",
    *,
    max_points: int | None = None,
) -> dict[str, Any]:
    """Parse PLY/STL/OBJ into XYZ vertices (optionally sampled)."""
    kind = detect_mesh_format(data, filename)
    if kind == "ply":
        head = data[:240]
        if b"format binary" in head:
            parsed = _parse_ply_binary_little(data)
            verts = list(parsed.get("vertices") or [])
            if max_points and len(verts) > max_points:
                step = max(1, len(verts) // max_points)
                verts = verts[::step][:max_points]
            return {
                "kind": "ply",
                "vertex_count": int(parsed.get("vertex_count") or len(verts)),
                "vertices": verts,
                "format": "ply_binary",
            }
        text = data.decode("utf-8", errors="ignore")
        if max_points:
            parsed = _parse_ply_ascii_sampled(text, max_points)
        else:
            parsed = _parse_ply_ascii(text)
            parsed["format"] = "ply_ascii"
        return {
            "kind": "ply",
            "vertex_count": int(parsed.get("vertex_count") or 0),
            "vertices": list(parsed.get("vertices") or []),
            "format": parsed.get("format", "ply_ascii"),
        }

    if kind == "stl":
        text_head = data[:80].decode("utf-8", errors="ignore").lstrip().lower()
        looks_ascii = text_head.startswith("solid") and b"facet" in data[:8192]
        if looks_ascii:
            parsed = _parse_stl_ascii(
                data.decode("utf-8", errors="ignore"),
                max_points=max_points,
            )
        else:
            parsed = _parse_stl_binary(data, max_points=max_points)
            # Fallback: some ASCII STLs don't include "facet" in first 8KB oddly
            if not parsed["vertices"] and text_head.startswith("solid"):
                parsed = _parse_stl_ascii(
                    data.decode("utf-8", errors="ignore"),
                    max_points=max_points,
                )
        return {
            "kind": "stl",
            "vertex_count": int(parsed.get("vertex_count") or 0),
            "vertices": list(parsed.get("vertices") or []),
            "format": parsed.get("format", "stl"),
            "triangle_count": parsed.get("triangle_count"),
        }

    if kind == "obj":
        parsed = _parse_obj_ascii(
            data.decode("utf-8", errors="ignore"),
            max_points=max_points,
        )
        return {
            "kind": "obj",
            "vertex_count": int(parsed.get("vertex_count") or 0),
            "vertices": list(parsed.get("vertices") or []),
            "format": "obj",
        }

    return {
        "kind": "unknown",
        "vertex_count": 0,
        "vertices": [],
        "format": "unknown",
        "error": "Unsupported mesh format (use PLY, STL, or OBJ)",
    }


_NP_TYPES = {
    "char": "i1", "int8": "i1", "uchar": "u1", "uint8": "u1",
    "short": "i2", "int16": "i2", "ushort": "u2", "uint16": "u2",
    "int": "i4", "int32": "i4", "uint": "u4", "uint32": "u4",
    "float": "f4", "float32": "f4", "double": "f8", "float64": "f8",
}


def _ply_triangles(data: bytes) -> tuple[np.ndarray, np.ndarray] | None:
    """Full-resolution vertices + triangle faces from a PLY (binary LE or ASCII).

    Returns None for layouts we don't handle (non-triangle faces, extra
    elements before the faces, big-endian) — the roughness check is skipped.
    """
    end = data.find(b"end_header")
    if end < 0:
        return None
    body_start = data.index(b"\n", end) + 1
    elements: list[list[Any]] = []  # [name, count, props]
    fmt = ""
    for line in data[:body_start].decode("ascii", errors="ignore").splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] == "format":
            fmt = p[1]
        elif p[0] == "element" and len(p) >= 3:
            elements.append([p[1], int(p[2]), []])
        elif p[0] == "property" and elements:
            elements[-1][2].append(p[1:])
    if [e[0] for e in elements[:2]] != ["vertex", "face"]:
        return None
    (_, nv, vprops), (_, nf, fprops) = elements[0], elements[1]
    names = [p[-1] for p in vprops]
    if any(p[0] == "list" for p in vprops) or not {"x", "y", "z"} <= set(names):
        return None
    if len(fprops) != 1 or fprops[0][0] != "list":
        return None
    if fmt == "ascii":
        rows = data[body_start:].decode("ascii", errors="ignore").split("\n")
        V = np.loadtxt(rows[:nv], dtype=np.float64, ndmin=2)
        F = np.loadtxt(rows[nv : nv + nf], dtype=np.int64, ndmin=2)
        if F.shape[1] != 4 or not (F[:, 0] == 3).all():
            return None
        xyz = [names.index(a) for a in "xyz"]
        return V[:, xyz], F[:, 1:]
    if fmt != "binary_little_endian":
        return None
    vdt = np.dtype([(n, "<" + _NP_TYPES[p[0]]) for p, n in zip(vprops, names)])
    count_t, index_t = _NP_TYPES[fprops[0][1]], _NP_TYPES[fprops[0][2]]
    fdt = np.dtype([("n", "<" + count_t), ("i", "<" + index_t, 3)])
    try:
        verts = np.frombuffer(data, vdt, nv, body_start)
        faces = np.frombuffer(data, fdt, nf, body_start + nv * vdt.itemsize)
    except ValueError:
        return None
    if not (faces["n"] == 3).all():
        return None
    V = np.column_stack([verts[a] for a in "xyz"]).astype(np.float64)
    return V, faces["i"].astype(np.int64)


def _stl_triangles(data: bytes) -> tuple[np.ndarray, np.ndarray] | None:
    """Welded vertices + faces from a binary or ASCII STL."""
    tri = None
    if len(data) >= 84:
        n = struct.unpack_from("<I", data, 80)[0]
        if n and 84 + n * 50 <= len(data) + 2:
            rec = np.dtype([("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
            try:
                tri = np.frombuffer(data, rec, n, 84)["v"].astype(np.float64)
            except ValueError:
                tri = None
    if tri is None:
        pts = [
            [float(t) for t in line.split()[1:4]]
            for line in data.decode("utf-8", errors="ignore").splitlines()
            if line.strip().lower().startswith("vertex")
        ]
        if not pts or len(pts) % 3:
            return None
        tri = np.asarray(pts, dtype=np.float64).reshape(-1, 3, 3)
    V, inv = np.unique(tri.reshape(-1, 3), axis=0, return_inverse=True)
    return V, inv.reshape(-1, 3)


def _obj_triangles(data: bytes) -> tuple[np.ndarray, np.ndarray] | None:
    """Vertices + fan-triangulated faces from an OBJ."""
    verts: list[list[float]] = []
    faces: list[list[int]] = []
    for line in data.decode("utf-8", errors="ignore").splitlines():
        if line.startswith("v "):
            verts.append([float(t) for t in line.split()[1:4]])
        elif line.startswith("f "):
            idx = [int(t.split("/")[0]) for t in line.split()[1:]]
            idx = [i - 1 if i > 0 else len(verts) + i for i in idx]
            faces += [[idx[0], idx[j], idx[j + 1]] for j in range(1, len(idx) - 1)]
    if not verts or not faces:
        return None
    return np.asarray(verts, dtype=np.float64), np.asarray(faces, dtype=np.int64)


def load_mesh_triangles(data: bytes, filename: str = "") -> tuple[np.ndarray, np.ndarray] | None:
    """(V, F) at full resolution, or None for point clouds / unhandled layouts."""
    kind = detect_mesh_format(data, filename)
    try:
        mesh = {"ply": _ply_triangles, "stl": _stl_triangles, "obj": _obj_triangles}.get(
            kind, lambda _d: None
        )(data)
    except (ValueError, IndexError, KeyError, struct.error):
        return None
    if mesh is None:
        return None
    V, F = mesh
    ok = np.isfinite(V).all(axis=1)
    if len(F) == 0 or F.min() < 0 or F.max() >= len(V) or not ok.all():
        return None
    return V, F


# Rough-patch detector. Calibrated on 5 labelled IS ScanFlow arches (3 good,
# 2 bad): rough-area share good ≤ 0.12 %, bad ≥ 1.03 %; the cut-off is their
# geometric midpoint. Everything else is relative to the scan itself.
# ponytail: 5-scan calibration; re-check stats["rough_area_pct"] as labelled
# scans from other scanners arrive.
_ROUGH_K = 16  # neighbours per local surface fit (~0.35 mm patch at 0.17 mm edges)
_ROUGH_HOT_X = 6.0  # vertex is "rough" at > 6× the scan's own median deviation
_ROUGH_MIN_PATCH_EDGES2 = 30.0  # patch must cover ≥ 30 edge² (≈1 mm² at 0.17 mm edges)
_ROUGH_MAX_POINTS = 6000  # cap on patch points sent to the viewer for red highlighting
_ROUGH_PCT_MEDIUM = 0.35
_ROUGH_PCT_HIGH = 0.70
# Whole-surface noise (median fit deviation / median edge length). The patch
# test is relative to the scan's own median, so uniform noise needs this.
# Real scans: 0.022–0.028. ponytail: no real uniformly-noisy scan seen yet;
# cut-offs are ~2× / ~3.5× the good maximum.
_NOISE_MEDIUM = 0.06
_NOISE_HIGH = 0.10


def _local_fit_residual(V: np.ndarray, nn: np.ndarray) -> np.ndarray:
    """RMS deviation of each k-NN patch from its best-fit quadric surface.

    Real anatomy (cusps, rugae, margins) is smooth at this sub-millimetre
    scale; scanner noise, faceting and stitching ridges are not.
    """
    P = V[nn] - V[nn].mean(axis=1, keepdims=True)
    _, W = np.linalg.eigh(np.einsum("nki,nkj->nij", P, P))  # ascending
    x = np.einsum("nki,ni->nk", P, W[:, :, 2])
    y = np.einsum("nki,ni->nk", P, W[:, :, 1])
    z = np.einsum("nki,ni->nk", P, W[:, :, 0])
    A = np.stack([x * x, x * y, y * y, x, y, np.ones_like(x)], axis=-1)
    AtA = np.einsum("nki,nkj->nij", A, A) + 1e-12 * np.eye(6)
    coef = np.linalg.solve(AtA, np.einsum("nki,nk->ni", A, z)[..., None])[..., 0]
    return np.sqrt(((z - np.einsum("nki,ni->nk", A, coef)) ** 2).mean(axis=1))


def _thin_points(P: np.ndarray, edge: float) -> tuple[np.ndarray, float]:
    """Voxel-thin patch vertices to ≤ _ROUGH_MAX_POINTS; return them + the
    radius a viewer should paint around each one to cover the patch."""
    size = max(edge, 1e-9)
    while True:
        _, keep = np.unique(np.floor(P / size).astype(np.int64), axis=0, return_index=True)
        if len(keep) <= _ROUGH_MAX_POINTS:
            return P[np.sort(keep)], 1.75 * size  # > voxel diagonal (√3)
        size *= 1.5


def _rough_patches(V: np.ndarray, F: np.ndarray) -> dict[str, Any]:
    """Share of the surface covered by connected patches of harsh roughness.

    ``points`` / ``radius`` locate the patches (file coordinates) so the
    viewer can paint them; they are not stats.
    """
    empty = {
        "rough_area_pct": 0.0, "rough_largest_patch_pct": 0.0, "surface_noise": 0.0,
        "points": [], "radius": 0.0,
    }
    if len(V) < 200:
        return empty
    k = min(_ROUGH_K, len(V))
    _, nn = cKDTree(V).query(V, k=k)
    # ponytail: all vertices, ~2 s per 200k; subsample if scans get much denser.
    r = np.concatenate([
        _local_fit_residual(V, nn[i : i + 20000]) for i in range(0, len(V), 20000)
    ])

    E = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    edge = float(np.median(np.linalg.norm(V[E[:, 0]] - V[E[:, 1]], axis=1)))
    # Floor stops a perfectly smooth (CAD/synthetic) mesh with ~0 median from
    # flagging everything.
    med = float(np.median(r))
    noise = med / edge if edge > 0 else 0.0
    hot = r > max(_ROUGH_HOT_X * med, 0.05 * edge)

    tri_area = np.linalg.norm(np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]]), axis=1) / 2
    v_area = np.zeros(len(V))
    for j in range(3):
        np.add.at(v_area, F[:, j], tri_area / 3)
    total = float(v_area.sum())

    E = E[hot[E[:, 0]] & hot[E[:, 1]]]
    n_comp, label = connected_components(
        coo_matrix((np.ones(len(E)), (E[:, 0], E[:, 1])), shape=(len(V), len(V))),
        directed=False,
    )
    patch = np.bincount(label[hot], weights=v_area[hot], minlength=n_comp)
    big = patch >= _ROUGH_MIN_PATCH_EDGES2 * edge * edge
    if total <= 0 or not big.any():
        return {**empty, "surface_noise": noise}
    pts, radius = _thin_points(V[hot & big[label]], edge)
    return {
        "rough_area_pct": 100.0 * float(patch[big].sum()) / total,
        "rough_largest_patch_pct": 100.0 * float(patch[big].max()) / total,
        "surface_noise": noise,
        "points": np.round(pts, 4).tolist(),
        "radius": round(radius, 5),
    }


def _is_truncated(data: bytes, filename: str) -> bool:
    """File shorter than its own header promises — an interrupted transfer.

    The vertex parsers happily read the part that arrived, so without this a
    half-uploaded scan can score as good.
    """
    kind = detect_mesh_format(data, filename)
    if kind == "stl":
        if b"facet" in data[:8192] or len(data) < 84:
            return False  # ASCII STL has no declared size
        return len(data) < 84 + 50 * struct.unpack_from("<I", data, 80)[0]
    end = data.find(b"end_header", 0, 65536)
    if kind != "ply" or end < 0:
        return False
    body_start = data.find(b"\n", end) + 1
    header = data[:body_start].decode("ascii", errors="ignore").splitlines()
    fmt = next((ln.split()[1] for ln in header if ln.startswith("format ")), "")
    elements: list[list[Any]] = []  # [count, props]
    for line in header:
        p = line.split()
        if p[:1] == ["element"] and len(p) >= 3 and p[2].isdigit():
            elements.append([int(p[2]), []])
        elif p[:1] == ["property"] and elements:
            elements[-1][1].append(p[1:])
    body = len(data) - body_start
    if fmt == "ascii":
        lines = data[body_start:].count(b"\n") + (0 if data.endswith(b"\n") else 1)
        return lines < sum(c for c, _ in elements)
    need = 0
    for count, props in elements:
        rec = 0
        for p in props:
            if p[0] == "list" and len(p) >= 3:
                # Lower bound: a face list holds at least a triangle.
                rec += _PLY_PROP_SIZES.get(p[1], 1) + 3 * _PLY_PROP_SIZES.get(p[2], 4)
            else:
                rec += _PLY_PROP_SIZES.get(p[0], 4)
        need += count * rec
    return body < need


def validate_scan_bytes(data: bytes, filename: str = "scan.ply") -> dict[str, Any]:
    reasons: list[str] = []
    issues: list[dict[str, str]] = []
    score = 1.0

    parsed = load_mesh_vertices(data, filename, max_points=50000)
    if parsed.get("error") or not parsed.get("vertices"):
        kind = parsed.get("kind", "unknown")
        return {
            "v": QUALITY_VERSION,
            "result": "bad",
            "reasons": [
                parsed.get("error")
                or f"Could not parse {kind.upper() if kind != 'unknown' else 'mesh'} file."
            ],
            "issues": [
                {
                    "severity": "high",
                    "code": "parse_fail",
                    "message": parsed.get("error") or "Unreadable mesh",
                }
            ],
            "note": "Supports PLY, STL (ascii/binary), and OBJ vertex meshes.",
            "filename": filename,
            "format": parsed.get("format", "unknown"),
            "mesh_kind": parsed.get("kind", "unknown"),
            "prompt_rescan": True,
        }

    n = int(parsed["vertex_count"])
    verts = parsed["vertices"]
    st = _stats(verts)

    # 0. Incomplete file — everything below would grade only the part that arrived.
    if _is_truncated(data, filename):
        reasons.append("The file is incomplete — the upload or export was cut off.")
        issues.append({
            "severity": "high",
            "code": "truncated",
            "message": f"{len(data)} bytes, shorter than its header declares",
        })
        score -= 0.6

    # 1. Completeness. For a surface scan the vertex count is the scale-invariant
    #    density signal (points-per-area collapses to ~count for a fixed shape),
    #    so we grade on count directly instead of a bogus volumetric density.
    if n < 500:
        reasons.append(f"Very low vertex count ({n}) — incomplete scan.")
        issues.append({"severity": "high", "code": "sparse", "message": f"Only {n} vertices"})
        score -= 0.55
    elif n < 5000:
        reasons.append(f"Low vertex count ({n}) — sparse/grainy capture.")
        issues.append({"severity": "medium", "code": "low_density", "message": f"{n} vertices"})
        score -= 0.25
    elif n < 15000:
        reasons.append(f"Moderate vertex count ({n}) — fine margins may lack detail.")
        issues.append({"severity": "low", "code": "moderate_density", "message": f"{n} vertices"})
        score -= 0.08

    # 2. Collapsed / degenerate surface — orientation- & scale-invariant via PCA.
    #    A real arch has 3-D relief (planarity well above zero); a flat plane,
    #    a single-axis export, or a collapsed mesh has planarity ≈ 0.
    if len(verts) >= 50:
        if st["planarity"] < 0.002:
            reasons.append("Collapsed / near-flat geometry — missing arch depth or bad export.")
            issues.append({
                "severity": "high",
                "code": "missing_margin",
                "message": f"planarity≈{st['planarity']:.4f}",
            })
            score -= 0.45
        elif st["planarity"] < 0.01:
            reasons.append("Very thin capture — low surface relief; margin detail may be missing.")
            issues.append({
                "severity": "medium",
                "code": "thin_capture",
                "message": f"planarity≈{st['planarity']:.4f}",
            })
            score -= 0.2

    # 3. Sliver / partial capture — one axis dominates the whole cloud.
    if len(verts) >= 50 and st["elongation"] > 0.985:
        reasons.append("Highly elongated fragment — likely a partial scan.")
        issues.append({
            "severity": "medium",
            "code": "partial",
            "message": f"elongation≈{st['elongation']:.3f}",
        })
        score -= 0.15

    # 4. Holes / missing sectors — enclosed empty pockets and interior
    #    angular gaps. Tongue space of a U-arch is connected to the bbox
    #    border and is not scored (see test_dense_arch_scores_good).
    cov = _coverage_gaps(verts)
    st["angular_gap"] = cov["angular_gap"]
    st["enclosed_hole"] = cov["enclosed_hole"]
    if len(verts) >= 200:
        if cov["angular_gap"] >= 0.06:
            reasons.append(
                "Gaps in the arch — missing teeth or dropped scan frames."
            )
            issues.append({
                "severity": "high" if cov["angular_gap"] >= 0.12 else "medium",
                "code": "gaps",
                "message": f"arch gap≈{cov['angular_gap']:.2f}",
            })
            score -= 0.40 if cov["angular_gap"] >= 0.12 else 0.28
        if cov["enclosed_hole"] >= 0.015:
            reasons.append(
                "Holes in the scanned surface — incomplete capture."
            )
            issues.append({
                "severity": "high" if cov["enclosed_hole"] >= 0.04 else "medium",
                "code": "holes",
                "message": f"surface holes≈{cov['enclosed_hole']:.2f}",
            })
            score -= 0.35 if cov["enclosed_hole"] >= 0.04 else 0.26

    # 5. Harsh / ridged / uneven surface — needs triangles, so point clouds skip it.
    rough_points: list[list[float]] = []
    rough_radius = 0.0
    mesh = load_mesh_triangles(data, filename)
    if mesh is not None:
        rough = _rough_patches(*mesh)
        rough_points, rough_radius = rough.pop("points"), rough.pop("radius")
        st.update(rough)
        pct = rough["rough_area_pct"]
        if pct >= _ROUGH_PCT_MEDIUM:
            high = pct >= _ROUGH_PCT_HIGH
            reasons.append(
                "Rough, ridged or uneven patches on the scanned surface — "
                "noise or stitching artefacts."
            )
            issues.append({
                "severity": "high" if high else "medium",
                "code": "rough_surface",
                "message": f"rough patches≈{pct:.2f}% of surface",
            })
            score -= 0.45 if high else 0.30
        noise = rough["surface_noise"]
        if noise >= _NOISE_MEDIUM:
            high = noise >= _NOISE_HIGH
            reasons.append("Grainy surface overall — scanner noise across the whole scan.")
            issues.append({
                "severity": "high" if high else "medium",
                "code": "noisy_surface",
                "message": f"surface noise≈{noise:.3f}",
            })
            score -= 0.45 if high else 0.30

    score = max(0.0, min(1.0, score))
    if any(i["code"] in ("gaps", "holes") for i in issues):
        # Visible coverage defects must never pass as a good scan.
        score = min(score, 0.74)
    if any(i["code"] == "missing_margin" for i in issues):
        result = "missing_margin"
    elif score >= 0.75:
        result = "good"
    elif score >= 0.45:
        result = "blurry"
    else:
        result = "bad"

    if not reasons:
        reasons.append(
            f"Checks passed for {parsed.get('kind', 'mesh').upper()} "
            "(vertex heuristics; PLY fixtures in references/scans/)."
        )

    prompt_rescan = result in ("bad", "blurry", "missing_margin") or any(
        i["code"] in ("gaps", "holes", "rough_surface", "noisy_surface")
        for i in issues
    )
    return {
        "v": QUALITY_VERSION,
        "result": result,
        "reasons": reasons,
        "issues": issues,
        "vertex_count": n,
        "stats": {k: _json_safe_float(v) for k, v in st.items()},
        "format": parsed.get("format"),
        "mesh_kind": parsed.get("kind"),
        "note": (
            "Mesh validator supports PLY / STL / OBJ. Scored on vertex "
            "completeness, PCA shape (planarity, elongation), arch "
            "coverage (interior gaps / enclosed surface holes) and, for "
            "triangle meshes, rough-surface patches."
        ),
        "filename": filename,
        "prompt_rescan": prompt_rescan,
        # Only paint patches when they actually failed the scan.
        "rough_points": rough_points if any(i["code"] == "rough_surface" for i in issues) else [],
        "rough_radius": rough_radius,
    }


def validate_ply_bytes(data: bytes, filename: str = "scan.ply") -> dict[str, Any]:
    """Backward-compatible alias."""
    return validate_scan_bytes(data, filename=filename)


def validate_ply_path(path: Path) -> dict[str, Any]:
    return validate_scan_bytes(path.read_bytes(), filename=path.name)


def _json_safe_float(v: float, default: float = 0.0) -> float:
    f = float(v)
    return round(f, 5) if math.isfinite(f) else default


def preview_mesh_bytes(
    data: bytes,
    filename: str = "",
    max_points: int = 10000,
) -> dict[str, Any]:
    """Return a downsampled XYZ point cloud for the chairside 3D viewer."""
    max_points = max(500, min(int(max_points), 20000))
    parsed = load_mesh_vertices(data, filename, max_points=max_points)
    verts = _finite_verts(list(parsed.get("vertices") or []))
    total = int(parsed.get("vertex_count") or 0)

    if not verts:
        return {
            "vertex_count": total,
            "sampled": 0,
            "vertices": [],
            "format": parsed.get("format", "unknown"),
            "mesh_kind": parsed.get("kind", "unknown"),
            "error": parsed.get("error") or "No valid vertices found",
        }

    arr = np.asarray(verts, dtype=np.float64)
    center = arr.mean(axis=0)
    centered = arr - center
    radii = np.linalg.norm(centered, axis=1)
    finite_r = radii[np.isfinite(radii)]
    span = float(np.max(finite_r)) if finite_r.size else 0.0
    if not math.isfinite(span) or span < 1e-12:
        span = 1.0
    normalized = (centered / span).tolist()
    clean = [
        [_json_safe_float(x), _json_safe_float(y), _json_safe_float(z)]
        for x, y, z in normalized
        if math.isfinite(x) and math.isfinite(y) and math.isfinite(z)
    ]

    return {
        "vertex_count": total,
        "sampled": len(clean),
        "vertices": clean,
        "format": parsed.get("format", "unknown"),
        "mesh_kind": parsed.get("kind", "unknown"),
        "center": [_json_safe_float(c) for c in center.tolist()],
        "span": _json_safe_float(span, 1.0),
    }


def preview_ply_bytes(data: bytes, max_points: int = 10000) -> dict[str, Any]:
    """Backward-compatible alias."""
    return preview_mesh_bytes(data, filename="", max_points=max_points)

"""Scan mesh quality validation + 3D preview sampling (PLY / STL / OBJ).

Heuristics calibrated against synthetic Medit-like PLY fixtures in
references/scans/. STL/OBJ use the same vertex-based checks after parsing.
"""

from __future__ import annotations

import math
import struct
from pathlib import Path
from typing import Any

import numpy as np


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


def validate_scan_bytes(data: bytes, filename: str = "scan.ply") -> dict[str, Any]:
    reasons: list[str] = []
    issues: list[dict[str, str]] = []
    score = 1.0

    parsed = load_mesh_vertices(data, filename, max_points=50000)
    if parsed.get("error") or not parsed.get("vertices"):
        kind = parsed.get("kind", "unknown")
        return {
            "result": "bad",
            "quality_score": 0.0,
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

    score = max(0.0, min(1.0, score))
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

    prompt_rescan = result in ("bad", "blurry", "missing_margin")
    return {
        "result": result,
        "quality_score": round(score, 3),
        "reasons": reasons,
        "issues": issues,
        "vertex_count": n,
        "stats": {k: _json_safe_float(v) for k, v in st.items()},
        "format": parsed.get("format"),
        "mesh_kind": parsed.get("kind"),
        "note": (
            "Mesh validator supports PLY / STL / OBJ. Scored on vertex "
            "completeness plus scale-/orientation-invariant PCA shape checks "
            "(planarity, elongation); supervised model later."
        ),
        "filename": filename,
        "prompt_rescan": prompt_rescan,
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

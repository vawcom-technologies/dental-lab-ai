"""PLY scan quality validation (Week 3).

Improved heuristics calibrated against synthetic Medit-like fixtures in
references/scans/. Replace with supervised CNN when client supplies labeled PLYs.
"""

from __future__ import annotations

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


def _parse_ply_binary_little(data: bytes) -> dict[str, Any]:
    """Minimal binary_little_endian xyz float parser."""
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
    for line in header.splitlines():
        if line.startswith("element vertex"):
            vertex_count = int(line.split()[-1])
            break

    body = data[header_end:]
    # Assume first 3 floats are xyz (common Medit export)
    need = vertex_count * 12
    if len(body) < need or vertex_count <= 0:
        return {"vertex_count": 0, "vertices": [], "format": "binary"}

    verts: list[tuple[float, float, float]] = []
    # Sample up to 50k verts for speed
    step = max(1, vertex_count // 50000)
    for i in range(0, vertex_count, step):
        off = i * 12
        x, y, z = struct.unpack_from("<fff", body, off)
        verts.append((x, y, z))
    return {"vertex_count": vertex_count, "vertices": verts, "format": "binary", "sampled": len(verts)}


def _stats(verts: list[tuple[float, float, float]]) -> dict[str, float]:
    arr = np.asarray(verts, dtype=np.float64)
    if arr.size == 0:
        return {"span_x": 0, "span_y": 0, "span_z": 0, "noise_z": 0, "density": 0}
    spans = arr.max(axis=0) - arr.min(axis=0)
    # Local roughness proxy: std of z after removing linear trend in xy
    z = arr[:, 2]
    noise = float(np.std(z - np.median(z)))
    volume = max(float(np.prod(np.maximum(spans, 1e-9))), 1e-9)
    density = len(verts) / volume
    return {
        "span_x": float(spans[0]),
        "span_y": float(spans[1]),
        "span_z": float(spans[2]),
        "noise_z": noise,
        "density": float(density),
    }


def validate_ply_bytes(data: bytes, filename: str = "scan.ply") -> dict[str, Any]:
    reasons: list[str] = []
    issues: list[dict[str, str]] = []
    score = 1.0
    parsed: dict[str, Any]

    head = data[:240]
    is_binary = b"format binary" in head
    if is_binary:
        parsed = _parse_ply_binary_little(data)
        if parsed["vertex_count"] == 0:
            return {
                "result": "bad",
                "quality_score": 0.15,
                "reasons": ["Binary PLY could not be parsed (unexpected layout)."],
                "issues": [{"severity": "high", "code": "parse_fail", "message": "Unreadable binary PLY"}],
                "note": "Week 3 binary parser supports common xyz float layouts.",
                "filename": filename,
                "prompt_rescan": True,
            }
    else:
        try:
            text = data.decode("utf-8", errors="ignore")
        except Exception:
            return {
                "result": "bad",
                "quality_score": 0.1,
                "reasons": ["Could not decode PLY."],
                "issues": [{"severity": "high", "code": "decode", "message": "Decode failed"}],
                "note": "Week 3 validator.",
                "filename": filename,
                "prompt_rescan": True,
            }
        if not text.lstrip().startswith("ply"):
            return {
                "result": "bad",
                "quality_score": 0.0,
                "reasons": ["File does not look like a PLY."],
                "issues": [{"severity": "high", "code": "not_ply", "message": "Not a PLY file"}],
                "note": "Week 3 validator.",
                "filename": filename,
                "prompt_rescan": True,
            }
        parsed = _parse_ply_ascii(text)

    n = int(parsed["vertex_count"])
    verts = parsed["vertices"]
    st = _stats(verts)

    # Vertex completeness
    if n < 500:
        reasons.append(f"Very low vertex count ({n}) — incomplete scan.")
        issues.append({"severity": "high", "code": "sparse", "message": f"Only {n} vertices"})
        score -= 0.55
    elif n < 5000:
        reasons.append(f"Low vertex count ({n}) — possible sparse/grainy capture.")
        issues.append({"severity": "medium", "code": "low_density", "message": f"{n} vertices"})
        score -= 0.25

    # Collapsed / missing margin (near-zero extent on an axis)
    min_span = min(st["span_x"], st["span_y"], st["span_z"])
    if len(verts) >= 50 and min_span < 1e-3:
        reasons.append("Near-zero extent on one axis — possible missing margin / collapsed mesh.")
        issues.append({"severity": "high", "code": "missing_margin", "message": "Collapsed axis extent"})
        score -= 0.4

    # Grainy / noisy surface (thin volume + high z deviation)
    if len(verts) >= 100 and st["span_z"] < 0.8 and st["noise_z"] > 0.06:
        reasons.append("High surface noise with thin extent — grainy/blurry scan quality.")
        issues.append({"severity": "medium", "code": "grainy", "message": f"noise≈{st['noise_z']:.3f}"})
        score -= 0.3

    if st["density"] < 1.0 and n >= 50:
        reasons.append("Very low vertex density — possible missing regions.")
        issues.append({"severity": "medium", "code": "holes", "message": "Low spatial density"})
        score -= 0.2

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
        reasons.append("Checks passed against Week 3 heuristics (fixtures in references/scans/).")

    prompt_rescan = result in ("bad", "blurry", "missing_margin")
    return {
        "result": result,
        "quality_score": round(score, 3),
        "reasons": reasons,
        "issues": issues,
        "vertex_count": n,
        "stats": {k: round(v, 5) for k, v in st.items()},
        "format": parsed.get("format"),
        "note": (
            "Week 3 validator calibrated on synthetic good/bad/blurry/missing_margin fixtures. "
            "Swap in supervised model when client Medit labeled PLYs arrive."
        ),
        "filename": filename,
        "prompt_rescan": prompt_rescan,
    }


def validate_ply_path(path: Path) -> dict[str, Any]:
    return validate_ply_bytes(path.read_bytes(), filename=path.name)

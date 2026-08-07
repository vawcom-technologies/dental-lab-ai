"""Quality-scoring tests for the mesh validator.

These lock the scale-/orientation-invariant scoring so a genuinely good scan is
not penalised (the old volumetric-density heuristic false-flagged nearly every
surface scan) while degenerate, sparse, or partial captures still drop.
"""

from __future__ import annotations

import numpy as np

from app.ai.scan_quality import validate_scan_bytes


def _ply_ascii(pts: np.ndarray) -> bytes:
    """Minimal ASCII PLY (xyz only) from an (N, 3) array."""
    lines = [
        "ply",
        "format ascii 1.0",
        f"element vertex {len(pts)}",
        "property float x",
        "property float y",
        "property float z",
        "end_header",
    ]
    lines += [f"{x:.5f} {y:.5f} {z:.5f}" for x, y, z in pts]
    return ("\n".join(lines) + "\n").encode("utf-8")


def _arch(n_u: int = 220, n_v: int = 140, big_R: float = 20.0, r: float = 6.0) -> np.ndarray:
    """Half-torus surface — a stand-in dental arch with real 3-D relief."""
    u = np.linspace(0.0, np.pi, n_u)
    v = np.linspace(0.0, 2.0 * np.pi, n_v)
    uu, vv = np.meshgrid(u, v)
    x = (big_R + r * np.cos(vv)) * np.cos(uu)
    y = (big_R + r * np.cos(vv)) * np.sin(uu)
    z = r * np.sin(vv)
    return np.stack([x, y, z], axis=-1).reshape(-1, 3)


def _codes(result: dict) -> set[str]:
    return {i["code"] for i in result.get("issues", [])}


def test_dense_arch_scores_good_without_false_issues():
    data = _ply_ascii(_arch())
    res = validate_scan_bytes(data, filename="arch.ply")
    assert res["result"] == "good"
    assert res["quality_score"] >= 0.9
    # Old heuristic would emit "holes"/"grainy" here — must not anymore.
    assert _codes(res) == set()
    assert res["prompt_rescan"] is False


def test_arch_is_scale_invariant():
    """Same shape in cm vs mm must score identically (no absolute thresholds)."""
    mm = validate_scan_bytes(_ply_ascii(_arch()), filename="mm.ply")
    cm = validate_scan_bytes(_ply_ascii(_arch() * 0.1), filename="cm.ply")
    assert mm["result"] == cm["result"] == "good"
    assert abs(mm["quality_score"] - cm["quality_score"]) < 1e-6


def test_arch_is_orientation_invariant():
    """Rotating the mesh must not change the score (PCA, not axis-aligned)."""
    pts = _arch()
    theta = 0.7
    rot = np.array([
        [np.cos(theta), -np.sin(theta), 0.0],
        [np.sin(theta), np.cos(theta), 0.0],
        [0.0, 0.0, 1.0],
    ])
    # tilt into all three axes too
    tilt = np.array([
        [1.0, 0.0, 0.0],
        [0.0, np.cos(0.5), -np.sin(0.5)],
        [0.0, np.sin(0.5), np.cos(0.5)],
    ])
    rotated = pts @ rot.T @ tilt.T
    a = validate_scan_bytes(_ply_ascii(pts), filename="a.ply")
    b = validate_scan_bytes(_ply_ascii(rotated), filename="b.ply")
    assert a["result"] == b["result"] == "good"
    assert abs(a["quality_score"] - b["quality_score"]) < 1e-6


def test_collapsed_plane_flags_missing_margin():
    rng = np.random.default_rng(0)
    xy = rng.uniform(-20, 20, size=(20000, 2))
    flat = np.column_stack([xy, np.zeros(len(xy))])  # z ≡ 0
    res = validate_scan_bytes(_ply_ascii(flat), filename="flat.ply")
    assert "missing_margin" in _codes(res)
    assert res["result"] == "missing_margin"
    assert res["prompt_rescan"] is True


def test_sparse_capture_flags_sparse_and_drops_score():
    res = validate_scan_bytes(_ply_ascii(_arch(n_u=18, n_v=16)), filename="sparse.ply")
    assert "sparse" in _codes(res)
    assert res["quality_score"] < 0.6
    assert res["prompt_rescan"] is True


def test_elongated_fragment_flags_partial():
    rng = np.random.default_rng(1)
    x = rng.uniform(0.0, 120.0, size=(20000,))
    ang = rng.uniform(0.0, 2 * np.pi, size=len(x))
    y = 3.0 * np.cos(ang)
    z = 3.0 * np.sin(ang)  # thin tube along x, but not flat
    tube = np.column_stack([x, y, z])
    res = validate_scan_bytes(_ply_ascii(tube), filename="tube.ply")
    assert "partial" in _codes(res)


def test_unparseable_returns_bad_zero():
    res = validate_scan_bytes(b"not a mesh at all", filename="junk.txt")
    assert res["result"] == "bad"
    assert res["quality_score"] == 0.0
    assert res["prompt_rescan"] is True

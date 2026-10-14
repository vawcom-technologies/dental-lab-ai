"""Validation tests for the mesh validator.

The validator only looks for recording / export failures. These lock that a
clean scan — including one with unusual anatomy such as a missing tooth — is
never flagged, while holes, filled-in areas, split or loose pieces, double
layers, noise, bite overlap and broken files are.
"""

from __future__ import annotations

from pathlib import Path

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


def _ply_mesh(pts: np.ndarray, faces: np.ndarray) -> bytes:
    lines = [
        "ply", "format ascii 1.0", f"element vertex {len(pts)}",
        "property float x", "property float y", "property float z",
        f"element face {len(faces)}", "property list uchar int vertex_indices",
        "end_header",
    ]
    lines += [f"{x:.5f} {y:.5f} {z:.5f}" for x, y, z in pts]
    lines += [f"3 {a} {b} {c}" for a, b, c in faces]
    return ("\n".join(lines) + "\n").encode("utf-8")


def _arch(n_u: int = 220, n_v: int = 140, big_R: float = 20.0, r: float = 6.0) -> np.ndarray:
    """Half-torus surface — a stand-in dental arch with real 3-D relief (mm)."""
    u = np.linspace(0.0, np.pi, n_u)
    v = np.linspace(0.0, 2.0 * np.pi, n_v)
    uu, vv = np.meshgrid(u, v)
    x = (big_R + r * np.cos(vv)) * np.cos(uu)
    y = (big_R + r * np.cos(vv)) * np.sin(uu)
    z = r * np.sin(vv)
    return np.stack([x, y, z], axis=-1).reshape(-1, 3)


def _codes(result: dict) -> set[str]:
    return {i["code"] for i in result.get("issues", [])}


# ── point clouds ─────────────────────────────────────────────────────────────


def test_dense_arch_scores_good_without_false_issues():
    res = validate_scan_bytes(_ply_ascii(_arch()), filename="arch.ply")
    assert res["result"] == "good"
    assert _codes(res) == {"point_cloud"}  # the "can't check holes" note only
    assert res["prompt_rescan"] is False


def test_arch_is_orientation_invariant():
    """Rotating the scan must not change the result."""
    pts = _arch()
    c, s = np.cos(0.7), np.sin(0.7)
    rot = np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])
    tilt = np.array([[1.0, 0.0, 0.0], [0.0, np.cos(0.5), -np.sin(0.5)], [0.0, np.sin(0.5), np.cos(0.5)]])
    a = validate_scan_bytes(_ply_ascii(pts), filename="a.ply")
    b = validate_scan_bytes(_ply_ascii(pts @ rot.T @ tilt.T), filename="b.ply")
    assert a["result"] == b["result"] == "good"
    assert abs(a["stats"]["planarity"] - b["stats"]["planarity"]) < 1e-6


def test_missing_tooth_with_gum_is_not_flagged():
    """Anatomy is never a defect: a sector with only the low gum surface left
    (a missing tooth) is still one continuous scan."""
    pts = _arch()
    u = np.arctan2(pts[:, 1], pts[:, 0])
    tooth = (u > 0.45 * np.pi) & (u < 0.55 * np.pi) & (pts[:, 2] > 0)
    res = validate_scan_bytes(_ply_ascii(pts[~tooth]), filename="missing-tooth.ply")
    assert res["result"] == "good"
    assert _codes(res) == {"point_cloud"}


def test_unusual_shape_is_not_flagged():
    """A long narrow scan is a shape, not a recording failure."""
    rng = np.random.default_rng(1)
    x = rng.uniform(0.0, 120.0, size=(20000,))
    ang = rng.uniform(0.0, 2 * np.pi, size=len(x))
    tube = np.column_stack([x, 3.0 * np.cos(ang), 3.0 * np.sin(ang)])
    res = validate_scan_bytes(_ply_ascii(tube), filename="tube.ply")
    assert res["result"] == "good"


def test_missing_sector_with_no_surface_flags_split():
    """No surface at all across a sector: the scan never joined up."""
    pts = _arch()
    u = np.arctan2(pts[:, 1], pts[:, 0])
    keep = (u < 0.45 * np.pi) | (u > 0.55 * np.pi)
    res = validate_scan_bytes(_ply_ascii(pts[keep]), filename="gapped.ply")
    assert "split" in _codes(res)
    assert res["result"] == "bad" and res["prompt_rescan"] is True


def test_collapsed_plane_flags_flat_export():
    rng = np.random.default_rng(0)
    xy = rng.uniform(-20, 20, size=(20000, 2))
    flat = np.column_stack([xy, np.zeros(len(xy))])
    res = validate_scan_bytes(_ply_ascii(flat), filename="flat.ply")
    assert "flat_export" in _codes(res)
    assert res["result"] == "bad" and res["prompt_rescan"] is True


def test_sparse_capture_flags_sparse_and_prompts_rescan():
    res = validate_scan_bytes(_ply_ascii(_arch(n_u=18, n_v=16)), filename="sparse.ply")
    assert "sparse" in _codes(res)
    assert res["result"] == "bad" and res["prompt_rescan"] is True


def test_wrong_units_flag_wrong_size():
    """The same arch exported in metres is 0.05 units across."""
    res = validate_scan_bytes(_ply_ascii(_arch() / 1000), filename="metres.ply")
    assert "wrong_size" in _codes(res)
    assert res["result"] == "bad"


def test_noisy_point_cloud_flags_noise():
    rng = np.random.default_rng(2)
    pts = _arch()
    res = validate_scan_bytes(_ply_ascii(pts + rng.normal(0, 0.08, pts.shape)), "noisy.ply")
    assert "noisy_surface" in _codes(res)


def test_unparseable_returns_bad():
    res = validate_scan_bytes(b"not a mesh at all", filename="junk.txt")
    assert res["result"] == "bad"
    assert res["prompt_rescan"] is True


def test_reference_fixtures():
    root = Path(__file__).resolve().parents[3] / "references" / "scans"
    expected = {
        "good_dense_arch.ply": "good",
        "bad_sparse_incomplete.ply": "bad",
        "blurry_noisy_surface.ply": "bad",
        "missing_margin_flat.ply": "bad",
    }
    for name, result in expected.items():
        path = root / name
        if path.exists():
            assert validate_scan_bytes(path.read_bytes(), name)["result"] == result, name


# ── triangle meshes ──────────────────────────────────────────────────────────

_NU, _NV, _R, _r = 300, 60, 20.0, 6.0
_EDGE = _R * np.pi / (_NU - 1)
_MID = (_NU // 2) * _NV + _NV // 2  # a vertex mid-surface, away from the outer edge


def _arch_grid(noise: float = 0.0, patch_noise: float = 0.0, seed: int = 0):
    """Open half-tube arch (one outer edge, like a real scan): points, normals, faces.

    ``noise`` is displacement along the normal everywhere (fraction of edge
    length); ``patch_noise`` is extra displacement inside a 3 mm disc.
    """
    u = np.linspace(0.0, np.pi, _NU)
    v = np.linspace(np.pi, 2.0 * np.pi, _NV)  # lower half: the "occlusal" side faces down
    uu, vv = np.meshgrid(u, v, indexing="ij")
    ring = np.stack([np.cos(uu), np.sin(uu), np.zeros_like(uu)], -1)
    normal = (np.cos(vv)[..., None] * ring + np.sin(vv)[..., None] * [0, 0, 1]).reshape(-1, 3)
    pts = (_R * ring).reshape(-1, 3) + _r * normal
    rng = np.random.default_rng(seed)
    disp = rng.normal(0.0, noise * _EDGE, len(pts))
    if patch_noise:
        near = np.linalg.norm(pts - pts[_MID], axis=1) < 3.0
        disp += near * rng.normal(0.0, patch_noise * _EDGE, len(pts))
    pts = pts + normal * disp[:, None]
    faces = []
    for i in range(_NU - 1):
        for j in range(_NV - 1):
            a, b = i * _NV + j, i * _NV + j + 1
            c, d = a + _NV, b + _NV
            faces += [(a, c, b), (b, c, d)]
    return pts, normal, np.asarray(faces)


def _arch_mesh(**kw) -> bytes:
    pts, _, faces = _arch_grid(**kw)
    return _ply_mesh(pts, faces)


def _disc(pts: np.ndarray, faces: np.ndarray, radius: float) -> np.ndarray:
    """Faces with any corner within ``radius`` mm of the arch's midpoint."""
    near = np.linalg.norm(pts - pts[_MID], axis=1) < radius
    return near[faces].any(axis=1)


def test_clean_mesh_is_good():
    res = validate_scan_bytes(_arch_mesh(noise=0.02), "arch.ply")
    assert res["result"] == "good" and _codes(res) == set()
    assert res["rough_points"] == []


def test_mesh_with_scanner_level_noise_is_not_flagged_rough():
    res = validate_scan_bytes(_arch_mesh(noise=0.02), "arch.ply")
    assert not _codes(res) & {"rough_surface", "noisy_surface"}
    assert res["stats"]["rough_area_pct"] < 0.35


def test_local_rough_patch_flags_rough_surface():
    res = validate_scan_bytes(_arch_mesh(noise=0.02, patch_noise=0.3), "arch.ply")
    assert "rough_surface" in _codes(res)
    assert res["result"] != "good"
    # Highlight points cluster on the 6 mm noisy disc, not across the arch.
    pts = np.asarray(res["rough_points"])
    assert len(pts) > 0 and res["rough_radius"] > 0
    assert np.ptp(pts, axis=0).max() < 8.0


def test_uniform_noise_flags_noisy_surface():
    res = validate_scan_bytes(_arch_mesh(noise=0.2), "arch.ply")
    assert "noisy_surface" in _codes(res)
    assert res["result"] != "good"


def test_point_cloud_skips_mesh_only_checks():
    res = validate_scan_bytes(_ply_ascii(_arch()), "arch.ply")
    assert "rough_area_pct" not in res["stats"]
    assert "patched_area_pct" not in res["stats"]


def test_open_hole_flags_holes_and_marks_it():
    pts, _, faces = _arch_grid(noise=0.02)
    res = validate_scan_bytes(_ply_mesh(pts, faces[~_disc(pts, faces, 1.5)]), "holed.ply")
    issue = next(i for i in res["issues"] if i["code"] == "holes")
    assert issue["severity"] == "high"  # ~3 mm wide
    assert res["result"] == "bad"
    marked = np.asarray(res["rough_points"])
    assert np.linalg.norm(marked - pts[_MID], axis=1).max() < 4.0


def test_small_open_hole_is_review():
    pts, _, faces = _arch_grid(noise=0.02)
    res = validate_scan_bytes(_ply_mesh(pts, faces[~_disc(pts, faces, 0.4)]), "small-hole.ply")
    assert "holes" in _codes(res) and res["result"] == "review"
    assert res["prompt_rescan"] is False


def test_filled_in_hole_flags_patched_holes():
    """Scanner software bridges a missed area with a fan of big triangles."""
    pts, _, faces = _arch_grid(noise=0.02)
    cut = _disc(pts, faces, 3.0)
    kept = faces[~cut]
    # Fan the cut's rim to one new centre vertex.
    E = np.sort(np.concatenate([kept[:, [0, 1]], kept[:, [1, 2]], kept[:, [2, 0]]]), axis=1)
    rim, n = np.unique(E, axis=0, return_counts=True)
    rim = rim[n == 1]
    rim = rim[np.linalg.norm(pts[rim[:, 0]] - pts[_MID], axis=1) < 5.0]
    centre = len(pts)
    fan = np.column_stack([rim, np.full(len(rim), centre)])
    res = validate_scan_bytes(
        _ply_mesh(np.vstack([pts, pts[_MID]]), np.vstack([kept, fan])), "filled.ply"
    )
    assert "patched_holes" in _codes(res)
    assert "holes" not in _codes(res)  # the fill closed it
    assert res["result"] == "bad"


def test_cut_across_the_arch_flags_split():
    pts, _, faces = _arch_grid(noise=0.02)
    mid = (_NU // 2) * _NV
    cut = (faces >= mid).any(axis=1) & (faces < mid + _NV).any(axis=1)
    res = validate_scan_bytes(_ply_mesh(pts, faces[~cut]), "split.ply")
    assert "split" in _codes(res) and res["result"] == "bad"


def test_floating_fragment_flags_loose_fragments():
    pts, _, faces = _arch_grid(noise=0.02)
    g = np.stack(np.meshgrid(np.linspace(0, 2, 12), np.linspace(0, 2, 12)), -1).reshape(-1, 2)
    frag = np.column_stack([g, np.full(len(g), 15.0)])  # 4 mm² flap well off the arch
    ff = []
    for i in range(11):
        for j in range(11):
            a = i * 12 + j
            ff += [(a, a + 12, a + 1), (a + 1, a + 12, a + 13)]
    res = validate_scan_bytes(
        _ply_mesh(np.vstack([pts, frag]), np.vstack([faces, np.asarray(ff) + len(pts)])), "frag.ply"
    )
    assert "loose_fragments" in _codes(res)
    assert res["result"] == "review"


def test_ghost_layer_flags_double_layer():
    """A second copy of a patch 0.2 mm off the surface, facing the same way."""
    pts, normal, faces = _arch_grid(noise=0.02)
    sel = _disc(pts, faces, 3.0)
    ids = np.unique(faces[sel])
    remap = np.full(len(pts), -1)
    remap[ids] = np.arange(len(ids)) + len(pts)
    ghost = pts[ids] + 0.2 * normal[ids]
    res = validate_scan_bytes(
        _ply_mesh(np.vstack([pts, ghost]), np.vstack([faces, remap[faces[sel]]])), "ghost.ply"
    )
    assert "double_layer" in _codes(res)
    assert res["result"] != "good"


def _bite_pair(overlap: float) -> tuple[bytes, bytes]:
    """Upper arch faces down; the lower is its mirror, raised to ``overlap`` mm into it."""
    pts, _, faces = _arch_grid(noise=0.02)
    lower = pts * [1, 1, -1] - [0, 0, 2 * _r - overlap]
    return _ply_mesh(pts, faces), _ply_mesh(lower, faces[:, ::-1])


def test_overlapping_bite_flags_both_arches():
    upper, lower = _bite_pair(overlap=1.0)
    for own, other in ((upper, lower), (lower, upper)):
        res = validate_scan_bytes(own, "u.ply", opposing=(other, "l.ply"))
        assert "bite_overlap" in _codes(res), res["stats"]
        assert res["result"] == "review"


def test_touching_bite_is_not_flagged():
    upper, lower = _bite_pair(overlap=-0.1)
    res = validate_scan_bytes(upper, "u.ply", opposing=(lower, "l.ply"))
    assert "bite_overlap" not in _codes(res)
    assert res["result"] == "good"

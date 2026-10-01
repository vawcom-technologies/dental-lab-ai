"""Tests for dentist-edited outline → mask → zone re-match."""

from __future__ import annotations

import numpy as np

from app.ai.shade import VITA_SHADES
from app.ai.shade_analyze import analyze_tooth_from_outline_rgb
from app.ai.shade_geometry import (
    EDIT_HANDLES_MAX,
    EDIT_HANDLES_MIN,
    anatomical_edit_handles_from_mask,
    mask_from_normalized_outline,
    simplify_normalized_outline,
    tooth_display_geometry,
)


def test_simplify_keeps_few_edit_handles():
    # Dense ring → explicit low budget still honored
    outline = []
    for i in range(24):
        t = 2 * np.pi * i / 24
        outline.append([0.5 + 0.2 * np.cos(t), 0.5 + 0.25 * np.sin(t)])
    simple = simplify_normalized_outline(outline, max_points=6, min_points=4)
    assert 4 <= len(simple) <= 6


def test_simplify_default_matches_chairside_budget():
    outline = []
    for i in range(36):
        t = 2 * np.pi * i / 36
        outline.append([0.5 + 0.22 * np.cos(t), 0.5 + 0.28 * np.sin(t)])
    simple = simplify_normalized_outline(outline)
    assert EDIT_HANDLES_MIN <= len(simple) <= EDIT_HANDLES_MAX


def test_mask_from_outline_covers_rectangle():
    h, w = 100, 100
    outline = [[0.2, 0.2], [0.6, 0.2], [0.6, 0.7], [0.2, 0.7]]
    mask = mask_from_normalized_outline(outline, height=h, width=w)
    assert int(mask.sum()) > 500
    assert not mask[10, 10]
    assert mask[40, 40]


def test_analyze_tooth_from_edited_outline_returns_zones():
    h, w = 400, 600
    img = np.zeros((h, w, 3), dtype=np.uint8)
    img[:] = (40, 28, 26)
    enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
    img[140:280, 220:300] = enamel
    # Sparse 4-point edited skeleton
    outline = [
        [220 / w, 140 / h],
        [300 / w, 140 / h],
        [300 / w, 280 / h],
        [220 / w, 280 / h],
    ]
    out = analyze_tooth_from_outline_rgb(img, outline, tooth_index=2)
    tooth = out["tooth"]
    assert tooth["tooth_index"] == 2
    assert tooth.get("outline_edited") is True
    assert tooth["geometry"]["edited"] is True
    assert len(tooth["geometry"]["outline"]) >= 4
    assert (
        EDIT_HANDLES_MIN
        <= len(tooth["geometry"]["edit_handles"])
        <= EDIT_HANDLES_MAX
    )
    middle = tooth["zones"]["middle"]
    assert middle["detected_shade"] is not None
    assert middle["override_shade"] is None


def test_dense_curved_outline_not_collapsed_to_handles():
    """Apply path densifies Beziers; display outline must keep those points."""
    h, w = 200, 200
    img = np.zeros((h, w, 3), dtype=np.uint8)
    img[:] = (40, 28, 26)
    enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
    img[60:140, 70:130] = enamel

    # Dense top-edge bulge (many samples along a curve).
    dense = [[70 / w, 60 / h]]
    for i in range(1, 16):
        t = i / 16
        # Quadratic bulge upward from left→right top edge
        y = 60 / h - 0.08 * 4 * t * (1 - t)
        x = (70 + (130 - 70) * t) / w
        dense.append([x, y])
    dense.extend(
        [
            [130 / w, 60 / h],
            [130 / w, 140 / h],
            [70 / w, 140 / h],
        ]
    )
    assert len(dense) >= 18

    handles = simplify_normalized_outline(dense, max_points=6, min_points=4)
    assert len(handles) <= 6
    mask_dense = mask_from_normalized_outline(dense, height=h, width=w)
    mask_handles = mask_from_normalized_outline(handles, height=h, width=w)
    # Straightened handles miss some bulge pixels the dense ring covers.
    assert int(mask_dense.sum()) > int(mask_handles.sum())

    out = analyze_tooth_from_outline_rgb(img, dense, tooth_index=0)
    geo = out["tooth"]["geometry"]
    assert len(geo["outline"]) >= 18  # densified polyline kept, not sparse handles
    assert EDIT_HANDLES_MIN <= len(geo["edit_handles"]) <= EDIT_HANDLES_MAX
    assert geo["outline"] == dense
    assert geo["axis"] is not None and len(geo["axis"]) == 2
    assert isinstance(geo["width_ticks"], list)


def test_display_outline_is_moderate_for_rounded_mask():
    h, w = 200, 160
    yy, xx = np.ogrid[:h, :w]
    mask = ((xx - 80) / 50) ** 2 + ((yy - 100) / 80) ** 2 <= 1.0
    geo = tooth_display_geometry(mask)
    assert geo is not None
    assert 96 <= len(geo["outline"]) <= 160
    # Even spacing around an ellipse — no long flat chords.
    ring = geo["outline"]
    chords = [
        (ring[i][0] - ring[(i + 1) % len(ring)][0]) ** 2
        + (ring[i][1] - ring[(i + 1) % len(ring)][1]) ** 2
        for i in range(len(ring))
    ]
    assert max(chords) < 0.08
    assert EDIT_HANDLES_MIN <= len(geo["edit_handles"]) <= EDIT_HANDLES_MAX


def test_display_fairing_reduces_stair_step_turn_energy():
    """Pixel stairs should soften; analysis mask bytes stay unchanged."""
    from app.ai.shade_geometry import fair_mask_for_display, normalized_display_outline

    h, w = 80, 60
    mask = np.zeros((h, w), dtype=bool)
    # Blocky "crown" with intentional stair edges.
    mask[10:70, 15:45] = True
    for i in range(12):
        mask[20 + i, 45 + (i % 3)] = True
        mask[20 + i, 14 - (i % 3)] = True
    before = mask.copy()
    faired = fair_mask_for_display(mask)
    assert np.array_equal(mask, before)
    assert int(faired.sum()) >= int(0.55 * int(mask.sum()))

    raw = normalized_display_outline(mask)
    assert raw is not None and len(raw) >= 96

    def turn_energy(ring: list[list[float]]) -> float:
        n = len(ring)
        e = 0.0
        for i in range(n):
            a = np.asarray(ring[i], dtype=np.float64)
            b = np.asarray(ring[(i + 1) % n], dtype=np.float64)
            c = np.asarray(ring[(i + 2) % n], dtype=np.float64)
            v1 = b - a
            v2 = c - b
            n1 = float(np.linalg.norm(v1))
            n2 = float(np.linalg.norm(v2))
            if n1 < 1e-12 or n2 < 1e-12:
                continue
            cross = abs(v1[0] * v2[1] - v1[1] * v2[0]) / (n1 * n2)
            e += cross
        return e

    # Compare faired ring vs contour taken from the raw mask without fairing.
    import cv2
    from app.ai.shade_geometry import (
        DISPLAY_OUTLINE_MAX,
        _even_sample_closed,
        _poly_norm,
    )

    u8 = (mask.astype(np.uint8)) * 255
    contours, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    cnt = max(contours, key=cv2.contourArea)
    jagged = _even_sample_closed(_poly_norm(cnt, w, h), DISPLAY_OUTLINE_MAX)
    assert turn_energy(raw) < turn_energy(jagged)


def test_anatomical_handles_cover_extremes():
    h, w = 200, 120
    yy, xx = np.ogrid[:h, :w]
    # Tall ellipse — cervical/incisal + left/right should appear as landmarks.
    mask = ((xx - 60) / 35) ** 2 + ((yy - 100) / 75) ** 2 <= 1.0
    handles = anatomical_edit_handles_from_mask(mask)
    assert EDIT_HANDLES_MIN <= len(handles) <= EDIT_HANDLES_MAX
    xs = [p[0] for p in handles]
    ys = [p[1] for p in handles]
    assert min(xs) < 0.4
    assert max(xs) > 0.6
    assert min(ys) < 0.4
    assert max(ys) > 0.6


def test_clinical_overlay_marks_match_reference_layout():
    """Purple box + yellow long axis + horizontal width ticks per crown."""
    h, w = 200, 120
    yy, xx = np.ogrid[:h, :w]
    mask = ((xx - 60) / 32) ** 2 + ((yy - 100) / 72) ** 2 <= 1.0
    geo = tooth_display_geometry(mask)
    assert geo is not None
    axis = geo["axis"]
    assert axis is not None and len(axis) == 2
    # Cervical → incisal is mostly vertical (x nearly constant, y increases).
    assert abs(axis[0][0] - axis[1][0]) < 0.08
    assert axis[1][1] > axis[0][1]
    ticks = geo["width_ticks"]
    assert 2 <= len(ticks) <= 3
    for a, b in ticks:
        assert abs(a[1] - b[1]) < 0.08
        assert abs(a[0] - b[0]) > 0.15
    ys, xs = np.nonzero(mask)
    bbox = geo["bbox"]
    assert bbox["x"] * w <= float(xs.min()) - 1
    assert (bbox["x"] + bbox["w"]) * w >= float(xs.max()) + 1
    assert bbox["y"] * h <= float(ys.min()) - 1
    assert (bbox["y"] + bbox["h"]) * h >= float(ys.max()) + 1


def test_display_outline_smooths_kaist_stairs_without_shrinking():
    """A 4 px-stair disc (KAIST upscaled 4×) comes out smooth, same size."""
    from app.ai.shade_geometry import normalized_display_outline

    def zigzag(ring):  # total turning / 2π: 1.0 = smooth convex loop
        v = np.diff(np.vstack([ring, ring[:1]]), axis=0)
        a = np.arctan2(v[:, 1], v[:, 0])
        return float(np.abs(np.angle(np.exp(1j * (np.roll(a, -1) - a)))).sum() / (2 * np.pi))

    yy, xx = np.mgrid[:200, :200]
    coarse = ((yy // 4 * 4 - 100) ** 2 + (xx // 4 * 4 - 100) ** 2) <= 70**2
    ring = np.asarray(normalized_display_outline(coarse, px_scale=4)) * 200
    r = np.hypot(ring[:, 0] - 100, ring[:, 1] - 100)
    assert abs(float(r.mean()) - 70) < 1.0  # no shrink
    assert zigzag(ring) < 2.0  # raw 4 px stairs: ~8


def test_smoothing_is_even_for_small_and_large_kaist_teeth():
    """Same KAIST stairs on a small and a 3× larger tooth → equally smooth."""
    import cv2

    from app.ai.shade_geometry import normalized_display_outline

    def zigzag(ring):
        v = np.diff(np.vstack([ring, ring[:1]]), axis=0)
        a = np.arctan2(v[:, 1], v[:, 0])
        return float(np.abs(np.angle(np.exp(1j * (np.roll(a, -1) - a)))).sum() / (2 * np.pi))

    def kaist_tooth(work_w, scale):
        work = np.zeros((work_w * 2, work_w * 2), np.uint8)
        cv2.ellipse(work, (work_w, work_w), (work_w // 2, int(work_w * 0.7)), 0, 0, 360, 1, -1)
        big = cv2.resize(work, None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST)
        return normalized_display_outline(big.astype(bool), px_scale=scale)

    small = zigzag(np.asarray(kaist_tooth(20, 4)))  # 20 KAIST px wide
    large = zigzag(np.asarray(kaist_tooth(60, 4)))  # 60 KAIST px wide
    assert small < 1.6 and large < 1.6

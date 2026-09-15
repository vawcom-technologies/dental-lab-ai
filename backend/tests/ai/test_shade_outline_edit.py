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
    assert 24 <= len(geo["outline"]) <= 48
    # Even spacing around an ellipse — no long flat chords.
    ring = geo["outline"]
    chords = [
        (ring[i][0] - ring[(i + 1) % len(ring)][0]) ** 2
        + (ring[i][1] - ring[(i + 1) % len(ring)][1]) ** 2
        for i in range(len(ring))
    ]
    assert max(chords) < 0.08
    assert EDIT_HANDLES_MIN <= len(geo["edit_handles"]) <= EDIT_HANDLES_MAX


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

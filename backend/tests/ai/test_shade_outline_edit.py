"""Tests for dentist-edited outline → mask → zone re-match."""

from __future__ import annotations

import numpy as np

from app.ai.shade import VITA_SHADES
from app.ai.shade_analyze import analyze_tooth_from_outline_rgb
from app.ai.shade_geometry import mask_from_normalized_outline, simplify_normalized_outline


def test_simplify_keeps_few_edit_handles():
    # Dense ring → ~4–6 control points for editing
    outline = []
    for i in range(24):
        t = 2 * np.pi * i / 24
        outline.append([0.5 + 0.2 * np.cos(t), 0.5 + 0.25 * np.sin(t)])
    simple = simplify_normalized_outline(outline, max_points=6, min_points=4)
    assert 4 <= len(simple) <= 6


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
    assert 4 <= len(tooth["geometry"]["outline"]) <= 6
    middle = tooth["zones"]["middle"]
    assert middle["detected_shade"] is not None
    assert middle["override_shade"] is None

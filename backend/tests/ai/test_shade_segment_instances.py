"""Instance separation / boundary / config-toggle tests for shade_segment."""

from __future__ import annotations

import numpy as np

from app.ai.shade import VITA_SHADES
from app.ai.shade_segment import (
    SegmentConfig,
    _split_instances_watershed,
    detect_teeth,
    with_config,
)
from app.ai.shade_segment_viz import render_instance_overlay, save_debug_panel


def _touching_anterior(h: int = 400, w: int = 600, n: int = 4, tooth_w: int = 48) -> np.ndarray:
    """n enamel blocks that touch with NO pixel gap — classic under-seg case.

    Interdental contacts have a short vertical neck (realistic pinch), so
    distance-transform / opening can find instance markers.
    """
    img = np.zeros((h, w, 3), dtype=np.uint8)
    img[:] = (40, 28, 26)
    gum = np.array([180, 110, 120], dtype=np.uint8)
    img[int(h * 0.30) : int(h * 0.42), int(w * 0.12) : int(w * 0.88)] = gum
    enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
    x0 = 160
    y0, y1 = int(h * 0.42), int(h * 0.62)
    # Draw each crown; contacts share a thin mid-height neck only
    for i in range(n):
        x = x0 + i * tooth_w
        img[y0:y1, x : x + tooth_w] = enamel
    for i in range(n - 1):
        joint = x0 + (i + 1) * tooth_w - 1
        # Carve deep V-notches at gingiva + incisal so only a neck remains
        img[y0 : y0 + 18, joint - 1 : joint + 2] = gum
        img[y1 - 18 : y1, joint - 1 : joint + 2] = (40, 28, 26)
    return img


def _gapped_smile(h: int = 400, w: int = 600) -> np.ndarray:
    img = np.zeros((h, w, 3), dtype=np.uint8)
    img[:] = (40, 28, 26)
    gum = np.array([180, 110, 120], dtype=np.uint8)
    img[int(h * 0.30) : int(h * 0.42), int(w * 0.12) : int(w * 0.88)] = gum
    enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
    for x0 in (180, 250, 320, 390):
        img[int(h * 0.42) : int(h * 0.62), x0 : x0 + 50] = enamel
    return img


class TestWatershedInstanceSplit:
    def test_watershed_splits_touching_binary_blob(self):
        # Two lobes connected by a thin neck
        u8 = np.zeros((80, 160), dtype=np.uint8)
        u8[15:65, 20:70] = 255
        u8[15:65, 90:140] = 255
        u8[35:50, 70:90] = 255  # neck
        parts = _split_instances_watershed(u8)
        assert len(parts) >= 2

    def test_touching_teeth_not_merged_with_watershed(self):
        img = _touching_anterior(n=4)
        teeth = [t for t in detect_teeth(img) if not t.rejected]
        # Primary fix: should recover ~4 instances, not 1 merged arch
        assert 3 <= len(teeth) <= 5

    def test_watershed_off_merges_or_undercounts_touching(self):
        img = _touching_anterior(n=4)
        cfg = with_config(watershed_split=False, valley_split=False)
        teeth = [t for t in detect_teeth(img, config=cfg) if not t.rejected]
        # Without any split step, touching enamel → one (or very few) CC(s)
        assert len(teeth) <= 2


class TestArchAndDtMarkers:
    def test_arch_curve_keeps_row_drops_outlier(self):
        from app.ai.shade_segment import _filter_by_arch_curve

        h, w = 80, 200
        comps = []
        for i, cx in enumerate((40, 80, 120, 160)):
            m = np.zeros((h, w), dtype=bool)
            m[30:55, cx - 12 : cx + 12] = True
            comps.append(m)
        # Off-arch blob above the smile
        junk = np.zeros((h, w), dtype=bool)
        junk[5:18, 90:110] = True
        comps.append(junk)
        kept = _filter_by_arch_curve(comps)
        assert len(kept) == 4

    def test_default_pipeline_still_finds_gapped_teeth(self):
        img = _gapped_smile()
        teeth = [t for t in detect_teeth(img) if not t.rejected]
        assert 3 <= len(teeth) <= 7
    def test_masks_avoid_heavy_gum_overlap(self):
        img = _gapped_smile()
        teeth = detect_teeth(img)
        assert len(teeth) >= 1
        gum_y0, gum_y1 = int(400 * 0.30), int(400 * 0.40)
        for t in teeth:
            if t.rejected:
                continue
            gum_overlap = int(t.mask[gum_y0:gum_y1, :].sum())
            tooth_area = int(t.mask.sum())
            assert tooth_area > 0
            assert gum_overlap / tooth_area < 0.10

    def test_sanity_flags_when_enabled(self):
        img = _gapped_smile()
        on = detect_teeth(img, config=with_config(sanity_reject=True))
        off = detect_teeth(img, config=with_config(sanity_reject=False))
        assert len(on) == len(off)

    def test_grabcut_toggle_still_returns_teeth(self):
        img = _gapped_smile()
        on = [t for t in detect_teeth(img, config=with_config(grabcut_refine=True)) if not t.rejected]
        off = [
            t
            for t in detect_teeth(img, config=with_config(grabcut_refine=False))
            if not t.rejected
        ]
        assert len(on) >= 3
        assert len(off) >= 3

    def test_contact_valley_stronger_across_gap_than_inside_tooth(self):
        from app.ai.shade_segment import _contact_valley_strength

        img = _gapped_smile()
        # Two separate teeth vs two halves of one tooth
        h, w = 400, 600
        a = np.zeros((h, w), dtype=bool)
        b = np.zeros((h, w), dtype=bool)
        a[int(h * 0.42) : int(h * 0.62), 180:230] = True
        b[int(h * 0.42) : int(h * 0.62), 250:300] = True  # real gap
        v_gap = _contact_valley_strength(img.astype(float), a, b)
        c = np.zeros((h, w), dtype=bool)
        d = np.zeros((h, w), dtype=bool)
        c[int(h * 0.42) : int(h * 0.62), 320:345] = True
        d[int(h * 0.42) : int(h * 0.62), 345:370] = True  # adjacent halves, no dark seam
        v_half = _contact_valley_strength(img.astype(float), c, d)
        assert v_gap > v_half


class TestDebugOverlay:
    def test_overlay_has_distinct_colors_per_instance(self):
        img = _gapped_smile()
        teeth = [t for t in detect_teeth(img) if not t.rejected]
        assert len(teeth) >= 2
        overlay = render_instance_overlay(img, teeth, alpha=0.9, draw_labels=False)
        # Sample a pixel from each tooth — colors should differ
        colors = []
        for t in teeth[:3]:
            ys, xs = np.nonzero(t.mask)
            colors.append(tuple(int(c) for c in overlay[ys[len(ys) // 2], xs[len(xs) // 2]]))
        assert len(set(colors)) >= 2

    def test_save_debug_panel_writes_png(self, tmp_path):
        img = _touching_anterior(n=3)
        out = save_debug_panel(img, tmp_path / "seg_debug.png", also_compare_no_watershed=True)
        assert out.exists()
        assert out.stat().st_size > 1000

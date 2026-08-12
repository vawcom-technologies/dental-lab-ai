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


def _open_mouth_dual_arch(h: int = 480, w: int = 640) -> np.ndarray:
    """Upper + lower anterior rows with a dark oral cavity between (open mouth).

    Without dual-arch split, a vertical stack of opposing crowns can become one
    tall instance (clinic T5 failure).
    """
    img = np.zeros((h, w, 3), dtype=np.uint8)
    img[:] = (25, 18, 16)  # dark oral cavity / lips
    gum = np.array([180, 110, 120], dtype=np.uint8)
    enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)

    # Upper gum + crowns
    img[int(h * 0.18) : int(h * 0.28), int(w * 0.15) : int(w * 0.85)] = gum
    upper_y0, upper_y1 = int(h * 0.28), int(h * 0.42)
    for x0 in (170, 240, 310, 380):
        img[upper_y0:upper_y1, x0 : x0 + 55] = enamel

    # Dark gap (open mouth) — critical
    # (already dark background)

    # Lower gum + crowns (opposing)
    lower_y0, lower_y1 = int(h * 0.58), int(h * 0.72)
    img[int(h * 0.72) : int(h * 0.82), int(w * 0.15) : int(w * 0.85)] = gum
    for x0 in (175, 245, 315, 385):
        img[lower_y0:lower_y1, x0 : x0 + 55] = enamel

    # Intentionally connect one upper+lower pair with a thin enamel bridge
    # (simulates leakage that used to produce a tall merged mask).
    bridge_x0, bridge_x1 = 318, 328
    img[upper_y1:lower_y0, bridge_x0:bridge_x1] = enamel
    return img


class TestDualArchSplit:
    def test_dual_arch_cut_severs_horizontal_gap(self):
        from app.ai.shade_segment import (
            _adaptive_enamel_mask,
            _dental_roi_from_enamel,
            _split_dual_arches,
        )

        img = _open_mouth_dual_arch()
        enamel = _adaptive_enamel_mask(img.astype(float))
        y0, y1, x0, x1 = _dental_roi_from_enamel(enamel)
        band = enamel[y0:y1, x0:x1]
        u8 = (band.astype(np.uint8)) * 255
        luma = (
            0.299 * img[y0:y1, x0:x1, 0]
            + 0.587 * img[y0:y1, x0:x1, 1]
            + 0.114 * img[y0:y1, x0:x1, 2]
        )
        # Bridge should exist in ROI before cut
        bridge_local_x0 = 318 - x0
        bridge_local_x1 = 328 - x0
        mid_y0 = int(0.45 * img.shape[0]) - y0
        mid_y1 = int(0.55 * img.shape[0]) - y0
        assert mid_y0 >= 0 and mid_y1 <= band.shape[0]
        assert int((u8[mid_y0:mid_y1, bridge_local_x0:bridge_local_x1] > 0).sum()) > 0
        cut = _split_dual_arches(u8, luminance=luma.astype(float))
        assert int((cut[mid_y0:mid_y1, bridge_local_x0:bridge_local_x1] > 0).sum()) == 0

    def test_open_mouth_does_not_merge_upper_lower_into_tall_tooth(self):
        img = _open_mouth_dual_arch()
        teeth = [t for t in detect_teeth(img) if not t.rejected]
        # Expect teeth from both arches (not a single tall stack).
        assert len(teeth) >= 6
        cys = []
        heights = []
        widths = []
        for t in teeth:
            ys, xs = np.nonzero(t.mask)
            cys.append(float(ys.mean()))
            heights.append(int(ys.max() - ys.min() + 1))
            widths.append(int(xs.max() - xs.min() + 1))
        # Both arches present
        assert max(cys) - min(cys) > 0.2 * img.shape[0]
        # No instance should span most of the open-mouth height.
        assert max(heights) < 0.40 * img.shape[0]
        # Anteriors are naturally tall/narrow — guard span, not aspect alone.
        for ht, wd in zip(heights, widths):
            assert ht < 0.22 * img.shape[0] + 12 or ht < 3.8 * max(wd, 1)

    def test_single_arch_still_works(self):
        img = _gapped_smile()
        teeth = [t for t in detect_teeth(img) if not t.rejected]
        assert 3 <= len(teeth) <= 7

    def test_clinic_like_bridged_arches_cut_inside_enamel_band(self):
        """Wide enamel leakage + lips above — gap must be mid-band, not lip strip."""
        from app.ai.shade_segment import (
            _adaptive_enamel_mask,
            _dental_roi_from_enamel,
            _find_occlusal_gap,
            _luma_rgb,
        )

        img = _open_mouth_dual_arch()
        # Thicken the bridge so enamel row never hits zero between arches.
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        img[int(img.shape[0] * 0.42) : int(img.shape[0] * 0.58), 300:340] = enamel
        # Bright lip strip above (false second "peak" for naive ROI search).
        img[int(img.shape[0] * 0.05) : int(img.shape[0] * 0.12), :] = (220, 170, 160)

        mask = _adaptive_enamel_mask(img.astype(float))
        y0, y1, x0, x1 = _dental_roi_from_enamel(mask)
        u8 = (mask[y0:y1, x0:x1].astype(np.uint8)) * 255
        lum = _luma_rgb(img[y0:y1, x0:x1].astype(float))
        gap = _find_occlusal_gap(u8, luminance=lum)
        assert gap is not None
        y_a, y_b = gap
        # Cut must sit between upper crowns (~0.28–0.42) and lower (~0.58–0.72).
        mid = 0.5 * (y_a + y_b) + y0
        assert 0.42 * img.shape[0] <= mid <= 0.58 * img.shape[0]

        teeth = [t for t in detect_teeth(img) if not t.rejected]
        assert len(teeth) >= 6
        for t in teeth:
            ys, xs = np.nonzero(t.mask)
            ht = int(ys.max() - ys.min() + 1)
            assert ht < 0.40 * img.shape[0]
            # Must not straddle both synthetic arch rows.
            cy = float(ys.mean())
            upper = 0.28 * img.shape[0] <= cy <= 0.45 * img.shape[0]
            lower = 0.55 * img.shape[0] <= cy <= 0.75 * img.shape[0]
            assert upper or lower


class TestLipAboveSmile:
    def test_bright_blob_above_crowns_is_dropped(self):
        """Upper-lip gloss must not become T1 on camera frontal crops."""
        from app.ai.shade_segment import _drop_lip_above_smile

        rows = [
            {
                "mask": None,
                "cy": 40.0,
                "cx": 100.0,
                "y0": 20.0,
                "h": 30.0,
                "w": 40.0,
                "area": 800,
                "med_a": 7.0,
                "med_L": 190.0,
            },
            {
                "mask": None,
                "cy": 120.0,
                "cx": 80.0,
                "y0": 90.0,
                "h": 60.0,
                "w": 35.0,
                "area": 1800,
                "med_a": 3.0,
                "med_L": 210.0,
            },
            {
                "mask": None,
                "cy": 118.0,
                "cx": 130.0,
                "y0": 88.0,
                "h": 58.0,
                "w": 36.0,
                "area": 1700,
                "med_a": 2.5,
                "med_L": 208.0,
            },
            {
                "mask": None,
                "cy": 122.0,
                "cx": 180.0,
                "y0": 92.0,
                "h": 55.0,
                "w": 34.0,
                "area": 1600,
                "med_a": 3.2,
                "med_L": 205.0,
            },
        ]
        kept = _drop_lip_above_smile(rows, band_h=220)
        assert len(kept) == 3
        assert all(d["cy"] > 100 for d in kept)


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

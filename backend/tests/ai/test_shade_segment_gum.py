"""Tests: avoid splitting one tooth into two; keep gum exclusion."""

from __future__ import annotations

import numpy as np

from app.ai.shade import VITA_SHADES
from app.ai.shade_segment import _enamel_only_mask, _split_arch_by_deep_valleys, detect_teeth


def _smile_with_gums(h: int = 400, w: int = 600) -> np.ndarray:
    img = np.zeros((h, w, 3), dtype=np.uint8)
    img[:] = (40, 28, 26)
    gum = np.array([180, 110, 120], dtype=np.uint8)
    img[int(h * 0.30) : int(h * 0.42), int(w * 0.12) : int(w * 0.88)] = gum
    enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
    for x0 in (180, 250, 320, 390):
        img[int(h * 0.42) : int(h * 0.62), x0 : x0 + 50] = enamel
    return img


def _one_wide_tooth(h: int = 400, w: int = 600) -> np.ndarray:
    """Single continuous enamel block (should stay 1 tooth, not 2)."""
    img = np.zeros((h, w, 3), dtype=np.uint8)
    img[:] = (35, 25, 22)
    enamel = np.array(VITA_SHADES["A1"], dtype=np.uint8)
    # One wide central tooth with a slight mid dip in luminance (not a real gap)
    img[int(h * 0.40) : int(h * 0.62), 250:370] = enamel
    img[int(h * 0.42) : int(h * 0.60), 300:320] = np.array(VITA_SHADES["A2"], dtype=np.uint8)
    return img


class TestGumExclusion:
    def test_enamel_mask_rejects_pink_gingiva_pixels(self):
        band = np.zeros((40, 40, 3), dtype=np.float64)
        band[:] = (185, 105, 115)
        mask = _enamel_only_mask(band)
        assert int(mask.sum()) == 0

    def test_enamel_mask_keeps_bright_enamel(self):
        band = np.zeros((40, 40, 3), dtype=np.float64)
        band[:] = VITA_SHADES["A2"]
        mask = _enamel_only_mask(band)
        assert int(mask.sum()) > 1000

    def test_detect_teeth_masks_do_not_cover_gum_shelf(self):
        img = _smile_with_gums()
        teeth = detect_teeth(img)
        assert len(teeth) >= 1
        gum_y0, gum_y1 = int(400 * 0.30), int(400 * 0.40)
        for t in teeth:
            gum_overlap = int(t.mask[gum_y0:gum_y1, :].sum())
            tooth_area = int(t.mask.sum())
            assert tooth_area > 0
            assert gum_overlap / tooth_area < 0.08


class TestNoOverSegmentation:
    def test_single_wide_tooth_not_split_in_two(self):
        img = _one_wide_tooth()
        teeth = [t for t in detect_teeth(img) if not t.rejected]
        assert len(teeth) == 1

    def test_shallow_valley_does_not_cut(self):
        # Solid bar: projection has no deep valley
        u8 = np.zeros((80, 200), dtype=np.uint8)
        u8[10:70, 40:160] = 255
        out = _split_arch_by_deep_valleys(u8)
        # Still one connected component
        import cv2

        n, _, _, _ = cv2.connectedComponentsWithStats(out, connectivity=8)
        assert n == 2  # background + 1

    def test_deep_gap_between_two_teeth_does_cut(self):
        u8 = np.zeros((80, 200), dtype=np.uint8)
        u8[10:70, 30:80] = 255
        u8[10:70, 120:170] = 255
        out = _split_arch_by_deep_valleys(u8)
        import cv2

        n, _, _, _ = cv2.connectedComponentsWithStats(out, connectivity=8)
        assert n == 3  # background + 2 teeth

    def test_four_separated_teeth_rough_count(self):
        img = _smile_with_gums()
        teeth = [t for t in detect_teeth(img) if not t.rejected]
        # Should be near 4, not exploding to 8+
        assert 3 <= len(teeth) <= 7

"""Tests: avoid splitting one tooth into two; keep gum exclusion."""

from __future__ import annotations

import numpy as np

from app.ai.shade import VITA_SHADES
from app.ai.shade_segment import (
    _adaptive_enamel_mask,
    _split_arch_by_deep_valleys,
    detect_gum_mask,
    detect_teeth,
)


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
        mask = _adaptive_enamel_mask(band)
        assert int(mask.sum()) == 0

    def test_enamel_mask_keeps_bright_enamel(self):
        band = np.zeros((40, 40, 3), dtype=np.float64)
        band[:] = VITA_SHADES["A2"]
        mask = _adaptive_enamel_mask(band)
        assert int(mask.sum()) > 1000

    def test_detect_teeth_masks_do_not_cover_gum_shelf(self):
        img = _smile_with_gums()
        teeth = detect_teeth(img, backend="classical")
        assert len(teeth) >= 1
        gum_y0, gum_y1 = int(400 * 0.30), int(400 * 0.40)
        for t in teeth:
            gum_overlap = int(t.mask[gum_y0:gum_y1, :].sum())
            tooth_area = int(t.mask.sum())
            assert tooth_area > 0
            assert gum_overlap / tooth_area < 0.08


class TestDetectGumMask:
    def test_covers_gum_shelf_and_excludes_enamel(self):
        img = _smile_with_gums()
        teeth = [t for t in detect_teeth(img, backend="classical") if not t.rejected]
        assert len(teeth) >= 1
        gum = detect_gum_mask(img, teeth)
        assert gum is not None
        gum_y0, gum_y1 = int(400 * 0.30), int(400 * 0.40)
        shelf = gum[gum_y0:gum_y1, :]
        shelf_area = (gum_y1 - gum_y0) * 600
        assert int(shelf.sum()) / shelf_area > 0.15
        enamel_y0, enamel_y1 = int(400 * 0.45), int(400 * 0.60)
        enamel_overlap = int(gum[enamel_y0:enamel_y1, :].sum())
        assert enamel_overlap / max(int(gum.sum()), 1) < 0.12

    def test_no_teeth_returns_none(self):
        img = _smile_with_gums()
        assert detect_gum_mask(img, []) is None

    def test_no_pink_pixels_returns_none(self):
        h, w = 400, 600
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        img[140:260, 220:280] = enamel
        teeth = [t for t in detect_teeth(img, backend="classical") if not t.rejected]
        if not teeth:
            mask = np.zeros((h, w), dtype=bool)
            mask[140:260, 220:280] = True
            teeth = [mask]
        assert detect_gum_mask(img, teeth) is None


class TestNaturalYellowEnamel:
    def test_enamel_mask_keeps_yellow_vita_shades(self):
        for shade in ("A3.5", "B4", "C4", "D4"):
            band = np.zeros((40, 40, 3), dtype=np.float64)
            band[:] = VITA_SHADES[shade]
            mask = _adaptive_enamel_mask(band)
            assert int(mask.sum()) > 1000, shade

    def test_enamel_mask_keeps_dim_yellow_smile(self):
        """Dim chairside light — yellow crowns below old L>=95 floor."""
        h, w = 400, 600
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (28, 20, 18)
        gum = np.array([140, 85, 95], dtype=np.uint8)
        img[int(h * 0.30) : int(h * 0.42), int(w * 0.12) : int(w * 0.88)] = gum
        yellow = np.array(VITA_SHADES["A3.5"], dtype=np.float64)
        yellow = np.clip(yellow * 0.72, 0, 255).astype(np.uint8)
        for x0 in (180, 250, 320, 390):
            img[int(h * 0.42) : int(h * 0.62), x0 : x0 + 50] = yellow
        mask = _adaptive_enamel_mask(img.astype(np.float64))
        assert int(mask.sum()) > 500
        teeth = [t for t in detect_teeth(img, backend="classical") if not t.rejected]
        assert len(teeth) >= 3

    def test_gum_still_rejected_with_yellow_teeth_present(self):
        band = np.zeros((40, 40, 3), dtype=np.float64)
        band[:] = (185, 105, 115)
        assert int(_adaptive_enamel_mask(band).sum()) == 0


class TestNoOverSegmentation:
    def test_single_wide_tooth_not_split_in_two(self):
        img = _one_wide_tooth()
        teeth = [t for t in detect_teeth(img, backend="classical") if not t.rejected]
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
        teeth = [t for t in detect_teeth(img, backend="classical") if not t.rejected]
        # Should be near 4, not exploding to 8+
        assert 3 <= len(teeth) <= 7

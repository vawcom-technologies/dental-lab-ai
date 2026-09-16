"""Tests for KAIST individual tooth segmentation backend."""

from __future__ import annotations

from unittest.mock import patch

import numpy as np

from app.ai.shade_segment import ToothMask, detect_teeth
from app.ai.shade_segment_kaist import (
    _labels_to_tooth_masks,
    kaist_available,
    mouth_crop_rgb,
)


class TestKaistNumpyShims:
    def test_function_base_iterable_importable_on_numpy2(self):
        from app.ai.kaist_compat import ensure_kaist_numpy_shims

        ensure_kaist_numpy_shims()
        from numpy.lib.function_base import iterable

        assert iterable([1, 2, 3]) is True
        assert iterable(3) is False


class TestKaistHelpers:
    def test_labels_to_masks_pastes_into_full_image(self):
        labels = np.zeros((40, 60), dtype=np.int32)
        labels[5:35, 10:25] = 1
        labels[5:35, 35:50] = 2
        box = (100, 140, 200, 260)  # y0,y1,x0,x1
        teeth = _labels_to_tooth_masks(labels, full_h=300, full_w=400, box=box)
        assert len(teeth) == 2
        assert teeth[0].mask[105:135, 210:225].all()
        assert not teeth[0].mask[0, 0]

    def test_labels_to_masks_keeps_arch_tag(self):
        labels = np.zeros((20, 30), dtype=np.int32)
        labels[2:18, 5:25] = 1
        box = (40, 60, 10, 40)
        teeth = _labels_to_tooth_masks(
            labels, full_h=100, full_w=80, box=box, arch="lower"
        )
        assert len(teeth) == 1
        assert teeth[0].arch == "lower"

    def test_paste_scales_small_mask_to_crop_box(self):
        """Regression: downscaled labels must fill the full mouth crop box."""
        from app.ai.shade_segment_kaist import _paste_mask

        small = np.zeros((20, 30), dtype=bool)
        small[2:18, 5:25] = True
        box = (100, 180, 200, 320)  # 80×120 box
        full = _paste_mask(small, (400, 500), box)
        # Must cover most of the box, not only a 20×30 corner
        assert int(full[100:180, 200:320].sum()) > 500
        assert full[100:180, 200:320].mean() > 0.3

    def test_mouth_crop_fallback_on_blank(self):
        img = np.zeros((200, 300, 3), dtype=np.uint8)
        crop, box = mouth_crop_rgb(img)
        assert crop.shape == img.shape
        assert box == (0, 200, 0, 300)

    def test_resize_for_work_downscales_large(self):
        from app.ai.shade_segment_kaist import _resize_for_work

        img = np.zeros((535, 775, 3), dtype=np.uint8)
        work, scale = _resize_for_work(img, max_side=320, min_side=256)
        assert max(work.shape[:2]) == 320
        assert scale < 1.0

    def test_resize_for_work_upscales_tiny_to_min_only(self):
        from app.ai.shade_segment_kaist import _resize_for_work

        img = np.zeros((165, 138, 3), dtype=np.uint8)
        work, scale = _resize_for_work(img, max_side=320, min_side=256)
        assert max(work.shape[:2]) == 256
        assert scale > 1.0
        assert max(work.shape[:2]) < 320

    def test_resize_for_work_keeps_mid_size(self):
        from app.ai.shade_segment_kaist import _resize_for_work

        img = np.zeros((200, 280, 3), dtype=np.uint8)
        work, scale = _resize_for_work(img, max_side=320, min_side=256)
        assert work.shape[:2] == (200, 280)
        assert scale == 1.0

    def test_resize_wide_arch_keeps_crown_height(self):
        """Production log: 124×480 maxillary strip → 83×320 (no upper teeth)."""
        from app.ai.shade_segment_kaist import _resize_for_work

        img = np.zeros((124, 480, 3), dtype=np.uint8)
        work, _scale = _resize_for_work(img, max_side=320, min_side=256)
        assert work.shape[0] >= 150
        assert work.shape[0] > 83

    def test_max_side_zero_clamps_to_default(self, monkeypatch):
        from app.ai import shade_segment_kaist as mod
        from app.core.config import settings

        monkeypatch.setattr(settings, "shade_segment_kaist_max_side", 0)
        assert mod._max_side() == 320

    def test_tooth_band_ignores_specular_flash(self):
        from app.ai.shade_segment_kaist import _tooth_band_mask

        img = np.zeros((80, 120, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        img[25:55, 20:100] = (200, 185, 145)
        img[30:40, 50:70] = (255, 255, 255)
        band = _tooth_band_mask(img)
        assert int(band[25:55, 20:100].sum()) > 400
        assert int(band[30:40, 50:70].sum()) < int(band[25:55, 20:100].sum()) * 0.5

    def test_tooth_band_keeps_flash_lit_upper_enamel(self):
        """Maxillary crowns at L>232 must stay in the band (clinic intraoral)."""
        from app.ai.shade_segment import _lab_channels
        from app.ai.shade_segment_kaist import _tooth_band_mask

        img = np.zeros((80, 120, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        img[20:60, 15:105] = (248, 236, 214)
        L, _a, _b = _lab_channels(img)
        assert float(L[40, 60]) > 232
        band = _tooth_band_mask(img)
        assert int(band[20:60, 15:105].sum()) > 800

    def test_focus_boxes_split_dual_arch(self):
        from app.ai.shade_segment_kaist import kaist_focus_boxes

        img = np.zeros((200, 240, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        img[30:80, 30:210] = (205, 188, 150)
        img[120:170, 30:210] = (205, 188, 150)
        boxes = kaist_focus_boxes(img)
        assert len(boxes) == 2
        assert boxes[0][1] <= boxes[1][0] + 8

    def test_focus_boxes_thin_gap_does_not_swallow_other_arch(self):
        """Clinic open-mouth: ~4–8 px dark strip. Symmetric pad used to
        include the lower smile in the 'upper' crop."""
        from app.ai.shade_segment_kaist import kaist_focus_boxes

        img = np.zeros((300, 400, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        img[70:188, 20:380] = (205, 188, 150)
        img[188:208, 20:380] = (28, 18, 20)
        img[208:255, 20:380] = (205, 188, 150)
        boxes = kaist_focus_boxes(img)
        assert len(boxes) == 2
        top, bot = boxes
        assert top[1] <= 210
        assert bot[0] >= 190
        assert top[1] <= bot[0] + 10
        # Upper crop must cover the maxillary row, not only a sliver.
        assert top[0] <= 80
        assert top[1] >= 180

    def test_focus_boxes_split_flash_lit_upper_arch(self):
        """Washed-out maxillary + darker mandibular must still be two crops."""
        from app.ai.shade_segment import _lab_channels
        from app.ai.shade_segment_kaist import kaist_focus_boxes

        img = np.zeros((300, 400, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        img[20:60, 20:380] = (180, 110, 120)
        img[60:125, 20:380] = (248, 236, 214)
        img[125:175, 20:380] = (28, 18, 20)
        img[175:230, 20:380] = (200, 175, 130)
        img[230:270, 20:380] = (180, 110, 120)
        L, _a, _b = _lab_channels(img)
        assert float(L[90, 200]) > 232
        boxes = kaist_focus_boxes(img)
        assert len(boxes) == 2
        top, bot = boxes
        assert top[1] <= 185
        assert bot[0] >= 155
        assert top[0] <= 70
        assert top[1] >= 115

    def test_focus_boxes_keep_dark_laterals_on_mouth_band(self):
        """Clinic 328×764: enamel ROI missed 22/23 and cropped them out."""
        from app.ai.shade_segment_kaist import kaist_focus_boxes

        h, w = 328, 764
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        gum = (180, 110, 120)
        bright = (230, 210, 175)
        dim = (175, 155, 120)
        img[16:48, :] = gum
        img[h - 36 : h - 8, :] = gum
        img[55:140, 240:360] = bright
        img[55:140, 370:490] = bright
        img[70:135, 40:120] = dim
        img[70:135, 640:730] = dim
        img[148:182, :] = (28, 18, 20)
        img[190:270, 240:360] = bright
        img[190:270, 370:490] = bright
        img[200:265, 40:120] = dim
        img[200:265, 640:730] = dim
        boxes = kaist_focus_boxes(img)
        assert len(boxes) == 2
        for _y0, _y1, x0, x1 in boxes:
            assert x0 == 0
            assert x1 == w

    def test_portrait_extraoral_smile_is_one_mouth_crop(self):
        """Face photos must not dual-split into mustache + beard (clinic 8:36)."""
        from app.ai.shade import VITA_SHADES
        from app.ai.shade_segment_kaist import kaist_focus_boxes

        h, w = 480, 360
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        gum = (180, 110, 120)
        img[40:120, 80:280] = gum
        img[200:255, 70:290] = enamel
        img[258:305, 80:280] = enamel
        img[320:400, 60:300] = gum
        boxes = kaist_focus_boxes(img)
        assert len(boxes) == 1
        y0, y1, _x0, _x1 = boxes[0]
        assert y0 <= 210
        assert y1 >= 290

    def test_portrait_crop_ignores_lip_below_smile(self):
        from app.ai.shade import VITA_SHADES
        from app.ai.shade_segment_kaist import kaist_focus_boxes

        h, w = 500, 360
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        img[180:250, 60:300] = enamel
        img[380:450, 80:280] = enamel  # lip / beard highlight
        boxes = kaist_focus_boxes(img)
        assert len(boxes) == 1
        _y0, y1, _x0, _x1 = boxes[0]
        assert y1 < 360

    def test_labels_drop_gingiva_keep_crowns(self):
        from app.ai.shade import VITA_SHADES
        from app.ai.shade_segment_kaist import _labels_to_tooth_masks

        h, w = 80, 200
        crop = np.zeros((h, w, 3), dtype=np.uint8)
        crop[:] = (180, 110, 120)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        labels = np.zeros((h, w), dtype=np.int32)
        for i, x0 in enumerate((20, 70, 120), start=1):
            crop[25:70, x0 : x0 + 40] = enamel
            labels[25:70, x0 : x0 + 40] = i
        labels[2:18, 30:170] = 9
        teeth = _labels_to_tooth_masks(
            labels, full_h=h, full_w=w, box=(0, h, 0, w), crop_rgb=crop
        )
        accepted = [t for t in teeth if not t.rejected]
        assert len(accepted) == 3
        assert all(float(np.nonzero(t.mask)[0].mean()) > 20 for t in accepted)

    def test_merge_vertical_halves_of_one_crown(self):
        from app.ai.shade_segment import _merge_split_crown_slices

        h, w = 80, 200
        left = np.zeros((h, w), dtype=bool)
        right = np.zeros((h, w), dtype=bool)
        left[10:70, 80:102] = True
        right[10:70, 102:124] = True
        out = _merge_split_crown_slices([left, right])
        assert len(out) == 1
        assert int(out[0].sum()) == int(left.sum()) + int(right.sum())

    def test_does_not_merge_two_full_adjacent_teeth(self):
        from app.ai.shade_segment import _merge_split_crown_slices

        h, w = 80, 240
        a = np.zeros((h, w), dtype=bool)
        b = np.zeros((h, w), dtype=bool)
        a[15:65, 40:90] = True
        b[15:65, 92:142] = True
        out = _merge_split_crown_slices([a, b])
        assert len(out) == 2

    def test_merges_touching_central_fragments_among_full_teeth(self):
        """Classical gap-fill often returns 11 as two touching slices."""
        from app.ai.shade_segment import _merge_split_crown_slices

        h, w = 160, 460
        masks = []
        # 13, 12, 11-left, 11-right, 21, 22 — same proportions as the clinic photo.
        for x0, tw in ((20, 58), (90, 73), (175, 47), (222, 71), (310, 73), (395, 58)):
            m = np.zeros((h, w), dtype=bool)
            m[30:130, x0 : x0 + tw] = True
            masks.append(m)
        out = _merge_split_crown_slices(masks)
        assert len(out) == 5
        cxs = sorted(float(np.nonzero(m)[1].mean()) for m in out)
        assert any(185 < cx < 250 for cx in cxs)

    def test_prepare_work_compresses_flash(self):
        from app.ai.shade_segment_kaist import prepare_kaist_work_rgb

        img = np.zeros((40, 40, 3), dtype=np.uint8)
        img[:] = (180, 160, 140)
        img[10:20, 10:20] = (255, 255, 255)
        out = prepare_kaist_work_rgb(img)
        assert out[15, 15].max() < 250


class TestKaistRouting:
    def test_kaist_unavailable_without_weights(self, monkeypatch):
        from app.ai import shade_segment_kaist as mod

        with patch.object(mod, "resolve_weights", return_value=mod.Path("/no/such.pth")):
            with patch.object(
                mod,
                "resolve_vendor_root",
                return_value=mod.Path("/no/vendor"),
            ):
                assert not kaist_available()

    def test_incomplete_weights_are_unavailable(self, tmp_path):
        from app.ai.shade_segment_kaist import _weights_file_error

        stub = tmp_path / "CP_teeth_seg.pth"
        stub.write_bytes(b"PK" + b"\x00" * 100)
        err = _weights_file_error(stub)
        assert err is not None
        assert "incomplete" in err

    @patch("app.ai.shade_segment_kaist.kaist_available", return_value=True)
    @patch("app.ai.shade_segment_kaist.detect_teeth_kaist")
    def test_kaist_backend_used_when_available(self, mock_detect, _mock_avail):
        h, w = 120, 160
        mask = np.zeros((h, w), dtype=bool)
        mask[30:90, 40:100] = True
        mock_detect.return_value = [
            ToothMask(
                tooth_index=0,
                mask=mask,
                confidence=0.9,
                rejected=False,
                reject_reason=None,
            )
        ]
        img = np.zeros((h, w, 3), dtype=np.uint8)
        teeth = detect_teeth(img, backend="kaist")
        assert len(teeth) == 1
        mock_detect.assert_called_once()

    @patch("app.ai.shade_segment_kaist.kaist_available", return_value=False)
    def test_kaist_falls_back_to_classical(self, _mock_avail):
        from app.ai.shade import VITA_SHADES

        img = np.zeros((400, 600, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        for x0 in (180, 250, 320, 390):
            img[int(400 * 0.42) : int(400 * 0.62), x0 : x0 + 50] = enamel

        meta: dict = {}
        teeth = detect_teeth(img, backend="kaist", meta_out=meta)
        assert len([t for t in teeth if not t.rejected]) >= 3
        assert meta.get("segment_backend") == "classical"
        assert meta.get("segment_fallback") is True

    @patch("app.ai.shade_segment_kaist.kaist_available", return_value=False)
    def test_auto_prefers_kaist_then_classical(self, _mock_avail):
        from app.ai.shade import VITA_SHADES

        img = np.zeros((400, 600, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        for x0 in (180, 250, 320, 390):
            img[int(400 * 0.42) : int(400 * 0.62), x0 : x0 + 50] = enamel

        meta: dict = {}
        teeth = detect_teeth(img, backend="auto", meta_out=meta)
        assert len([t for t in teeth if not t.rejected]) >= 3
        assert meta.get("segment_backend") == "classical"
        assert meta.get("segment_fallback") is True

    @patch("app.ai.shade_segment_kaist.kaist_available", return_value=True)
    @patch("app.ai.shade_segment_kaist.detect_teeth_kaist", return_value=[])
    def test_kaist_empty_falls_back_to_classical(self, mock_detect, _mock_avail):
        """Wide iPad shots often yield 0 KAIST masks — classical must take over."""
        from app.ai.shade import VITA_SHADES

        img = np.zeros((400, 600, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        for x0 in (180, 250, 320, 390):
            img[int(400 * 0.42) : int(400 * 0.62), x0 : x0 + 50] = enamel

        meta: dict = {}
        teeth = detect_teeth(img, backend="kaist", meta_out=meta)
        assert len([t for t in teeth if not t.rejected]) >= 3
        assert meta.get("segment_backend") == "classical"
        assert meta.get("segment_fallback") is True
        mock_detect.assert_called_once()

    def test_complete_missing_arch_fills_upper_from_classical(self):
        """KAIST-only lower row on an open-mouth photo must get maxillary fill."""
        from app.ai.shade import VITA_SHADES
        from app.ai.shade_segment import _complete_missing_kaist_arch, _mask_centroid_y

        h, w = 480, 640
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (25, 18, 16)
        gum = np.array([180, 110, 120], dtype=np.uint8)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        img[int(h * 0.18) : int(h * 0.28), int(w * 0.15) : int(w * 0.85)] = gum
        for x0 in (170, 240, 310, 380):
            img[int(h * 0.28) : int(h * 0.42), x0 : x0 + 55] = enamel
        img[int(h * 0.72) : int(h * 0.82), int(w * 0.15) : int(w * 0.85)] = gum
        for x0 in (175, 245, 315, 385):
            img[int(h * 0.58) : int(h * 0.72), x0 : x0 + 55] = enamel

        lower: list[ToothMask] = []
        for i, x0 in enumerate((175, 245, 315, 385)):
            mask = np.zeros((h, w), dtype=bool)
            mask[int(h * 0.58) : int(h * 0.72), x0 : x0 + 55] = True
            lower.append(
                ToothMask(
                    tooth_index=i,
                    mask=mask,
                    confidence=0.9,
                    rejected=False,
                    arch="lower",
                )
            )
        out = _complete_missing_kaist_arch(img, lower, None)
        assert len(out) > len(lower)
        assert any((_mask_centroid_y(t) or 0) < 0.5 * h for t in out)

    @patch("app.ai.shade_segment_kaist.kaist_available", return_value=True)
    @patch("app.ai.shade_segment_kaist.detect_teeth_kaist")
    def test_kaist_lower_only_open_mouth_gets_upper_fdi(
        self, mock_detect, _mock_avail
    ):
        """Screenshot regression: mandibular KAIST boxes labeled 13/12/11/21."""
        from app.ai.shade import VITA_SHADES

        h, w = 480, 640
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (25, 18, 16)
        gum = np.array([180, 110, 120], dtype=np.uint8)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        img[int(h * 0.18) : int(h * 0.28), int(w * 0.15) : int(w * 0.85)] = gum
        for x0 in (170, 240, 310, 380):
            img[int(h * 0.28) : int(h * 0.42), x0 : x0 + 55] = enamel
        img[int(h * 0.72) : int(h * 0.82), int(w * 0.15) : int(w * 0.85)] = gum
        kaist_only = []
        for i, x0 in enumerate((175, 245, 315, 385)):
            img[int(h * 0.58) : int(h * 0.72), x0 : x0 + 55] = enamel
            mask = np.zeros((h, w), dtype=bool)
            mask[int(h * 0.58) : int(h * 0.72), x0 : x0 + 55] = True
            kaist_only.append(
                ToothMask(
                    tooth_index=i,
                    mask=mask,
                    confidence=0.9,
                    rejected=False,
                    arch="lower",
                )
            )
        mock_detect.return_value = kaist_only
        teeth = [t for t in detect_teeth(img, backend="kaist") if not t.rejected]
        fdis = {t.fdi for t in teeth}
        assert {11, 21} & fdis
        assert {41, 31} & fdis

    def test_add_uncovered_fills_missing_central_gap(self):
        """Flash-lit 11 sits between a detected 12 and 21 — must be inserted."""
        from app.ai.shade import VITA_SHADES
        from app.ai.shade_segment import _add_uncovered_classical_teeth

        h, w = 480, 640
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (25, 18, 16)
        gum = np.array([180, 110, 120], dtype=np.uint8)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        img[int(h * 0.18) : int(h * 0.28), int(w * 0.15) : int(w * 0.85)] = gum
        upper_xs = (170, 240, 310, 380)
        for x0 in upper_xs:
            img[int(h * 0.28) : int(h * 0.42), x0 : x0 + 55] = enamel
        img[int(h * 0.72) : int(h * 0.82), int(w * 0.15) : int(w * 0.85)] = gum
        for x0 in (175, 245, 315, 385):
            img[int(h * 0.58) : int(h * 0.72), x0 : x0 + 55] = enamel

        kaist: list[ToothMask] = []
        # Skip the upper-right central at x=240 (clinic screenshot).
        for i, x0 in enumerate((170, 310, 380)):
            mask = np.zeros((h, w), dtype=bool)
            mask[int(h * 0.28) : int(h * 0.42), x0 : x0 + 55] = True
            kaist.append(
                ToothMask(
                    tooth_index=i,
                    mask=mask,
                    confidence=0.9,
                    rejected=False,
                    arch="upper",
                )
            )
        for i, x0 in enumerate((175, 245, 315, 385)):
            mask = np.zeros((h, w), dtype=bool)
            mask[int(h * 0.58) : int(h * 0.72), x0 : x0 + 55] = True
            kaist.append(
                ToothMask(
                    tooth_index=10 + i,
                    mask=mask,
                    confidence=0.9,
                    rejected=False,
                    arch="lower",
                )
            )
        out = _add_uncovered_classical_teeth(img, kaist, None)
        assert len(out) > len(kaist)
        gap_cx = 240 + 27.5
        gap_teeth = [
            t
            for t in out
            if abs(float(np.nonzero(t.mask)[1].mean()) - gap_cx) < 30
            and float(np.nonzero(t.mask)[0].mean()) < 0.5 * h
        ]
        assert gap_teeth

    @patch("app.ai.shade_segment_kaist.kaist_available", return_value=True)
    @patch("app.ai.shade_segment_kaist.detect_teeth_kaist")
    def test_kaist_missing_central_gets_11_not_neighbor(
        self, mock_detect, _mock_avail
    ):
        from app.ai.shade import VITA_SHADES

        h, w = 480, 640
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (25, 18, 16)
        gum = np.array([180, 110, 120], dtype=np.uint8)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        img[int(h * 0.18) : int(h * 0.28), int(w * 0.15) : int(w * 0.85)] = gum
        for x0 in (170, 240, 310, 380):
            img[int(h * 0.28) : int(h * 0.42), x0 : x0 + 55] = enamel
        img[int(h * 0.72) : int(h * 0.82), int(w * 0.15) : int(w * 0.85)] = gum
        for x0 in (175, 245, 315, 385):
            img[int(h * 0.58) : int(h * 0.72), x0 : x0 + 55] = enamel

        kaist: list[ToothMask] = []
        for i, x0 in enumerate((170, 310, 380)):
            mask = np.zeros((h, w), dtype=bool)
            mask[int(h * 0.28) : int(h * 0.42), x0 : x0 + 55] = True
            kaist.append(
                ToothMask(
                    tooth_index=i,
                    mask=mask,
                    confidence=0.9,
                    rejected=False,
                    arch="upper",
                )
            )
        for i, x0 in enumerate((175, 245, 315, 385)):
            mask = np.zeros((h, w), dtype=bool)
            mask[int(h * 0.58) : int(h * 0.72), x0 : x0 + 55] = True
            kaist.append(
                ToothMask(
                    tooth_index=10 + i,
                    mask=mask,
                    confidence=0.9,
                    rejected=False,
                    arch="lower",
                )
            )
        mock_detect.return_value = kaist
        teeth = [t for t in detect_teeth(img, backend="kaist") if not t.rejected]
        t11 = next(t for t in teeth if t.fdi == 11)
        t12 = next(t for t in teeth if t.fdi == 12)
        assert abs(float(np.nonzero(t11.mask)[1].mean()) - 267.5) < 30
        assert float(np.nonzero(t12.mask)[1].mean()) < float(
            np.nonzero(t11.mask)[1].mean()
        )

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

    def test_focus_boxes_split_dual_arch(self):
        from app.ai.shade_segment_kaist import kaist_focus_boxes

        img = np.zeros((200, 240, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        img[30:80, 30:210] = (205, 188, 150)
        img[120:170, 30:210] = (205, 188, 150)
        boxes = kaist_focus_boxes(img)
        assert len(boxes) == 2
        assert boxes[0][1] <= boxes[1][0] + 8

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

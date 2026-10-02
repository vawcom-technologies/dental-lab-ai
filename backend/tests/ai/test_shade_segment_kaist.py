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

    def test_upscale_labels_scales_the_contour(self):
        import cv2

        from app.ai.shade_segment_kaist import _upscale_labels

        labels = np.zeros((20, 20), dtype=np.int32)
        yy, xx = np.ogrid[:20, :20]
        labels[(xx - 10) ** 2 + (yy - 10) ** 2 <= 49] = 1
        out = _upscale_labels(labels, (80, 80))
        nearest = cv2.resize(
            labels.astype(np.float32),
            (80, 80),
            interpolation=cv2.INTER_NEAREST,
        )
        assert int((out > 0).sum()) > 0
        area_ratio = float((out > 0).sum()) / float(labels.sum() * 16)
        assert 0.85 < area_ratio < 1.15
        assert not np.array_equal(out > 0, nearest > 0)


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

    def test_resize_for_work_clamps_long_side(self):
        from app.ai.shade_segment_kaist import _resize_for_work

        big = _resize_for_work(np.zeros((535, 775, 3), np.uint8), 320, 256)
        tiny = _resize_for_work(np.zeros((165, 138, 3), np.uint8), 320, 256)
        mid = np.zeros((200, 300, 3), np.uint8)
        assert max(big.shape[:2]) == 320
        assert max(tiny.shape[:2]) == 256
        assert _resize_for_work(mid, 320, 256) is mid
        strip = _resize_for_work(np.zeros((600, 2400, 3), np.uint8), 320, 256)
        assert strip.shape[0] == 112 and strip.shape[1] <= 800  # not 320×80

    def test_mouth_crop_fallback_on_blank(self):
        img = np.zeros((200, 300, 3), dtype=np.uint8)
        crop, box = mouth_crop_rgb(img)
        assert crop.shape == img.shape
        assert box == (0, 200, 0, 300)


    def test_max_side_zero_clamps_to_default(self, monkeypatch):
        from app.ai import shade_segment_kaist as mod
        from app.core.config import settings

        monkeypatch.setattr(settings, "shade_segment_kaist_max_side", 0)
        assert mod._max_side() == 320  # same on CPU (Railway) as on the Mac


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


class TestKaistWarmup:
    def test_warmup_skips_when_unavailable(self):
        from app.ai.shade_segment_kaist import KaistSegmentStatus, warmup_kaist_weights

        fake = KaistSegmentStatus(
            available=False,
            vendor_root="",
            weights="",
            device="cpu",
            resize=False,
            max_side=320,
            min_side=256,
            snake_iters=8,
            bring_back_iters=48,
            evolve_iters=22,
            import_error="weights missing",
        )
        with patch(
            "app.ai.shade_segment_kaist.kaist_segment_status", return_value=fake
        ):
            assert warmup_kaist_weights().startswith("skipped")


def test_split_merged_crowns_cuts_double_width_tooth_at_contact():
    from app.ai.shade_segment import _split_merged_crowns

    def tooth(x0, x1, y0=20, y1=80):
        m = np.zeros((100, 400), dtype=bool)
        m[y0:y1, x0:x1] = True
        return ToothMask(tooth_index=0, mask=m, confidence=0.9, rejected=False)

    merged = tooth(150, 250)
    merged.mask[20:45, 196:204] = False  # interproximal notch at x≈200
    row = [tooth(40, 90), tooth(95, 145), merged, tooth(255, 305)]
    upper = tooth(150, 250, 0, 15)  # other arch: wide but no same-row peers
    out = _split_merged_crowns(row + [upper])
    assert len(out) == 6
    pieces = [t for t in out if t.mask[50, 150:250].any() and t.mask[:, :150].sum() == 0
              and t.mask[:, 251:].sum() == 0 and t.mask[:16].sum() == 0]
    assert len(pieces) == 2
    cut = min(np.nonzero(p.mask)[1].max() for p in pieces)
    assert 194 <= cut <= 206

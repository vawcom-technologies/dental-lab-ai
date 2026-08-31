"""Tests for ML segmentation wrapper and A/B harness (no weights required)."""

from __future__ import annotations

from unittest.mock import patch

import numpy as np

from app.ai.shade_segment import detect_teeth
from app.ai.shade_segment_ab import compare_segmentation, summarize_ab
from app.ai.shade_segment_ml import (
    fdi_mask_to_tooth_masks,
    ml_available,
    ml_segment_status,
    resolve_weights_dir,
)


class TestFdiMaskConversion:
    def test_two_anterior_teeth_sorted_left_to_right(self):
        h, w = 400, 600
        fdi = np.zeros((h, w), dtype=np.uint8)
        # FDI 21 (upper right central) on the left of image, 11 on the right
        fdi[100:280, 120:200] = 21
        fdi[100:280, 380:460] = 11

        teeth = fdi_mask_to_tooth_masks(fdi, anterior_only=True)
        assert len(teeth) == 2
        assert all(not t.rejected for t in teeth)

        cx0 = float(np.nonzero(teeth[0].mask)[1].mean())
        cx1 = float(np.nonzero(teeth[1].mask)[1].mean())
        assert cx0 < cx1

    def test_premolar_excluded_when_anterior_only(self):
        fdi = np.zeros((200, 200), dtype=np.uint8)
        fdi[50:150, 50:100] = 14  # premolar — not shade-relevant
        fdi[50:150, 110:160] = 11

        teeth = fdi_mask_to_tooth_masks(fdi, anterior_only=True)
        assert len(teeth) == 1

    def test_premolar_included_when_anterior_only_false(self):
        fdi = np.zeros((200, 200), dtype=np.uint8)
        fdi[50:150, 50:100] = 14
        fdi[50:150, 110:160] = 11

        teeth = fdi_mask_to_tooth_masks(fdi, anterior_only=False)
        assert len(teeth) == 2


class TestBackendRouting:
    def test_classical_backend_unchanged(self):
        from app.ai.shade import VITA_SHADES

        img = np.zeros((400, 600, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        for x0 in (180, 250, 320, 390):
            img[int(400 * 0.42) : int(400 * 0.62), x0 : x0 + 50] = enamel

        teeth = detect_teeth(img, backend="classical")
        assert len([t for t in teeth if not t.rejected]) >= 3


class TestProductionBackend:
    def test_rfdetr_unavailable_without_api_key(self, monkeypatch):
        monkeypatch.delenv("ROBOFLOW_API_KEY", raising=False)
        from app.ai.shade_segment_rfdetr import rfdetr_available

        with patch("app.ai.shade_segment_rfdetr._api_key", return_value=""):
            assert not rfdetr_available()

    def test_auto_falls_back_to_classical(self):
        from app.ai.shade import VITA_SHADES

        img = np.zeros((400, 600, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        for x0 in (180, 250, 320, 390):
            img[int(400 * 0.42) : int(400 * 0.62), x0 : x0 + 50] = enamel

        # auto == kaist-first; without KAIST this is emergency classical
        with patch(
            "app.ai.shade_segment_kaist.kaist_available", return_value=False
        ):
            teeth = detect_teeth(img, backend="auto")
        assert len([t for t in teeth if not t.rejected]) >= 3


class TestAbHarness:
    def test_summarize_without_rfdetr(self, monkeypatch):
        from app.ai.shade import VITA_SHADES
        from app.ai import shade_segment_rfdetr as rfmod

        monkeypatch.setattr(rfmod, "_api_key", lambda: "")
        img = np.zeros((400, 600, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        for x0 in (180, 250, 320, 390):
            img[int(400 * 0.42) : int(400 * 0.62), x0 : x0 + 50] = enamel

        ab = compare_segmentation(img)
        summary = summarize_ab(ab)
        assert summary["classical"]["accepted"] >= 3
        assert summary["classical_ms"] > 0
        assert summary["rfdetr_available"] is False
        assert ab.rfdetr is None


class TestMlStatus:
    def test_resolve_weights_dir_relative_to_backend(self):
        p = resolve_weights_dir("weights/segmentanytooth")
        assert p.name == "segmentanytooth"
        assert p.parent.name == "weights"

    def test_status_reports_missing_weights(self, tmp_path):
        status = ml_segment_status(weight_dir=tmp_path, view="front")
        assert not status.available
        assert "segmentanytooth_vit_tiny.pt" in status.missing_files

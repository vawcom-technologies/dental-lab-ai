"""Tests for RF-DETR / PLAK Roboflow segmentation backend."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import numpy as np

from app.ai.shade_segment import detect_teeth
from app.ai.shade_segment_rfdetr import (
    _instances_from_predictions,
    _mask_from_polygon,
    detect_teeth_rfdetr,
    rfdetr_available,
)


class TestRfdetrMaskParsing:
    def test_polygon_mask(self):
        h, w = 200, 300
        points = [{"x": 50, "y": 40}, {"x": 120, "y": 42}, {"x": 100, "y": 150}]
        m = _mask_from_polygon(points, h, w)
        assert m is not None
        assert int(m.sum()) > 100

    def test_filters_plaque_keeps_tooth(self):
        h, w = 100, 100
        preds = [
            {
                "class": "plaque",
                "confidence": 0.9,
                "points": [{"x": 10, "y": 10}, {"x": 40, "y": 10}, {"x": 25, "y": 40}],
            },
            {
                "class": "tooth",
                "confidence": 0.85,
                "points": [{"x": 55, "y": 10}, {"x": 90, "y": 10}, {"x": 72, "y": 45}],
            },
        ]
        pairs = _instances_from_predictions(preds, h, w)
        assert len(pairs) == 1


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

    def test_rfdetr_unavailable_without_api_key(self, monkeypatch):
        monkeypatch.delenv("ROBOFLOW_API_KEY", raising=False)
        from app.ai import shade_segment_rfdetr as mod

        with patch.object(mod, "_api_key", return_value=""):
            assert not mod.rfdetr_available()

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

    @patch("app.ai.shade_segment_rfdetr.rfdetr_available", return_value=True)
    @patch("app.ai.shade_segment_rfdetr.detect_teeth_rfdetr")
    def test_rfdetr_backend_used_when_available(self, mock_detect, _mock_avail):
        h, w = 120, 160
        mask = np.zeros((h, w), dtype=bool)
        mask[30:90, 40:100] = True
        from app.ai.shade_segment import ToothMask

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
        teeth = detect_teeth(img, backend="rfdetr")
        assert len(teeth) == 1
        mock_detect.assert_called_once()

    def test_expand_semantic_bundle_tooth_class(self):
        import base64
        import io

        from PIL import Image

        from app.ai.shade_segment_rfdetr import _expand_semantic_bundle

        # Tiny class-id map: 0 bg, 1 tooth
        arr = np.zeros((20, 20), dtype=np.uint8)
        arr[5:15, 5:15] = 1
        buf = io.BytesIO()
        Image.fromarray(arr).save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode()
        preds = _expand_semantic_bundle(
            {
                "segmentation_mask": b64,
                "class_map": {"background": "0", "tooth": "1"},
                "present_class_ids": [0, 1],
            }
        )
        assert len(preds) == 1
        assert preds[0]["class"] == "tooth"
        assert int(preds[0]["_mask"].sum()) == 100

    def test_normalize_model_id_short_form(self):
        from app.ai.shade_segment_rfdetr import _normalize_model_id

        assert (
            _normalize_model_id("mahvish-hasan/plak---projectdens-7p9sm-atp73-1-yolo26s-sem-t1")
            == "mahvish-hasan/plak---projectdens-7p9sm-atp73-1-yolo26s-sem-t1"
        )
        assert (
            _normalize_model_id("projectdens/plak---projectdens-7p9sm/16")
            == "plak---projectdens-7p9sm/16"
        )

    def test_semantic_tooth_mask_splits_components(self):
        from app.ai.shade_segment_rfdetr import _instances_from_predictions

        h, w = 100, 200
        preds = [
            {
                "class": "tooth",
                "confidence": 0.9,
                "_mask": np.zeros((h, w), dtype=bool),
            }
        ]
        m = preds[0]["_mask"]
        m[20:50, 30:70] = True
        m[20:50, 120:160] = True  # two separate teeth
        pairs = _instances_from_predictions(preds, h, w)
        assert len(pairs) == 2

    def test_wide_semantic_blob_splits_into_instances(self):
        """Touching crowns in one class mask must not stay one merged blob."""
        from app.ai.shade_segment_rfdetr import _split_semantic_tooth_union

        h, w = 80, 400
        union = np.zeros((h, w), dtype=bool)
        # Continuous enamel bar (merged arch)
        union[20:70, 40:360] = True
        # Shallow contact notches so DT ridge has valleys
        for x in (100, 160, 220, 280):
            union[20:70, x : x + 2] = False
        parts = _split_semantic_tooth_union(union)
        assert len(parts) >= 4
        reunited = np.zeros_like(union)
        for p in parts:
            reunited |= p
        # Fidelity: no carved valleys — every original tooth pixel kept.
        assert int(np.logical_and(union, ~reunited).sum()) == 0

    def test_semantic_dust_components_dropped(self):
        from app.ai.shade_segment_rfdetr import _split_semantic_tooth_union

        h, w = 80, 300
        union = np.zeros((h, w), dtype=bool)
        union[20:70, 40:260] = True  # main arch
        union[10:14, 10:14] = True  # dust
        parts = _split_semantic_tooth_union(union)
        assert all(int(p.sum()) >= 40 for p in parts)
        assert max(int(p.sum()) for p in parts) > 1000

    def test_expand_uses_confidence_mask_mean(self):
        import base64
        import io

        from PIL import Image

        from app.ai.shade_segment_rfdetr import _expand_semantic_bundle

        arr = np.zeros((20, 20), dtype=np.uint8)
        arr[5:15, 5:15] = 1
        conf = np.full((20, 20), 50, dtype=np.uint8)
        conf[5:15, 5:15] = 200
        buf = io.BytesIO()
        Image.fromarray(arr).save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode()
        cbuf = io.BytesIO()
        Image.fromarray(conf).save(cbuf, format="PNG")
        cb64 = base64.b64encode(cbuf.getvalue()).decode()
        preds = _expand_semantic_bundle(
            {
                "segmentation_mask": b64,
                "confidence_mask": cb64,
                "class_map": {"0": "background", "1": "tooth"},
                "present_class_ids": [0, 1],
            }
        )
        assert len(preds) == 1
        assert abs(preds[0]["confidence"] - (200 / 255.0)) < 0.02

    def test_infer_http_converts_rgb_to_bgr(self):
        """inference_sdk JPEG-encodes numpy as BGR — RGB must be converted."""
        import cv2

        from app.ai.shade_segment_rfdetr import _infer_http_client

        rgb = np.zeros((40, 60, 3), dtype=np.uint8)
        rgb[:, :] = (200, 50, 30)  # strong red in RGB
        captured = {}

        class FakeClient:
            def configure(self, _cfg):
                return self

            def infer(self, image, model_id=None):
                captured["image"] = np.asarray(image).copy()
                captured["model_id"] = model_id
                return {"predictions": []}

        with patch(
            "inference_sdk.InferenceHTTPClient", return_value=FakeClient()
        ), patch(
            "inference_sdk.InferenceConfiguration", return_value=MagicMock()
        ):
            _infer_http_client(
                rgb,
                model_id="test/1",
                api_key="k",
                api_url="https://serverless.roboflow.com",
                conf=0.25,
            )
        sent = captured["image"]
        assert sent.shape == rgb.shape
        # OpenCV BGR: channel 0 is Blue (= RGB's B=30), channel 2 is Red (=200)
        assert int(sent[0, 0, 0]) == 30
        assert int(sent[0, 0, 2]) == 200
        bgr_expected = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        assert np.array_equal(sent, bgr_expected)

    @patch("app.ai.shade_segment_rfdetr.rfdetr_segment_status")
    @patch("app.ai.shade_segment_rfdetr._infer_http_client")
    def test_detect_teeth_rfdetr_parses_predictions(self, mock_infer, mock_status):
        from app.ai.shade_segment_rfdetr import RfdetrSegmentStatus

        mock_status.return_value = RfdetrSegmentStatus(
            available=True,
            model_id="plak---projectdens-7p9sm/16",
            api_key_set=True,
            inference_api_url="https://serverless.roboflow.com",
        )
        mock_infer.return_value = {
            "predictions": [
                {
                    "class": "tooth",
                    "confidence": 0.92,
                    "points": [
                        {"x": 20, "y": 20},
                        {"x": 80, "y": 22},
                        {"x": 50, "y": 90},
                    ],
                }
            ]
        }
        img = np.zeros((120, 120, 3), dtype=np.uint8)
        teeth = detect_teeth_rfdetr(img)
        assert len(teeth) == 1
        assert int(teeth[0].mask.sum()) > 40

"""Tests for nearest VITA match and per-tooth analyze orchestration."""

from __future__ import annotations

import numpy as np
import pytest

from app.ai.shade import (
    GINGIVA_SHADES,
    VITA_SHADES,
    _rgb_to_lab,
    match_lab_nearest,
)
from app.ai.shade_analyze import analyze_shade_from_bytes, analyze_shade_from_rgb
from app.ai.shade_zones import split_tooth_zones, sample_zone_lab


class TestMatchLabNearest:
    def test_exact_centroid_returns_that_shade_with_near_zero_delta(self):
        for shade, rgb in VITA_SHADES.items():
            lab = _rgb_to_lab(np.asarray(rgb, dtype=np.float64))
            result = match_lab_nearest(lab)
            assert result["shade"] == shade
            assert result["delta_e_2000"] < 0.05

    def test_top_matches_sorted_and_bounded(self):
        lab = _rgb_to_lab(np.asarray(VITA_SHADES["A2"], dtype=np.float64))
        result = match_lab_nearest(lab, top_n=3)
        assert len(result["top_matches"]) == 3
        deltas = [m["delta_e_2000"] for m in result["top_matches"]]
        assert deltas == sorted(deltas)
        assert result["top_matches"][0]["shade"] == result["shade"]

    def test_default_palette_never_returns_gingiva_shade(self):
        lab = _rgb_to_lab(np.asarray(GINGIVA_SHADES["G3"], dtype=np.float64))
        result = match_lab_nearest(lab)
        assert result["shade"] in VITA_SHADES
        assert result["shade"] not in GINGIVA_SHADES

    def test_gingiva_palette_matches_g_shades_only(self):
        assert set(GINGIVA_SHADES) == {"G1", "G2", "G3", "G4", "G5"}
        assert GINGIVA_SHADES["G5"][0] < GINGIVA_SHADES["G4"][0]
        for shade, rgb in GINGIVA_SHADES.items():
            lab = _rgb_to_lab(np.asarray(rgb, dtype=np.float64))
            result = match_lab_nearest(lab, palette=GINGIVA_SHADES)
            assert result["shade"] == shade
            assert result["delta_e_2000"] < 0.05
            assert all(m["shade"] in GINGIVA_SHADES for m in result["top_matches"])


class TestAnalyzeShadeFromRgb:
    def test_synthetic_enamel_blob_yields_zones_with_null_override(self):
        # Controlled-looking smile image: warm enamel rectangles in the smile band
        h, w = 400, 600
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (40, 30, 28)  # dark non-enamel background
        # Two tall enamel teeth (A2-ish RGB) in the anterior band
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        img[140:280, 220:270] = enamel
        img[140:280, 290:340] = enamel

        result = analyze_shade_from_rgb(img)
        assert result["tooth_count"] >= 1
        accepted = [t for t in result["teeth"] if not t["rejected"]]
        assert len(accepted) >= 1

        tooth = accepted[0]
        for zone_name in ("cervical", "middle", "incisal"):
            z = tooth["zones"][zone_name]
            assert z["detected_shade"] is not None
            assert z["override_shade"] is None
            assert z["effective_shade"] == z["detected_shade"]
            assert z["delta_e_2000"] is not None
        assert result.get("gum") is None

    def test_detection_output_never_sets_override(self):
        h, w = 360, 480
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (35, 28, 26)
        img[130:250, 200:250] = np.array(VITA_SHADES["B1"], dtype=np.uint8)
        out = analyze_shade_from_rgb(img)
        for tooth in out["teeth"]:
            for zone in tooth["zones"].values():
                assert zone["override_shade"] is None
        assert out.get("gum") is None

    def test_smile_with_gum_shelf_returns_gingiva_match(self):
        h, w = 400, 600
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (40, 28, 26)
        gum = np.array([180, 110, 120], dtype=np.uint8)
        img[int(h * 0.30) : int(h * 0.42), int(w * 0.12) : int(w * 0.88)] = gum
        enamel = np.array(VITA_SHADES["A2"], dtype=np.uint8)
        for x0 in (180, 250, 320, 390):
            img[int(h * 0.42) : int(h * 0.62), x0 : x0 + 50] = enamel

        result = analyze_shade_from_rgb(img)
        gum_out = result.get("gum")
        assert gum_out is not None
        assert gum_out["detected_shade"] in GINGIVA_SHADES
        assert gum_out["sampled_rgb"] is not None
        assert len(gum_out["sampled_rgb"]) == 3
        assert gum_out["sampled_rgb"][0] > gum_out["sampled_rgb"][1]
        assert gum_out["delta_e_2000"] is not None
        assert 0.05 <= gum_out["confidence"] <= 0.97
        for tooth in result["teeth"]:
            for zone in tooth["zones"].values():
                shade = zone["detected_shade"]
                if shade is not None:
                    assert shade in VITA_SHADES


    def test_unreadable_bytes_raise_value_error(self):
        with pytest.raises(ValueError, match="Could not read this photo"):
            analyze_shade_from_bytes(b"not-an-image")

    def test_heic_bytes_decode_like_app_store_ipad(self):
        """Existing IPA FilePicker sends HEIC; Pillow alone cannot open it."""
        import io

        from PIL import Image

        from app.ai.shade_analyze import _load_rgb_from_bytes, _register_heif_opener

        _register_heif_opener()
        src = Image.new("RGB", (48, 36), (200, 180, 160))
        buf = io.BytesIO()
        try:
            src.save(buf, format="HEIF")
        except Exception as exc:
            pytest.skip(f"HEIF encode unavailable: {exc}")
        rgb = _load_rgb_from_bytes(buf.getvalue())
        assert rgb.shape == (36, 48, 3)
        assert rgb.dtype == np.uint8


class TestZoneSampleThenMatch:
    def test_zone_lab_matches_nearest_shade(self):
        h, w = 120, 80
        img = np.zeros((h, w, 3), dtype=np.uint8)
        rgb = np.array(VITA_SHADES["C2"], dtype=np.uint8)
        mask = np.zeros((h, w), dtype=bool)
        mask[20:100, 25:55] = True
        img[mask] = rgb
        zones = split_tooth_zones(mask)
        lab = sample_zone_lab(img, zones["middle"], erode_px=0, min_pixels=10)
        assert lab is not None
        matched = match_lab_nearest(lab)
        assert matched["shade"] == "C2"

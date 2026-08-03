"""Tests for nearest VITA match and per-tooth analyze orchestration."""

from __future__ import annotations

import numpy as np

from app.ai.shade import VITA_SHADES, _rgb_to_lab, match_lab_nearest
from app.ai.shade_analyze import analyze_shade_from_rgb
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

    def test_detection_output_never_sets_override(self):
        h, w = 360, 480
        img = np.zeros((h, w, 3), dtype=np.uint8)
        img[:] = (35, 28, 26)
        img[130:250, 200:250] = np.array(VITA_SHADES["B1"], dtype=np.uint8)
        out = analyze_shade_from_rgb(img)
        for tooth in out["teeth"]:
            for zone in tooth["zones"].values():
                assert zone["override_shade"] is None


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

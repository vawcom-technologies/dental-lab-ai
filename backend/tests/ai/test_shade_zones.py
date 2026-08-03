"""Unit tests for per-tooth axis, zone split, and override immutability."""

from __future__ import annotations

import math

import numpy as np

from app.ai.shade_result import ZoneShadeState, apply_detection, apply_override
from app.ai.shade_zones import ZONES, split_tooth_zones, tooth_long_axis


def _rotated_ellipse_mask(
    h: int,
    w: int,
    *,
    cy: float,
    cx: float,
    axis_len: float,
    axis_wid: float,
    angle_deg: float,
) -> np.ndarray:
    """Ellipse mask; axis_len is semi-axis along angle_deg (CCW from +x), axis_wid perpendicular."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    theta = math.radians(angle_deg)
    # Rotate so ellipse long axis aligns with angle in (x,y); convert to image y-down.
    dx = xx - cx
    dy = yy - cy
    cos_t, sin_t = math.cos(theta), math.sin(theta)
    # Local coords: long axis along angle from +x
    xr = dx * cos_t + dy * sin_t
    yr = -dx * sin_t + dy * cos_t
    return ((xr / axis_len) ** 2 + (yr / axis_wid) ** 2) <= 1.0


class TestToothLongAxis:
    def test_upright_mask_axis_points_down(self):
        # axis_len = semi-axis along angle; 90° → tall vertical tooth
        mask = _rotated_ellipse_mask(
            120, 80, cy=60, cx=40, axis_len=40, axis_wid=14, angle_deg=90
        )
        axis = tooth_long_axis(mask)
        assert axis.direction_yx[0] > 0.85  # mostly +row (incisal)

    def test_tilted_mask_follows_tilt(self):
        # Long axis ~ +30° from vertical toward +x
        angle = 90 - 30
        mask = _rotated_ellipse_mask(
            140, 140, cy=70, cx=70, axis_len=48, axis_wid=14, angle_deg=angle
        )
        axis = tooth_long_axis(mask)
        expected_angle_from_vertical = math.degrees(
            math.atan2(axis.direction_yx[1], axis.direction_yx[0])
        )
        assert abs(expected_angle_from_vertical - 30.0) < 12.0
        assert axis.direction_yx[0] > 0

    def test_rotated_negative_tilt(self):
        angle = 90 + 25
        mask = _rotated_ellipse_mask(
            140, 140, cy=70, cx=70, axis_len=48, axis_wid=14, angle_deg=angle
        )
        axis = tooth_long_axis(mask)
        expected_angle_from_vertical = math.degrees(
            math.atan2(axis.direction_yx[1], axis.direction_yx[0])
        )
        assert abs(expected_angle_from_vertical - (-25.0)) < 12.0
        assert axis.direction_yx[0] > 0


class TestZoneSplit:
    def test_three_zones_cover_mask_without_gaps_or_overlaps(self):
        mask = _rotated_ellipse_mask(
            120, 80, cy=60, cx=40, axis_len=42, axis_wid=14, angle_deg=90
        )
        zones = split_tooth_zones(mask)
        assert set(zones) == set(ZONES)

        stacked = np.stack([zones[z] for z in ZONES], axis=0)
        per_pixel = stacked.sum(axis=0)
        # Inside mask: exactly one zone; outside: zero
        assert np.all(per_pixel[mask] == 1)
        assert np.all(per_pixel[~mask] == 0)
        assert int(per_pixel.sum()) == int(mask.sum())

    def test_equal_length_proportions_along_axis(self):
        mask = _rotated_ellipse_mask(
            160, 90, cy=80, cx=45, axis_len=55, axis_wid=16, angle_deg=90
        )
        axis = tooth_long_axis(mask)
        zones = split_tooth_zones(mask)
        ys, xs = np.nonzero(mask)
        pts = np.column_stack([ys.astype(np.float64), xs.astype(np.float64)])
        proj = (pts - axis.centroid_yx) @ axis.direction_yx
        lo, hi = float(proj.min()), float(proj.max())
        span = hi - lo
        assert span > 10

        extents = []
        for name in ZONES:
            zys, zxs = np.nonzero(zones[name])
            zpts = np.column_stack([zys.astype(np.float64), zxs.astype(np.float64)])
            zp = (zpts - axis.centroid_yx) @ axis.direction_yx
            extents.append(float(zp.max() - zp.min()))

        # Each zone spans ~1/3 of the axis projection range (pixel rounding)
        expected = span / 3.0
        for e in extents:
            assert abs(e - expected) / expected < 0.2

    def test_tilted_tooth_still_splits_into_three(self):
        mask = _rotated_ellipse_mask(
            150, 150, cy=75, cx=75, axis_len=48, axis_wid=15, angle_deg=60
        )
        zones = split_tooth_zones(mask)
        counts = [int(zones[z].sum()) for z in ZONES]
        assert all(c > 0 for c in counts)
        union = zones["cervical"] | zones["middle"] | zones["incisal"]
        assert np.array_equal(union, mask)


class TestOverrideImmutability:
    def test_detection_preserves_override(self):
        state = ZoneShadeState(detected_shade="A2", delta_e_2000=1.5, override_shade="A3")
        updated = apply_detection(state, detected_shade="B1", delta_e_2000=2.2)
        assert updated.detected_shade == "B1"
        assert updated.delta_e_2000 == 2.2
        assert updated.override_shade == "A3"
        assert updated.effective_shade == "A3"

    def test_detection_does_not_invent_override(self):
        state = ZoneShadeState(detected_shade="A2", delta_e_2000=1.1, override_shade=None)
        updated = apply_detection(state, detected_shade="A3.5", delta_e_2000=0.9)
        assert updated.override_shade is None
        assert updated.effective_shade == "A3.5"

    def test_override_does_not_clobber_detected(self):
        state = ZoneShadeState(detected_shade="A2", delta_e_2000=1.4, override_shade=None)
        overridden = apply_override(state, "C1")
        assert overridden.detected_shade == "A2"
        assert overridden.delta_e_2000 == 1.4
        assert overridden.override_shade == "C1"
        assert overridden.effective_shade == "C1"
        cleared = apply_override(overridden, None)
        assert cleared.detected_shade == "A2"
        assert cleared.override_shade is None
        assert cleared.effective_shade == "A2"

    def test_rerun_detection_never_silently_drops_override(self):
        state = ZoneShadeState(detected_shade="A1", delta_e_2000=2.0, override_shade=None)
        state = apply_override(state, "A3.5")
        for shade, de in (("B2", 1.0), ("C3", 3.0), ("A4", 0.5)):
            state = apply_detection(state, detected_shade=shade, delta_e_2000=de)
            assert state.override_shade == "A3.5"
            assert state.effective_shade == "A3.5"
            assert state.detected_shade == shade

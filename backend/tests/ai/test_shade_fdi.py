"""ISO 3950 numbering: front → back in each quadrant, not image left → right."""

from __future__ import annotations

from dataclasses import replace

import numpy as np

from app.ai.shade_segment import ToothMask, _assign_arch_metadata


def _box(h: int, w: int, y0: int, y1: int, x0: int, x1: int) -> np.ndarray:
    m = np.zeros((h, w), dtype=bool)
    m[y0:y1, x0:x1] = True
    return m


def _teeth_from_centers(h: int, w: int, row_y: int, centers: list[int]) -> list[ToothMask]:
    out: list[ToothMask] = []
    for i, cx in enumerate(centers):
        out.append(
            ToothMask(
                tooth_index=i,
                mask=_box(h, w, row_y - 30, row_y + 30, cx - 22, cx + 22),
                confidence=1.0,
                rejected=False,
            )
        )
    return out


class TestFdiFrontToBack:
    def test_six_upper_centrals_are_11_and_21(self):
        h, w = 220, 640
        # Image LTR = patient's right posterior → left posterior.
        xs = [90, 160, 230, 410, 480, 550]
        out = _assign_arch_metadata(_teeth_from_centers(h, w, 80, xs))
        assert [t.fdi for t in out] == [11, 12, 13, 21, 22, 23]
        t11 = next(t for t in out if t.fdi == 11)
        t21 = next(t for t in out if t.fdi == 21)
        assert abs(float(np.nonzero(t11.mask)[1].mean()) - 230) < 8
        assert abs(float(np.nonzero(t21.mask)[1].mean()) - 410) < 8
        # List order is front→back per quadrant, not left→right.
        assert out[0].fdi == 11
        assert out[3].fdi == 21

    def test_intraoral_dark_triangle_is_not_the_midline(self):
        """11–21 in contact + a wide 21–22 dark space must still be 11/21."""
        h, w = 220, 640
        xs = [90, 160, 250, 330, 490, 560]
        out = _assign_arch_metadata(_teeth_from_centers(h, w, 80, xs))
        t11 = next(t for t in out if t.fdi == 11)
        t21 = next(t for t in out if t.fdi == 21)
        assert abs(float(np.nonzero(t11.mask)[1].mean()) - 250) < 8
        assert abs(float(np.nonzero(t21.mask)[1].mean()) - 330) < 8
        assert [t.fdi for t in out] == [11, 12, 13, 21, 22, 23]

    def test_dual_arch_uses_all_four_quadrants(self):
        h, w = 360, 640
        upper = _teeth_from_centers(h, w, 90, [100, 180, 250, 390, 460, 540])
        lower = _teeth_from_centers(h, w, 250, [110, 185, 255, 385, 455, 530])
        # Offset lower tooth_index so they stay distinct before assign.
        lower = [
            ToothMask(
                tooth_index=i + 6,
                mask=t.mask,
                confidence=1.0,
                rejected=False,
            )
            for i, t in enumerate(lower)
        ]
        out = _assign_arch_metadata(upper + lower)
        by_arch = {t.fdi: t.arch for t in out if t.fdi}
        assert by_arch[11] == "upper" and by_arch[21] == "upper"
        assert by_arch[41] == "lower" and by_arch[31] == "lower"
        assert [t.fdi for t in out if t.arch == "upper"] == [11, 12, 13, 21, 22, 23]
        assert [t.fdi for t in out if t.arch == "lower"] == [41, 42, 43, 31, 32, 33]

    def test_one_sided_right_quadrant_is_11_12_13(self):
        h, w = 200, 600
        # Entire row sits on the image-left (patient's right).
        out = _assign_arch_metadata(_teeth_from_centers(h, w, 80, [70, 130, 190]))
        assert [t.fdi for t in out] == [11, 12, 13]
        t11 = next(t for t in out if t.fdi == 11)
        # Front of Q1 is closest to the midline = rightmost of this group.
        assert float(np.nonzero(t11.mask)[1].mean()) > 170

    def test_preset_lower_arch_uses_mandibular_numbers(self):
        """KAIST-only mandibular row must not be labeled 13/12/11/21."""
        h, w = 360, 640
        lower = [
            replace(t, arch="lower")
            for t in _teeth_from_centers(h, w, 250, [110, 185, 255, 385])
        ]
        out = _assign_arch_metadata(lower)
        assert [t.fdi for t in out] == [41, 42, 43, 31]
        by_x = sorted(out, key=lambda t: float(np.nonzero(t.mask)[1].mean()))
        assert [t.fdi for t in by_x] == [43, 42, 41, 31]

    def test_extraoral_smile_low_in_frame_still_upper(self):
        """Portrait extra-oral smiles sit in the lower half — still 11/21."""
        h, w = 400, 640
        out = _assign_arch_metadata(
            _teeth_from_centers(h, w, 280, [90, 160, 230, 410, 480, 550])
        )
        assert [t.fdi for t in out] == [11, 12, 13, 21, 22, 23]


def test_lower_midline_follows_upper_central_contact():
    """Photo centre (x=600) is nearer the wrong lower contact (570 vs 640);
    the upper 11|21 contact (x≈632) must decide the lower midline."""
    import numpy as np

    from app.ai.shade_segment import ToothMask, _assign_fdi_and_reorder

    def tooth(x0, x1, y0, y1, arch):
        m = np.zeros((400, 1200), dtype=bool)
        m[y0:y1, x0:x1] = True
        return ToothMask(0, m, 0.9, False, arch=arch)

    upper = [tooth(x, x + 95, 50, 180, "upper") for x in (435, 535, 635)]
    lower = [tooth(x, x + 50, 220, 330, "lower") for x in (455, 515, 575, 655, 715)]
    out = _assign_fdi_and_reorder(upper + lower)
    by_x = {int(np.nonzero(t.mask)[1].min()): t.fdi for t in out if t.arch == "lower"}
    assert by_x[575] == 41 and by_x[655] == 31


def test_closed_bite_long_upper_centrals_stay_upper():
    """Screenshot regression: upper centrals as low as side lower teeth → 41/31."""
    import numpy as np

    from app.ai.shade_segment import ToothMask, _assign_arch_metadata

    def tooth(x0, x1, y0, y1):
        m = np.zeros((400, 420), dtype=bool)
        m[y0:y1, x0:x1] = True
        return ToothMask(0, m, 0.9, False)

    upper = [tooth(40, 90, 110, 200), tooth(95, 140, 105, 205), tooth(145, 205, 100, 290),
             tooth(210, 270, 100, 290), tooth(275, 320, 105, 205), tooth(325, 375, 110, 200)]
    lower_sides = [tooth(60, 100, 200, 230), tooth(100, 140, 200, 230),
                   tooth(280, 320, 200, 230), tooth(320, 360, 200, 230)]
    out = _assign_arch_metadata(upper + lower_sides)
    by_x = {int(np.nonzero(t.mask)[1].min()): (t.arch, t.fdi) for t in out}
    assert by_x[145] == ("upper", 11) and by_x[210] == ("upper", 21)
    assert all(by_x[x][0] == "lower" for x in (60, 100, 280, 320))

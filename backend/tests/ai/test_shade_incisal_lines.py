import numpy as np

from app.ai.shade_geometry import incisal_lines
from app.ai.shade_segment import ToothMask, _assign_arch_metadata


def _box_row(arch, x0, x1, y0, y1):
    xs = np.linspace(x0, x1, 10)
    ring = (
        [[x, y0] for x in xs]
        + [[x1, y] for y in np.linspace(y0, y1, 10)]
        + [[x, y1] for x in xs[::-1]]
        + [[x0, y] for y in np.linspace(y1, y0, 10)]
    )
    return {"arch": arch, "rejected": False, "geometry": {"outline": ring}}


def test_separated_arches_get_both_incisal_lines():
    # Gap 0.05 on 0.3-tall crowns (17%) → teeth held apart → two lines.
    rows = [_box_row("upper", 0.1 + 0.2 * i, 0.25 + 0.2 * i, 0.2, 0.5) for i in range(3)]
    rows += [_box_row("lower", 0.1 + 0.2 * i, 0.25 + 0.2 * i, 0.55, 0.8) for i in range(3)]
    rows.append({**_box_row("lower", 0.3, 0.4, 0.0, 0.1), "rejected": True})
    lines = incisal_lines(rows)
    up = np.asarray(lines["upper_incisal"])
    lo = np.asarray(lines["lower_incisal"])
    assert np.allclose(up[:, 1], 0.5, atol=1e-3)  # bottom of upper crowns
    assert np.allclose(lo[:, 1], 0.55, atol=1e-3)  # top of lower crowns
    assert up[0, 0] == 0.1 and up[-1, 0] == 0.65


def test_closed_bite_gets_one_occlusal_line():
    # Gap 0.01 on 0.3-tall crowns (3%) → touching → one line on the upper edge.
    rows = [_box_row("upper", 0.1 + 0.2 * i, 0.25 + 0.2 * i, 0.2, 0.5) for i in range(3)]
    rows += [_box_row("lower", 0.1 + 0.2 * i, 0.25 + 0.2 * i, 0.51, 0.8) for i in range(3)]
    lines = incisal_lines(rows)
    assert set(lines) == {"occlusal"}
    assert np.allclose(np.asarray(lines["occlusal"])[:, 1], 0.5, atol=1e-3)


def test_single_tooth_arch_has_no_line():
    assert incisal_lines([_box_row("upper", 0.1, 0.2, 0.2, 0.5)]) == {}


def test_arch_assignment_keeps_display_outline():
    mask = np.zeros((40, 40), bool)
    mask[5:20, 5:15] = True
    ring = ((0.1, 0.1), (0.4, 0.1), (0.4, 0.5))
    t = ToothMask(0, mask, 0.9, False, display_outline=ring)
    assert _assign_arch_metadata([t])[0].display_outline == ring


def test_midline_sits_at_central_contact_spanning_all_crowns():
    from app.ai.shade_geometry import midline_from_rows

    def row(fdi, x, y, w=0.1, h=0.2):
        return {"fdi": fdi, "rejected": False, "geometry": {"bbox": {"x": x, "y": y, "w": w, "h": h}}}

    rows = [row(12, 0.2, 0.2), row(11, 0.3, 0.1), row(21, 0.42, 0.1), row(41, 0.33, 0.5)]
    assert midline_from_rows(rows) == [[0.41, 0.1], [0.41, 0.7]]
    assert midline_from_rows([row(12, 0.2, 0.2)]) is None


def test_lip_suggestions_trace_lip_against_skin_not_gums():
    from app.ai.shade_geometry import lip_suggestions

    img = np.zeros((300, 400, 3), np.uint8)
    img[:] = (230, 185, 165)  # skin (pinkish)
    yy, xx = np.ogrid[:300, :400]
    mouth = ((xx - 200) / 150.0) ** 2 + ((yy - 150) / 80.0) ** 2 <= 1  # lips 70→230
    img[mouth] = (175, 85, 90)  # lip
    img[110:130, 110:290] = (185, 95, 100)  # gum band: lip-coloured, inside lips
    img[130:175, 110:290] = (240, 236, 222)  # upper teeth
    rows = [_box_row("upper", x / 400, (x + 55) / 400, 130 / 300, 175 / 300) for x in (110, 172, 234)]
    lips = lip_suggestions(img, rows)
    up = np.asarray(lips["upper_lip"]) * [400, 300]
    lo = np.asarray(lips["lower_lip"]) * [400, 300]
    assert abs(up[3, 1] - 70) < 8 and abs(lo[3, 1] - 230) < 8  # lip-skin border, not gum
    assert abs(up[0, 0] - 50) < 12 and abs(up[-1, 0] - 350) < 12  # spans to the corners


def test_no_lip_suggestion_without_skin_border():
    """Retracted / tight shot: red tissue fills the frame → nothing suggested."""
    from app.ai.shade_geometry import lip_suggestions

    img = np.zeros((300, 400, 3), np.uint8)
    img[:] = (175, 85, 90)  # gum/lip tissue everywhere, no skin
    img[130:175, 110:290] = (240, 236, 222)
    rows = [_box_row("upper", x / 400, (x + 55) / 400, 130 / 300, 175 / 300) for x in (110, 172, 234)]
    assert lip_suggestions(img, rows) == {}


def test_tight_crop_keeps_the_visible_lip():
    """Chin cut off: lower lip runs off the frame → keep only the upper lip."""
    from app.ai.shade_geometry import lip_suggestions

    img = np.zeros((300, 400, 3), np.uint8)
    img[:] = (230, 185, 165)  # skin
    yy, xx = np.ogrid[:300, :400]
    img[((xx - 200) / 150.0) ** 2 + ((yy - 150) / 80.0) ** 2 <= 1] = (175, 85, 90)
    img[130:175, 110:290] = (240, 236, 222)
    crop = np.ascontiguousarray(img[:200])  # lower lip border (y≈230) cut off
    rows = [_box_row("upper", x / 400, (x + 55) / 400, 130 / 200, 175 / 200) for x in (110, 172, 234)]
    assert set(lip_suggestions(crop, rows)) == {"upper_lip"}

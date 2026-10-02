"""Geometry helpers for drawing tooth outlines and zone splits on photos.

Coordinates are normalized to [0, 1] as [x, y] (image width/height) so the
Flutter overlay can map them under BoxFit.contain regardless of display size.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from app.ai.shade_zones import ZONES, tooth_long_axis

# Chairside edit budgets — keep Flutter simplifyOutlineForEdit in sync.
# Display ring stays dense so the stroke can follow enamel instead of a blob.
DISPLAY_OUTLINE_MAX = 160
DISPLAY_OUTLINE_MIN = 96
# Few enough that a finger can tell corners apart on a small crown.
EDIT_HANDLES_MAX = 8
EDIT_HANDLES_MIN = 6


# Outline smoothing: one point per this many segmentation pixels, then
# Taubin passes. 2 removed KAIST stairs evenly on every photo and kept crown
# shape; 3 rounded small lower incisors into ovals.
_OUTLINE_POINT_SPACING = 2.0
_OUTLINE_SMOOTH_ITERS = 20


def fair_mask_for_display(mask: np.ndarray) -> np.ndarray:
    """Light morph + blur for stroke extraction only — never replace analysis masks.

    Kills 1px stair-steps from low-res KAIST TEM labels without hexagonizing
    the crown (heavy approxPolyDP did that on clinic photos).
    """
    import cv2

    if mask.dtype != bool:
        mask = mask.astype(bool)
    area = int(mask.sum())
    if area < 8:
        return mask

    u8 = (mask.astype(np.uint8)) * 255
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    u8 = cv2.morphologyEx(u8, cv2.MORPH_CLOSE, k, iterations=1)
    u8 = cv2.morphologyEx(u8, cv2.MORPH_OPEN, k, iterations=1)
    soft = cv2.GaussianBlur(u8, (5, 5), 0)
    faired = soft > 127
    allow = cv2.dilate((mask.astype(np.uint8)) * 255, k, iterations=1) > 0
    out = faired & allow
    if int(out.sum()) < max(8, int(0.55 * area)):
        return mask

    n, labels, stats, _ = cv2.connectedComponentsWithStats(
        out.astype(np.uint8), 8
    )
    if n <= 2:
        return out
    best = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return labels == best


def normalized_display_outline(
    mask: np.ndarray,
    *,
    origin_xy: tuple[float, float] = (0.0, 0.0),
    full_size: tuple[int, int] | None = None,
    px_scale: float = 1.0,
) -> list[list[float]] | None:
    """Closed [0,1] display ring from a faired copy of [mask].

    [origin_xy] offsets crop-local pixels into full-image normalized coords.
    [full_size] is (height, width) of the full frame; defaults to mask shape.
    """
    import cv2

    if mask.dtype != bool:
        mask = mask.astype(bool)
    mh, mw = mask.shape
    if mh < 2 or mw < 2 or int(mask.sum()) < 8:
        return None

    display = fair_mask_for_display(mask)
    u8 = (display.astype(np.uint8)) * 255
    contours, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not contours:
        return None
    cnt = max(contours, key=cv2.contourArea)
    if cv2.contourArea(cnt) < 8 or len(cnt) < 3:
        return None

    fh, fw = full_size if full_size is not None else (mh, mw)
    if fh < 2 or fw < 2:
        return None
    ox, oy = origin_xy
    # KAIST runs at ~320 px and is enlarged 3–4× ([px_scale]) onto the photo,
    # so its stairs/wobbles are a fixed size in *segmentation* pixels. Space
    # points in those pixels, then smooth a fixed number of neighbours: every
    # tooth loses its stairs alike, whether it is big or small in KAIST's
    # image. Taubin (shrink/inflate pairs) keeps the crown's size and shape.
    pts = cnt.reshape(-1, 2).astype(np.float64)
    peri = float(cv2.arcLength(cnt, True))
    n = int(np.clip(peri / (max(px_scale, 1.0) * _OUTLINE_POINT_SPACING), 24, 600))
    ring = _taubin_closed(
        np.asarray(_even_sample_closed(pts.tolist(), n)),
        iterations=_OUTLINE_SMOOTH_ITERS,
    )
    smooth = _even_sample_closed(ring.tolist(), DISPLAY_OUTLINE_MAX)
    return [
        [round((float(x) + ox) / float(fw), 5), round((float(y) + oy) / float(fh), 5)]
        for x, y in smooth
    ]


# Arch gap / upper crown height below this → one bite line, not two.
_SEPARATED_BITE_FRAC = 0.12


def incisal_lines(rows: list[dict[str, Any]]) -> dict[str, list[list[float]]]:
    """Smooth incisal curves per arch, fitted to the drawn crown outlines.

    Upper arch → lowest outline points (biting edge); lower → highest.
    Single-row smiles (arch=None) are numbered as upper, so drawn as upper.
    Closed bite (arches touch/overlap) → one "occlusal" line on the upper edge;
    teeth held apart (retractor/instrument) → both lines.
    """
    out: dict[str, list[list[float]]] = {}
    crown_h: list[float] = []
    for arch, key, pick in (
        ("upper", "upper_incisal", np.max),
        ("lower", "lower_incisal", np.min),
    ):
        xs: list[float] = []
        ys: list[float] = []
        span: list[float] = []
        teeth = 0
        for r in rows:
            if r.get("rejected") or (r.get("arch") or "upper") != arch:
                continue
            pts = np.asarray((r.get("geometry") or {}).get("outline") or [], float)
            if len(pts) < 8:
                continue
            x0, x1 = float(pts[:, 0].min()), float(pts[:, 0].max())
            # Middle 60% of the crown: corners round off and would sag the fit.
            edges = np.linspace(x0 + 0.2 * (x1 - x0), x1 - 0.2 * (x1 - x0), 6)
            for a, b in zip(edges[:-1], edges[1:]):
                sel = pts[(pts[:, 0] >= a) & (pts[:, 0] <= b)]
                if len(sel):
                    xs.append(float((a + b) / 2))
                    ys.append(float(pick(sel[:, 1])))
            span += [x0, x1]
            teeth += 1
            if arch == "upper":
                crown_h.append(float(np.ptp(pts[:, 1])))
        if teeth < 2:
            continue
        coef = np.polyfit(xs, ys, 2 if teeth >= 3 else 1)
        xx = np.linspace(min(span), max(span), 24)
        out[key] = [
            [round(float(x), 5), round(float(np.clip(y, 0.0, 1.0)), 5)]
            for x, y in zip(xx, np.polyval(coef, xx))
        ]
    if "upper_incisal" in out and "lower_incisal" in out:
        up = np.asarray(out["upper_incisal"])
        lo = np.asarray(out["lower_incisal"])
        xs_common = np.linspace(max(up[0, 0], lo[0, 0]), min(up[-1, 0], lo[-1, 0]), 20)
        gap = float(
            np.median(
                np.interp(xs_common, lo[:, 0], lo[:, 1])
                - np.interp(xs_common, up[:, 0], up[:, 1])
            )
        )
        # Closed bites measured 4–6% of crown height, a separated arch 20%.
        if gap < _SEPARATED_BITE_FRAC * float(np.median(crown_h)):
            return {"occlusal": out["upper_incisal"]}
    return out


def midline_from_rows(rows: list[dict[str, Any]]) -> list[list[float]] | None:
    """Vertical [[x, top], [x, bottom]] at the 11|21 contact (else 41|31).

    Same contact the FDI numbering uses, spanning all crowns top to bottom.
    """
    boxes = {
        r.get("fdi"): (r.get("geometry") or {}).get("bbox")
        for r in rows
        if not r.get("rejected")
    }
    pair = next(
        ((boxes[a], boxes[b]) for a, b in ((11, 21), (41, 31)) if boxes.get(a) and boxes.get(b)),
        None,
    )
    tops = [b["y"] for b in boxes.values() if b]
    bottoms = [b["y"] + b["h"] for b in boxes.values() if b]
    if pair is None or not tops:
        return None
    x = sum(b["x"] + b["w"] / 2 for b in pair) / 2
    return [[round(x, 5), round(min(tops), 5)], [round(x, 5), round(max(bottoms), 5)]]


# Lip vs skin: lips are redder and darker. Feature = a* − weight·L.
_LIP_DARK_WEIGHT = 0.5
# Inward dent bigger than this fraction of mouth height = pale highlight on
# the lip read as skin → replaced by the neighbours' average.
_LIP_DENT_FRAC = 0.08


def lip_suggestions(
    image_rgb: np.ndarray, rows: list[dict[str, Any]], *, points: int = 7
) -> dict[str, list[list[float]]]:
    """Starting points for the user-placed outer lip lines (lip against skin).

    Gums and lips share a colour, but gums never touch skin — so this traces
    the outside of the red/dark mouth region joined to the teeth, corner to
    corner. Threshold is per photo (Otsu), so pink skin is handled. Each lip
    is returned only if its border is found with skin beyond it, so a tight
    crop keeps the visible lip and retracted shots get nothing.
    """
    import cv2

    full_h, full_w = image_rgb.shape[:2]
    scale = 400.0 / max(full_h, full_w)
    small = cv2.resize(
        np.ascontiguousarray(image_rgb, np.uint8),
        (max(1, int(full_w * scale)), max(1, int(full_h * scale))),
        interpolation=cv2.INTER_AREA,
    )
    h, w = small.shape[:2]
    lab = cv2.cvtColor(cv2.GaussianBlur(small, (0, 0), 1.5), cv2.COLOR_RGB2LAB)
    lab = lab.astype(np.float32)
    lip_like = lab[..., 1] - _LIP_DARK_WEIGHT * lab[..., 0]

    teeth = np.zeros((h, w), np.uint8)
    for r in rows:
        ring = (r.get("geometry") or {}).get("outline") or []
        if not r.get("rejected") and len(ring) >= 3:
            cv2.fillPoly(teeth, [(np.asarray(ring) * [w, h]).astype(np.int32)], 1)
    if not teeth.any():
        return {}

    # Search window: around the teeth, generous enough to hold both lips.
    ys, xs = np.nonzero(teeth)
    th, tw = ys.max() - ys.min(), xs.max() - xs.min()
    y0, y1 = max(0, int(ys.min() - 1.5 * th)), min(h, int(ys.max() + 1.5 * th))
    x0, x1 = max(0, int(xs.min() - 0.4 * tw)), min(w, int(xs.max() + 0.4 * tw))
    roi = lip_like[y0:y1, x0:x1]
    vals = roi[teeth[y0:y1, x0:x1] == 0]
    if vals.size < 50 or float(np.ptp(vals)) < 1e-3:
        return {}
    v8 = ((vals - vals.min()) * (255.0 / np.ptp(vals))).astype(np.uint8)
    t8, _ = cv2.threshold(v8, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    cut = float(vals.min() + np.ptp(vals) * t8 / 255.0)

    mouth = np.zeros((h, w), np.uint8)
    mouth[y0:y1, x0:x1] = roi > cut
    mouth |= teeth
    ellipse = cv2.getStructuringElement
    mouth = cv2.morphologyEx(mouth, cv2.MORPH_CLOSE, ellipse(cv2.MORPH_ELLIPSE, (7, 7)))
    mouth = cv2.morphologyEx(mouth, cv2.MORPH_OPEN, ellipse(cv2.MORPH_ELLIPSE, (5, 5)))
    n, labels = cv2.connectedComponents(mouth)
    hits = np.bincount(labels[teeth > 0], minlength=n)
    hits[0] = 0
    mouth = (labels == int(np.argmax(hits))).astype(np.uint8)
    contours, _ = cv2.findContours(mouth, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    mouth = np.zeros_like(mouth)
    cv2.drawContours(mouth, contours, -1, 1, -1)  # fill: teeth/gaps inside
    cols = np.nonzero(mouth.any(axis=0))[0]
    left, right = int(cols.min()), int(cols.max())
    kw = max(3, (right - left) // 10) | 1  # bridge small pale dips on the lip
    mouth = cv2.morphologyEx(
        mouth, cv2.MORPH_CLOSE, ellipse(cv2.MORPH_ELLIPSE, (kw, max(3, kw // 4) | 1))
    )

    half = max(1, (right - left) // 50)
    upper: list[list[float]] = []
    lower: list[list[float]] = []
    for k in range(points):
        x = int(round(left + (right - left) * k / (points - 1)))
        tops, bottoms = [], []
        for xx in range(max(left, x - half), min(right, x + half) + 1):
            col = np.nonzero(mouth[:, xx])[0]
            if col.size:
                tops.append(col.min())
                bottoms.append(col.max())
        if not tops:
            return {}
        upper.append([x / w, float(np.median(tops)) / h])
        lower.append([x / w, float(np.median(bottoms)) / h])

    # Pale highlights only ever dent the outline inward; real curves bulge out.
    span = max(p[1] for p in lower) - min(p[1] for p in upper)
    for line, inward in ((upper, 1.0), (lower, -1.0)):
        for i in range(1, points - 1):
            expected = 0.5 * (line[i - 1][1] + line[i + 1][1])
            if (line[i][1] - expected) * inward > _LIP_DENT_FRAC * span:
                line[i][1] = expected
    # Judge each lip on its own: tight / camera crops often cut off the nose
    # or chin side, and all-or-nothing then dropped a clearly visible lip.
    # A lip counts only if its border stays inside the search window AND skin
    # lies just beyond it — retracted shots have mucosa there, never skin.
    found_up = min(p[1] for p in upper) * h > y0 + 2 and _skin_beyond(lab, upper, h, w, -1)
    found_lo = max(p[1] for p in lower) * h < y1 - 3 and _skin_beyond(lab, lower, h, w, 1)
    if found_up and found_lo:  # both lips meet at the mouth corners
        for i in (0, points - 1):
            upper[i][1] = lower[i][1] = 0.5 * (upper[i][1] + lower[i][1])

    def norm(line: list[list[float]]) -> list[list[float]]:
        return [[round(float(x), 5), round(float(np.clip(y, 0, 1)), 5)] for x, y in line]

    out: dict[str, list[list[float]]] = {}
    if found_up:
        out["upper_lip"] = norm(upper)
    if found_lo:
        out["lower_lip"] = norm(lower)
    return out


# Skin just outside a lip border (OpenCV Lab, L 0–255, a* 128-centred).
# Measured: skin L 164–226 / a* +10…+23; retracted mucosa L 100–141 / a* +31…+50.
_SKIN_MIN_L = 150.0
_SKIN_MAX_A = 27.0


def _skin_beyond(
    lab: np.ndarray, line: list[list[float]], h: int, w: int, outward: int
) -> bool:
    """Is the band just outside the middle of a lip line skin-coloured?"""
    mid = line[len(line) // 3 : len(line) - len(line) // 3] or line
    xs = [int(np.clip(p[0] * w, 0, w - 1)) for p in mid]
    # 8–16 px out (at 400 px wide): soft lip edges stay lip-coloured nearer in.
    ys = [int(np.clip(p[1] * h + outward * k, 0, h - 1)) for p in mid for k in (8, 12, 16)]
    band = lab[np.ix_(sorted(set(ys)), range(min(xs), max(xs) + 1))].reshape(-1, 3)
    if band.size == 0:
        return False
    return float(band[:, 0].mean()) > _SKIN_MIN_L and float(band[:, 1].mean()) - 128 < _SKIN_MAX_A


def tooth_display_geometry(
    mask: np.ndarray,
    zone_masks: dict[str, np.ndarray] | None = None,
    *,
    px_scale: float = 1.0,
) -> dict[str, Any] | None:
    """Build outline, edit handles, clinical marks, zone divider lines."""
    import cv2

    if mask.dtype != bool:
        mask = mask.astype(bool)
    h, w = mask.shape
    if h < 2 or w < 2 or int(mask.sum()) < 8:
        return None

    u8 = (mask.astype(np.uint8)) * 255
    contours, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not contours:
        return None
    cnt = max(contours, key=cv2.contourArea)
    if cv2.contourArea(cnt) < 8:
        return None

    # Display stroke is faired separately; analysis mask stays untouched.
    outline = normalized_display_outline(mask, px_scale=px_scale)
    if outline is None or len(outline) < 3:
        dense = _poly_norm(cnt, w, h)
        if len(dense) > DISPLAY_OUTLINE_MAX:
            outline = _even_sample_closed(dense, DISPLAY_OUTLINE_MAX)
        elif len(dense) < DISPLAY_OUTLINE_MIN:
            outline = _even_sample_closed(dense, DISPLAY_OUTLINE_MIN)
        else:
            outline = dense
    edit_handles = anatomical_edit_handles_from_mask(
        mask,
        max_points=EDIT_HANDLES_MAX,
        min_points=EDIT_HANDLES_MIN,
    )

    x, y, bw, bh = cv2.boundingRect(cnt)
    bbox = _padded_bbox(x, y, bw, bh, w, h)
    label = {
        "x": round((x + bw / 2) / w, 5),
        "y": round(max(0.0, (y - 4) / h), 5),
    }

    try:
        axis_obj = tooth_long_axis(mask)
    except ValueError:
        axis_obj = None

    zone_lines = _zone_divider_lines(mask, w, h, axis=axis_obj)
    clinical_axis = _clinical_axis_line(mask, w, h, axis=axis_obj)
    width_ticks = _width_ticks(mask, w, h, axis=axis_obj)
    zone_outlines: dict[str, list[list[float]]] = {}
    if zone_masks:
        for name in ZONES:
            zm = zone_masks.get(name)
            if zm is None:
                continue
            zc = _mask_outline(zm, w, h)
            if zc:
                zone_outlines[name] = zc

    return {
        "outline": outline,
        "edit_handles": edit_handles,
        "bbox": bbox,
        "label": label,
        "axis": clinical_axis,
        "width_ticks": width_ticks,
        "zone_lines": zone_lines,
        "zone_outlines": zone_outlines,
    }


def anatomical_edit_handles_from_mask(
    mask: np.ndarray,
    *,
    max_points: int = EDIT_HANDLES_MAX,
    min_points: int = EDIT_HANDLES_MIN,
) -> list[list[float]]:
    """Place edit dots at cervical / incisal / contact landmarks on the mask.

    Pure Douglas–Peucker extrema often miss mesial/distal and cervical corners.
    Landmarks are taken from the dense contour, ordered around the ring, then
    capped to [min_points, max_points].
    """
    import cv2

    if mask.dtype != bool:
        mask = mask.astype(bool)
    h, w = mask.shape
    if h < 2 or w < 2 or int(mask.sum()) < 8:
        return []

    u8 = (mask.astype(np.uint8)) * 255
    # CHAIN_APPROX_NONE keeps every boundary pixel for landmark search.
    contours, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not contours:
        return []
    cnt = max(contours, key=cv2.contourArea)
    pts_xy = cnt.reshape(-1, 2).astype(np.float64)
    n = int(pts_xy.shape[0])
    if n < 3:
        return [[round(float(p[0]) / w, 5), round(float(p[1]) / h, 5)] for p in pts_xy]

    try:
        axis = tooth_long_axis(mask)
        direction = np.asarray(axis.direction_yx, dtype=np.float64)
        centroid = np.asarray(axis.centroid_yx, dtype=np.float64)
    except ValueError:
        return simplify_normalized_outline(
            [[round(float(p[0]) / w, 5), round(float(p[1]) / h, 5)] for p in pts_xy],
            max_points=max_points,
            min_points=min_points,
        )

    pts_yx = np.column_stack([pts_xy[:, 1], pts_xy[:, 0]])
    proj = (pts_yx - centroid) @ direction
    perp = np.array([-direction[1], direction[0]], dtype=np.float64)
    lat = pts_yx @ perp
    lo = float(proj.min())
    hi = float(proj.max())
    span = max(hi - lo, 1e-6)

    landmark: set[int] = set()
    landmark.add(int(np.argmin(proj)))  # cervical tip
    landmark.add(int(np.argmax(proj)))  # incisal tip
    landmark.add(int(np.argmin(lat)))  # contact / side
    landmark.add(int(np.argmax(lat)))  # contact / side

    # Lateral extrema in cervical → incisal bands (corners + waist).
    band_cuts = (0.18, 0.40, 0.65, 0.85)
    prev = lo
    for cut in band_cuts:
        hi_b = lo + cut * span
        band = (proj >= prev) & (proj <= hi_b)
        idxs = np.flatnonzero(band)
        if idxs.size >= 2:
            landmark.add(int(idxs[int(np.argmin(lat[idxs]))]))
            landmark.add(int(idxs[int(np.argmax(lat[idxs]))]))
        elif idxs.size == 1:
            landmark.add(int(idxs[0]))
        prev = hi_b

    ordered = [i for i in range(n) if i in landmark]
    if len(ordered) < min_points:
        step = max(1, n // min_points)
        for i in range(0, n, step):
            landmark.add(i)
        ordered = [i for i in range(n) if i in landmark]

    if len(ordered) > max_points:
        ordered = _thin_contour_indices(ordered, pts_xy, max_points)

    handles = [
        [round(float(pts_xy[i][0]) / w, 5), round(float(pts_xy[i][1]) / h, 5)]
        for i in ordered
    ]
    while len(handles) < min_points:
        best_i, best_len = 0, -1.0
        m = len(handles)
        for i in range(m):
            a = handles[i]
            b = handles[(i + 1) % m]
            d = (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2
            if d > best_len:
                best_len = d
                best_i = i
        a = handles[best_i]
        b = handles[(best_i + 1) % m]
        mid = [round(0.5 * (a[0] + b[0]), 5), round(0.5 * (a[1] + b[1]), 5)]
        handles = handles[: best_i + 1] + [mid] + handles[best_i + 1 :]
    return handles


def _thin_contour_indices(
    ordered: list[int],
    pts_xy: np.ndarray,
    max_points: int,
) -> list[int]:
    """Greedy keep: preserve spread along the ring up to max_points."""
    if len(ordered) <= max_points:
        return ordered
    # Seed with first point, then repeatedly add the index farthest (in arc
    # steps) from the nearest already-kept neighbor along the ordered ring.
    keep = [ordered[0]]
    remaining = ordered[1:]
    while len(keep) < max_points and remaining:
        best_j = 0
        best_score = -1.0
        for j, idx in enumerate(remaining):
            px, py = pts_xy[idx]
            dist = min(
                (px - pts_xy[k][0]) ** 2 + (py - pts_xy[k][1]) ** 2 for k in keep
            )
            if dist > best_score:
                best_score = dist
                best_j = j
        keep.append(remaining.pop(best_j))
    # Re-order around the original contour
    keep_set = set(keep)
    return [i for i in ordered if i in keep_set]


def _mask_outline(mask: np.ndarray, w: int, h: int) -> list[list[float]]:
    import cv2

    u8 = (mask.astype(np.uint8)) * 255
    contours, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return []
    cnt = max(contours, key=cv2.contourArea)
    epsilon = max(0.5, 0.004 * cv2.arcLength(cnt, True))
    approx = cv2.approxPolyDP(cnt, epsilon, True)
    outline = _poly_norm(approx, w, h)
    if len(outline) > 64:
        outline = simplify_normalized_outline(outline, max_points=64, min_points=12)
    return outline


def _even_sample_closed(pts: list[list[float]], count: int) -> list[list[float]]:
    """Arc-length resample a closed ring so a spline can follow the crown."""
    if len(pts) < 3 or count < 3:
        return pts
    arr = np.asarray(pts, dtype=np.float64)
    nxt = np.roll(arr, -1, axis=0)
    seg = np.sqrt(((nxt - arr) ** 2).sum(axis=1))
    peri = float(seg.sum())
    if peri < 1e-9:
        return [[round(float(p[0]), 5), round(float(p[1]), 5)] for p in pts[:count]]
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    out: list[list[float]] = []
    j = 0
    n = int(arr.shape[0])
    for t in np.linspace(0.0, peri, count, endpoint=False):
        while j + 1 < len(cum) and cum[j + 1] <= t:
            j += 1
        span = cum[j + 1] - cum[j]
        u = 0.0 if span < 1e-12 else (t - cum[j]) / span
        a = arr[j % n]
        b = arr[(j + 1) % n]
        p = a + u * (b - a)
        out.append([round(float(p[0]), 5), round(float(p[1]), 5)])
    return out


def _taubin_closed(
    pts: np.ndarray, *, iterations: int, lam: float = 0.5, mu: float = -0.53
) -> np.ndarray:
    """Taubin smoothing of a closed ring: removes jaggies without shrinking."""
    p = np.asarray(pts, dtype=np.float64).copy()
    for _ in range(int(iterations)):
        for k in (lam, mu):
            avg = 0.5 * (np.roll(p, 1, axis=0) + np.roll(p, -1, axis=0))
            p += k * (avg - p)
    return p

def _poly_norm(approx: np.ndarray, w: int, h: int) -> list[list[float]]:
    out: list[list[float]] = []
    for p in approx:
        x = float(p[0][0]) / w
        y = float(p[0][1]) / h
        out.append([round(x, 5), round(y, 5)])
    return out


def simplify_normalized_outline(
    outline: list[list[float]],
    *,
    max_points: int = EDIT_HANDLES_MAX,
    min_points: int = EDIT_HANDLES_MIN,
) -> list[list[float]]:
    """Reduce a polygon to ~edit-handle count for dentist edge edits.

    Uses approxPolyDP on a unit-square embedding, then inserts midpoints of the
    longest edges if below min_points.
    """
    import cv2

    pts = [[float(p[0]), float(p[1])] for p in outline if len(p) >= 2]
    if len(pts) < 3:
        return pts
    # Work in a large pixel space so epsilon is meaningful
    scale = 1000.0
    arr = np.array(
        [[[p[0] * scale, p[1] * scale]] for p in pts], dtype=np.float32
    )
    peri = float(cv2.arcLength(arr, True))
    if peri < 1e-6:
        return pts[:max_points]

    simplified = pts
    # Increase epsilon until we have ≤ max_points (or give up)
    for frac in (0.01, 0.015, 0.02, 0.03, 0.045, 0.06, 0.08, 0.12):
        approx = cv2.approxPolyDP(arr, frac * peri, True)
        if len(approx) >= 3:
            simplified = [
                [round(float(p[0][0]) / scale, 5), round(float(p[0][1]) / scale, 5)]
                for p in approx
            ]
        if len(simplified) <= max_points:
            break

    # Still too many: take evenly spaced subset of the simplified ring
    if len(simplified) > max_points:
        n = len(simplified)
        idxs = [int(round(i * (n - 1) / (max_points - 1))) for i in range(max_points)]
        # Ensure unique + closed ring order
        seen: set[int] = set()
        ordered: list[list[float]] = []
        for i in idxs:
            if i not in seen:
                seen.add(i)
                ordered.append(simplified[i])
        simplified = ordered if len(ordered) >= 3 else simplified[:max_points]

    # Too few: add midpoints on the longest edges
    while len(simplified) < min_points:
        best_i, best_len = 0, -1.0
        n = len(simplified)
        for i in range(n):
            a = simplified[i]
            b = simplified[(i + 1) % n]
            d = (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2
            if d > best_len:
                best_len = d
                best_i = i
        a = simplified[best_i]
        b = simplified[(best_i + 1) % n]
        mid = [round(0.5 * (a[0] + b[0]), 5), round(0.5 * (a[1] + b[1]), 5)]
        simplified = simplified[: best_i + 1] + [mid] + simplified[best_i + 1 :]

    return simplified


def mask_from_normalized_outline(
    outline: list[list[float]], *, height: int, width: int
) -> np.ndarray:
    """Rasterize a normalized [x,y] polygon into a boolean mask."""
    import cv2

    if height < 2 or width < 2 or len(outline) < 3:
        raise ValueError("outline too small")
    pts = []
    for p in outline:
        if len(p) < 2:
            continue
        x = int(round(float(p[0]) * (width - 1)))
        y = int(round(float(p[1]) * (height - 1)))
        pts.append([x, y])
    if len(pts) < 3:
        raise ValueError("need at least 3 outline points")
    arr = np.array(pts, dtype=np.int32).reshape(-1, 1, 2)
    mask = np.zeros((height, width), dtype=np.uint8)
    cv2.fillPoly(mask, [arr], 255)
    return mask > 0


def _padded_bbox(
    x: int, y: int, bw: int, bh: int, w: int, h: int
) -> dict[str, float]:
    """Axis-aligned box slightly larger than the mask, like clinical overlays."""
    pad_x = max(1.0, 0.02 * float(bw))
    pad_y = max(1.0, 0.02 * float(bh))
    nx = max(0.0, float(x) - pad_x)
    ny = max(0.0, float(y) - pad_y)
    nw = min(float(w) - nx, float(bw) + 2.0 * pad_x)
    nh = min(float(h) - ny, float(bh) + 2.0 * pad_y)
    return {
        "x": round(nx / w, 5),
        "y": round(ny / h, 5),
        "w": round(nw / w, 5),
        "h": round(nh / h, 5),
    }


def _norm_yx(p_yx: np.ndarray, w: int, h: int) -> list[float]:
    return [
        round(float(np.clip(p_yx[1] / w, 0.0, 1.0)), 5),
        round(float(np.clip(p_yx[0] / h, 0.0, 1.0)), 5),
    ]


def _clinical_axis_line(
    mask: np.ndarray,
    w: int,
    h: int,
    *,
    axis: Any | None = None,
) -> list[list[float]] | None:
    """Cervical → incisal long axis, extended a little past the crown."""
    if axis is None:
        try:
            axis = tooth_long_axis(mask)
        except ValueError:
            return None
    ys, xs = np.nonzero(mask)
    if ys.size < 4:
        return None
    pts = np.column_stack([ys.astype(np.float64), xs.astype(np.float64)])
    proj = (pts - axis.centroid_yx) @ axis.direction_yx
    lo = float(proj.min())
    hi = float(proj.max())
    span = hi - lo
    if span < 1e-6:
        return None
    p_cerv = axis.centroid_yx + axis.direction_yx * (lo - 0.06 * span)
    p_inc = axis.centroid_yx + axis.direction_yx * (hi + 0.10 * span)
    return [_norm_yx(p_cerv, w, h), _norm_yx(p_inc, w, h)]


def _width_ticks(
    mask: np.ndarray,
    w: int,
    h: int,
    *,
    axis: Any | None = None,
) -> list[list[list[float]]]:
    """Horizontal width marks at cervical / middle / incisal bands."""
    if axis is None:
        try:
            axis = tooth_long_axis(mask)
        except ValueError:
            return []
    ys, xs = np.nonzero(mask)
    if ys.size < 8:
        return []
    pts = np.column_stack([ys.astype(np.float64), xs.astype(np.float64)])
    proj = (pts - axis.centroid_yx) @ axis.direction_yx
    lo = float(proj.min())
    hi = float(proj.max())
    span = hi - lo
    if span < 1e-6:
        return []
    ticks: list[list[list[float]]] = []
    tol = max(1.25, 0.035 * span)
    for frac in (0.18, 0.50, 0.82):
        t = lo + frac * span
        near = np.abs(proj - t) <= tol
        if int(near.sum()) < 2:
            continue
        band = pts[near]
        i0 = int(np.argmin(band[:, 1]))
        i1 = int(np.argmax(band[:, 1]))
        ticks.append([_norm_yx(band[i0], w, h), _norm_yx(band[i1], w, h)])
    return ticks


def _zone_divider_lines(
    mask: np.ndarray,
    w: int,
    h: int,
    *,
    axis: Any | None = None,
) -> list[list[list[float]]]:
    """Two lines across the tooth at 1/3 and 2/3 along cervical→incisal axis."""
    if axis is None:
        try:
            axis = tooth_long_axis(mask)
        except ValueError:
            return []

    ys, xs = np.nonzero(mask)
    pts = np.column_stack([ys.astype(np.float64), xs.astype(np.float64)])
    proj = (pts - axis.centroid_yx) @ axis.direction_yx
    lo = float(proj.min())
    hi = float(proj.max())
    span = hi - lo
    if span < 1e-6:
        return []

    perp = np.array([-axis.direction_yx[1], axis.direction_yx[0]], dtype=np.float64)
    lines: list[list[list[float]]] = []
    # Tolerance scales mildly with tooth size
    tol = max(1.25, 0.04 * span)
    for frac in (1.0 / 3.0, 2.0 / 3.0):
        t = lo + frac * span
        near = np.abs(proj - t) <= tol
        if int(near.sum()) < 2:
            continue
        band = pts[near]
        dots = band @ perp
        i0 = int(np.argmin(dots))
        i1 = int(np.argmax(dots))
        p0 = band[i0]
        p1 = band[i1]
        # Store as [x, y] normalized
        lines.append(
            [
                [round(float(p0[1]) / w, 5), round(float(p0[0]) / h, 5)],
                [round(float(p1[1]) / w, 5), round(float(p1[0]) / h, 5)],
            ]
        )
    return lines

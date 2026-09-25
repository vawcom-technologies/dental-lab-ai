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
EDIT_HANDLES_MAX = 12
EDIT_HANDLES_MIN = 8


def tooth_display_geometry(
    mask: np.ndarray,
    zone_masks: dict[str, np.ndarray] | None = None,
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

    # Even-sample the pixel contour. Douglas–Peucker here rounded off
    # incisal corners before the app drew the ring.
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

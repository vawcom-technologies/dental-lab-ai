"""Geometry helpers for drawing tooth outlines and zone splits on photos.

Coordinates are normalized to [0, 1] as [x, y] (image width/height) so the
Flutter overlay can map them under BoxFit.contain regardless of display size.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from app.ai.shade_zones import ZONES, tooth_long_axis


def tooth_display_geometry(
    mask: np.ndarray,
    zone_masks: dict[str, np.ndarray] | None = None,
) -> dict[str, Any] | None:
    """Build outline, bbox, zone divider lines, and optional zone outlines."""
    import cv2

    if mask.dtype != bool:
        mask = mask.astype(bool)
    h, w = mask.shape
    if h < 2 or w < 2 or int(mask.sum()) < 8:
        return None

    u8 = (mask.astype(np.uint8)) * 255
    contours, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None
    cnt = max(contours, key=cv2.contourArea)
    if cv2.contourArea(cnt) < 8:
        return None

    # Sparse ring for soft-curve display (~6–12 verts). Flutter rounds corners.
    epsilon = max(1.0, 0.016 * cv2.arcLength(cnt, True))
    approx = cv2.approxPolyDP(cnt, epsilon, True)
    outline = simplify_normalized_outline(
        _poly_norm(approx, w, h), max_points=12, min_points=6
    )

    x, y, bw, bh = cv2.boundingRect(cnt)
    bbox = {
        "x": round(x / w, 5),
        "y": round(y / h, 5),
        "w": round(bw / w, 5),
        "h": round(bh / h, 5),
    }
    label = {
        "x": round((x + bw / 2) / w, 5),
        "y": round(max(0.0, (y - 4) / h), 5),
    }

    zone_lines = _zone_divider_lines(mask, w, h)
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
        "bbox": bbox,
        "label": label,
        "zone_lines": zone_lines,
        "zone_outlines": zone_outlines,
    }


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
    max_points: int = 6,
    min_points: int = 4,
) -> list[list[float]]:
    """Reduce a polygon to ~4–6 control points for dentist edge edits.

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


def _zone_divider_lines(mask: np.ndarray, w: int, h: int) -> list[list[list[float]]]:
    """Two lines across the tooth at 1/3 and 2/3 along cervical→incisal axis."""
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

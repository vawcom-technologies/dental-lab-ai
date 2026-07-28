"""Scan body diameter → tooth position + manufacturer (Week 3).

Measures the outer platform diameter of an implant scan body (typical 3–6 mm).

Photo path cannot know millimetres without a scale. Pipeline:
  1. Find the circular scan body (Hough + contours + radial edge refine)
  2. If calibrated (known mm or pixels/mm) → convert to mm and match table
  3. If not → return pixel size only + ask user to enter mm / pick table / calibrate
"""

from __future__ import annotations

import io
import math
from typing import Any

import numpy as np

# Provisional lookup (mm) — REPLACE with client's manufacturer table
DIAMETER_TABLE: list[dict[str, Any]] = [
    {"diameter_mm": 3.0, "manufacturer": "Straumann", "tooth_position": "14", "platform": "Narrow"},
    {"diameter_mm": 3.3, "manufacturer": "Straumann", "tooth_position": "12", "platform": "Narrow"},
    {"diameter_mm": 3.5, "manufacturer": "Straumann", "tooth_position": "15", "platform": "Regular"},
    {"diameter_mm": 3.75, "manufacturer": "Nobel Biocare", "tooth_position": "13", "platform": "NP"},
    {"diameter_mm": 4.0, "manufacturer": "Nobel Biocare", "tooth_position": "16", "platform": "RP"},
    {"diameter_mm": 4.1, "manufacturer": "Straumann", "tooth_position": "24", "platform": "Regular"},
    {"diameter_mm": 4.3, "manufacturer": "Nobel Biocare", "tooth_position": "25", "platform": "RP"},
    {"diameter_mm": 4.5, "manufacturer": "BioHorizons", "tooth_position": "26", "platform": "Internal"},
    {"diameter_mm": 4.8, "manufacturer": "Straumann", "tooth_position": "36", "platform": "Wide"},
    {"diameter_mm": 5.0, "manufacturer": "Nobel Biocare", "tooth_position": "36", "platform": "WP"},
    {"diameter_mm": 5.5, "manufacturer": "Zimmer Biomet", "tooth_position": "46", "platform": "Wide"},
    {"diameter_mm": 6.0, "manufacturer": "Nobel Biocare", "tooth_position": "47", "platform": "WP"},
]

# Clinical implant scan-body platform diameters (mm)
_MIN_MM = 2.8
_MAX_MM = 6.5
_MATCH_TOLERANCE_MM = 0.25


def list_reference_table() -> list[dict[str, Any]]:
    return [dict(row) for row in DIAMETER_TABLE]


def _rank_rows(detected_mm: float) -> list[dict[str, Any]]:
    ranked: list[dict[str, Any]] = []
    for row in DIAMETER_TABLE:
        err = abs(row["diameter_mm"] - detected_mm)
        conf = max(0.0, 1.0 - (err / _MATCH_TOLERANCE_MM))
        conf = round(min(0.99, conf), 3)
        ranked.append({**row, "error_mm": round(err, 3), "confidence_score": conf})
    ranked.sort(key=lambda r: (r["error_mm"], -r["confidence_score"]))
    return ranked


def match_scan_body(detected_diameter_mm: float) -> dict[str, Any]:
    detected = float(detected_diameter_mm)
    if not math.isfinite(detected) or detected <= 0:
        return {
            "detected_diameter": None,
            "matched_tooth_position": None,
            "matched_manufacturer": None,
            "matched_platform": None,
            "table_diameter_mm": None,
            "confidence_score": 0.0,
            "candidates": [],
            "ambiguous": False,
            "unit": "mm",
            "note": "Enter a positive diameter in millimetres (mm), typically 3–6 mm.",
            "provisional": True,
        }

    if not DIAMETER_TABLE:
        return {
            "detected_diameter": round(detected, 2),
            "matched_tooth_position": None,
            "matched_manufacturer": None,
            "matched_platform": None,
            "table_diameter_mm": None,
            "confidence_score": 0.0,
            "candidates": [],
            "ambiguous": False,
            "unit": "mm",
            "note": "No manufacturer reference table yet — request from client.",
            "provisional": True,
        }

    ranked = _rank_rows(detected)
    best = ranked[0]
    second = ranked[1] if len(ranked) > 1 else None
    ambiguous = bool(
        second
        and best["error_mm"] < _MATCH_TOLERANCE_MM
        and abs(best["error_mm"] - second["error_mm"]) < 0.06
    )

    note = (
        "Matched against provisional diameter table. "
        "Replace with client ground-truth before production."
    )
    if detected < _MIN_MM or detected > _MAX_MM:
        note = (
            f"Reading {detected:.2f} mm is outside typical scan-body range "
            f"({_MIN_MM}–{_MAX_MM} mm). Re-measure with a caliper or re-calibrate the photo."
        )
    elif best["error_mm"] > _MATCH_TOLERANCE_MM:
        note = (
            f"No close table match (Δ {best['error_mm']:.2f} mm). "
            "Check measurement / calibration, or pick a row manually."
        )
    elif ambiguous:
        note = (
            f"Close between {best['diameter_mm']} mm ({best['manufacturer']}) and "
            f"{second['diameter_mm']} mm ({second['manufacturer']}). Confirm manually."
        )

    return {
        "detected_diameter": round(detected, 2),
        "matched_tooth_position": best.get("tooth_position"),
        "matched_manufacturer": best.get("manufacturer"),
        "matched_platform": best.get("platform"),
        "table_diameter_mm": best["diameter_mm"],
        "error_mm": best["error_mm"],
        "confidence_score": best["confidence_score"],
        "candidates": ranked[:4],
        "ambiguous": ambiguous,
        "unit": "mm",
        "note": note,
        "provisional": True,
    }


def _resize_max(arr: np.ndarray, max_side: int = 1200) -> tuple[np.ndarray, float]:
    h, w = arr.shape[:2]
    side = max(h, w)
    if side <= max_side:
        return arr, 1.0
    scale = max_side / side
    try:
        import cv2
    except ImportError:
        return arr, 1.0
    out = cv2.resize(arr, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    return out, scale


def _prep_gray(arr: np.ndarray) -> np.ndarray:
    import cv2

    lab = cv2.cvtColor(arr, cv2.COLOR_RGB2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.4, tileGridSize=(8, 8))
    l2 = clahe.apply(l)
    enhanced = cv2.cvtColor(cv2.merge([l2, a, b]), cv2.COLOR_LAB2RGB)
    gray = cv2.cvtColor(enhanced, cv2.COLOR_RGB2GRAY)
    gray = cv2.bilateralFilter(gray, 7, 55, 55)
    return gray


def _circle_score(gray: np.ndarray, x: int, y: int, r: int) -> float:
    """Prefer crisp ring contrast, central placement, plausible size."""
    import cv2

    h, w = gray.shape
    if r < 6 or x - r < 2 or y - r < 2 or x + r >= w - 2 or y + r >= h - 2:
        return -1.0

    short = min(h, w)
    frac = (2 * r) / short
    # Scan bodies in clinical close-ups: typically 6–30% of frame
    if frac < 0.04 or frac > 0.45:
        return -1.0
    size_score = 1.0 - abs(frac - 0.14) / 0.14
    size_score = float(np.clip(size_score, 0.0, 1.0))

    cx, cy = w / 2, h / 2
    dist = math.hypot(x - cx, y - cy) / (math.hypot(cx, cy) + 1e-6)
    center_score = float(np.clip(1.0 - dist * 1.2, 0.0, 1.0))

    mask_disk = np.zeros_like(gray, dtype=np.uint8)
    cv2.circle(mask_disk, (x, y), max(r - 3, 1), 255, -1)
    mask_ring = np.zeros_like(gray, dtype=np.uint8)
    cv2.circle(mask_ring, (x, y), r + 2, 255, 3)
    inner = gray[mask_disk > 0]
    ring = gray[mask_ring > 0]
    if inner.size < 20 or ring.size < 20:
        return -1.0
    contrast = abs(float(np.median(ring)) - float(np.median(inner))) / 255.0
    contrast_score = float(np.clip(contrast * 2.8, 0.0, 1.0))

    size_bonus = float(np.clip((frac - 0.07) / 0.18, 0.0, 1.0)) * 0.08
    return 0.34 * contrast_score + 0.30 * size_score + 0.28 * center_score + size_bonus


def _hough_candidates(gray: np.ndarray) -> list[tuple[int, int, int, float]]:
    import cv2

    h, w = gray.shape
    short = min(h, w)
    min_r = max(8, int(short * 0.03))
    max_r = max(min_r + 10, int(short * 0.24))
    found: list[tuple[int, int, int, float]] = []

    for blur_k, dp, p2 in (
        (5, 1.15, 28),
        (5, 1.2, 22),
        (7, 1.3, 18),
        (3, 1.1, 32),
    ):
        g = cv2.medianBlur(gray, blur_k)
        circles = cv2.HoughCircles(
            g,
            cv2.HOUGH_GRADIENT,
            dp=dp,
            minDist=max(24, short // 8),
            param1=110,
            param2=p2,
            minRadius=min_r,
            maxRadius=max_r,
        )
        if circles is None:
            continue
        for c in np.round(circles[0]).astype(int):
            x, y, r = int(c[0]), int(c[1]), int(c[2])
            score = _circle_score(gray, x, y, r)
            if score > 0.18:
                found.append((x, y, r, score))
    return found


def _contour_candidates(gray: np.ndarray) -> list[tuple[int, int, int, float]]:
    import cv2

    h, w = gray.shape
    short = min(h, w)
    edges = cv2.Canny(gray, 60, 160)
    edges = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1)
    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    found: list[tuple[int, int, int, float]] = []
    for cnt in contours:
        area = cv2.contourArea(cnt)
        if area < (short * 0.035) ** 2 or area > (short * 0.28) ** 2:
            continue
        peri = cv2.arcLength(cnt, True)
        if peri < 1e-6:
            continue
        circularity = 4 * math.pi * area / (peri * peri)
        if circularity < 0.68:
            continue
        (x, y), r = cv2.minEnclosingCircle(cnt)
        xi, yi, ri = int(round(x)), int(round(y)), int(round(r))
        score = _circle_score(gray, xi, yi, ri) * 0.85 + circularity * 0.15
        if score > 0.2:
            found.append((xi, yi, ri, float(score)))
    return found


def _pick_best_circle(
    candidates: list[tuple[int, int, int, float]],
) -> tuple[int, int, int, float] | None:
    if not candidates:
        return None

    clusters: list[list[tuple[int, int, int, float]]] = []
    for cand in sorted(candidates, key=lambda t: -t[3]):
        x, y, r, s = cand
        placed = False
        for cluster in clusters:
            kx, ky, kr, _ = cluster[0]
            if math.hypot(x - kx, y - ky) < max(10, 0.4 * max(kr, r)):
                cluster.append(cand)
                placed = True
                break
        if not placed:
            clusters.append([cand])

    refined: list[tuple[int, int, int, float]] = []
    for cluster in clusters:
        best_score = max(c[3] for c in cluster)
        outer_ok = [
            c
            for c in cluster
            if c[3] >= max(0.42, best_score - 0.28) or c[3] >= best_score * 0.7
        ]
        pick = max(outer_ok or cluster, key=lambda c: (c[2], c[3]))
        refined.append(pick)

    if not refined:
        return None
    return max(refined, key=lambda t: (t[3], t[2]))


def _refine_radius(gray: np.ndarray, x: int, y: int, r: int) -> float:
    """Sub-pixel outer edge via radial gradient peak around a coarse radius."""
    h, w = gray.shape
    if r < 8:
        return float(r)

    angles = np.linspace(0, 2 * math.pi, 72, endpoint=False)
    r_min = max(6, int(r * 0.65))
    r_max = min(int(r * 1.45), min(x, y, w - x - 1, h - y - 1) - 1)
    if r_max <= r_min + 3:
        return float(r)

    radii = np.arange(r_min, r_max + 1)
    profile = np.zeros(len(radii), dtype=np.float64)
    counts = np.zeros(len(radii), dtype=np.float64)

    for a in angles:
        ca, sa = math.cos(a), math.sin(a)
        for i, rr in enumerate(radii):
            px = int(round(x + rr * ca))
            py = int(round(y + rr * sa))
            if 0 <= px < w and 0 <= py < h:
                profile[i] += gray[py, px]
                counts[i] += 1.0

    counts = np.maximum(counts, 1.0)
    profile /= counts
    # Outer platform edge = strongest absolute gradient (bright↔dark)
    grad = np.abs(np.gradient(profile))
    # Prefer peaks near the coarse radius
    prior = np.exp(-0.5 * ((radii - r) / max(3.0, r * 0.12)) ** 2)
    scored = grad * prior
    # Smooth
    if len(scored) >= 5:
        kernel = np.array([0.15, 0.2, 0.3, 0.2, 0.15])
        scored = np.convolve(scored, kernel, mode="same")

    idx = int(np.argmax(scored))
    # Quadratic interpolate around peak
    if 0 < idx < len(radii) - 1:
        y0, y1, y2 = scored[idx - 1], scored[idx], scored[idx + 1]
        denom = (y0 - 2 * y1 + y2)
        if abs(denom) > 1e-9:
            delta = 0.5 * (y0 - y2) / denom
            delta = float(np.clip(delta, -0.5, 0.5))
            return float(radii[idx] + delta)
    return float(radii[idx])


def _empty_detect(
    *,
    note: str,
    image_size: dict[str, int],
    method: str = "none",
) -> dict[str, Any]:
    return {
        "detected_diameter": None,
        "matched_tooth_position": None,
        "matched_manufacturer": None,
        "matched_platform": None,
        "table_diameter_mm": None,
        "confidence_score": 0.0,
        "candidates": [],
        "ambiguous": False,
        "unit": "mm",
        "detection_method": method,
        "needs_calibration": True,
        "pixel_radius": None,
        "pixel_diameter": None,
        "pixels_per_mm": None,
        "calibrated": False,
        "center": None,
        "image_size": image_size,
        "note": note,
        "provisional": True,
        "what_it_measures": (
            "Outer platform diameter of the implant scan body, in millimetres (mm). "
            "Typical values are 3.0–6.0 mm — not metres."
        ),
    }


def detect_diameter_from_image(
    data: bytes,
    pixels_per_mm: float | None = None,
    known_diameter_mm: float | None = None,
) -> dict[str, Any]:
    """Detect circular scan body; convert to mm only with a valid scale.

    Scale resolution order:
    1. ``known_diameter_mm`` — calibrate ppm from detected pixel radius
    2. ``pixels_per_mm`` — explicit scale (must yield 2.8–6.5 mm or rejected)
    3. No scale → return pixel size only; user must enter mm / pick table / calibrate
    """
    try:
        import cv2  # noqa: F401
    except ImportError:
        return {
            **_empty_detect(
                note="OpenCV unavailable — enter diameter manually in millimetres (mm).",
                image_size={"width": 0, "height": 0},
                method="fallback_default",
            )
        }

    from PIL import Image

    img = Image.open(io.BytesIO(data)).convert("RGB")
    arr = np.asarray(img)
    image_size = {"width": int(arr.shape[1]), "height": int(arr.shape[0])}
    work, scale = _resize_max(arr)
    gray = _prep_gray(work)

    candidates = _hough_candidates(gray) + _contour_candidates(gray)
    best = _pick_best_circle(candidates)
    if best is None:
        return _empty_detect(
            note=(
                "No circular scan body found. Enter the platform diameter in millimetres "
                "(typically 3–6 mm) from a caliper, or try a clearer close-up photo."
            ),
            image_size=image_size,
        )

    x, y, r, circ_score = best
    r_ref = _refine_radius(gray, x, y, r)
    inv = 1.0 / scale if scale else 1.0
    ox = int(round(x * inv))
    oy = int(round(y * inv))
    oradius = float(r_ref * inv)
    pixel_diameter = 2.0 * oradius

    what = (
        "Outer platform diameter of the implant scan body, in millimetres (mm). "
        "Typical values are 3.0–6.0 mm — not metres."
    )

    base_meta = {
        "detection_method": "hough+contour+radial",
        "circle_score": round(circ_score, 3),
        "pixel_radius": round(oradius, 1),
        "pixel_diameter": round(pixel_diameter, 1),
        "center": {"x": ox, "y": oy},
        "image_size": image_size,
        "unit": "mm",
        "what_it_measures": what,
        "provisional": True,
    }

    # --- Calibrated with known physical diameter ---
    if known_diameter_mm and known_diameter_mm > 0:
        ppm = pixel_diameter / float(known_diameter_mm)
        result = match_scan_body(float(known_diameter_mm))
        result.update(base_meta)
        result.update(
            {
                "pixels_per_mm": round(ppm, 3),
                "calibrated": True,
                "needs_calibration": False,
                "confidence_score": round(
                    min(0.99, result["confidence_score"] * 0.55 + circ_score * 0.45),
                    3,
                ),
                "note": (
                    f"Calibrated to {known_diameter_mm:.2f} mm "
                    f"({ppm:.1f} px/mm). " + result["note"]
                ),
            }
        )
        return result

    # --- Explicit pixels/mm (only accept if result is clinically plausible) ---
    if pixels_per_mm is not None and pixels_per_mm > 0:
        ppm = float(pixels_per_mm)
        diameter_mm = pixel_diameter / ppm
        if _MIN_MM <= diameter_mm <= _MAX_MM:
            result = match_scan_body(float(diameter_mm))
            result.update(base_meta)
            result.update(
                {
                    "pixels_per_mm": round(ppm, 3),
                    "calibrated": True,
                    "needs_calibration": False,
                    "confidence_score": round(
                        min(0.99, result["confidence_score"] * 0.6 + circ_score * 0.4),
                        3,
                    ),
                }
            )
            return result
        # Bad scale → fall through to uncalibrated (do NOT return 23 mm etc.)
        base_meta["rejected_scale_mm"] = round(diameter_mm, 2)
        base_meta["rejected_pixels_per_mm"] = round(ppm, 3)

    # --- No usable scale: pixel measurement only ---
    # Suggest nearest mid-table size as a soft hint (not a measurement).
    hint = 4.1
    soft = match_scan_body(hint)
    out = {
        **soft,
        **base_meta,
        "detected_diameter": None,  # critical: do not invent mm
        "matched_tooth_position": None,
        "matched_manufacturer": None,
        "matched_platform": None,
        "table_diameter_mm": None,
        "confidence_score": round(min(0.45, circ_score * 0.5), 3),
        "candidates": soft["candidates"],
        "ambiguous": False,
        "pixels_per_mm": None,
        "calibrated": False,
        "needs_calibration": True,
        "suggested_hint_mm": hint,
        "note": (
            f"Circle found (Ø {pixel_diameter:.0f} px) but scale is unknown — "
            f"this is NOT {pixel_diameter / 20:.1f} mm. "
            "Enter the real diameter in millimetres (caliper), tap a table row, "
            "or calibrate with a known mm value. Typical scan bodies are 3–6 mm."
        ),
    }
    return out

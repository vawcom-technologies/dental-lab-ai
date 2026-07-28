"""Scan body diameter → tooth position + manufacturer (Week 3).

Uses a provisional implant scan-body diameter table until the client
supplies ground-truth data. Optional circle detection on photos via OpenCV.
"""

from __future__ import annotations

import io
from typing import Any

import numpy as np

# Provisional lookup (mm) — REPLACE with client's manufacturer table
DIAMETER_TABLE: list[dict[str, Any]] = [
    {"diameter_mm": 3.0, "manufacturer": "Straumann", "tooth_position": "14", "platform": "Narrow"},
    {"diameter_mm": 3.5, "manufacturer": "Straumann", "tooth_position": "15", "platform": "Regular"},
    {"diameter_mm": 4.0, "manufacturer": "Nobel Biocare", "tooth_position": "16", "platform": "RP"},
    {"diameter_mm": 4.1, "manufacturer": "Straumann", "tooth_position": "24", "platform": "Regular"},
    {"diameter_mm": 4.5, "manufacturer": "BioHorizons", "tooth_position": "26", "platform": "Internal"},
    {"diameter_mm": 5.0, "manufacturer": "Nobel Biocare", "tooth_position": "36", "platform": "WP"},
    {"diameter_mm": 5.5, "manufacturer": "Zimmer Biomet", "tooth_position": "46", "platform": "Wide"},
]


def list_reference_table() -> list[dict[str, Any]]:
    return DIAMETER_TABLE


def match_scan_body(detected_diameter_mm: float) -> dict[str, Any]:
    if not DIAMETER_TABLE:
        return {
            "detected_diameter": detected_diameter_mm,
            "matched_tooth_position": None,
            "matched_manufacturer": None,
            "confidence_score": 0.0,
            "note": "No manufacturer reference table yet — request from client.",
            "provisional": True,
        }
    best = min(
        DIAMETER_TABLE,
        key=lambda row: abs(row["diameter_mm"] - detected_diameter_mm),
    )
    err = abs(best["diameter_mm"] - detected_diameter_mm)
    conf = max(0.0, min(0.99, 1.0 - err / 2.0))
    return {
        "detected_diameter": round(detected_diameter_mm, 2),
        "matched_tooth_position": best.get("tooth_position"),
        "matched_manufacturer": best.get("manufacturer"),
        "matched_platform": best.get("platform"),
        "table_diameter_mm": best["diameter_mm"],
        "confidence_score": round(conf, 3),
        "note": (
            "Matched against provisional diameter table. "
            "Replace with client ground-truth before production."
        ),
        "provisional": True,
    }


def detect_diameter_from_image(data: bytes, pixels_per_mm: float = 20.0) -> dict[str, Any]:
    """Detect largest circular feature; convert to mm using pixels_per_mm scale."""
    try:
        import cv2
    except ImportError:
        return {
            **match_scan_body(4.0),
            "detection_method": "fallback_default",
            "note": "OpenCV unavailable — enter diameter manually.",
        }

    from PIL import Image

    img = Image.open(io.BytesIO(data)).convert("RGB")
    arr = np.asarray(img)
    gray = cv2.cvtColor(arr, cv2.COLOR_RGB2GRAY)
    gray = cv2.medianBlur(gray, 5)
    circles = cv2.HoughCircles(
        gray,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=40,
        param1=100,
        param2=30,
        minRadius=8,
        maxRadius=0,
    )
    if circles is None:
        return {
            "detected_diameter": None,
            "matched_tooth_position": None,
            "matched_manufacturer": None,
            "confidence_score": 0.0,
            "detection_method": "hough_none",
            "note": "No circular scan body found — enter diameter (mm) manually.",
            "provisional": True,
        }

    circles = np.round(circles[0]).astype(int)
    # Largest radius
    x, y, r = max(circles, key=lambda c: c[2])
    diameter_mm = (2 * r) / max(pixels_per_mm, 1e-6)
    result = match_scan_body(float(diameter_mm))
    result.update(
        {
            "detection_method": "hough_circles",
            "pixel_radius": int(r),
            "pixels_per_mm": pixels_per_mm,
            "center": {"x": int(x), "y": int(y)},
        }
    )
    return result

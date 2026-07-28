"""VITA Classical shade suggestion (Week 3).

Uses Lab-ish distance against calibrated centroids. Optional sampling from
client VITA guide image when present.
"""

from __future__ import annotations

import io
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

# Base centroids (sRGB) — refined if guide image is available
VITA_SHADES: dict[str, tuple[float, float, float]] = {
    "A1": (242, 224, 201),
    "A2": (236, 210, 180),
    "A3": (226, 192, 156),
    "A3.5": (214, 176, 138),
    "A4": (198, 158, 122),
    "B1": (244, 230, 210),
    "B2": (236, 216, 188),
    "B3": (224, 196, 160),
    "B4": (210, 178, 140),
    "C1": (230, 214, 196),
    "C2": (214, 194, 172),
    "C3": (196, 174, 150),
    "C4": (176, 154, 132),
    "D2": (228, 208, 186),
    "D3": (210, 186, 160),
    "D4": (196, 172, 146),
}

_GUIDE_PATHS = [
    Path(__file__).resolve().parents[3] / "references" / "shades" / "vita-classical-a1-d4.png",
    Path(__file__).resolve().parents[3] / "mobile" / "assets" / "clinical" / "vita-classical-a1-d4.png",
]


def _rgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """Approximate sRGB→Lab for relative matching."""
    r = rgb / 255.0
    # linearize
    r = np.where(r > 0.04045, ((r + 0.055) / 1.055) ** 2.4, r / 12.92)
    x = r[0] * 0.4124 + r[1] * 0.3576 + r[2] * 0.1805
    y = r[0] * 0.2126 + r[1] * 0.7152 + r[2] * 0.0722
    z = r[0] * 0.0193 + r[1] * 0.1192 + r[2] * 0.9505
    x, y, z = x / 0.95047, y / 1.0, z / 1.08883

    def f(t: float) -> float:
        return t ** (1 / 3) if t > 0.008856 else (7.787 * t) + 16 / 116

    fx, fy, fz = f(x), f(y), f(z)
    return np.array([116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)], dtype=np.float64)


def _try_calibrate_from_guide() -> dict[str, tuple[float, float, float]]:
    """Sample evenly across guide tooth row if image exists (best-effort)."""
    path = next((p for p in _GUIDE_PATHS if p.exists()), None)
    if path is None:
        return VITA_SHADES
    try:
        img = Image.open(path).convert("RGB")
        arr = np.asarray(img, dtype=np.float64)
        h, w, _ = arr.shape
        # Sample mid-height of shade tabs (upper portion of guide photo)
        y = int(h * 0.28)
        # Classical order on many guides (left→right) often B1 A1 B2 ... — keep named map stable:
        # sample 16 slots across width for A1..D4 keys in our dict order
        keys = list(VITA_SHADES.keys())
        calibrated = dict(VITA_SHADES)
        for i, key in enumerate(keys):
            x = int(w * (0.08 + 0.84 * (i + 0.5) / len(keys)))
            patch = arr[max(0, y - 8) : y + 8, max(0, x - 6) : x + 6]
            if patch.size:
                mean = patch.reshape(-1, 3).mean(axis=0)
                calibrated[key] = (float(mean[0]), float(mean[1]), float(mean[2]))
        return calibrated
    except Exception:
        return VITA_SHADES


_CALIBRATED = _try_calibrate_from_guide()


def _mean_rgb(image: Image.Image, center_ratio: float = 0.3) -> np.ndarray:
    rgb = image.convert("RGB")
    arr = np.asarray(rgb, dtype=np.float64)
    h, w, _ = arr.shape
    cy, cx = h // 2, w // 2
    rh, rw = max(1, int(h * center_ratio / 2)), max(1, int(w * center_ratio / 2))
    crop = arr[cy - rh : cy + rh, cx - rw : cx + rw]
    return crop.reshape(-1, 3).mean(axis=0)


def suggest_shade_from_bytes(data: bytes) -> dict[str, Any]:
    image = Image.open(io.BytesIO(data))
    mean = _mean_rgb(image)
    mean_lab = _rgb_to_lab(mean)
    scored: list[tuple[str, float]] = []
    for shade, rgb in _CALIBRATED.items():
        dist = float(np.linalg.norm(mean_lab - _rgb_to_lab(np.asarray(rgb, dtype=np.float64))))
        scored.append((shade, dist))
    scored.sort(key=lambda x: x[1])
    best_shade, best_dist = scored[0]
    # Lab distances are smaller scale than RGB
    confidence = max(0.0, min(0.97, 1.0 - (best_dist / 60.0)))
    top = [{"shade": s, "distance": round(d, 2)} for s, d in scored[:5]]
    return {
        "suggested_shade": best_shade,
        "confidence": round(confidence, 3),
        "top_matches": top,
        "sampled_rgb": [round(float(x), 1) for x in mean.tolist()],
        "calibrated_from_guide": any(p.exists() for p in _GUIDE_PATHS),
        "note": (
            "Week 3 shade matcher (Lab distance"
            + (", calibrated from VITA guide image)" if any(p.exists() for p in _GUIDE_PATHS) else ")")
            + ". Manual override remains required."
        ),
    }

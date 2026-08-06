"""VITA Classical shade matching — CIE Lab + CIEDE2000.

Per-zone analysis uses match_lab_nearest (raw ΔE). Segmentation owns sampling.
"""

from __future__ import annotations

import math
from typing import Any

import numpy as np

# ponytail: mid-body mean from vita_teeth PNGs
VITA_SHADES: dict[str, tuple[float, float, float]] = {
    "A1": (210, 199, 169),
    "A2": (206, 188, 143),
    "A3": (208, 192, 154),
    "A3.5": (203, 181, 131),
    "A4": (191, 166, 119),
    "B1": (210, 202, 174),
    "B2": (206, 193, 154),
    "B3": (205, 185, 136),
    "B4": (201, 180, 128),
    "C1": (198, 187, 155),
    "C2": (192, 177, 137),
    "C3": (190, 175, 134),
    "C4": (181, 157, 112),
    "D2": (200, 188, 157),
    "D3": (200, 183, 143),
    "D4": (197, 182, 136),
}

# Override-only Target guide tabs (not used for CIEDE2000 matching).
TARGET_SHADES = frozenset({"M1", "M2", "M3"})
ALLOWED_SHADES = frozenset(VITA_SHADES) | TARGET_SHADES


def _rgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    arr = np.asarray(rgb, dtype=np.float64)
    single = arr.ndim == 1
    if single:
        arr = arr.reshape(1, 3)

    r = arr / 255.0
    r = np.where(r > 0.04045, ((r + 0.055) / 1.055) ** 2.4, r / 12.92)
    x = r[:, 0] * 0.4124564 + r[:, 1] * 0.3575761 + r[:, 2] * 0.1804375
    y = r[:, 0] * 0.2126729 + r[:, 1] * 0.7151522 + r[:, 2] * 0.0721750
    z = r[:, 0] * 0.0193339 + r[:, 1] * 0.1191920 + r[:, 2] * 0.9503041
    x, y, z = x / 0.95047, y / 1.00000, z / 1.08883
    eps = 0.008856

    def f(t: np.ndarray) -> np.ndarray:
        return np.where(t > eps, np.cbrt(t), (7.787 * t) + 16.0 / 116.0)

    fx, fy, fz = f(x), f(y), f(z)
    lab = np.stack([116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)], axis=1)
    return lab[0] if single else lab


_VITA_LAB = {k: _rgb_to_lab(np.asarray(v, dtype=np.float64)) for k, v in VITA_SHADES.items()}


def _delta_e_cie2000(lab1: np.ndarray, lab2: np.ndarray) -> float:
    """CIEDE2000 color difference (Sharma et al.)."""
    L1, a1, b1 = float(lab1[0]), float(lab1[1]), float(lab1[2])
    L2, a2, b2 = float(lab2[0]), float(lab2[1]), float(lab2[2])

    C1 = math.hypot(a1, b1)
    C2 = math.hypot(a2, b2)
    C_bar = 0.5 * (C1 + C2)
    C_bar7 = C_bar**7
    G = 0.5 * (1.0 - math.sqrt(C_bar7 / (C_bar7 + 25.0**7)))

    a1p = (1.0 + G) * a1
    a2p = (1.0 + G) * a2
    C1p = math.hypot(a1p, b1)
    C2p = math.hypot(a2p, b2)

    def _hp(ap: float, bp: float, cp: float) -> float:
        if cp == 0:
            return 0.0
        h = math.degrees(math.atan2(bp, ap))
        return h + 360.0 if h < 0 else h

    h1p = _hp(a1p, b1, C1p)
    h2p = _hp(a2p, b2, C2p)

    dLp = L2 - L1
    dCp = C2p - C1p

    if C1p * C2p == 0:
        dhp = 0.0
    else:
        dh = h2p - h1p
        if dh > 180:
            dh -= 360
        elif dh < -180:
            dh += 360
        dhp = 2.0 * math.sqrt(C1p * C2p) * math.sin(math.radians(dh) / 2.0)

    Lbp = 0.5 * (L1 + L2)
    Cbp = 0.5 * (C1p + C2p)

    if C1p * C2p == 0:
        hbp = h1p + h2p
    else:
        hsum = h1p + h2p
        hdiff = abs(h1p - h2p)
        if hdiff > 180:
            hbp = (hsum + 360.0) * 0.5 if hsum < 360 else (hsum - 360.0) * 0.5
        else:
            hbp = hsum * 0.5

    T = (
        1.0
        - 0.17 * math.cos(math.radians(hbp - 30.0))
        + 0.24 * math.cos(math.radians(2.0 * hbp))
        + 0.32 * math.cos(math.radians(3.0 * hbp + 6.0))
        - 0.20 * math.cos(math.radians(4.0 * hbp - 63.0))
    )
    d_ro = 30.0 * math.exp(-(((hbp - 275.0) / 25.0) ** 2))
    Cbp7 = Cbp**7
    Rc = 2.0 * math.sqrt(Cbp7 / (Cbp7 + 25.0**7))
    Sl = 1.0 + (0.015 * (Lbp - 50.0) ** 2) / math.sqrt(20.0 + (Lbp - 50.0) ** 2)
    Sc = 1.0 + 0.045 * Cbp
    Sh = 1.0 + 0.015 * Cbp * T
    Rt = -math.sin(math.radians(2.0 * d_ro)) * Rc

    # Slightly de-emphasize lightness (clinic lighting varies a lot)
    kL, kC, kH = 1.15, 1.0, 1.0
    return float(
        math.sqrt(
            (dLp / (kL * Sl)) ** 2
            + (dCp / (kC * Sc)) ** 2
            + (dhp / (kH * Sh)) ** 2
            + Rt * (dCp / (kC * Sc)) * (dhp / (kH * Sh))
        )
    )


def match_lab_nearest(
    sample_lab: np.ndarray,
    *,
    top_n: int = 3,
) -> dict[str, Any]:
    """Nearest VITA Classical shade by raw CIEDE2000 (no chroma/family reweighting).

    Used for per-zone matching where the goal is color fidelity to the photo.
    """
    lab = np.asarray(sample_lab, dtype=np.float64).reshape(3)
    scored = [
        (shade, _delta_e_cie2000(lab, _VITA_LAB[shade]))
        for shade in VITA_SHADES
    ]
    scored.sort(key=lambda x: x[1])
    best_shade, best_de = scored[0]
    return {
        "shade": best_shade,
        "delta_e_2000": float(best_de),
        "top_matches": [
            {"shade": s, "delta_e_2000": round(float(d), 2)}
            for s, d in scored[: max(1, top_n)]
        ],
    }

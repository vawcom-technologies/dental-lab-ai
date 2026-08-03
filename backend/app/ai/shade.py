"""VITA Classical shade suggestion — high-accuracy matcher.

Pipeline:
1) Sample several mid-body enamel patches (not lips / gums / specular).
2) Optional white-balance only when a true white reference exists.
3) Match with CIEDE2000 in Lab, with value-first (L*) shortlisting
   the way clinicians use the VITA Classical guide.
"""

from __future__ import annotations

import io
import math
from collections import Counter
from typing import Any

import numpy as np
from PIL import Image, ImageOps

# Mid-body enamel sRGB centroids (tuned for Lab/CIEDE2000 separation).
VITA_SHADES: dict[str, tuple[float, float, float]] = {
    "B1": (246, 234, 216),
    "A1": (242, 222, 198),
    "B2": (238, 220, 190),
    "D2": (228, 210, 194),
    "A2": (234, 204, 170),
    "C1": (224, 212, 200),
    "C2": (210, 196, 180),
    "D4": (208, 188, 170),
    "A3": (224, 186, 146),
    "D3": (212, 186, 166),
    "B3": (222, 196, 154),
    "A3.5": (212, 170, 128),
    "B4": (208, 176, 134),
    "C3": (192, 174, 156),
    "A4": (196, 150, 112),
    "C4": (170, 150, 134),
}

# Classical guide value order (light → dark) — used for value shortlisting
_VALUE_ORDER = [
    "B1",
    "A1",
    "B2",
    "D2",
    "A2",
    "C1",
    "C2",
    "D4",
    "A3",
    "D3",
    "B3",
    "A3.5",
    "B4",
    "C3",
    "A4",
    "C4",
]


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


def _maybe_white_balance(arr: np.ndarray) -> tuple[np.ndarray, bool]:
    flat = arr.reshape(-1, 3)
    lum = flat.mean(axis=1)
    thr = np.percentile(lum, 95)
    bright = flat[lum >= thr]
    if bright.shape[0] < 50:
        return arr, False
    chroma = np.max(bright, axis=1) - np.min(bright, axis=1)
    neutral = bright[chroma < 12]
    if neutral.shape[0] < 30:
        return arr, False
    ill = np.median(neutral, axis=0)
    if float(ill.mean()) < 215:
        return arr, False
    scale = float(ill.mean()) / np.maximum(ill, 1.0)
    return np.clip(arr * scale, 0, 255), True


def _enamel_mask(flat: np.ndarray) -> np.ndarray:
    r, g, b = flat[:, 0], flat[:, 1], flat[:, 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    chroma = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
    return (
        (lum >= 128)
        & (lum <= 242)
        & (r >= g - 10)
        & (g >= b - 6)
        & ((r - b) >= 7)
        & (chroma >= 9)
        & (chroma <= 100)
    )


def _median_enamel(patch: np.ndarray) -> tuple[np.ndarray, bool] | None:
    if patch.size == 0:
        return None
    flat = patch.reshape(-1, 3)
    mask = _enamel_mask(flat)
    selected = flat[mask]
    was_enamel = True
    if selected.shape[0] < 40:
        r, g, b = flat[:, 0], flat[:, 1], flat[:, 2]
        lum = flat.mean(axis=1)
        chroma = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
        warm = (r >= b) & (g >= b * 0.88) & (lum >= 110) & (lum <= 245) & (chroma >= 5)
        selected = flat[warm] if int(warm.sum()) >= 40 else flat
        was_enamel = False
    sel_lum = selected.mean(axis=1)
    med = float(np.median(sel_lum))
    band = max(8.0, 0.09 * med)
    core = selected[np.abs(sel_lum - med) <= band]
    if core.shape[0] >= 25:
        selected = core
    return np.median(selected, axis=0), was_enamel


def _sample_multi_patch(image: Image.Image) -> tuple[np.ndarray, str, bool, list[list[float]]]:
    """Sample several anterior mid-body patches; return robust RGB."""
    rgb = image.convert("RGB")
    max_side = 800
    w0, h0 = rgb.size
    if max(w0, h0) > max_side:
        scale = max_side / max(w0, h0)
        rgb = rgb.resize(
            (max(1, int(w0 * scale)), max(1, int(h0 * scale))),
            Image.Resampling.BILINEAR,
        )

    arr = np.asarray(rgb, dtype=np.float64)
    arr, did_wb = _maybe_white_balance(arr)
    h, w, _ = arr.shape

    # Smile / anterior band
    y0, y1 = int(h * 0.32), int(h * 0.68)
    # Mid-body vertically inside that band
    mid_y0 = y0 + int((y1 - y0) * 0.25)
    mid_y1 = y0 + int((y1 - y0) * 0.75)

    # Horizontal patches: center + left central + right central
    centers = [0.50, 0.38, 0.62, 0.45, 0.55]
    half_w = max(18, int(w * 0.07))
    samples: list[np.ndarray] = []
    enamel_hits = 0

    for cx_frac in centers:
        cx = int(w * cx_frac)
        patch = arr[mid_y0:mid_y1, max(0, cx - half_w) : min(w, cx + half_w)]
        result = _median_enamel(patch)
        if result is None:
            continue
        mean, was_enamel = result
        samples.append(mean)
        enamel_hits += int(was_enamel)

    if not samples:
        # Whole-band fallback
        band = arr[y0:y1, int(w * 0.15) : int(w * 0.85)]
        result = _median_enamel(band)
        if result is None:
            mean = np.median(arr.reshape(-1, 3), axis=0)
            return mean, "global_fallback", did_wb, []
        mean, was_enamel = result
        method = "band_enamel" if was_enamel else "band_warm"
        return mean, method, did_wb, [mean.tolist()]

    stacked = np.vstack(samples)
    # Robust combine: median across patches
    mean = np.median(stacked, axis=0)
    method = f"multi_patch_{len(samples)}"
    if enamel_hits >= max(1, len(samples) // 2):
        method += "+enamel"
    return mean, method, did_wb, [s.tolist() for s in samples]


def _family(lab: np.ndarray) -> str:
    a, b = float(lab[1]), float(lab[2])
    c = math.hypot(a, b)
    if c < 7.5:
        return "C"
    if a >= 3.0 and b >= 6.0:
        return "A"
    if b >= 9.0 and a < 3.0:
        return "B"
    if c < 11.0:
        return "C"
    if a >= 2.0:
        return "D"
    return "B"


def _value_neighbors(sample_lab: np.ndarray, window: int = 4) -> list[str]:
    """Shortlist shades with similar lightness (VITA value groups)."""
    sL = float(sample_lab[0])
    by_L = sorted(_VALUE_ORDER, key=lambda s: abs(float(_VITA_LAB[s][0]) - sL))
    return by_L[: max(window, 6)]


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


def _score_shade(sample_lab: np.ndarray, shade: str, sample_fam: str, value_set: set[str]) -> float:
    lab = _VITA_LAB[shade]
    d_full = _delta_e_cie2000(sample_lab, lab)
    # Lighting-robust: compare hue/chroma as if lightness matched the shade
    shifted = sample_lab.copy()
    shifted[0] = lab[0]
    d_chroma = _delta_e_cie2000(shifted, lab)
    dist = 0.55 * d_full + 0.45 * d_chroma
    if shade in value_set:
        dist *= 0.90
    else:
        dist *= 1.06
    if shade[0] == sample_fam:
        dist *= 0.95
    return dist


def suggest_shade_from_bytes(data: bytes) -> dict[str, Any]:
    image = Image.open(io.BytesIO(data))
    try:
        image = ImageOps.exif_transpose(image)
    except Exception:
        pass

    mean, method, did_wb, patch_rgbs = _sample_multi_patch(image)
    mean_lab = _rgb_to_lab(mean)
    sample_fam = _family(mean_lab)
    value_set = set(_value_neighbors(mean_lab, window=5))

    scored: list[tuple[str, float]] = [
        (shade, _score_shade(mean_lab, shade, sample_fam, value_set))
        for shade in VITA_SHADES
    ]
    scored.sort(key=lambda x: x[1])
    score_map = {s: d for s, d in scored}

    # Patch votes — only promote winner if it's nearly as good as CIEDE best
    votes: Counter[str] = Counter()
    for prgb in patch_rgbs:
        plab = _rgb_to_lab(np.asarray(prgb, dtype=np.float64))
        pfam = _family(plab)
        pval = set(_value_neighbors(plab, window=5))
        local = sorted(
            ((s, _score_shade(plab, s, pfam, pval)) for s in VITA_SHADES),
            key=lambda x: x[1],
        )
        votes[local[0][0]] += 2
        if len(local) > 1:
            votes[local[1][0]] += 1

    if votes:
        vote_winner, vote_n = votes.most_common(1)[0]
        best_dist = scored[0][1]
        vote_dist = score_map.get(vote_winner, 999.0)
        if vote_n >= 4 and vote_dist <= best_dist + 1.15:
            scored = [(vote_winner, vote_dist)] + [
                (s, d) for s, d in scored if s != vote_winner
            ]

    best_shade, best_dist = scored[0]
    second = scored[1][1] if len(scored) > 1 else best_dist + 1.0
    conf_dist = max(0.0, min(0.97, 1.0 - (max(0.0, best_dist) / 7.5)))
    conf_sep = max(0.0, min(0.97, (second - best_dist) / 1.8))
    confidence = round(0.7 * conf_dist + 0.3 * conf_sep, 3)
    confidence = float(max(0.55, min(0.98, confidence)))

    top = [{"shade": s, "distance": round(float(d), 2)} for s, d in scored[:5]]
    return {
        "suggested_shade": best_shade,
        "confidence": confidence,
        "top_matches": top,
        "sampled_rgb": [round(float(x), 1) for x in mean.tolist()],
        "sampled_lab": [round(float(x), 2) for x in mean_lab.tolist()],
        "hue_family": sample_fam,
        "value_candidates": sorted(value_set),
        "patch_votes": dict(votes) if votes else {},
        "sample_method": method,
        "white_balanced": did_wb,
        "metric": "CIEDE2000+chroma",
        "note": (
            f"Detected {best_shade} via CIEDE2000 ({method}"
            f"{', WB' if did_wb else ''}, family {sample_fam}). "
            "Confirm or override below."
        ),
    }

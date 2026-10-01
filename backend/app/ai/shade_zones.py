"""Per-tooth cervical / middle / incisal zone split and Lab sampling.

# ASSUMPTION: Cervical → incisal along the tooth long axis toward image bottom
# (smile photos: gingiva above, incisal edge below).
# ASSUMPTION: Specular exclusion uses L* > SPECULAR_L_STAR.
# ASSUMPTION: Edge erosion of EDGE_ERODE_PX before sampling.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from app.ai.shade import _rgb_to_lab

ZONES: tuple[str, str, str] = ("cervical", "middle", "incisal")

SPECULAR_L_STAR = 88.0
EDGE_ERODE_PX = 3
MIN_ZONE_SAMPLE_PIXELS = 12
_SHADOW_L_STAR = 38.0
_INNER_CROP = 0.11
_LAB_MAD_K = 2.5
_MIN_AXIS_PIXELS = 12
_PCA_ELONGATION_MIN = 1.15  # rounder crowns have no reliable tilt → vertical
_MAX_TILT_TAN = 0.70  # ~35° from vertical; steeper axes are blob artifacts


@dataclass(frozen=True)
class ToothAxis:
    centroid_yx: np.ndarray  # shape (2,)
    direction_yx: np.ndarray  # unit vector, cervical → incisal


def tooth_long_axis(mask: np.ndarray) -> ToothAxis:
    """PCA long axis of a tooth mask; oriented cervical → incisal."""
    if mask.dtype != bool:
        mask = mask.astype(bool)
    ys, xs = np.nonzero(mask)
    if ys.size < _MIN_AXIS_PIXELS:
        raise ValueError("mask too small for axis estimation")

    pts = np.column_stack([ys.astype(np.float64), xs.astype(np.float64)])
    centroid = pts.mean(axis=0)
    centered = pts - centroid
    cov = (centered.T @ centered) / max(pts.shape[0] - 1, 1)
    eigvals, eigvecs = np.linalg.eigh(cov)
    order = int(np.argmax(eigvals))
    direction = eigvecs[:, order].copy()
    elongation = float(eigvals[order] / max(float(eigvals[1 - order]), 1e-12))

    # Frontal photos: crowns stand near-vertical. A round crown's PCA axis (or
    # a steep one) is noise and split the 3 zones diagonally — use vertical.
    if (
        elongation < _PCA_ELONGATION_MIN
        or abs(float(direction[1])) > abs(float(direction[0])) * _MAX_TILT_TAN
    ):
        direction = np.array([1.0, 0.0], dtype=np.float64)

    # ASSUMPTION: +row is toward incisal (image bottom).
    if direction[0] < 0:
        direction = -direction
    norm = float(np.linalg.norm(direction))
    if norm < 1e-12:
        direction = np.array([1.0, 0.0], dtype=np.float64)
    else:
        direction = direction / norm
    return ToothAxis(centroid_yx=centroid, direction_yx=direction)


def split_tooth_zones(mask: np.ndarray, *, lower: bool = False) -> dict[str, np.ndarray]:
    """Split a tooth mask into 3 equal-length zones along its own long axis.

    [lower] teeth have the gingiva below and the incisal edge on top, so the
    cervical → incisal order runs up the image instead of down.

    Zones are disjoint and their union equals the input mask (no gaps/overlaps).
    """
    if mask.dtype != bool:
        mask = mask.astype(bool)
    axis = tooth_long_axis(mask)
    ys, xs = np.nonzero(mask)
    pts = np.column_stack([ys.astype(np.float64), xs.astype(np.float64)])
    proj = (pts - axis.centroid_yx) @ axis.direction_yx
    if lower:
        proj = -proj
    lo = float(proj.min())
    hi = float(proj.max())
    span = hi - lo

    zone_id = np.zeros(proj.shape[0], dtype=np.int8)
    if span > 1e-9:
        t1 = lo + span / 3.0
        t2 = lo + 2.0 * span / 3.0
        zone_id[proj >= t1] = 1
        zone_id[proj >= t2] = 2
    # span ~ 0: all pixels stay in cervical (degenerate); caller may reject.

    out: dict[str, np.ndarray] = {}
    for i, name in enumerate(ZONES):
        z = np.zeros_like(mask, dtype=bool)
        sel = zone_id == i
        z[ys[sel], xs[sel]] = True
        out[name] = z
    return out


def sample_zone_lab(
    image_rgb: np.ndarray,
    zone_mask: np.ndarray,
    *,
    specular_l_star: float = SPECULAR_L_STAR,
    erode_px: int = EDGE_ERODE_PX,
    min_pixels: int = MIN_ZONE_SAMPLE_PIXELS,
    max_sample_pixels: int = 400,
    exclude_shadows: bool = True,
    drop_non_enamel: bool = False,
) -> np.ndarray | None:
    """Median CIE Lab of a zone after specular + edge exclusion. None if too few pixels."""
    import cv2

    if image_rgb.shape[:2] != zone_mask.shape[:2]:
        raise ValueError("image and zone_mask shape mismatch")

    mask_u8 = (zone_mask.astype(np.uint8)) * 255
    if erode_px > 0:
        k = 2 * erode_px + 1
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
        eroded = cv2.erode(mask_u8, kernel)
        # If erosion wipes the zone, fall back to uneroded mask.
        if int(np.count_nonzero(eroded)) >= min_pixels:
            mask_u8 = eroded

    ys, xs = np.nonzero(mask_u8)
    if ys.size < min_pixels:
        return None

    # Prefer the inner enamel core — contacts and gingival margin skew Lab.
    y0, y1 = int(ys.min()), int(ys.max())
    x0, x1 = int(xs.min()), int(xs.max())
    py = _INNER_CROP * max(y1 - y0, 1)
    px = _INNER_CROP * max(x1 - x0, 1)
    inner = (
        (ys >= y0 + py)
        & (ys <= y1 - py)
        & (xs >= x0 + px)
        & (xs <= x1 - px)
    )
    if int(inner.sum()) >= min_pixels:
        ys, xs = ys[inner], xs[inner]

    # Subsample for speed on large masks
    if ys.size > max_sample_pixels:
        rng = np.random.default_rng(0)
        pick = rng.choice(ys.size, size=max_sample_pixels, replace=False)
        ys, xs = ys[pick], xs[pick]

    pixels = np.asarray(image_rgb, dtype=np.float64)[ys, xs]
    labs = _rgb_to_lab(pixels)
    keep = labs[:, 0] <= specular_l_star
    if exclude_shadows:
        keep = keep & (labs[:, 0] >= _SHADOW_L_STAR)
    filtered = labs[keep]
    if filtered.shape[0] >= min_pixels:
        labs = filtered
    elif labs.shape[0] < min_pixels:
        return None
    if drop_non_enamel:
        # Pink gingiva (high a*) and gray-blue incisal translucency are not
        # on the VITA enamel scale. Keep them only if the zone is nothing else.
        enamel = (labs[:, 1] <= 8.0) & (labs[:, 2] >= 6.0)
        if int(enamel.sum()) >= min_pixels:
            labs = labs[enamel]
    # Drop chroma / L* outliers (gingiva bleed, restorations) via MAD.
    if labs.shape[0] >= min_pixels + 4:
        med = np.median(labs, axis=0)
        dev = np.abs(labs - med)
        mad = np.maximum(np.median(dev, axis=0), [1.0, 0.8, 0.8])
        inliers = np.all(dev <= _LAB_MAD_K * mad, axis=1)
        if int(inliers.sum()) >= min_pixels:
            labs = labs[inliers]
    return np.median(labs, axis=0)

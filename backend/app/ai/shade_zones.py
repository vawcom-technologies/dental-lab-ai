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

SPECULAR_L_STAR = 90.0
EDGE_ERODE_PX = 2
MIN_ZONE_SAMPLE_PIXELS = 12
_MIN_AXIS_PIXELS = 12
_PCA_ELONGATION_MIN = 1.15  # else fall back to minAreaRect


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

    if elongation < _PCA_ELONGATION_MIN:
        direction = _min_area_rect_direction(mask, centroid)

    # Prefer cervical→incisal (image vertical). Wide gum+tooth blobs otherwise
    # pick a horizontal long axis and draw zone lines the wrong way.
    if abs(float(direction[1])) > abs(float(direction[0])) * 1.1:
        other = eigvecs[:, 1 - order]
        if abs(float(other[0])) >= abs(float(direction[0])):
            direction = other.copy()

    # ASSUMPTION: +row is toward incisal (image bottom).
    if direction[0] < 0:
        direction = -direction
    norm = float(np.linalg.norm(direction))
    if norm < 1e-12:
        direction = np.array([1.0, 0.0], dtype=np.float64)
    else:
        direction = direction / norm
    return ToothAxis(centroid_yx=centroid, direction_yx=direction)


def _min_area_rect_direction(mask: np.ndarray, centroid: np.ndarray) -> np.ndarray:
    """Fallback long-axis direction from cv2.minAreaRect."""
    import cv2

    u8 = (mask.astype(np.uint8)) * 255
    contours, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return np.array([1.0, 0.0], dtype=np.float64)
    cnt = max(contours, key=cv2.contourArea)
    if cv2.contourArea(cnt) < 4:
        return np.array([1.0, 0.0], dtype=np.float64)
    (_cx, _cy), (rw, rh), angle_deg = cv2.minAreaRect(cnt)
    # OpenCV angle: long side orientation in image x/y; convert to (y, x) unit vector.
    if rw < rh:
        angle_deg += 90.0
    theta = np.deg2rad(angle_deg)
    # Image x increases right, y down. Direction along long side:
    dx, dy = np.cos(theta), np.sin(theta)
    direction = np.array([dy, dx], dtype=np.float64)
    # Prefer the orientation closer to vertical tooth axis when ambiguous
    _ = centroid  # API symmetry with PCA path
    return direction


def split_tooth_zones(mask: np.ndarray) -> dict[str, np.ndarray]:
    """Split a tooth mask into 3 equal-length zones along its own long axis.

    Zones are disjoint and their union equals the input mask (no gaps/overlaps).
    """
    if mask.dtype != bool:
        mask = mask.astype(bool)
    axis = tooth_long_axis(mask)
    ys, xs = np.nonzero(mask)
    pts = np.column_stack([ys.astype(np.float64), xs.astype(np.float64)])
    proj = (pts - axis.centroid_yx) @ axis.direction_yx
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

    # Subsample for speed on large masks
    if ys.size > max_sample_pixels:
        rng = np.random.default_rng(0)
        pick = rng.choice(ys.size, size=max_sample_pixels, replace=False)
        ys, xs = ys[pick], xs[pick]

    pixels = np.asarray(image_rgb, dtype=np.float64)[ys, xs]
    labs = _rgb_to_lab(pixels)
    keep = labs[:, 0] <= specular_l_star
    labs = labs[keep]
    if labs.shape[0] < min_pixels:
        # Specular gate too aggressive — use all subsampled pixels
        labs = _rgb_to_lab(pixels)
        if labs.shape[0] < min_pixels:
            return None
    return np.median(labs, axis=0)

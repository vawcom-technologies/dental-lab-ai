"""Orchestrate per-tooth zone shade analysis.

Pipeline: segment → split zones → sample Lab → nearest VITA (CIEDE2000).
Does not persist; does not set override_shade (always null from detection).
"""

from __future__ import annotations

import io
from typing import Any

import numpy as np
from PIL import Image, ImageOps

from app.ai.shade import match_lab_nearest
from app.ai.shade_geometry import (
    mask_from_normalized_outline,
    simplify_normalized_outline,
    tooth_display_geometry,
)
from app.ai.shade_segment import ToothMask, detect_teeth, mask_confidence
from app.ai.shade_zones import ZONES, sample_zone_lab, split_tooth_zones

# ASSUMPTION: Match legacy matcher resize — keeps chairside latency acceptable.
_MAX_SIDE = 800
# ASSUMPTION: Prefer partial zone matches over rejecting the whole tooth.
_MIN_ZONE_PIXELS_FOR_SPLIT = 12


def _load_rgb_from_bytes(data: bytes) -> np.ndarray:
    image = Image.open(io.BytesIO(data))
    try:
        image = ImageOps.exif_transpose(image)
    except Exception:
        pass
    image = image.convert("RGB")
    w0, h0 = image.size
    if max(w0, h0) > _MAX_SIDE:
        scale = _MAX_SIDE / max(w0, h0)
        image = image.resize(
            (max(1, int(w0 * scale)), max(1, int(h0 * scale))),
            Image.Resampling.BILINEAR,
        )
    return np.asarray(image, dtype=np.uint8)


def _maybe_downscale_rgb(arr: np.ndarray) -> np.ndarray:
    h, w, _ = arr.shape
    if max(h, w) <= _MAX_SIDE:
        return arr
    scale = _MAX_SIDE / max(h, w)
    import cv2

    return cv2.resize(
        arr,
        (max(1, int(w * scale)), max(1, int(h * scale))),
        interpolation=cv2.INTER_AREA,
    )


def analyze_shade_from_bytes(data: bytes) -> dict[str, Any]:
    return analyze_shade_from_rgb(_load_rgb_from_bytes(data))


def analyze_shade_from_rgb(image_rgb: np.ndarray) -> dict[str, Any]:
    """Run full per-tooth / per-zone shade analysis on an RGB array."""
    arr = np.asarray(image_rgb)
    if arr.ndim != 3 or arr.shape[2] != 3:
        raise ValueError("image_rgb must be HxWx3")

    arr = _maybe_downscale_rgb(arr)
    teeth = detect_teeth(arr)
    # Only surface usable masks — fragments must not appear as T1..Tn in the UI.
    teeth = [t for t in teeth if not t.rejected]
    tooth_results = [_analyze_tooth(arr, tooth) for tooth in teeth]
    # Re-index after filtering
    for i, row in enumerate(tooth_results):
        row["tooth_index"] = i
        row["label"] = f"Tooth {i + 1}"
    accepted = sum(1 for t in tooth_results if not t["rejected"])
    h, w = arr.shape[:2]
    return {
        "teeth": tooth_results,
        "tooth_count": len(tooth_results),
        "accepted_count": accepted,
        "image_width": w,
        "image_height": h,
        "note": (
            f"Detected {accepted} tooth mask(s) (left → right). "
            "Tap a tooth on the photo or in the list; "
            "lines show cervical / middle / incisal zones."
            if accepted
            else "No reliable tooth masks found — retake with teeth filling the frame, even lighting, lips retracted."
        ),
    }


def analyze_tooth_from_outline_bytes(
    data: bytes,
    outline: list[list[float]],
    *,
    tooth_index: int = 0,
) -> dict[str, Any]:
    """Re-analyze one tooth from a dentist-edited normalized outline.

    Detection still owns auto-masks; this path lets the user nudge boundaries
    and refresh zone Lab / VITA matches without re-segmenting the whole arch.
    """
    return analyze_tooth_from_outline_rgb(
        _load_rgb_from_bytes(data), outline, tooth_index=tooth_index
    )


def analyze_tooth_from_outline_rgb(
    image_rgb: np.ndarray,
    outline: list[list[float]],
    *,
    tooth_index: int = 0,
) -> dict[str, Any]:
    arr = np.asarray(image_rgb)
    if arr.ndim != 3 or arr.shape[2] != 3:
        raise ValueError("image_rgb must be HxWx3")
    arr = _maybe_downscale_rgb(arr)
    h, w = arr.shape[:2]

    # Keep the sparse edit skeleton (≈4–6 points); fillPoly does not need densify.
    handles = simplify_normalized_outline(outline, max_points=6, min_points=4)
    mask = mask_from_normalized_outline(handles, height=h, width=w)
    if int(mask.sum()) < 40:
        raise ValueError("edited outline covers too few pixels")

    tooth = ToothMask(
        tooth_index=tooth_index,
        mask=mask,
        confidence=mask_confidence(mask, h),
        rejected=False,
        reject_reason=None,
    )
    row = _analyze_tooth(arr, tooth)
    row["tooth_index"] = tooth_index
    row["label"] = f"Tooth {tooth_index + 1}"
    row["outline_edited"] = True
    # Preserve the dentist's control points (not a densified ring)
    if isinstance(row.get("geometry"), dict):
        row["geometry"]["outline"] = handles
        row["geometry"]["edited"] = True
    return {
        "tooth": row,
        "image_width": w,
        "image_height": h,
    }


def _analyze_tooth(image_rgb: np.ndarray, tooth: ToothMask) -> dict[str, Any]:
    base: dict[str, Any] = {
        "tooth_index": tooth.tooth_index,
        "label": f"Tooth {tooth.tooth_index + 1}",
        "confidence": tooth.confidence,
        "rejected": tooth.rejected,
        "reject_reason": tooth.reject_reason,
        "zones": {z: _empty_zone() for z in ZONES},
        "geometry": None,
    }
    # Skip only unusable dust; still zone soft-rejected masks so the dentist can pick them.
    if tooth.rejected and tooth.reject_reason == "too_small":
        base["geometry"] = tooth_display_geometry(tooth.mask)
        return base

    try:
        zone_masks = split_tooth_zones(tooth.mask)
    except ValueError:
        base["rejected"] = True
        base["reject_reason"] = tooth.reject_reason or "incomplete"
        base["geometry"] = tooth_display_geometry(tooth.mask)
        return base

    zones_out: dict[str, dict[str, Any]] = {}
    matched_any = False
    for name in ZONES:
        zmask = zone_masks[name]
        if int(zmask.sum()) < _MIN_ZONE_PIXELS_FOR_SPLIT:
            zones_out[name] = _empty_zone()
            continue
        zones_out[name] = _match_zone(image_rgb, zmask)
        if zones_out[name]["detected_shade"] is not None:
            matched_any = True

    base["zones"] = zones_out
    base["geometry"] = tooth_display_geometry(tooth.mask, zone_masks)
    if matched_any:
        # Usable samples win over soft segment rejection.
        base["rejected"] = False
        base["reject_reason"] = None
    elif not tooth.rejected:
        base["rejected"] = True
        base["reject_reason"] = "incomplete"
    return base


def _match_zone(image_rgb: np.ndarray, zone_mask: np.ndarray) -> dict[str, Any]:
    lab = sample_zone_lab(image_rgb, zone_mask)
    if lab is None:
        return _empty_zone()

    matched = match_lab_nearest(lab, top_n=5)
    # Fresh detection: override always null → effective == detected
    return {
        "detected_shade": matched["shade"],
        "delta_e_2000": round(float(matched["delta_e_2000"]), 2),
        "override_shade": None,
        "effective_shade": matched["shade"],
        "sampled_lab": [round(float(x), 2) for x in lab.tolist()],
        "top_matches": matched["top_matches"],
    }


def _empty_zone() -> dict[str, Any]:
    return {
        "detected_shade": None,
        "delta_e_2000": None,
        "override_shade": None,
        "effective_shade": None,
        "sampled_lab": None,
        "top_matches": [],
    }

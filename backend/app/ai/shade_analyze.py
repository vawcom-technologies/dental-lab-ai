"""Orchestrate per-tooth zone shade analysis.

Pipeline: segment → split zones → sample Lab → nearest VITA (CIEDE2000).
Does not persist; does not set override_shade (always null from detection).
"""

from __future__ import annotations

import io
import logging
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import numpy as np
from PIL import Image, ImageOps

logger = logging.getLogger(__name__)
_HEIF_REGISTERED = False


def _register_heif_opener() -> None:
    """App Store iPad still uploads HEIC from Photos (FilePicker, no JPEG bake)."""
    global _HEIF_REGISTERED
    if _HEIF_REGISTERED:
        return
    try:
        from pillow_heif import register_heif_opener

        register_heif_opener()
        _HEIF_REGISTERED = True
    except Exception as exc:
        logger.warning("HEIC opener unavailable — iPad HEIC uploads will fail: %s", exc)

from app.ai.shade import (
    GINGIVA_SHADES,
    confidence_from_delta_e,
    match_lab_nearest,
)
from app.ai.shade_geometry import (
    EDIT_HANDLES_MAX,
    EDIT_HANDLES_MIN,
    mask_from_normalized_outline,
    simplify_normalized_outline,
    tooth_display_geometry,
)
from app.ai.shade_segment import (
    ToothMask,
    detect_gum_mask,
    detect_teeth,
    mask_confidence,
    tooth_display_label,
)
from app.ai.shade_zones import ZONES, sample_zone_lab, split_tooth_zones

# ASSUMPTION: Segment at higher resolution; Lab sampling uses mask pixels at this scale.
_MAX_SIDE_SEGMENT = 1280
_MAX_SIDE = 800  # legacy cap for outline JSON when downscaling uploads
# ASSUMPTION: Prefer partial zone matches over rejecting the whole tooth.
_MIN_ZONE_PIXELS_FOR_SPLIT = 12


def _load_rgb_from_bytes(data: bytes) -> np.ndarray:
    _register_heif_opener()
    try:
        image = Image.open(io.BytesIO(data))
        image.load()
    except Exception as exc:
        raise ValueError(
            "Could not read this photo. Export it as JPEG and try again."
        ) from exc
    icc = image.info.get("icc_profile")
    try:
        image = ImageOps.exif_transpose(image)
    except Exception:
        pass
    if icc and not image.info.get("icc_profile"):
        image.info["icc_profile"] = icc
    image = _to_srgb(image)
    w0, h0 = image.size
    max_side = _segment_max_side()
    if max(w0, h0) > max_side:
        scale = max_side / max(w0, h0)
        image = image.resize(
            (max(1, int(w0 * scale)), max(1, int(h0 * scale))),
            Image.Resampling.BILINEAR,
        )
    return np.asarray(image, dtype=np.uint8)


def _to_srgb(image: Image.Image) -> Image.Image:
    """Map the upload into sRGB so it uses the same space as the shade tabs."""
    icc = image.info.get("icc_profile")
    if icc:
        try:
            from PIL import ImageCms

            src = ImageCms.ImageCmsProfile(io.BytesIO(icc))
            dst = ImageCms.createProfile("sRGB")
            converted = ImageCms.profileToProfile(image, src, dst, outputMode="RGB")
            if converted is not None:
                return converted
        except Exception:
            logger.info("shade photo ICC profile could not be applied")
    return image.convert("RGB")


def _segment_max_side() -> int:
    try:
        from app.core.config import settings

        imgsz = int(settings.shade_segment_imgsz or _MAX_SIDE_SEGMENT)
        return max(_MAX_SIDE_SEGMENT, imgsz)
    except Exception:
        return _MAX_SIDE_SEGMENT


def _maybe_downscale_rgb(arr: np.ndarray) -> np.ndarray:
    h, w, _ = arr.shape
    max_side = _segment_max_side()
    if max(h, w) <= max_side:
        return arr
    scale = max_side / max(h, w)
    import cv2

    return cv2.resize(
        arr,
        (max(1, int(w * scale)), max(1, int(h * scale))),
        interpolation=cv2.INTER_AREA,
    )


def analyze_shade_from_bytes(data: bytes) -> dict[str, Any]:
    started = time.perf_counter()
    rgb = _load_rgb_from_bytes(data)
    logger.info(
        "shade_analyze decode_ms=%.0f bytes=%s",
        (time.perf_counter() - started) * 1000,
        len(data),
    )
    return analyze_shade_from_rgb(rgb)


def analyze_shade_from_rgb(image_rgb: np.ndarray) -> dict[str, Any]:
    """Run full per-tooth / per-zone shade analysis on an RGB array."""
    arr = np.asarray(image_rgb)
    if arr.ndim != 3 or arr.shape[2] != 3:
        raise ValueError("image_rgb must be HxWx3")

    t0 = time.perf_counter()
    arr = _maybe_downscale_rgb(arr)
    downscale_ms = (time.perf_counter() - t0) * 1000
    segment_meta: dict[str, Any] = {}
    t1 = time.perf_counter()
    teeth = detect_teeth(arr, meta_out=segment_meta)
    segment_ms = (time.perf_counter() - t1) * 1000
    # Only surface usable masks — fragments must not appear as T1..Tn in the UI.
    teeth = [t for t in teeth if not t.rejected]
    t2 = time.perf_counter()
    tooth_results = _analyze_teeth(arr, teeth)
    zones_ms = (time.perf_counter() - t2) * 1000
    # Re-index after filtering (preserve arch labels from segmenter).
    for i, (row, tooth) in enumerate(zip(tooth_results, teeth)):
        row["tooth_index"] = i
        row["fdi"] = tooth.fdi
        row["label"] = tooth_display_label(
            ToothMask(
                tooth_index=i,
                mask=tooth.mask,
                confidence=tooth.confidence,
                rejected=tooth.rejected,
                reject_reason=tooth.reject_reason,
                arch=tooth.arch,
                arch_index=tooth.arch_index,
                fdi=tooth.fdi,
            )
        )
        row["arch"] = tooth.arch
        row["arch_index"] = tooth.arch_index
    accepted = sum(1 for t in tooth_results if not t["rejected"])
    h, w = arr.shape[:2]
    dual = any(t.arch for t in teeth)
    note = (
        (
            f"Detected {accepted} tooth mask(s) (ISO 3950, front → back per quadrant). "
            "Tap a tooth on the photo or in the list. "
            "Boxes, axes, and green ticks mark each crown."
        )
        if dual and accepted
        else (
            f"Detected {accepted} tooth mask(s) (ISO 3950, front → back per quadrant). "
            "Tap a tooth on the photo or in the list. "
            "Boxes, axes, and green ticks mark each crown."
        )
        if accepted
        else "No reliable tooth masks found — retake with teeth filling the frame, even lighting, lips retracted."
    )
    backend = segment_meta.get("segment_backend") or "classical"
    requested = segment_meta.get("segment_backend_requested") or backend
    if segment_meta.get("segment_fallback"):
        note = f"[segment={backend}, fallback from {requested}] " + note
    else:
        note = f"[segment={backend}] " + note
    t3 = time.perf_counter()
    gum = _analyze_gum(arr, teeth)
    gum_ms = (time.perf_counter() - t3) * 1000
    logger.info(
        "shade_analyze downscale_ms=%.0f segment_ms=%.0f zones_ms=%.0f gum_ms=%.0f teeth=%s",
        downscale_ms,
        segment_ms,
        zones_ms,
        gum_ms,
        len(tooth_results),
    )
    return {
        "teeth": tooth_results,
        "tooth_count": len(tooth_results),
        "accepted_count": accepted,
        "image_width": w,
        "image_height": h,
        "note": note,
        "gum": gum,
        **segment_meta,
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

    # Client densifies Bezier bulges into a polyline — fill that, not sparse handles
    # (approxPolyDP handles straighten mid-edge curves).
    dense = [[float(p[0]), float(p[1])] for p in outline if len(p) >= 2]
    handles = simplify_normalized_outline(
        dense, max_points=EDIT_HANDLES_MAX, min_points=EDIT_HANDLES_MIN
    )
    mask = mask_from_normalized_outline(dense, height=h, width=w)
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
    # Display keeps the curved polyline; sparse handles are edit-only.
    if isinstance(row.get("geometry"), dict):
        row["geometry"]["edited"] = True
        row["geometry"]["edit_handles"] = handles
        if len(dense) >= 8:
            row["geometry"]["outline"] = dense
    return {
        "tooth": row,
        "image_width": w,
        "image_height": h,
    }


def _geometry_for_tooth(
    tooth: ToothMask,
    zone_masks: dict[str, np.ndarray] | None = None,
) -> dict[str, Any] | None:
    """Outline follows the pre-snap crown; shade zones stay on `tooth.mask`."""
    geo = tooth_display_geometry(tooth.mask, zone_masks)
    outline = tooth.display_outline
    if geo is None or not outline or len(outline) < 3:
        return geo
    pts = [[float(p[0]), float(p[1])] for p in outline]
    geo["outline"] = pts
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    bw = max(1e-4, x1 - x0)
    bh = max(1e-4, y1 - y0)
    pad_x = 0.02 * bw
    pad_y = 0.02 * bh
    nx = max(0.0, x0 - pad_x)
    ny = max(0.0, y0 - pad_y)
    geo["bbox"] = {
        "x": round(nx, 5),
        "y": round(ny, 5),
        "w": round(min(1.0 - nx, bw + 2.0 * pad_x), 5),
        "h": round(min(1.0 - ny, bh + 2.0 * pad_y), 5),
    }
    geo["label"] = {
        "x": round((x0 + x1) / 2.0, 5),
        "y": round(max(0.0, y0 - 0.01), 5),
    }
    return geo


def _analyze_teeth(
    image_rgb: np.ndarray, teeth: list[ToothMask]
) -> list[dict[str, Any]]:
    """Zone Lab + geometry per tooth. Parallel when several crowns are present."""
    if len(teeth) < 3:
        return [_analyze_tooth(image_rgb, t) for t in teeth]
    workers = min(4, len(teeth))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        return list(pool.map(lambda t: _analyze_tooth(image_rgb, t), teeth))


def _analyze_tooth(image_rgb: np.ndarray, tooth: ToothMask) -> dict[str, Any]:
    base: dict[str, Any] = {
        "tooth_index": tooth.tooth_index,
        "label": tooth_display_label(tooth),
        "arch": tooth.arch,
        "arch_index": tooth.arch_index,
        "fdi": tooth.fdi,
        "confidence": tooth.confidence,
        "rejected": tooth.rejected,
        "reject_reason": tooth.reject_reason,
        "zones": {z: _empty_zone() for z in ZONES},
        "geometry": None,
    }
    # Skip only unusable dust; still zone soft-rejected masks so the dentist can pick them.
    if tooth.rejected and tooth.reject_reason == "too_small":
        base["geometry"] = _geometry_for_tooth(tooth)
        return base

    try:
        zone_masks = split_tooth_zones(tooth.mask)
    except ValueError:
        base["rejected"] = True
        base["reject_reason"] = tooth.reject_reason or "incomplete"
        base["geometry"] = _geometry_for_tooth(tooth)
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
    base["geometry"] = _geometry_for_tooth(tooth, zone_masks)
    if matched_any:
        # Usable samples win over soft segment rejection.
        base["rejected"] = False
        base["reject_reason"] = None
    elif not tooth.rejected:
        base["rejected"] = True
        base["reject_reason"] = "incomplete"
    return base


def _match_zone(image_rgb: np.ndarray, zone_mask: np.ndarray) -> dict[str, Any]:
    lab = sample_zone_lab(image_rgb, zone_mask, drop_non_enamel=True)
    if lab is None:
        return _empty_zone()

    matched = match_lab_nearest(lab, top_n=5)
    # corrected_lab is the sample placed on the shared VITA scale's exposure.
    used = matched.get("corrected_lab") or lab.tolist()
    # Fresh detection: override always null → effective == detected
    return {
        "detected_shade": matched["shade"],
        "delta_e_2000": round(float(matched["delta_e_2000"]), 2),
        "override_shade": None,
        "effective_shade": matched["shade"],
        "sampled_lab": [round(float(x), 2) for x in used],
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


def _median_rgb(image_rgb: np.ndarray, mask: np.ndarray) -> list[int]:
    ys, xs = np.nonzero(mask)
    med = np.median(np.asarray(image_rgb, dtype=np.float64)[ys, xs], axis=0)
    return [int(np.clip(round(float(v)), 0, 255)) for v in med]


def _analyze_gum(
    image_rgb: np.ndarray,
    teeth: list[ToothMask],
) -> dict[str, Any] | None:
    """Case-level gingiva shade from tooth-adjacent pink pixels. None if no gum."""
    if not teeth:
        return None
    gum_mask = detect_gum_mask(image_rgb, teeth)
    if gum_mask is None:
        return None
    pixel_count = int(gum_mask.sum())
    # Thin gingival bands vanish if we erode like tooth zones.
    lab = sample_zone_lab(
        image_rgb, gum_mask, erode_px=0, min_pixels=8, exclude_shadows=False
    )
    if lab is None:
        return None
    matched = match_lab_nearest(lab, top_n=5, palette=GINGIVA_SHADES)
    de = float(matched["delta_e_2000"])
    return {
        "detected_shade": matched["shade"],
        "delta_e_2000": round(de, 2),
        "sampled_lab": [round(float(x), 2) for x in lab.tolist()],
        "sampled_rgb": _median_rgb(image_rgb, gum_mask),
        "confidence": round(confidence_from_delta_e(de), 3),
        "pixel_count": pixel_count,
        "top_matches": matched["top_matches"],
    }

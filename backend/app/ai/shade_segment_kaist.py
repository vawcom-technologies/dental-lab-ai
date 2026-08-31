"""KAIST individual tooth segmentation (mireiffe/individual_tooth_segmentation).

Runs the upstream 4-step pipeline (pseudoER → initContour → snake → TEM) on a
mouth crop so outlines match their demo quality. Full-face uploads are cropped
via classical enamel ROI first.

Work image long side is clamped into [min_side, max_side] (defaults 256–320).
Tiny crops upscale only to the floor (not the ceiling — that wasted ~2× snake
time). Large crops downscale. Mid-size crops stay native. Labels map back.

# ASSUMPTION: Vendor checkout at backend/vendor/individual_tooth_segmentation
# ASSUMPTION: Weights at SHADE_SEGMENT_KAIST_WEIGHTS (~1.5 GB .pth)
# ASSUMPTION: RESIZE=False for demo-quality contours (config default)
# ASSUMPTION: Upstream targets ~12 anterior teeth on tight mouth crops
"""

from __future__ import annotations

import logging
import os
import sys
import tempfile
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from app.ai.shade_segment import ToothMask, _sanity_check_instances, mask_confidence

logger = logging.getLogger(__name__)

_MAX_TEETH = 16
_MIN_MASK_PIXELS = 40
_DEFAULT_MAX_SIDE = 320
_DEFAULT_MIN_SIDE = 256
_DEFAULT_WEIGHTS = "weights/kaist/CP_teeth_seg.pth"
_KAIST_LOCK = threading.Lock()
_VENDOR_REL = Path("vendor/individual_tooth_segmentation")
_WEIGHTS_URL = (
    "https://parter.kaist.ac.kr/colee/work/segmentation22/CP_teeth_seg.pth"
)


@dataclass
class KaistSegmentStatus:
    available: bool
    vendor_root: str
    weights: str
    device: str
    resize: bool
    max_side: int
    min_side: int
    snake_iters: int
    bring_back_iters: int
    evolve_iters: int
    import_error: str | None = None


def _backend_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _max_side() -> int:
    try:
        from app.core.config import settings

        raw = int(settings.shade_segment_kaist_max_side or 0)
    except Exception:
        raw = _DEFAULT_MAX_SIDE
    # 0 used to mean full-res; that made iPad photos miss the 90s timeout.
    return raw if raw > 0 else _DEFAULT_MAX_SIDE


def _min_side() -> int:
    try:
        from app.core.config import settings

        raw = int(getattr(settings, "shade_segment_kaist_min_side", 0) or 0)
    except Exception:
        raw = _DEFAULT_MIN_SIDE
    return raw if raw > 0 else _DEFAULT_MIN_SIDE


def _snake_iters() -> int:
    try:
        from app.core.config import settings

        return max(1, int(settings.shade_segment_kaist_snake_iters or 10))
    except Exception:
        return 10


def _bring_back_iters() -> int:
    try:
        from app.core.config import settings

        return max(20, int(settings.shade_segment_kaist_bring_back_iters or 60))
    except Exception:
        return 60


def _evolve_iters() -> int:
    try:
        from app.core.config import settings

        return max(10, int(settings.shade_segment_kaist_evolve_iters or 30))
    except Exception:
        return 30


def resolve_vendor_root(path: str | Path | None = None) -> Path:
    if path is not None and str(path).strip():
        p = Path(str(path))
    else:
        try:
            from app.core.config import settings

            raw = (getattr(settings, "shade_segment_kaist_vendor", None) or "").strip()
        except Exception:
            raw = ""
        p = Path(raw) if raw else _backend_root() / _VENDOR_REL
    if not p.is_absolute():
        p = _backend_root() / p
    return p.resolve()


def resolve_weights(path: str | Path | None = None) -> Path:
    if path is not None and str(path).strip():
        raw = str(path).strip()
    else:
        try:
            from app.core.config import settings

            raw = (settings.shade_segment_kaist_weights or _DEFAULT_WEIGHTS).strip()
        except Exception:
            raw = _DEFAULT_WEIGHTS
    p = Path(raw)
    if not p.is_absolute():
        p = _backend_root() / p
    return p.resolve()


def _device() -> str:
    try:
        from app.core.config import settings

        raw = (settings.shade_segment_kaist_device or "auto").strip().lower() or "auto"
    except Exception:
        raw = "auto"
    if raw in ("auto", ""):
        try:
            import torch

            if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
                return "mps"
        except Exception:
            pass
        return "cpu"
    return raw


def _resize_enabled() -> bool:
    try:
        from app.core.config import settings

        return bool(settings.shade_segment_kaist_resize)
    except Exception:
        return False


def _optional_import_error(vendor: Path | None = None) -> str | None:
    root = vendor or resolve_vendor_root()
    if not (root / "src" / "makeup.py").is_file():
        return f"vendor missing: {root} (run: python scripts/run_kaist_pilot.py --setup)"
    if not resolve_weights().is_file():
        return (
            f"weights missing: {resolve_weights()} "
            f"(download: {_WEIGHTS_URL})"
        )
    try:
        import torch  # noqa: F401
        import cv2  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError as exc:
        return str(exc)
    return None


def kaist_segment_status(
    *,
    vendor: str | Path | None = None,
    weights: str | Path | None = None,
) -> KaistSegmentStatus:
    v = resolve_vendor_root(vendor)
    w = resolve_weights(weights)
    err = _optional_import_error(v)
    if err is None and not w.is_file():
        err = f"weights missing: {w}"
    return KaistSegmentStatus(
        available=err is None,
        vendor_root=str(v),
        weights=str(w),
        device=_device(),
        resize=_resize_enabled(),
        max_side=_max_side(),
        min_side=_min_side(),
        snake_iters=_snake_iters(),
        bring_back_iters=_bring_back_iters(),
        evolve_iters=_evolve_iters(),
        import_error=err,
    )


def kaist_available(
    *,
    vendor: str | Path | None = None,
    weights: str | Path | None = None,
) -> bool:
    return kaist_segment_status(vendor=vendor, weights=weights).available


def mouth_crop_rgb(
    image_rgb: np.ndarray,
    *,
    pad_frac: float = 0.28,
) -> tuple[np.ndarray, tuple[int, int, int, int]]:
    """Crop to enamel ROI with generous pad (KAIST demos include lips/gums).

    Enamel masks often miss cervical/incisal fringe — tight crops make outlines
    look too small on the real crowns. Falls back to full image if ROI fails.
    """
    from app.ai.shade_segment import _adaptive_enamel_mask, _dental_roi_from_enamel

    h, w = image_rgb.shape[:2]
    full = (0, h, 0, w)
    try:
        enamel = _adaptive_enamel_mask(image_rgb)
        roi = _dental_roi_from_enamel(enamel)
    except Exception:
        logger.exception("kaist mouth crop failed — using full image")
        return image_rgb, full
    if roi is None:
        return image_rgb, full
    y0, y1, x0, x1 = roi
    # Extra vertical pad: crowns are taller than the bright enamel body
    ph = max(8, int(pad_frac * (y1 - y0)))
    pw = max(8, int(0.7 * pad_frac * (x1 - x0)))
    y0 = max(0, y0 - ph)
    y1 = min(h, y1 + ph)
    x0 = max(0, x0 - pw)
    x1 = min(w, x1 + pw)
    if (y1 - y0) < 64 or (x1 - x0) < 64:
        return image_rgb, full
    return image_rgb[y0:y1, x0:x1].copy(), (y0, y1, x0, x1)


def _paste_mask(
    crop_mask: np.ndarray,
    full_shape: tuple[int, int],
    box: tuple[int, int, int, int],
) -> np.ndarray:
    y0, y1, x0, x1 = box
    bh, bw = max(1, y1 - y0), max(1, x1 - x0)
    out = np.zeros(full_shape, dtype=bool)
    m = np.asarray(crop_mask, dtype=bool)
    # Always fit mask to the crop box — catches any missed upscale
    if m.shape[:2] != (bh, bw):
        import cv2

        m = cv2.resize(
            m.astype(np.uint8),
            (bw, bh),
            interpolation=cv2.INTER_NEAREST,
        ).astype(bool)
    out[y0:y1, x0:x1] = m
    return out


def _labels_to_tooth_masks(
    labels: np.ndarray,
    *,
    full_h: int,
    full_w: int,
    box: tuple[int, int, int, int],
) -> list[ToothMask]:
    teeth: list[ToothMask] = []
    uniq = [int(v) for v in np.unique(labels) if int(v) > 0]
    # Sort left→right by centroid for stable indexing before arch assign
    scored: list[tuple[float, int, np.ndarray]] = []
    for lid in uniq:
        m = labels == lid
        if int(m.sum()) < _MIN_MASK_PIXELS:
            continue
        ys, xs = np.nonzero(m)
        scored.append((float(xs.mean()), lid, m))
    scored.sort(key=lambda t: t[0])

    band_h = max(1, box[1] - box[0])
    for i, (_cx, _lid, crop_m) in enumerate(scored[:_MAX_TEETH]):
        full = _paste_mask(crop_m, (full_h, full_w), box)
        if int(full.sum()) < _MIN_MASK_PIXELS:
            continue
        teeth.append(
            ToothMask(
                tooth_index=i,
                mask=full,
                confidence=mask_confidence(full, band_h),
                rejected=False,
                reject_reason=None,
            )
        )
    return _sanity_check_instances(teeth)


def _resize_for_work(
    crop_rgb: np.ndarray,
    max_side: int,
    min_side: int = _DEFAULT_MIN_SIDE,
) -> tuple[np.ndarray, float]:
    """Clamp long side into [min_side, max_side]; return (work, scale).

    scale maps work→crop. Upscale only to min_side — forcing tiny crops to
    max_side made Level-set Step2/3 ~2× slower for little outline gain.
    """
    hi = max(32, int(max_side))
    lo = max(32, min(int(min_side), hi))
    ch, cw = crop_rgb.shape[:2]
    long = max(ch, cw)
    if long <= 0:
        return crop_rgb, 1.0
    if long > hi:
        target = hi
    elif long < lo:
        target = lo
    else:
        return crop_rgb, 1.0
    scale = target / long
    import cv2

    interp = cv2.INTER_AREA if scale < 1.0 else cv2.INTER_LINEAR
    work = cv2.resize(
        crop_rgb,
        (max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))),
        interpolation=interp,
    )
    return work, scale


def _upscale_labels(labels: np.ndarray, out_hw: tuple[int, int]) -> np.ndarray:
    import cv2

    h, w = out_hw
    if labels.shape[:2] == (h, w):
        return labels
    return cv2.resize(
        labels.astype(np.float32),
        (w, h),
        interpolation=cv2.INTER_NEAREST,
    ).astype(np.int32)


def _run_upstream_pipeline(
    crop_rgb: np.ndarray,
    *,
    vendor: Path,
    weights: Path,
    device: str,
    resize: bool,
    snake_iters: int,
    bring_back_iters: int,
    evolve_iters: int,
) -> np.ndarray:
    """Run TeethSeg ALL steps; return TEM label map (HxW int) in crop coords."""
    os.environ.setdefault("MPLBACKEND", "Agg")

    vendor_s = str(vendor)
    if vendor_s not in sys.path:
        sys.path.insert(0, vendor_s)

    from app.ai.kaist_compat import patch_kaist_vendor

    patch_kaist_vendor(
        snake_iters=snake_iters,
        bring_back_iters=bring_back_iters,
        evolve_iters=evolve_iters,
    )

    from PIL import Image

    import src.myTools as mts
    from src.makeup import TeethSeg

    with tempfile.TemporaryDirectory(prefix="kaist_seg_") as tmp:
        root = Path(tmp)
        data_dir = root / "data"
        out_dir = root / "out"
        data_dir.mkdir()
        out_dir.mkdir()
        # Upstream ErDataset keys images by integer stem
        img_id = 1
        Image.fromarray(crop_rgb.astype(np.uint8)).save(data_dir / f"{img_id}.png")

        config: dict[str, Any] = {
            "DEFAULT": {"ROOT": str(root), "DEVICE": device},
            "DATA": {
                "DIR": "data",
                "EXT": ["png", "jpg", "jpeg", "jfif", "jpge"],
            },
            # Absolute path — os.path.join(ROOT, abs) → abs on POSIX
            "MODEL": {"WEIGHTS": str(weights)},
            "EVAL": {"DIR": "out"},
            "RESIZE": bool(resize),
        }

        dir_img = out_dir / f"{img_id:05d}"
        dir_img.mkdir(parents=True, exist_ok=True)
        sts = mts.SaveTools(str(dir_img))
        ts = TeethSeg(str(dir_img), img_id, sts, config)
        ts.pseudoER()
        ts.initContour()
        ts.snake()
        ts.tem()

        labels = ts._dt.get("res")
        if labels is None:
            raise RuntimeError("KAIST TEM returned no label map")
        return np.asarray(labels)


def detect_teeth_kaist(
    image_rgb: np.ndarray,
    *,
    crop: bool = True,
    vendor: str | Path | None = None,
    weights: str | Path | None = None,
) -> list[ToothMask]:
    """Segment per-tooth masks via KAIST pipeline. Empty list on hard failure."""
    arr = np.asarray(image_rgb)
    if arr.ndim != 3 or arr.shape[2] != 3:
        raise ValueError("image_rgb must be HxWx3")

    status = kaist_segment_status(vendor=vendor, weights=weights)
    if not status.available:
        logger.warning("kaist unavailable: %s", status.import_error)
        return []

    h, w = arr.shape[:2]
    if crop:
        crop_rgb, box = mouth_crop_rgb(arr)
    else:
        crop_rgb, box = arr, (0, h, 0, w)

    work_rgb, scale = _resize_for_work(
        crop_rgb, status.max_side, status.min_side
    )

    logger.info(
        "kaist segment crop=%s work=%s scale=%.3f snake=%s bring=%s evolve=%s device=%s",
        crop_rgb.shape[:2],
        work_rgb.shape[:2],
        scale,
        status.snake_iters,
        status.bring_back_iters,
        status.evolve_iters,
        status.device,
    )

    # One snake at a time — concurrent MPS jobs stalled the first iPad photo
    # past the 90s client timeout while a second upload ran.
    with _KAIST_LOCK:
        try:
            labels = _run_upstream_pipeline(
                work_rgb,
                vendor=Path(status.vendor_root),
                weights=Path(status.weights),
                device=status.device,
                resize=status.resize,
                snake_iters=status.snake_iters,
                bring_back_iters=status.bring_back_iters,
                evolve_iters=status.evolve_iters,
            )
        except Exception:
            logger.exception("kaist pipeline failed")
            return []

    labels = np.asarray(labels)
    if labels.shape[:2] != work_rgb.shape[:2]:
        logger.warning(
            "kaist label size %s != work %s — resizing to work then crop",
            labels.shape[:2],
            work_rgb.shape[:2],
        )
        labels = _upscale_labels(labels, work_rgb.shape[:2])
    if labels.shape[:2] != crop_rgb.shape[:2]:
        logger.info(
            "kaist mapping labels %s → crop %s",
            labels.shape[:2],
            crop_rgb.shape[:2],
        )
        labels = _upscale_labels(labels, crop_rgb.shape[:2])

    teeth = _labels_to_tooth_masks(labels, full_h=h, full_w=w, box=box)
    logger.info(
        "kaist done teeth=%s accepted=%s",
        len(teeth),
        sum(1 for t in teeth if not t.rejected),
    )
    return teeth

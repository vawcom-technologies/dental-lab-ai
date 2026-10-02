"""KAIST individual tooth segmentation (mireiffe/individual_tooth_segmentation).

Runs the upstream 4-step pipeline (pseudoER → initContour → snake → TEM) on a
mouth crop so outlines match their demo quality. Full-face uploads are cropped
via classical enamel ROI first.

Work image long side is clamped into [min_side, max_side] (.env 256–320).
The level-set steps are tuned for that scale; labels map back to the crop.

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
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from app.ai.shade_segment import ToothMask, _sanity_check_instances, mask_confidence

logger = logging.getLogger(__name__)

_MAX_TEETH = 16  # both arches on one mouth crop
_MIN_MASK_PIXELS = 40
_DEFAULT_MAX_SIDE = 256
_DEFAULT_MIN_SIDE = 224
# Wide-strip guard for the work image (see _resize_for_work).
_MIN_WORK_SHORT = 112
_MAX_WORK_LONG = 800
_DEFAULT_WEIGHTS = "weights/kaist/CP_teeth_seg.pth"
_MIN_WEIGHTS_BYTES = 1_000_000_000  # finished CP_teeth_seg.pth is ~1.5 GB
_KAIST_LOCK = threading.Lock()
# Per-step ms of the latest KAIST run (diagnostics; returned in timings_ms).
last_step_ms: dict[str, float] = {}
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
    hi = raw if raw > 0 else _DEFAULT_MAX_SIDE
    # Railway / CPU: snakes are O(pixels). Cap unless the operator set a
    # smaller ceiling already.
    if _device() == "cpu" and hi > 256:
        return 256
    return hi


def _min_side() -> int:
    try:
        from app.core.config import settings

        raw = int(getattr(settings, "shade_segment_kaist_min_side", 0) or 0)
    except Exception:
        raw = _DEFAULT_MIN_SIDE
    lo = raw if raw > 0 else _DEFAULT_MIN_SIDE
    if _device() == "cpu":
        return min(lo, 224)
    return lo


def _snake_iters() -> int:
    try:
        from app.core.config import settings

        return max(1, int(settings.shade_segment_kaist_snake_iters or 5))
    except Exception:
        return 5


def _bring_back_iters() -> int:
    try:
        from app.core.config import settings

        return max(12, int(settings.shade_segment_kaist_bring_back_iters or 28))
    except Exception:
        return 28


def _evolve_iters() -> int:
    try:
        from app.core.config import settings

        return max(8, int(settings.shade_segment_kaist_evolve_iters or 14))
    except Exception:
        return 14


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
            import warnings

            with warnings.catch_warnings():
                warnings.filterwarnings("ignore")
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


def _weights_file_error(path: Path) -> str | None:
    if not path.is_file():
        return f"weights missing: {path} (download: {_WEIGHTS_URL})"
    size = int(path.stat().st_size)
    if size < _MIN_WEIGHTS_BYTES:
        return (
            f"weights incomplete: {path} ({size} bytes, need ~1.5 GB). "
            "Run: python scripts/run_kaist_pilot.py --download-weights"
        )
    return None


def _optional_import_error(
    vendor: Path | None = None,
    weights: Path | None = None,
) -> str | None:
    root = vendor or resolve_vendor_root()
    if not (root / "src" / "makeup.py").is_file():
        return f"vendor missing: {root} (run: python scripts/run_kaist_pilot.py --setup)"
    weights_err = _weights_file_error(weights or resolve_weights())
    if weights_err:
        return weights_err
    try:
        import warnings

        with warnings.catch_warnings():
            warnings.filterwarnings("ignore")
            import torch  # noqa: F401
        import cv2  # noqa: F401
        from PIL import Image  # noqa: F401
        import skfmm  # noqa: F401
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
    err = _optional_import_error(v, w)
    # Don't import torch until weights exist — NumPy 2 + Torch 2.2 logs a
    # scary traceback on every shade request even when KAIST is skipped.
    device = _device() if err is None else "cpu"
    return KaistSegmentStatus(
        available=err is None,
        vendor_root=str(v),
        weights=str(w),
        device=device,
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


def warmup_kaist_weights() -> str:
    """Load the existing ResNeSt checkpoint into RAM. Does not change the .pth."""
    status = kaist_segment_status()
    if not status.available:
        logger.info("kaist warmup skipped: %s", status.import_error)
        return f"skipped: {status.import_error}"

    vendor_s = str(Path(status.vendor_root))
    if vendor_s not in sys.path:
        sys.path.insert(0, vendor_s)

    from app.ai.kaist_compat import patch_kaist_vendor

    started = time.perf_counter()
    patch_kaist_vendor(
        snake_iters=status.snake_iters,
        bring_back_iters=status.bring_back_iters,
        evolve_iters=status.evolve_iters,
    )
    from src.teethSeg import PseudoER

    config: dict[str, Any] = {
        "DEFAULT": {"ROOT": vendor_s, "DEVICE": status.device},
        "MODEL": {"WEIGHTS": str(Path(status.weights))},
    }
    try:
        with _KAIST_LOCK:
            PseudoER(config, 1).setModel()
    except Exception as exc:
        logger.exception("kaist warmup failed")
        return f"failed: {exc}"
    logger.info(
        "kaist warmup done ms=%.0f device=%s",
        (time.perf_counter() - started) * 1000,
        status.device,
    )
    return "ok"


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
    px_scale: float = 1.0,
) -> list[ToothMask]:
    """One ToothMask per KAIST label, left→right. Raw crowns — no enamel snap."""
    scored: list[tuple[float, np.ndarray]] = []
    for lid in np.unique(labels):
        if int(lid) <= 0:
            continue
        m = labels == lid
        if int(m.sum()) < _MIN_MASK_PIXELS:
            continue
        scored.append((float(np.nonzero(m)[1].mean()), m))
    scored.sort(key=lambda t: t[0])

    band_h = max(1, box[1] - box[0])
    teeth: list[ToothMask] = []
    for i, (_cx, crop_m) in enumerate(scored[:_MAX_TEETH]):
        full = _paste_mask(crop_m, (full_h, full_w), box)
        if int(full.sum()) < _MIN_MASK_PIXELS:
            continue
        teeth.append(
            ToothMask(
                tooth_index=i,
                mask=full,
                confidence=mask_confidence(full, band_h),
                rejected=False,
                px_scale=px_scale,
            )
        )
    return _sanity_check_instances(teeth)


def _resize_for_work(
    crop_rgb: np.ndarray,
    max_side: int,
    min_side: int = _DEFAULT_MIN_SIDE,
) -> np.ndarray:
    """Clamp the long side into [min_side, max_side].

    KAIST's level-set steps use fixed pixel widths and iteration budgets, so
    the crop must stay near the scale it was tuned for. Keeping 500–640 px
    crops native left contours stuck inside the crowns and ran ~4× slower.
    """
    import cv2

    hi = max(32, int(max_side))
    lo = max(32, min(int(min_side), hi))
    ch, cw = crop_rgb.shape[:2]
    long = max(ch, cw)
    short = min(ch, cw)
    if long <= 0:
        return crop_rgb
    scale = 1.0 if lo <= long <= hi else (hi if long > hi else lo) / long
    # Wide strips (camera "Upper/Lower teeth" crops are ~4:1): sizing by the
    # long side left them ~50 px tall and KAIST found 1 tooth in 16. Keep the
    # short side at a floor instead, width capped. Normal photos stay above it.
    if short * scale < _MIN_WORK_SHORT:
        scale = min(_MIN_WORK_SHORT / short, _MAX_WORK_LONG / long)
    if abs(scale - 1.0) < 1e-6:
        return crop_rgb
    return cv2.resize(
        crop_rgb,
        (max(1, round(cw * scale)), max(1, round(ch * scale))),
        interpolation=cv2.INTER_AREA if scale < 1.0 else cv2.INTER_LINEAR,
    )


def _upscale_labels(labels: np.ndarray, out_hw: tuple[int, int]) -> np.ndarray:
    """Draw each label's contour at the destination size.

    Nearest-neighbor resize stair-steps the crown when the work image is
    smaller than the crop. Scaling the contour points keeps the enamel curve.
    """
    import cv2

    h, w = out_hw
    src = np.asarray(labels)
    if src.shape[:2] == (h, w):
        return src.astype(np.int32, copy=False)
    src_h, src_w = src.shape[:2]
    if src_h < 1 or src_w < 1 or h < 1 or w < 1:
        return np.zeros((max(h, 1), max(w, 1)), dtype=np.int32)
    sx = w / float(src_w)
    sy = h / float(src_h)
    out = np.zeros((h, w), dtype=np.int32)
    for lid in np.unique(src):
        lid_i = int(lid)
        if lid_i <= 0:
            continue
        u8 = (src == lid).astype(np.uint8) * 255
        contours, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        polys: list[np.ndarray] = []
        for cnt in contours:
            if cnt is None or len(cnt) < 3:
                continue
            pts = cnt.astype(np.float64)
            pts[:, 0, 0] = np.clip(pts[:, 0, 0] * sx, 0, w - 1)
            pts[:, 0, 1] = np.clip(pts[:, 0, 1] * sy, 0, h - 1)
            polys.append(np.round(pts).astype(np.int32))
        if polys:
            cv2.fillPoly(out, polys, lid_i)
        else:
            nearest = cv2.resize(
                u8,
                (w, h),
                interpolation=cv2.INTER_NEAREST,
            )
            out[nearest > 0] = lid_i
    return out


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
    with _KAIST_LOCK:
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
        # MPS/CNN is not safe to run twice at once. Snakes are CPU per TeethSeg.
        steps: dict[str, float] = {}
        t = time.perf_counter()
        with _KAIST_LOCK:
            ts.pseudoER()
        steps["cnn"] = (time.perf_counter() - t) * 1000
        for name, step in (("init_contour", ts.initContour), ("snake", ts.snake), ("tem", ts.tem)):
            t = time.perf_counter()
            step()
            steps[name] = (time.perf_counter() - t) * 1000
        last_step_ms.clear()
        last_step_ms.update({k: round(v) for k, v in steps.items()})

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
    """Segment per-tooth masks via KAIST on one mouth crop. Empty list on failure."""
    arr = np.asarray(image_rgb)
    if arr.ndim != 3 or arr.shape[2] != 3:
        raise ValueError("image_rgb must be HxWx3")

    status = kaist_segment_status(vendor=vendor, weights=weights)
    if not status.available:
        logger.warning("kaist unavailable: %s", status.import_error)
        return []

    started = time.perf_counter()
    h, w = arr.shape[:2]
    crop_rgb, box = mouth_crop_rgb(arr) if crop else (arr, (0, h, 0, w))
    work_rgb = _resize_for_work(crop_rgb, status.max_side, status.min_side)
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
    # Contour-scaled back to the crop so edges stay smooth, not stair-stepped.
    labels = _upscale_labels(np.asarray(labels), crop_rgb.shape[:2])
    teeth = _labels_to_tooth_masks(
        labels,
        full_h=h,
        full_w=w,
        box=box,
        px_scale=crop_rgb.shape[1] / max(1, work_rgb.shape[1]),
    )
    logger.info(
        "kaist done crop=%s work=%s teeth=%s ms=%.0f",
        crop_rgb.shape[:2],
        work_rgb.shape[:2],
        len(teeth),
        (time.perf_counter() - started) * 1000,
    )
    return teeth

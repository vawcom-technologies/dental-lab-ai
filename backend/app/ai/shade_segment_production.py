"""Production teeth segmentation — YOLO11 instance-seg + SAM2 boundary refine.

Target accuracy path (no email-gated weights):
  1. Train yolo11s-seg on public dental datasets (scripts/train_teeth_segmenter.py)
  2. Fine-tune on Elite Dent clinic photos (same script --finetune)
  3. Optional SAM2 box-prompt refine for incisal/cervical edges

Architecture mirrors SegmentAnyTooth (detect/seg → SAM refine) but weights are
owned and commercially licensable via Ultralytics.

# ASSUMPTION: Inference at imgsz>=1280 for boundary precision on iPad photos.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from app.ai.shade_segment import ToothMask, _sanity_check_instances, mask_confidence

logger = logging.getLogger(__name__)

_MAX_TEETH = 12
_MIN_MASK_PIXELS = 40
_DEFAULT_CONF = 0.25


@dataclass
class ProductionSegmentStatus:
    available: bool
    yolo_weights: str
    sam_refine: bool
    sam_weights: str | None
    imgsz: int
    import_error: str | None = None


_yolo_model: Any | None = None
_yolo_path: str | None = None
_sam_model: Any | None = None
_sam_path: str | None = None


def _backend_root() -> Path:
    return Path(__file__).resolve().parents[2]


def resolve_yolo_weights(path: str | None = None) -> Path:
    raw = (path or "").strip()
    if not raw:
        from app.core.config import settings

        raw = settings.shade_segment_yolo_weights
    p = Path(raw)
    if not p.is_absolute():
        p = _backend_root() / p
    return p.resolve()


def _optional_import_error() -> str | None:
    try:
        import torch  # noqa: F401
        from ultralytics import YOLO  # noqa: F401
    except ImportError as exc:
        return str(exc)
    return None


def production_segment_status(
    *,
    yolo_weights: str | Path | None = None,
) -> ProductionSegmentStatus:
    from app.core.config import settings

    yolo = resolve_yolo_weights(str(yolo_weights) if yolo_weights else None)
    import_error = _optional_import_error()
    sam_refine = bool(settings.shade_segment_sam_refine)
    sam_w = (settings.shade_segment_sam_weights or "sam2_b.pt").strip() or None
    return ProductionSegmentStatus(
        available=yolo.is_file() and import_error is None,
        yolo_weights=str(yolo),
        sam_refine=sam_refine,
        sam_weights=sam_w,
        imgsz=int(settings.shade_segment_imgsz or 1280),
        import_error=import_error,
    )


def production_available(*, yolo_weights: str | Path | None = None) -> bool:
    return production_segment_status(yolo_weights=yolo_weights).available


def clear_production_cache() -> None:
    global _yolo_model, _yolo_path, _sam_model, _sam_path
    _yolo_model = None
    _yolo_path = None
    _sam_model = None
    _sam_path = None


def _load_yolo(weights: Path) -> Any:
    global _yolo_model, _yolo_path
    key = str(weights)
    if _yolo_model is not None and _yolo_path == key:
        return _yolo_model
    from ultralytics import YOLO
    from ultralytics.utils import LOGGER

    LOGGER.setLevel("ERROR")
    _yolo_model = YOLO(str(weights))
    _yolo_path = key
    logger.info("Production YOLO loaded: %s", weights)
    return _yolo_model


def _load_sam(weights: str) -> Any:
    global _sam_model, _sam_path
    if _sam_model is not None and _sam_path == weights:
        return _sam_model
    from ultralytics import SAM
    from ultralytics.utils import LOGGER

    LOGGER.setLevel("ERROR")
    _sam_model = SAM(weights)
    _sam_path = weights
    logger.info("Production SAM loaded: %s", weights)
    return _sam_model


def _mask_from_yolo_polygon(
    polygon_xy: np.ndarray, h: int, w: int
) -> np.ndarray | None:
    import cv2

    if polygon_xy.size < 6:
        return None
    pts = polygon_xy.reshape(-1, 2).astype(np.float32)
    pts[:, 0] = np.clip(pts[:, 0], 0, w - 1)
    pts[:, 1] = np.clip(pts[:, 1], 0, h - 1)
    m = np.zeros((h, w), dtype=np.uint8)
    cv2.fillPoly(m, [pts.astype(np.int32)], 1)
    return m.astype(bool) if int(m.sum()) >= _MIN_MASK_PIXELS else None


def _resize_mask_to_image(mask: np.ndarray, h: int, w: int) -> np.ndarray:
    import cv2

    if mask.shape[0] == h and mask.shape[1] == w:
        return mask.astype(bool)
    resized = cv2.resize(
        mask.astype(np.uint8),
        (w, h),
        interpolation=cv2.INTER_NEAREST,
    )
    return resized.astype(bool)


def _instances_from_yolo_result(
    result: Any, h: int, w: int
) -> list[tuple[np.ndarray, float, tuple[float, float, float, float]]]:
    """Extract (mask, conf, xyxy) per instance from one YOLO result."""
    out: list[tuple[np.ndarray, float, tuple[float, float, float, float]]] = []
    if result.boxes is None or len(result.boxes) == 0:
        return out

    boxes = result.boxes.xyxy.cpu().numpy()
    confs = result.boxes.conf.cpu().numpy()
    if boxes.ndim == 1:
        boxes = boxes.reshape(1, -1)
        confs = np.array([confs])

    masks_obj = result.masks
    if masks_obj is not None and masks_obj.data is not None:
        mask_data = masks_obj.data.cpu().numpy()
        for i in range(len(boxes)):
            m = _resize_mask_to_image(mask_data[i] > 0.5, h, w)
            if int(m.sum()) >= _MIN_MASK_PIXELS:
                xyxy = tuple(float(x) for x in boxes[i])
                out.append((m, float(confs[i]), xyxy))
        return out

    if masks_obj is not None and masks_obj.xy is not None:
        polys = masks_obj.xy
        for i, poly in enumerate(polys):
            m = _mask_from_yolo_polygon(np.asarray(poly), h, w)
            if m is not None:
                xyxy = tuple(float(x) for x in boxes[min(i, len(boxes) - 1)])
                out.append((m, float(confs[min(i, len(confs) - 1)]), xyxy))

    return out


def _refine_with_sam2(
    image_rgb: np.ndarray,
    instances: list[tuple[np.ndarray, float, tuple[float, float, float, float]]],
    sam_weights: str,
) -> list[tuple[np.ndarray, float]]:
    if not instances:
        return []

    sam = _load_sam(sam_weights)
    h, w = image_rgb.shape[:2]
    refined: list[tuple[np.ndarray, float]] = []

    for seed, conf, xyxy in instances:
        x0, y0, x1, y1 = xyxy
        pad = max(8, int(0.08 * max(x1 - x0, y1 - y0)))
        bx0 = max(0, int(x0) - pad)
        by0 = max(0, int(y0) - pad)
        bx1 = min(w, int(x1) + pad)
        by1 = min(h, int(y1) + pad)
        if bx1 <= bx0 + 4 or by1 <= by0 + 4:
            refined.append((seed, conf))
            continue

        crop = np.clip(image_rgb[by0:by1, bx0:bx1], 0, 255).astype(np.uint8)
        box = np.array([[x0 - bx0, y0 - by0, x1 - bx0, y1 - by0]], dtype=np.float32)
        try:
            sam_out = sam(crop, bboxes=box, verbose=False)
        except Exception:
            refined.append((seed, conf))
            continue

        if not sam_out or sam_out[0].masks is None:
            refined.append((seed, conf))
            continue

        mdata = sam_out[0].masks.data
        if mdata is None or len(mdata) == 0:
            refined.append((seed, conf))
            continue

        local = _resize_mask_to_image(mdata[0].cpu().numpy() > 0.5, by1 - by0, bx1 - bx0)
        full = np.zeros((h, w), dtype=bool)
        full[by0:by1, bx0:bx1] = local
        # Restrict SAM to YOLO neighborhood — prevents gum/lip leaks
        import cv2

        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
        allow = cv2.dilate((seed.astype(np.uint8)) * 255, k, iterations=2) > 0
        full &= allow
        if int(full.sum()) < _MIN_MASK_PIXELS:
            full = seed
        refined.append((full, conf))

    return refined


def _sort_instances(
    instances: list[tuple[np.ndarray, float]],
) -> list[tuple[np.ndarray, float]]:
    keyed = []
    for m, conf in instances:
        ys, xs = np.nonzero(m)
        keyed.append((float(ys.mean()), float(xs.mean()), m, conf))
    keyed.sort(key=lambda t: (t[0], t[1]))
    return [(m, conf) for _cy, _cx, m, conf in keyed]


def _instances_to_tooth_masks(
    instances: list[tuple[np.ndarray, float]], h: int
) -> list[ToothMask]:
    teeth: list[ToothMask] = []
    for idx, (m, conf) in enumerate(instances[:_MAX_TEETH]):
        teeth.append(
            ToothMask(
                tooth_index=idx,
                mask=m,
                confidence=round(
                    float(
                        np.clip(
                            0.55 * conf + 0.45 * mask_confidence(m, h),
                            0.0,
                            0.99,
                        )
                    ),
                    3,
                ),
                rejected=False,
                reject_reason=None,
            )
        )
    return _sanity_check_instances(teeth)


def detect_teeth_production(
    image_rgb: np.ndarray,
    *,
    yolo_weights: str | Path | None = None,
    imgsz: int | None = None,
    conf: float | None = None,
    sam_refine: bool | None = None,
) -> list[ToothMask]:
    """Production ML segmenter — requires trained weights at weights/teeth_seg/best.pt."""
    from app.core.config import settings

    status = production_segment_status(yolo_weights=yolo_weights)
    if not status.available:
        if status.import_error:
            raise ImportError(
                f"Production segmentation deps missing: {status.import_error}. "
                "Run: pip install -r requirements-ml.txt"
            )
        raise FileNotFoundError(
            f"Production YOLO weights not found at {status.yolo_weights}. "
            "Train with: python scripts/train_teeth_segmenter.py"
        )

    yolo = _load_yolo(Path(status.yolo_weights))
    h, w = image_rgb.shape[:2]
    imgsz_val = int(imgsz or status.imgsz)
    conf_val = float(conf if conf is not None else settings.shade_segment_conf or _DEFAULT_CONF)

    u8 = np.clip(np.asarray(image_rgb), 0, 255).astype(np.uint8)
    results = yolo.predict(
        u8,
        imgsz=imgsz_val,
        conf=conf_val,
        iou=0.45,
        verbose=False,
    )
    if not results:
        return []

    instances = _instances_from_yolo_result(results[0], h, w)
    if not instances:
        return []

    use_sam = status.sam_refine if sam_refine is None else sam_refine
    if use_sam and status.sam_weights:
        try:
            pairs = _refine_with_sam2(u8, instances, status.sam_weights)
        except Exception:
            logger.exception("SAM2 refine failed — using YOLO masks only")
            pairs = [(m, c) for m, c, _ in instances]
    else:
        pairs = [(m, c) for m, c, _ in instances]

    pairs = _sort_instances(pairs)
    teeth = _instances_to_tooth_masks(pairs, h)
    accepted = sum(1 for t in teeth if not t.rejected)
    logger.info(
        "production segment teeth=%s accepted=%s imgsz=%s sam=%s",
        len(teeth),
        accepted,
        imgsz_val,
        use_sam,
    )
    return teeth

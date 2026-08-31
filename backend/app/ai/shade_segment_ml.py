"""SegmentAnyTooth ML backend for per-tooth instance masks.

Wraps YOLO11-nano detection + Light HQ-SAM segmentation when weights and
optional deps (torch, ultralytics, segment-anything-hq) are installed.

Weights are NOT bundled — place downloaded .pt files under
``backend/weights/segmentanytooth/`` (see README there).

# ASSUMPTION: Shade workflow uses frontal smile photos by default (view=front).
# ASSUMPTION: Anterior FDI units (x1–x3 per quadrant) are kept for shade matching.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

import numpy as np

from app.ai.shade_segment import ToothMask, _sanity_check_instances, mask_confidence

logger = logging.getLogger(__name__)

MlView = Literal["upper", "lower", "left", "right", "front"]

# FDI tooth numbers used for anterior shade matching (centrals, laterals, canines).
_ANTERIOR_FDI = frozenset(
    {
        11,
        12,
        13,
        21,
        22,
        23,
        31,
        32,
        33,
        41,
        42,
        43,
    }
)

# SegmentAnyTooth left-lateral class names when image is flipped.
_LEFT_CLASSES = [
    "le28",
    "le27",
    "le26",
    "le25",
    "le24",
    "le23",
    "le22",
    "le21",
    "le38",
    "le37",
    "le36",
    "le35",
    "le34",
    "le33",
    "le32",
    "le31",
    "le11",
    "le12",
    "le13",
    "le14",
    "le41",
    "le42",
    "le43",
    "le44",
]


@dataclass
class MlSegmentStatus:
    available: bool
    weights_dir: str
    view: str
    missing_files: list[str]
    import_error: str | None = None


@dataclass(frozen=True)
class _ModelCache:
    view: str
    weight_dir: str
    yolo: Any
    sam: Any


_model_cache: _ModelCache | None = None


def _backend_root() -> Path:
    return Path(__file__).resolve().parents[2]


def resolve_weights_dir(path: str | None = None) -> Path:
    raw = (path or "").strip()
    if not raw:
        from app.core.config import settings

        raw = settings.shade_segment_ml_weights_dir
    p = Path(raw)
    if not p.is_absolute():
        p = _backend_root() / p
    return p.resolve()


def required_weight_paths(weight_dir: Path, view: str) -> tuple[Path, Path]:
    sam = weight_dir / "segmentanytooth_vit_tiny.pt"
    yolo_view = "right" if view == "left" else view
    yolo = weight_dir / f"segmentanytooth_yolo11_{yolo_view}.pt"
    return sam, yolo


def ml_segment_status(
    *,
    weight_dir: str | Path | None = None,
    view: str = "front",
) -> MlSegmentStatus:
    """Report whether ML segmentation can run on this machine."""
    wd = resolve_weights_dir(str(weight_dir) if weight_dir is not None else None)
    sam, yolo = required_weight_paths(wd, view)
    missing = [p.name for p in (sam, yolo) if not p.is_file()]
    import_error = _optional_import_error()
    return MlSegmentStatus(
        available=not missing and import_error is None,
        weights_dir=str(wd),
        view=view,
        missing_files=missing,
        import_error=import_error,
    )


def ml_available(
    *,
    weight_dir: str | Path | None = None,
    view: str = "front",
) -> bool:
    return ml_segment_status(weight_dir=weight_dir, view=view).available


def _optional_import_error() -> str | None:
    try:
        import cv2  # noqa: F401
        import torch  # noqa: F401
        from ultralytics import YOLO  # noqa: F401
        from segment_anything_hq import sam_model_registry  # noqa: F401
    except ImportError as exc:
        return str(exc)
    return None


def _load_models(view: str, weight_dir: Path) -> tuple[Any, Any]:
    global _model_cache
    key = str(weight_dir)
    if (
        _model_cache is not None
        and _model_cache.view == view
        and _model_cache.weight_dir == key
    ):
        return _model_cache.yolo, _model_cache.sam

    import cv2
    from ultralytics import YOLO
    from ultralytics.utils import LOGGER

    from app.ai.shade_segment_ml_sam import sam_load

    LOGGER.setLevel("ERROR")
    sam_path, yolo_path = required_weight_paths(weight_dir, view)
    yolo_view = "right" if view == "left" else view

    sam = sam_load(str(sam_path))
    yolo = YOLO(model=str(yolo_path))
    _model_cache = _ModelCache(view=view, weight_dir=key, yolo=yolo, sam=sam)
    logger.info(
        "SegmentAnyTooth models loaded view=%s weights=%s",
        yolo_view,
        weight_dir,
    )
    return yolo, sam


def predict_fdi_mask_rgb(
    image_rgb: np.ndarray,
    *,
    view: MlView = "front",
    weight_dir: str | Path | None = None,
    sam_batch_size: int = 10,
) -> np.ndarray:
    """Run YOLO11 + SAM; return HxW uint8 mask with FDI tooth numbers per pixel."""
    status = ml_segment_status(weight_dir=weight_dir, view=view)
    if not status.available:
        if status.missing_files:
            raise FileNotFoundError(
                f"Missing SegmentAnyTooth weights in {status.weights_dir}: "
                + ", ".join(status.missing_files)
            )
        raise ImportError(
            f"ML segmentation deps not installed: {status.import_error}. "
            "Install with: pip install -r requirements-ml.txt"
        )

    import cv2
    from ultralytics.utils import LOGGER

    from app.ai.shade_segment_ml_sam import sam_predict

    LOGGER.setLevel("ERROR")
    wd = resolve_weights_dir(str(weight_dir) if weight_dir is not None else None)
    yolo, sam = _load_models(view, wd)

    arr = np.clip(np.asarray(image_rgb), 0, 255).astype(np.uint8)
    if arr.ndim != 3 or arr.shape[2] != 3:
        raise ValueError("image_rgb must be HxWx3")

    should_flip = view == "left"
    image_bgr = cv2.cvtColor(arr, cv2.COLOR_RGB2BGR)
    if should_flip:
        image_bgr = cv2.flip(image_bgr, 1)

    result = yolo.predict(
        image_bgr,
        save=False,
        save_txt=False,
        save_conf=False,
        save_crop=False,
        project=None,
        verbose=False,
    )[0]

    h, w = arr.shape[:2]
    if result.boxes is None or len(result.boxes) == 0:
        return np.zeros((h, w), dtype=np.uint8)

    names = result.names if not should_flip else _LEFT_CLASSES
    boxes = result.boxes.xyxy.squeeze(0).cpu().numpy()
    clss = result.boxes.cls.squeeze(0).cpu().numpy().astype(np.int32)

    if boxes.ndim == 1:
        boxes = boxes.reshape(1, -1)
        clss = np.array([clss])

    sort_ids = np.argsort(clss)
    clss = clss[sort_ids]
    boxes = boxes[sort_ids]

    image_rgb_work = arr.copy()
    if should_flip:
        image_width = image_bgr.shape[1]
        image_rgb_work = cv2.flip(image_rgb_work, 1)
        flipped = boxes.copy()
        flipped[:, [0, 2]] = image_width - flipped[:, [2, 0]]
        boxes = flipped

    sam_masks = sam_predict(
        sam=sam,
        boxes_xyxy=boxes,
        image=image_rgb_work,
        batch_size=sam_batch_size,
    )

    predict_mask = np.zeros((h, w), dtype=np.uint8)
    for cls_id, current_mask in zip(clss, sam_masks):
        if cls_id < 0 or cls_id >= len(names):
            continue
        label = names[int(cls_id)]
        try:
            fdi = int(str(label)[-2:])
        except ValueError:
            continue
        if fdi <= 0:
            continue
        predict_mask[current_mask == 1] = fdi

    return predict_mask


def fdi_mask_to_tooth_masks(
    fdi_mask: np.ndarray,
    *,
    anterior_only: bool = True,
) -> list[ToothMask]:
    """Convert FDI label map to per-tooth bool masks sorted upper→lower, left→right."""
    h, w = fdi_mask.shape[:2]
    labels = sorted(int(v) for v in np.unique(fdi_mask) if int(v) > 0)
    if anterior_only:
        labels = [lb for lb in labels if lb in _ANTERIOR_FDI]
    if not labels:
        return []

    instances: list[tuple[np.ndarray, float, float]] = []
    for fdi in labels:
        m = fdi_mask == fdi
        if int(m.sum()) < 40:
            continue
        ys, xs = np.nonzero(m)
        cy = float(ys.mean())
        cx = float(xs.mean())
        instances.append((m, cy, cx))

    instances.sort(key=lambda t: (t[1], t[2]))

    teeth: list[ToothMask] = []
    for idx, (m, _cy, _cx) in enumerate(instances):
        full = np.zeros((h, w), dtype=bool)
        full[:] = m
        conf = mask_confidence(m, h)
        teeth.append(
            ToothMask(
                tooth_index=idx,
                mask=full,
                confidence=conf,
                rejected=False,
                reject_reason=None,
            )
        )
    return _sanity_check_instances(teeth)


def detect_teeth_ml(
    image_rgb: np.ndarray,
    *,
    view: MlView | None = None,
    weight_dir: str | Path | None = None,
    anterior_only: bool = True,
) -> list[ToothMask]:
    """ML segmentation entry — same return type as detect_teeth()."""
    if view is None:
        from app.core.config import settings

        view = settings.shade_segment_ml_view  # type: ignore[assignment]
    view = view or "front"

    fdi = predict_fdi_mask_rgb(image_rgb, view=view, weight_dir=weight_dir)
    return fdi_mask_to_tooth_masks(fdi, anterior_only=anterior_only)


def clear_model_cache() -> None:
    """Drop cached YOLO/SAM models (for tests)."""
    global _model_cache
    _model_cache = None

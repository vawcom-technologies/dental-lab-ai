"""A/B harness: classical CV vs RF-DETR / PLAK Roboflow segmentation.

Usage:
  cd backend && python -m app.ai.shade_segment_ab photo.jpg -o /tmp/ab.png
  cd backend && python -m app.ai.shade_segment_ab photo.jpg --json
"""

from __future__ import annotations

import argparse
import json
import logging
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from app.ai.shade_segment import SegmentConfig, ToothMask, detect_teeth
from app.ai.shade_segment_rfdetr import (
    RfdetrSegmentStatus,
    detect_teeth_rfdetr,
    rfdetr_segment_status,
)
from app.ai.shade_segment_viz import render_instance_overlay

logger = logging.getLogger(__name__)


@dataclass
class SegmentAbResult:
    classical: list[ToothMask]
    rfdetr: list[ToothMask] | None
    classical_ms: float
    rfdetr_ms: float | None
    rfdetr_status: RfdetrSegmentStatus
    rfdetr_error: str | None = None


def _centroid(mask: np.ndarray) -> tuple[float, float]:
    ys, xs = np.nonzero(mask)
    if ys.size == 0:
        return 0.0, 0.0
    return float(xs.mean()), float(ys.mean())


def _mask_iou(a: np.ndarray, b: np.ndarray) -> float:
    inter = int(np.logical_and(a, b).sum())
    if inter == 0:
        return 0.0
    union = int(np.logical_or(a, b).sum())
    return inter / float(max(union, 1))


def _pairwise_best_iou(
    classical: list[ToothMask], rfdetr: list[ToothMask]
) -> list[dict[str, Any]]:
    """Greedy match RF-DETR masks to classical by centroid distance; report IoU."""
    if not classical or not rfdetr:
        return []

    pairs: list[tuple[float, int, int]] = []
    for i, c in enumerate(classical):
        cx, cy = _centroid(c.mask)
        for j, m in enumerate(rfdetr):
            mx, my = _centroid(m.mask)
            dist = (cx - mx) ** 2 + (cy - my) ** 2
            pairs.append((dist, i, j))
    pairs.sort(key=lambda t: t[0])

    used_c: set[int] = set()
    used_m: set[int] = set()
    out: list[dict[str, Any]] = []
    for _dist, i, j in pairs:
        if i in used_c or j in used_m:
            continue
        used_c.add(i)
        used_m.add(j)
        iou = _mask_iou(classical[i].mask, rfdetr[j].mask)
        out.append(
            {
                "classical_index": i,
                "rfdetr_index": j,
                "iou": round(iou, 4),
                "classical_confidence": classical[i].confidence,
                "rfdetr_confidence": rfdetr[j].confidence,
            }
        )
    return out


def _summarize_teeth(teeth: list[ToothMask]) -> dict[str, Any]:
    accepted = [t for t in teeth if not t.rejected]
    return {
        "total": len(teeth),
        "accepted": len(accepted),
        "rejected": len(teeth) - len(accepted),
        "mean_confidence": round(
            float(np.mean([t.confidence for t in accepted])) if accepted else 0.0,
            3,
        ),
        "reject_reasons": [t.reject_reason for t in teeth if t.rejected],
    }


def compare_segmentation(
    image_rgb: np.ndarray,
    *,
    model_id: str | None = None,
    classical_config: SegmentConfig | None = None,
) -> SegmentAbResult:
    """Run classical and RF-DETR segmenters; return both + timings."""
    status = rfdetr_segment_status()

    t0 = time.perf_counter()
    classical = detect_teeth(
        image_rgb,
        config=classical_config,
        backend="classical",
    )
    classical_ms = (time.perf_counter() - t0) * 1000

    rfdetr_teeth: list[ToothMask] | None = None
    rfdetr_ms: float | None = None
    rfdetr_error: str | None = None

    if status.available:
        try:
            t1 = time.perf_counter()
            rfdetr_teeth = detect_teeth_rfdetr(image_rgb, model_id=model_id)
            rfdetr_ms = (time.perf_counter() - t1) * 1000
        except Exception as exc:
            rfdetr_error = str(exc)
            logger.exception("RF-DETR segmentation failed during A/B")
    else:
        rfdetr_error = status.import_error or (
            "ROBOFLOW_API_KEY not set" if not status.api_key_set else "RF-DETR unavailable"
        )

    return SegmentAbResult(
        classical=classical,
        rfdetr=rfdetr_teeth,
        classical_ms=classical_ms,
        rfdetr_ms=rfdetr_ms,
        rfdetr_status=status,
        rfdetr_error=rfdetr_error,
    )


def summarize_ab(result: SegmentAbResult) -> dict[str, Any]:
    """JSON-serializable summary for API / CLI."""
    payload: dict[str, Any] = {
        "classical": _summarize_teeth(result.classical),
        "classical_ms": round(result.classical_ms, 1),
        "rfdetr_available": result.rfdetr_status.available,
        "rfdetr_model_id": result.rfdetr_status.model_id,
        "rfdetr_api_key_set": result.rfdetr_status.api_key_set,
        "rfdetr_inference_api_url": result.rfdetr_status.inference_api_url,
        "rfdetr_import_error": result.rfdetr_status.import_error,
        "rfdetr_error": result.rfdetr_error,
    }
    if result.rfdetr is not None:
        payload["rfdetr"] = _summarize_teeth(result.rfdetr)
        payload["rfdetr_ms"] = round(result.rfdetr_ms or 0.0, 1)
        payload["pairwise_iou"] = _pairwise_best_iou(result.classical, result.rfdetr)
        if payload["pairwise_iou"]:
            payload["mean_pairwise_iou"] = round(
                float(np.mean([p["iou"] for p in payload["pairwise_iou"]])),
                4,
            )
    return payload


def save_ab_panel(
    image_rgb: np.ndarray,
    out_path: str | Path,
    *,
    model_id: str | None = None,
) -> Path:
    """Write side-by-side: input | classical | RF-DETR (or placeholder)."""
    import cv2

    path = Path(out_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    ab = compare_segmentation(image_rgb, model_id=model_id)
    classical_panel = render_instance_overlay(image_rgb, ab.classical)

    if ab.rfdetr is not None:
        rfdetr_panel = render_instance_overlay(image_rgb, ab.rfdetr)
    else:
        rfdetr_panel = np.asarray(image_rgb, dtype=np.uint8).copy()
        msg = ab.rfdetr_error or "RF-DETR unavailable"
        cv2.putText(
            cv2.cvtColor(rfdetr_panel, cv2.COLOR_RGB2BGR),
            msg[:80],
            (12, 32),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 0, 255),
            2,
        )
        rfdetr_panel = cv2.cvtColor(
            cv2.cvtColor(rfdetr_panel, cv2.COLOR_RGB2BGR), cv2.COLOR_BGR2RGB
        )

    panels = [
        np.asarray(image_rgb, dtype=np.uint8),
        classical_panel,
        rfdetr_panel,
    ]
    h = max(p.shape[0] for p in panels)
    padded = []
    for p in panels:
        if p.shape[0] < h:
            pad = np.zeros((h - p.shape[0], p.shape[1], 3), dtype=np.uint8)
            p = np.vstack([p, pad])
        padded.append(p)

    labels = ["Input", f"Classical ({ab.classical_ms:.0f}ms)", "RF-DETR"]
    if ab.rfdetr_ms is not None:
        labels[2] = f"RF-DETR ({ab.rfdetr_ms:.0f}ms)"

    panel = np.hstack(padded)
    bgr = cv2.cvtColor(panel, cv2.COLOR_RGB2BGR)
    x_offsets = [0]
    for p in padded[:-1]:
        x_offsets.append(x_offsets[-1] + p.shape[1])
    for label, x in zip(labels, x_offsets):
        cv2.putText(
            bgr, label, (x + 8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2
        )

    cv2.imwrite(str(path), bgr)
    return path


def _load_rgb(path: Path) -> np.ndarray:
    from PIL import Image, ImageOps

    img = Image.open(path)
    try:
        img = ImageOps.exif_transpose(img)
    except Exception:
        pass
    return np.asarray(img.convert("RGB"), dtype=np.uint8)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Shade segmentation A/B harness")
    parser.add_argument("image", type=Path, help="Smile photo (JPEG/PNG)")
    parser.add_argument("-o", "--out", type=Path, help="Write comparison PNG")
    parser.add_argument("--model-id", default=None, help="Roboflow model_id override")
    parser.add_argument("--json", action="store_true", help="Print JSON summary to stdout")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO)
    rgb = _load_rgb(args.image)

    if args.json:
        ab = compare_segmentation(rgb, model_id=args.model_id)
        print(json.dumps(summarize_ab(ab), indent=2))
    if args.out:
        save_ab_panel(rgb, args.out, model_id=args.model_id)
        print(f"Wrote {args.out}")
    elif not args.json:
        ab = compare_segmentation(rgb, model_id=args.model_id)
        print(json.dumps(summarize_ab(ab), indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

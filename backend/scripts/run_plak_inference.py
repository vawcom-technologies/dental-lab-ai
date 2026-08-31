#!/usr/bin/env python3
"""Run PLAK tooth segmentation on a local image (Roboflow Inference).

Usage:
  cd backend
  export ROBOFLOW_API_KEY=your_key
  python scripts/run_plak_inference.py path/to/smile.jpg
  python scripts/run_plak_inference.py smile.jpg -o /tmp/out.png --json

Model ID (v16 semantic segmentation):
  projectdens/plak---projectdens-7p9sm/16
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

DEFAULT_MODEL_ID = (
    "mahvish-hasan/plak---projectdens-7p9sm-atp73-1-yolo26s-sem-t1"
)


def _load_env() -> None:
    """Load backend/.env into os.environ (scripts don't use pydantic Settings)."""
    env_path = BACKEND_ROOT / ".env"
    if not env_path.is_file():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def _load_rgb(path: Path):
    from PIL import Image, ImageOps

    img = Image.open(path)
    try:
        img = ImageOps.exif_transpose(img)
    except Exception:
        pass
    import numpy as np

    return np.asarray(img.convert("RGB"), dtype=np.uint8)


def main(argv: list[str] | None = None) -> int:
    _load_env()
    parser = argparse.ArgumentParser(description="PLAK tooth segmentation test")
    parser.add_argument("image", type=Path, help="Smile photo")
    parser.add_argument(
        "--model-id",
        default=os.environ.get(
            "SHADE_SEGMENT_ROBOFLOW_MODEL_ID",
            DEFAULT_MODEL_ID,
        ),
        help="Roboflow model_id",
    )
    parser.add_argument("-o", "--out", type=Path, help="Write overlay PNG")
    parser.add_argument("--json", action="store_true", help="Print tooth summary JSON")
    args = parser.parse_args(argv)

    if not os.environ.get("ROBOFLOW_API_KEY", "").strip():
        print(
            "Set ROBOFLOW_API_KEY in backend/.env (or export it).",
            file=sys.stderr,
        )
        print(f"Looked for: {BACKEND_ROOT / '.env'}", file=sys.stderr)
        return 1
    if not args.image.is_file():
        print(f"Image not found: {args.image}", file=sys.stderr)
        print(
            "Pass a real path, e.g. python scripts/run_plak_inference.py ~/Desktop/smile.jpg -o /tmp/out.png --json",
            file=sys.stderr,
        )
        return 1

    from app.ai.shade_segment_rfdetr import (
        _normalize_model_id,
        detect_teeth_rfdetr,
        rfdetr_segment_status,
    )
    from app.ai.shade_segment_viz import render_instance_overlay

    status = rfdetr_segment_status()
    mid = _normalize_model_id(args.model_id)
    print(f"model_id={mid} api={status.inference_api_url} available={status.available}")

    rgb = _load_rgb(args.image)
    teeth = detect_teeth_rfdetr(rgb, model_id=mid)
    accepted = [t for t in teeth if not t.rejected]

    summary = {
        "model_id": mid,
        "tooth_count": len(teeth),
        "accepted_count": len(accepted),
        "teeth": [
            {
                "index": t.tooth_index,
                "confidence": t.confidence,
                "rejected": t.rejected,
                "reject_reason": t.reject_reason,
                "mask_pixels": int(t.mask.sum()),
            }
            for t in teeth
        ],
    }
    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print(json.dumps(summary))

    if args.out:
        overlay = render_instance_overlay(rgb, teeth)
        from PIL import Image

        Image.fromarray(overlay).save(args.out)
        print(f"Wrote overlay: {args.out}")

    return 0 if accepted else 2


if __name__ == "__main__":
    raise SystemExit(main())

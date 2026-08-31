#!/usr/bin/env python3
"""Train production teeth segmenter (YOLO11-seg) for shade detection.

Public datasets (instant download with free Roboflow API key):
  - teeth-and-gum-seperation  (~1800 images) — primary
  - intraoral-tooth-detection-rohlq (~1200) — optional merge via second run

After base training, fine-tune on clinic photos for maximum accuracy:
  python scripts/train_teeth_segmenter.py --finetune ./clinic_dataset/data.yaml

Output: backend/weights/teeth_seg/best.pt

Requires: pip install -r requirements-ml.txt roboflow
Env: ROBOFLOW_API_KEY=your_key
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
WEIGHTS_OUT = BACKEND_ROOT / "weights" / "teeth_seg"

# Primary public dataset — intraoral smile / teeth instance segmentation
PRIMARY = {
    "workspace": "iitb-yluyt",
    "project": "teeth-and-gum-seperation",
    "version": 4,
}


def _download_dataset(api_key: str) -> Path:
    from roboflow import Roboflow

    rf = Roboflow(api_key=api_key)
    project = rf.workspace(PRIMARY["workspace"]).project(PRIMARY["project"])
    version = project.version(PRIMARY["version"])
    dataset = version.download("yolov11", location=str(BACKEND_ROOT / "data" / "teeth_train"))
    return Path(dataset.location)


def _train(
    data_yaml: Path,
    *,
    model: str,
    imgsz: int,
    epochs: int,
    batch: int,
    project: Path,
    name: str,
) -> Path:
    from ultralytics import YOLO

    yolo = YOLO(model)
    yolo.train(
        data=str(data_yaml),
        imgsz=imgsz,
        epochs=epochs,
        batch=batch,
        project=str(project),
        name=name,
        patience=20,
        save=True,
        plots=True,
        # Accuracy-oriented defaults for clinical boundaries
        mosaic=0.5,
        mixup=0.1,
        copy_paste=0.1,
        degrees=8.0,
        translate=0.08,
        scale=0.35,
        fliplr=0.5,
        hsv_h=0.015,
        hsv_s=0.5,
        hsv_v=0.35,
    )
    best = project / name / "weights" / "best.pt"
    if not best.is_file():
        raise FileNotFoundError(f"Training finished but best.pt missing at {best}")
    return best


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Train production teeth YOLO11-seg")
    parser.add_argument(
        "--api-key",
        default=os.environ.get("ROBOFLOW_API_KEY", ""),
        help="Roboflow API key (or set ROBOFLOW_API_KEY)",
    )
    parser.add_argument(
        "--finetune",
        type=Path,
        default=None,
        help="Path to clinic data.yaml for fine-tuning (skip Roboflow download)",
    )
    parser.add_argument("--model", default="yolo11s-seg.pt", help="Base checkpoint")
    parser.add_argument("--imgsz", type=int, default=1280, help="Train/infer resolution")
    parser.add_argument("--epochs", type=int, default=120)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--name", default="teeth_seg")
    args = parser.parse_args(argv)

    WEIGHTS_OUT.mkdir(parents=True, exist_ok=True)
    runs = BACKEND_ROOT / "runs" / "segment"

    if args.finetune is not None:
        data_yaml = args.finetune.resolve()
        if not data_yaml.is_file():
            print(f"Fine-tune data.yaml not found: {data_yaml}", file=sys.stderr)
            return 1
        base = WEIGHTS_OUT / "best.pt"
        model = str(base) if base.is_file() else args.model
        print(f"Fine-tuning from {model} on {data_yaml}")
    else:
        if not args.api_key.strip():
            print(
                "Set ROBOFLOW_API_KEY or pass --api-key to download training data.\n"
                "Sign up free at https://roboflow.com — takes ~2 minutes.",
                file=sys.stderr,
            )
            return 1
        print("Downloading public dental segmentation dataset…")
        ds = _download_dataset(args.api_key.strip())
        data_yaml = ds / "data.yaml"
        model = args.model
        print(f"Dataset ready: {data_yaml}")

    best = _train(
        data_yaml,
        model=model,
        imgsz=args.imgsz,
        epochs=args.epochs,
        batch=args.batch,
        project=runs,
        name=args.name,
    )

    dest = WEIGHTS_OUT / "best.pt"
    shutil.copy2(best, dest)
    print(f"\nProduction weights installed: {dest}")
    print("\nEnable in backend/.env:")
    print("  SHADE_SEGMENT_BACKEND=production")
    print(f"  SHADE_SEGMENT_YOLO_WEIGHTS=weights/teeth_seg/best.pt")
    print(f"  SHADE_SEGMENT_IMGSZ={args.imgsz}")
    print("  SHADE_SEGMENT_SAM_REFINE=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

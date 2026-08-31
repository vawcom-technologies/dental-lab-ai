#!/usr/bin/env python3
"""Pilot KAIST individual tooth segmentation on clinic smile photos.

Usage:
  cd backend
  python scripts/run_kaist_pilot.py --setup
  python scripts/run_kaist_pilot.py --download-weights
  python scripts/run_kaist_pilot.py path/to/smile.jpg -o /tmp/kaist_out
  python scripts/run_kaist_pilot.py path/to/folder/ -o /tmp/kaist_out --no-crop

Compare overlays to vendor/individual_tooth_segmentation/figures/.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

VENDOR = BACKEND_ROOT / "vendor" / "individual_tooth_segmentation"
WEIGHTS = BACKEND_ROOT / "weights" / "kaist" / "CP_teeth_seg.pth"
# HTTPS redirects here; their cert chain is broken — download with verify=False.
WEIGHTS_URL = (
    "https://parter.kaist.ac.kr/colee/work/segmentation22/CP_teeth_seg.pth"
)
REPO_URL = "https://github.com/mireiffe/individual_tooth_segmentation.git"


def _load_env() -> None:
    env_path = BACKEND_ROOT / ".env"
    if not env_path.is_file():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def cmd_setup() -> int:
    if (VENDOR / "src" / "makeup.py").is_file():
        print(f"Vendor already present: {VENDOR}")
        return 0
    VENDOR.parent.mkdir(parents=True, exist_ok=True)
    print(f"Cloning {REPO_URL} → {VENDOR}")
    subprocess.check_call(
        ["git", "clone", "--depth", "1", REPO_URL, str(VENDOR)]
    )
    print("Done. Next: python scripts/run_kaist_pilot.py --download-weights")
    return 0


def cmd_download_weights() -> int:
    import ssl

    WEIGHTS.parent.mkdir(parents=True, exist_ok=True)
    if WEIGHTS.is_file() and WEIGHTS.stat().st_size > 1_000_000_000:
        print(f"Weights already present: {WEIGHTS} ({WEIGHTS.stat().st_size} bytes)")
        return 0
    # Remove partial failed downloads
    if WEIGHTS.is_file():
        WEIGHTS.unlink()

    print(f"Downloading {WEIGHTS_URL}")
    print(f"→ {WEIGHTS}")
    print("(~1.5 GB; KAIST cert is self-signed — TLS verify disabled for this host)")

    # Prefer curl -k (resumable, progress). Fallback: urllib + unverified SSL.
    curl = subprocess.run(["which", "curl"], capture_output=True, text=True)
    if curl.returncode == 0:
        rc = subprocess.call(
            [
                "curl",
                "-L",
                "-k",
                "--fail",
                "--progress-bar",
                "-o",
                str(WEIGHTS),
                WEIGHTS_URL,
            ]
        )
        if rc != 0:
            if WEIGHTS.is_file():
                WEIGHTS.unlink()
            print("curl download failed.", file=sys.stderr)
            return 1
    else:
        try:
            ctx = ssl._create_unverified_context()
            with urllib.request.urlopen(WEIGHTS_URL, context=ctx) as resp:
                with open(WEIGHTS, "wb") as f:
                    while True:
                        chunk = resp.read(1024 * 1024)
                        if not chunk:
                            break
                        f.write(chunk)
        except Exception as exc:
            if WEIGHTS.is_file():
                WEIGHTS.unlink()
            print(f"Download failed: {exc}", file=sys.stderr)
            print(
                "Manual fallback:\n"
                f'  curl -L -k -o "{WEIGHTS}" "{WEIGHTS_URL}"',
                file=sys.stderr,
            )
            return 1

    size = WEIGHTS.stat().st_size
    if size < 1_000_000_000:
        print(f"Download looks incomplete ({size} bytes)", file=sys.stderr)
        return 1
    print(f"Saved {size} bytes")
    return 0


def _load_rgb(path: Path):
    from PIL import Image, ImageOps
    import numpy as np

    img = Image.open(path)
    try:
        img = ImageOps.exif_transpose(img)
    except Exception:
        pass
    return np.asarray(img.convert("RGB"), dtype=np.uint8)


def _overlay(rgb, teeth):
    import cv2
    import numpy as np

    out = rgb.copy()
    for t in teeth:
        if t.rejected or not np.any(t.mask):
            continue
        u8 = (t.mask.astype(np.uint8)) * 255
        cnts, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cv2.drawContours(out, cnts, -1, (0, 255, 0), 2)
    return out


def _iter_images(path: Path) -> list[Path]:
    exts = {".png", ".jpg", ".jpeg", ".jfif", ".webp"}
    if path.is_file():
        return [path]
    return sorted(p for p in path.iterdir() if p.suffix.lower() in exts)


def cmd_run(args: argparse.Namespace) -> int:
    from app.ai.shade_segment_kaist import (
        detect_teeth_kaist,
        kaist_segment_status,
        mouth_crop_rgb,
    )

    st = kaist_segment_status()
    if not st.available:
        print(f"KAIST unavailable: {st.import_error}", file=sys.stderr)
        return 1

    paths = _iter_images(args.image)
    if not paths:
        print(f"No images found at {args.image}", file=sys.stderr)
        return 1

    out_dir = args.out
    if out_dir:
        out_dir.mkdir(parents=True, exist_ok=True)

    for src in paths:
        print(f"=== {src.name} ===")
        rgb = _load_rgb(src)
        if args.save_crop and out_dir:
            crop, box = mouth_crop_rgb(rgb)
            from PIL import Image

            Image.fromarray(crop).save(out_dir / f"{src.stem}_crop.png")
            print(f"  crop box={box} → {src.stem}_crop.png")

        teeth = detect_teeth_kaist(rgb, crop=not args.no_crop)
        accepted = [t for t in teeth if not t.rejected]
        print(f"  teeth={len(teeth)} accepted={len(accepted)}")
        if out_dir:
            from PIL import Image

            overlay = _overlay(rgb, accepted)
            dest = out_dir / f"{src.stem}_kaist.png"
            Image.fromarray(overlay).save(dest)
            print(f"  wrote {dest}")
    return 0


def main(argv: list[str] | None = None) -> int:
    _load_env()
    p = argparse.ArgumentParser(description="KAIST tooth segmentation pilot")
    p.add_argument("image", type=Path, nargs="?", help="Image file or folder")
    p.add_argument("-o", "--out", type=Path, help="Output directory for overlays")
    p.add_argument(
        "--no-crop",
        action="store_true",
        help="Skip mouth crop (use when inputs are already tight mouth crops)",
    )
    p.add_argument(
        "--save-crop",
        action="store_true",
        help="Also write the mouth crop used for inference",
    )
    p.add_argument("--setup", action="store_true", help="Clone upstream vendor repo")
    p.add_argument(
        "--download-weights",
        action="store_true",
        help="Download CP_teeth_seg.pth into weights/kaist/",
    )
    args = p.parse_args(argv)

    if args.setup:
        return cmd_setup()
    if args.download_weights:
        return cmd_download_weights()
    if args.image is None:
        p.print_help()
        return 2
    return cmd_run(args)


if __name__ == "__main__":
    raise SystemExit(main())

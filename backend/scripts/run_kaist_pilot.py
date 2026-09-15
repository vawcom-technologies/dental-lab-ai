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
import threading
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

VENDOR = BACKEND_ROOT / "vendor" / "individual_tooth_segmentation"
WEIGHTS = BACKEND_ROOT / "weights" / "kaist" / "CP_teeth_seg.pth"
# Official README uses HTTP; HTTPS has a broken/self-signed cert.
WEIGHTS_URLS = (
    "http://parter.kaist.ac.kr/colee/work/segmentation22/CP_teeth_seg.pth",
    "https://parter.kaist.ac.kr/colee/work/segmentation22/CP_teeth_seg.pth",
)
WEIGHTS_URL = WEIGHTS_URLS[0]
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


WEIGHTS_BYTES = 1_483_702_637
_DOWNLOAD_WORKERS = 12


def _curl_range(url: str, dest: Path, start: int, end: int) -> int:
    want = end - start + 1
    if dest.is_file() and dest.stat().st_size == want:
        print(f"part {dest.name} already {want} bytes", flush=True)
        return 0
    dest.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "curl",
        "-k",
        "--fail",
        "--retry",
        "80",
        "--retry-all-errors",
        "--retry-delay",
        "3",
        "--connect-timeout",
        "20",
        "--speed-time",
        "90",
        "--speed-limit",
        "512",
        "--silent",
        "--show-error",
        "-C",
        "-",
        "-r",
        f"{start}-{end}",
        "-o",
        str(dest),
        url,
    ]
    print(f"part {dest.name} bytes {start}-{end}", flush=True)
    return int(subprocess.call(cmd))


def cmd_download_weights() -> int:
    from concurrent.futures import ThreadPoolExecutor, as_completed

    WEIGHTS.parent.mkdir(parents=True, exist_ok=True)
    have = WEIGHTS.stat().st_size if WEIGHTS.is_file() else 0
    if have >= WEIGHTS_BYTES:
        print(f"Weights already present: {WEIGHTS} ({have} bytes)")
        return 0

    url = WEIGHTS_URLS[1]  # HTTPS; HTTP only 301s here
    rest = WEIGHTS_BYTES - have
    workers = max(1, min(_DOWNLOAD_WORKERS, rest // (4 * 1024 * 1024) or 1))
    chunk = (rest + workers - 1) // workers
    part_dir = WEIGHTS.parent / ".kaist_parts"
    part_dir.mkdir(exist_ok=True)

    print(f"→ {WEIGHTS}", flush=True)
    print(
        f"resuming {have}/{WEIGHTS_BYTES} ({have / WEIGHTS_BYTES:.1%}); "
        f"{workers} parallel HTTPS ranges",
        flush=True,
    )

    ranges: list[tuple[Path, int, int]] = []
    pos = have
    idx = 0
    while pos < WEIGHTS_BYTES:
        end = min(WEIGHTS_BYTES - 1, pos + chunk - 1)
        ranges.append((part_dir / f"part_{idx:02d}", pos, end))
        pos = end + 1
        idx += 1

    last_err = "download failed"
    stop = threading.Event()

    def _progress() -> None:
        while not stop.wait(20):
            part_sum = sum(p.stat().st_size for p, _, _ in ranges if p.is_file())
            total = have + part_sum
            print(
                f"progress {total}/{WEIGHTS_BYTES} ({total / WEIGHTS_BYTES:.1%})",
                flush=True,
            )

    threading.Thread(target=_progress, daemon=True).start()
    with ThreadPoolExecutor(max_workers=len(ranges)) as pool:
        futs = {
            pool.submit(_curl_range, url, dest, start, end): dest
            for dest, start, end in ranges
        }
        failed = False
        try:
            for fut in as_completed(futs):
                dest = futs[fut]
                rc = fut.result()
                size = dest.stat().st_size if dest.is_file() else 0
                print(f"done {dest.name} rc={rc} size={size}", flush=True)
                if rc != 0:
                    failed = True
                    last_err = f"curl failed for {dest.name} (rc={rc})"
        finally:
            stop.set()
        if failed:
            print(f"Download looks incomplete ({have} + parts): {last_err}", file=sys.stderr)
            return 1

    print("concatenating parts…", flush=True)
    with open(WEIGHTS, "ab") as out:
        for dest, _, _ in ranges:
            with open(dest, "rb") as inp:
                while True:
                    buf = inp.read(1024 * 1024)
                    if not buf:
                        break
                    out.write(buf)

    final = WEIGHTS.stat().st_size
    if final != WEIGHTS_BYTES:
        print(
            f"Download looks incomplete ({final} bytes, expected {WEIGHTS_BYTES})",
            file=sys.stderr,
        )
        return 1
    for dest, _, _ in ranges:
        dest.unlink(missing_ok=True)
    try:
        part_dir.rmdir()
    except OSError:
        pass
    print(f"Saved {final} bytes", flush=True)
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

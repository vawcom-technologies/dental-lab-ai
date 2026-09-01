#!/usr/bin/env python3
"""Bake KAIST vendor + CPU Torch into the Railway image.

Does not download CP_teeth_seg.pth (~1.5 GB). Keep that on a volume or
run: python scripts/run_kaist_pilot.py --download-weights
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from urllib.request import urlretrieve

BACKEND_ROOT = Path(__file__).resolve().parents[1]
VENDOR = BACKEND_ROOT / "vendor" / "individual_tooth_segmentation"
REPO_ZIP = (
    "https://github.com/mireiffe/individual_tooth_segmentation/"
    "archive/refs/heads/main.zip"
)
REPO_GIT = "https://github.com/mireiffe/individual_tooth_segmentation.git"


def _pip(*args: str) -> None:
    subprocess.check_call([sys.executable, "-m", "pip", "install", *args])


def _ensure_vendor() -> None:
    if (VENDOR / "src" / "makeup.py").is_file():
        print(f"KAIST vendor already present: {VENDOR}")
        return
    VENDOR.parent.mkdir(parents=True, exist_ok=True)
    git = subprocess.run(["which", "git"], capture_output=True, text=True)
    if git.returncode == 0:
        print(f"Cloning {REPO_GIT} → {VENDOR}")
        subprocess.check_call(
            ["git", "clone", "--depth", "1", REPO_GIT, str(VENDOR)]
        )
        return
    print("git missing — fetching vendor zip")
    zpath = Path("/tmp/kaist-vendor.zip")
    urlretrieve(REPO_ZIP, zpath)
    dest = Path("/tmp/kaist-vendor-unpack")
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zpath) as zf:
        zf.extractall(dest)
    unpacked = dest / "individual_tooth_segmentation-main"
    if not unpacked.is_dir():
        raise SystemExit(f"unexpected zip layout under {dest}")
    if VENDOR.exists():
        shutil.rmtree(VENDOR)
    unpacked.rename(VENDOR)
    zpath.unlink(missing_ok=True)
    print(f"Vendor ready: {VENDOR}")


def _ensure_deps() -> None:
    extra: list[str] = []
    if sys.platform.startswith("linux"):
        extra = ["--index-url", "https://download.pytorch.org/whl/cpu"]
        print("Installing CPU Torch (Linux / Railway)")
    else:
        print("Installing Torch from PyPI")
    _pip(*extra, "torch>=2.2.0,<3", "torchvision>=0.17.0,<1")
    _pip(
        "pyyaml",
        "scikit-fmm>=2025.1.29",
        "scikit-image>=0.24.0",
        "scipy",
        "matplotlib",
    )


def main() -> int:
    os.chdir(BACKEND_ROOT)
    _ensure_vendor()
    _ensure_deps()
    print("KAIST image setup done (weights still needed on disk)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

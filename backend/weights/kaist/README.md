# KAIST individual tooth segmentation

Per-tooth outlines from
[mireiffe/individual_tooth_segmentation](https://github.com/mireiffe/individual_tooth_segmentation)
(Kim & Lee, 2024) — RGB extra-oral mouth photos with instance contours.

## Setup

```bash
cd backend

# 1) Clone the upstream repo (gitignored under vendor/)
./scripts/run_kaist_pilot.py --setup

# 2) Download weights (~1.5 GB) into this folder
#    https://parter.kaist.ac.kr/colee/work/segmentation22/CP_teeth_seg.pth
#    (host uses a broken TLS cert — the script uses curl -k)
./scripts/run_kaist_pilot.py --download-weights

# 3) Install deps (torch>=2.2 — upstream 2.0.1 has no py3.12 wheels)
pip install -r requirements-kaist.txt
```

## Pilot on clinic photos

Mouth-crop first (full-face shots will not match their demos):

```bash
python scripts/run_kaist_pilot.py path/to/smile.jpg -o /tmp/kaist_out
python scripts/run_kaist_pilot.py path/to/mouth_crops/ -o /tmp/kaist_out --no-crop
```

Compare overlays to `vendor/individual_tooth_segmentation/figures/`.

## App wiring

KAIST is the **default** shade segmenter (`SHADE_SEGMENT_BACKEND=kaist`).
Classical CV is emergency-only: used only if vendor/weights are missing or
KAIST crashes — not when KAIST runs and finds 0 teeth.

```env
SHADE_SEGMENT_BACKEND=kaist
SHADE_SEGMENT_KAIST_WEIGHTS=weights/kaist/CP_teeth_seg.pth
SHADE_SEGMENT_KAIST_DEVICE=cpu
SHADE_SEGMENT_KAIST_RESIZE=false
# Emergency only:
# SHADE_SEGMENT_BACKEND=classical
```

`RESIZE=false` is required for demo-quality contours.

## Speed vs accuracy (chairside defaults)

KAIST clamps the snake canvas into **256–320px** (upscale tiny crops only to the
floor; downscale large ones). Mid-size crops stay native. Masks map back to the
photo. Full-res (`MAX_SIDE=0`) misses the iPad 90s client timeout. Weights stay
cached after the first request.

Step1 (CNN) uses MPS/CUDA; Steps 2–3 (snakes) are CPU — that is the latency floor.

```env
SHADE_SEGMENT_KAIST_DEVICE=auto          # mps on Apple Silicon when available
SHADE_SEGMENT_KAIST_MAX_SIDE=320         # downscale ceiling; 0 → 320
SHADE_SEGMENT_KAIST_MIN_SIDE=256         # upscale floor for tiny crops
SHADE_SEGMENT_KAIST_SNAKE_ITERS=10
SHADE_SEGMENT_KAIST_BRING_BACK_ITERS=60
SHADE_SEGMENT_KAIST_EVOLVE_ITERS=30
```

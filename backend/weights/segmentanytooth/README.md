# SegmentAnyTooth model weights

Place downloaded `.pt` files in this directory. The shade ML backend looks for:

| File | Purpose |
|------|---------|
| `segmentanytooth_vit_tiny.pt` | Light HQ-SAM segmentation |
| `segmentanytooth_yolo11_front.pt` | YOLO11 detection (frontal smile) |
| `segmentanytooth_yolo11_upper.pt` | Upper occlusal view |
| `segmentanytooth_yolo11_lower.pt` | Lower occlusal view |
| `segmentanytooth_yolo11_right.pt` | Right lateral (left uses same weights) |

## Obtain weights

1. Sign the [SegmentAnyTooth Non-Commercial License](https://github.com/thangngoc89/SegmentAnyTooth/blob/main/SegmentAnyTooth_license_agreement.pdf)
2. Email the signed form to **hi+segmentanytooth@khoanguyen.me**
3. Download weights and copy them here

## Install Python deps

```bash
cd backend
pip install -r requirements-ml.txt
```

## Enable ML segmentation

In `backend/.env`:

```env
SHADE_SEGMENT_BACKEND=auto
SHADE_SEGMENT_ML_VIEW=front
SHADE_SEGMENT_ML_WEIGHTS_DIR=weights/segmentanytooth
```

- `auto` — use ML when weights are present, else classical CV
- `ml` — ML only (falls back to classical if inference fails)
- `classical` — original heuristic pipeline

## A/B comparison

```bash
cd backend
python -m app.ai.shade_segment_ab path/to/smile.jpg -o /tmp/ab.png --json
```

Or `POST /api/ai/shade/segment-ab` (authenticated) with an image upload.

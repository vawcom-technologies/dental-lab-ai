# Production teeth segmentation weights

Place `best.pt` here after training:

```bash
cd backend
pip install -r requirements-ml.txt roboflow
export ROBOFLOW_API_KEY=your_key   # free signup at roboflow.com
python scripts/train_teeth_segmenter.py --model yolo11s-seg.pt --imgsz 1280 --epochs 120
```

This downloads ~1800 annotated intraoral photos and trains YOLO11-seg.
SAM2 (`sam2_b.pt`) auto-downloads on first run for boundary refinement.

## Maximum accuracy (required for clinic production)

Public dataset training gets you ~80–90% of the way. **Clinic fine-tuning is mandatory** for guaranteed accuracy on Elite Dent photos:

1. Annotate 200–500 smile photos in Roboflow (polygon masks per tooth)
2. Export as YOLO11-seg
3. Fine-tune:

```bash
python scripts/train_teeth_segmenter.py --finetune /path/to/clinic/data.yaml --epochs 60
```

## Enable after training

```env
SHADE_SEGMENT_BACKEND=production
SHADE_SEGMENT_YOLO_WEIGHTS=weights/teeth_seg/best.pt
SHADE_SEGMENT_IMGSZ=1280
SHADE_SEGMENT_SAM_REFINE=true
```

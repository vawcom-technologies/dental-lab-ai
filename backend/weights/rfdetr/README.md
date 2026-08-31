# RF-DETR / PLAK tooth segmentation

Tooth outlines use a Roboflow **YOLO26 semantic** PLAK model via
[Roboflow Inference SDK](https://github.com/roboflow/inference).

Default model ID: **`mahvish-hasan/plak---projectdens-7p9sm-atp73-1-yolo26s-sem-t1`**
(also works: `projectdens/plak---projectdens-7p9sm/16`).

## Semantic vs Roboflow Test tab

The Test tab paints the **tooth class mask** (one color for all teeth). That is
what the API returns. Our app needs **per-tooth instances** for shade zones, so
we split the tooth-class region with connected components + a gentle
distance-transform watershed that **keeps every tooth-class pixel** (union of
instances matches the Roboflow overlay). Contact cuts are approximate — for
perfect per-crown boundaries, retrain as **instance segmentation**.

## Setup

```bash
cd backend
pip install -r requirements-ml.txt
```

In `backend/.env` (never commit the API key):

```env
ROBOFLOW_API_KEY=your_key_here
SHADE_SEGMENT_BACKEND=rfdetr
SHADE_SEGMENT_ROBOFLOW_MODEL_ID=projectdens/plak---projectdens-7p9sm/16
SHADE_SEGMENT_INFERENCE_API_URL=https://serverless.roboflow.com
SHADE_SEGMENT_CONF=0.25
```

Short model ID also works: `plak---projectdens-7p9sm/16`

## Test on an image

```bash
cd backend
export ROBOFLOW_API_KEY=your_key
python scripts/run_plak_inference.py path/to/smile.jpg -o /tmp/plak.png --json
```

## GDPR production

Use self-hosted Inference Server instead of serverless:

```bash
pip install inference-cli
inference server start
```

```env
SHADE_SEGMENT_INFERENCE_API_URL=http://localhost:9001
```

## Model page

https://universe.roboflow.com/projectdens/plak---projectdens-7p9sm

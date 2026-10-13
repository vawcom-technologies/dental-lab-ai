#!/usr/bin/env python3
"""Compare GPT tooth outlines against KAIST on a folder of smile photos.

Each model returns one polygon per crown; masks then go through the same
zone split + VITA matching as the app, so we see whether the *shade* changes.

Usage:
  cd backend
  .venv/bin/python scripts/eval_gpt_segment.py ../references/smiles \
      --models gpt-6,gpt-5.4-mini -o debug/gpt_eval

Writes per photo: <name>_panel.png (input | KAIST | each model) and
<name>_<model>.json (raw reply). Prints a summary table and writes summary.csv.
KAIST is the reference here (no hand-drawn ground truth) — read the panels too.
"""

from __future__ import annotations

import argparse
import base64
import csv
import io
import json
import os
import sys
import time
from pathlib import Path

import numpy as np

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

from dotenv import load_dotenv  # noqa: E402

load_dotenv(BACKEND_ROOT / ".env")

from app.ai.shade_analyze import _analyze_tooth, _maybe_downscale_rgb  # noqa: E402
from app.ai.shade_segment import (  # noqa: E402
    ToothMask,
    _assign_arch_metadata,
    _sanity_check_instances,
    detect_teeth,
)
from app.ai.shade_segment_ab import _load_rgb, _pairwise_best_iou  # noqa: E402
from app.ai.shade_segment_viz import render_instance_overlay  # noqa: E402

from app.ai.shade_zones import ZONES  # noqa: E402
PROMPT = (
    "This is a dental smile photo. Outline the visible enamel crown of every "
    "tooth you can see, upper and lower arch. Each polygon must hug the crown "
    "edge: exclude gum, lips, tongue, and dark gaps between teeth. Use 16-32 "
    "points per tooth, clockwise. Coordinates are integers on a 0-1000 grid "
    "where (0,0) is the image top-left and (1000,1000) its bottom-right."
)
SCHEMA = {
    "name": "teeth",
    "strict": True,
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "required": ["teeth"],
        "properties": {
            "teeth": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["fdi", "polygon"],
                    "properties": {
                        "fdi": {"type": "integer"},
                        "polygon": {
                            "type": "array",
                            "items": {
                                "type": "array",
                                "items": {"type": "integer"},
                            },
                        },
                    },
                },
            }
        },
    },
}


def _jpeg_b64(rgb: np.ndarray) -> str:
    from PIL import Image

    buf = io.BytesIO()
    Image.fromarray(rgb).save(buf, format="JPEG", quality=92)
    return base64.b64encode(buf.getvalue()).decode()


def ask_model(rgb: np.ndarray, model: str, effort: str | None) -> tuple[dict, float, dict]:
    import httpx

    key = os.environ.get("INTERPRETER_LLM_API_KEY") or os.environ.get("OPENAI_API_KEY")
    if not key:
        raise SystemExit("Set OPENAI_API_KEY in backend/.env")
    base = os.environ.get("INTERPRETER_LLM_BASE_URL", "https://api.openai.com/v1").rstrip("/")
    body = {
        "model": model,
        "response_format": {"type": "json_schema", "json_schema": SCHEMA},
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": PROMPT},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{_jpeg_b64(rgb)}",
                            "detail": "high",
                        },
                    },
                ],
            }
        ],
    }
    if effort:
        body["reasoning_effort"] = effort
    t0 = time.perf_counter()
    res = httpx.post(
        f"{base}/chat/completions",
        headers={"Authorization": f"Bearer {key}"},
        json=body,
        timeout=180,
    )
    ms = (time.perf_counter() - t0) * 1000
    res.raise_for_status()
    data = res.json()
    content = data["choices"][0]["message"]["content"] or "{}"
    return json.loads(content), ms, data.get("usage") or {}


def polygons_to_teeth(reply: dict, h: int, w: int) -> list[ToothMask]:
    import cv2

    teeth: list[ToothMask] = []
    for item in reply.get("teeth") or []:
        pts = [p for p in item.get("polygon") or [] if len(p) == 2]
        if len(pts) < 3:
            continue
        xy = np.array(pts, dtype=np.float32) / 1000.0 * [w, h]
        m = np.zeros((h, w), dtype=np.uint8)
        cv2.fillPoly(m, [np.round(xy).astype(np.int32)], 1)
        if m.sum() < 40:
            continue
        teeth.append(
            ToothMask(tooth_index=len(teeth), mask=m.astype(bool), confidence=0.9, rejected=False)
        )
    return _assign_arch_metadata(_sanity_check_instances(teeth))


def zone_shades(rgb: np.ndarray, teeth: list[ToothMask]) -> list[dict[str, str | None]]:
    rows = [_analyze_tooth(rgb, t) for t in teeth]
    return [{z: r["zones"][z]["detected_shade"] for z in ZONES} for r in rows]


def compare(rgb, ref: list[ToothMask], cand: list[ToothMask]) -> dict:
    """Centroid-match candidate teeth to KAIST; IoU + same-shade rate per zone."""
    pairs = _pairwise_best_iou(ref, cand)
    ref_sh, cand_sh = zone_shades(rgb, ref), zone_shades(rgb, cand)
    same = total = 0
    for p in pairs:
        if p["iou"] < 0.3:  # different teeth, not a boundary disagreement
            continue
        a, b = ref_sh[p["classical_index"]], cand_sh[p["rfdetr_index"]]
        for z in ZONES:
            if a[z] and b[z]:
                total += 1
                same += a[z] == b[z]
    ious = [p["iou"] for p in pairs if p["iou"] >= 0.3]
    return {
        "matched": len(ious),
        "mean_iou": round(float(np.mean(ious)), 3) if ious else 0.0,
        "zone_same_shade": f"{same}/{total}",
    }


def panel(rgb: np.ndarray, columns: list[tuple[str, list[ToothMask]]], out: Path) -> None:
    import cv2

    tiles = []
    for label, teeth in [("input", [])] + columns:
        tile = render_instance_overlay(rgb, teeth) if teeth else rgb.copy()
        tile = cv2.cvtColor(tile, cv2.COLOR_RGB2BGR)
        cv2.putText(tile, label, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 0), 4)
        cv2.putText(tile, label, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 2)
        tiles.append(tile)
    cv2.imwrite(str(out), np.vstack(tiles))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", type=Path)
    ap.add_argument("--models", default="", help="comma list, e.g. gpt-6,gpt-5.4-mini")
    ap.add_argument("--effort", default=None, help="reasoning_effort to pass (optional)")
    ap.add_argument("-o", "--out", type=Path, default=BACKEND_ROOT / "debug" / "gpt_eval")
    args = ap.parse_args()
    models = [m.strip() for m in args.models.split(",") if m.strip()]
    args.out.mkdir(parents=True, exist_ok=True)

    photos = sorted(
        p for p in args.folder.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".heic"}
    )
    rows = []
    for photo in photos:
        rgb = _maybe_downscale_rgb(_load_rgb(photo))  # same size the app segments
        h, w = rgb.shape[:2]
        meta: dict = {}
        t0 = time.perf_counter()
        kaist = [t for t in detect_teeth(rgb, backend="kaist", meta_out=meta) if not t.rejected]
        kaist_ms = (time.perf_counter() - t0) * 1000
        used = meta.get("segment_backend", "?")
        rows.append({"photo": photo.name, "model": used, "teeth": len(kaist), "ms": round(kaist_ms)})
        columns = [(f"{used} ({len(kaist)} teeth)", kaist)]

        for model in models:
            row = {"photo": photo.name, "model": model}
            try:
                reply, ms, usage = ask_model(rgb, model, args.effort)
            except Exception as exc:  # report and move on — one bad call shouldn't kill the run
                rows.append({**row, "error": str(exc)[:120]})
                columns.append((f"{model}: ERROR", []))
                continue
            (args.out / f"{photo.stem}_{model}.json").write_text(json.dumps(reply, indent=1))
            teeth = [t for t in polygons_to_teeth(reply, h, w) if not t.rejected]
            row.update(
                teeth=len(teeth),
                ms=round(ms),
                tokens_in=usage.get("prompt_tokens"),
                tokens_out=usage.get("completion_tokens"),
                **compare(rgb, kaist, teeth),
            )
            rows.append(row)
            columns.append((f"{model} ({len(teeth)} teeth)", teeth))

        panel(rgb, columns, args.out / f"{photo.stem}_panel.png")
        for r in rows[-(1 + len(models)):]:
            print(r)

    keys = list(dict.fromkeys(k for r in rows for k in r))
    with open(args.out / "summary.csv", "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=keys)
        writer.writeheader()
        writer.writerows(rows)
    print(f"\nWrote panels + summary.csv to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

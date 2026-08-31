#!/usr/bin/env python3
"""Check whether a Roboflow model_id is reachable with your API key.

Usage:
  cd backend
  export ROBOFLOW_API_KEY=...
  python scripts/roboflow_check_model.py
  python scripts/roboflow_check_model.py plak---projectdens-7p9sm/16
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))


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


def main(argv: list[str] | None = None) -> int:
    _load_env()
    parser = argparse.ArgumentParser(description="Verify Roboflow model_id for inference")
    parser.add_argument(
        "model_id",
        nargs="?",
        default=os.environ.get(
            "SHADE_SEGMENT_ROBOFLOW_MODEL_ID", "plak---projectdens-7p9sm/16"
        ),
    )
    args = parser.parse_args(argv)

    key = os.environ.get("ROBOFLOW_API_KEY", "").strip()
    if not key:
        print("ERROR: set ROBOFLOW_API_KEY in backend/.env", file=sys.stderr)
        return 1

    from app.ai.shade_segment_rfdetr import _normalize_model_id

    mid = _normalize_model_id(args.model_id)
    print(f"model_id (normalized): {mid}")

    try:
        from inference_sdk import InferenceHTTPClient, InferenceConfiguration
    except ImportError:
        print("ERROR: pip install inference-sdk", file=sys.stderr)
        return 1

    import numpy as np

    client = InferenceHTTPClient(
        api_url=os.environ.get(
            "SHADE_SEGMENT_INFERENCE_API_URL", "https://serverless.roboflow.com"
        ),
        api_key=key,
    ).configure(InferenceConfiguration(api_key_transport="header"))

    img = np.zeros((256, 256, 3), dtype=np.uint8)
    img[60:196, 60:196] = 210

    try:
        result = client.infer(img, model_id=mid)
        if isinstance(result, list):
            result = result[0] if result else {}
        preds = result.get("predictions", []) if isinstance(result, dict) else []
        # Semantic seg may return a dict (class → mask); instance seg returns a list.
        if isinstance(preds, dict):
            print(f"OK — inference works. classes={len(preds)}: {list(preds.keys())[:8]}")
        elif isinstance(preds, list):
            print(f"OK — inference works. predictions={len(preds)}")
            for p in preds[:5]:
                if isinstance(p, dict):
                    print(f"  class={p.get('class')!r} conf={p.get('confidence')}")
        else:
            print(f"OK — inference works. predictions type={type(preds).__name__}")
        return 0
    except Exception as exc:
        msg = str(exc)
        print(f"FAIL — {msg[:400]}")
        if "404" in msg or "not found" in msg.lower():
            print(
                "\nThis usually means the dataset version exists but no model is "
                "trained/deployed for your API key.\n"
                "Fix: Roboflow Universe → open PLAK → Fork to your workspace → "
                "Train → Deploy → use YOUR project slug/version as model_id.\n"
                "Example after fork: mahvish-hasan/plak-teeth/1 → model_id plak-teeth/1"
            )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

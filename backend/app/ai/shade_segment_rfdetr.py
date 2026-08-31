"""Tooth instance segmentation via Roboflow Inference + PLAK (RF-DETR ecosystem).

Uses the projectDens PLAK Universe model for per-tooth masks — no local training
required. Weights are cached on first inference; patient images stay on your server
when using in-process inference or a self-hosted Inference Server.

Fine-tune later (10–15 clinic images in Roboflow) by pointing
SHADE_SEGMENT_ROBOFLOW_MODEL_ID at your workspace project/version.

# ASSUMPTION: Default model is YOLO26 *semantic* (class mask), not instance-seg.
#   Roboflow Test tab paints the tooth-class PNG; API has no per-tooth polygons.
#   We instance-split via CC + fidelity-preserving watershed on wide arches
#   (union of instances == original tooth class mask — no carved valleys).
#   Perfect contact separation needs an instance-seg retrain.
# ASSUMPTION: inference_sdk encodes numpy as OpenCV BGR JPEG — always convert
#   from our RGB arrays before infer() (Roboflow UI uploads JPEG correctly).
# ASSUMPTION: PLAK classes include tooth + plaque — only tooth masks are kept.
# ASSUMPTION: Frontal smile photos; zone split runs downstream in shade_zones.py.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from app.ai.shade_segment import ToothMask, _sanity_check_instances, mask_confidence

logger = logging.getLogger(__name__)

# Universe PLAK v16 (semantic segmentation — tooth + plaque classes)
# https://universe.roboflow.com/projectdens/plak---projectdens-7p9sm
DEFAULT_MODEL_ID = (
    "mahvish-hasan/plak---projectdens-7p9sm-atp73-1-yolo26s-sem-t1"
)

# Roboflow Serverless API (dev). For GDPR production use self-hosted Inference Server.
DEFAULT_INFERENCE_API_URL = "https://serverless.roboflow.com"

_MAX_TEETH = 12
_MIN_MASK_PIXELS = 40
_MIN_COMPONENT_PIXELS = 25
_DEFAULT_CONF = 0.25

# Keep tooth crowns only (PLAK also detects plaque / ty alias).
_TOOTH_CLASS_NAMES = frozenset(
    {
        "tooth",
        "teeth",
        "tooth-crown",
        "crown",
        "ty",
    }
)
_SKIP_CLASS_NAMES = frozenset({"plaque", "gingiva", "gum", "background", "bg"})


def _is_tooth_class(name: str) -> bool:
    n = (name or "").strip().lower()
    if not n:
        return False
    if n in _TOOTH_CLASS_NAMES:
        return True
    return n.startswith("tooth")


@dataclass
class RfdetrSegmentStatus:
    available: bool
    model_id: str
    api_key_set: bool
    inference_api_url: str | None
    import_error: str | None = None


_model_cache: dict[str, Any] = {}


def _api_key() -> str:
    from app.core.config import settings

    return (
        (settings.shade_segment_roboflow_api_key or "").strip()
        or (settings.roboflow_api_key or "").strip()
        or os.environ.get("ROBOFLOW_API_KEY", "").strip()
    )


def _normalize_model_id(raw: str) -> str:
    """Roboflow Inference expects `project-slug/version` (no workspace prefix)."""
    mid = raw.strip().strip("/")
    if not mid:
        return DEFAULT_MODEL_ID
    parts = mid.split("/")
    if len(parts) >= 3:
        # workspace/project/version → project/version
        return f"{parts[-2]}/{parts[-1]}"
    if len(parts) == 2:
        return mid
    return DEFAULT_MODEL_ID


def _model_id() -> str:
    from app.core.config import settings

    raw = (settings.shade_segment_roboflow_model_id or DEFAULT_MODEL_ID).strip()
    return _normalize_model_id(raw)


def _inference_api_url() -> str:
    from app.core.config import settings

    raw = (settings.shade_segment_inference_api_url or "").strip()
    return raw or DEFAULT_INFERENCE_API_URL


def _optional_import_error() -> str | None:
    try:
        from inference_sdk import InferenceHTTPClient  # noqa: F401
    except ImportError:
        try:
            import inference  # noqa: F401
        except ImportError as exc:
            return str(exc)
    return None


def rfdetr_segment_status() -> RfdetrSegmentStatus:
    return RfdetrSegmentStatus(
        available=bool(_api_key()) and _optional_import_error() is None,
        model_id=_model_id(),
        api_key_set=bool(_api_key()),
        inference_api_url=_inference_api_url(),
        import_error=_optional_import_error(),
    )


def rfdetr_available() -> bool:
    return rfdetr_segment_status().available


def clear_rfdetr_cache() -> None:
    _model_cache.clear()


def _mask_from_polygon(points: list[Any], h: int, w: int) -> np.ndarray | None:
    import cv2

    if not points:
        return None
    pts: list[list[float]] = []
    for p in points:
        if isinstance(p, dict):
            pts.append([float(p.get("x", 0)), float(p.get("y", 0))])
        elif isinstance(p, (list, tuple)) and len(p) >= 2:
            pts.append([float(p[0]), float(p[1])])
    if len(pts) < 3:
        return None
    arr = np.array(pts, dtype=np.float32)
    arr[:, 0] = np.clip(arr[:, 0], 0, w - 1)
    arr[:, 1] = np.clip(arr[:, 1], 0, h - 1)
    m = np.zeros((h, w), dtype=np.uint8)
    cv2.fillPoly(m, [arr.astype(np.int32)], 1)
    return m.astype(bool) if int(m.sum()) >= _MIN_MASK_PIXELS else None


def _mask_from_bbox(pred: dict[str, Any], h: int, w: int) -> np.ndarray | None:
    """Fallback when segmentation points are missing."""
    try:
        cx = float(pred["x"])
        cy = float(pred["y"])
        bw = float(pred["width"])
        bh = float(pred["height"])
    except (KeyError, TypeError, ValueError):
        return None
    x0 = int(max(0, cx - bw / 2))
    y0 = int(max(0, cy - bh / 2))
    x1 = int(min(w, cx + bw / 2))
    y1 = int(min(h, cy + bh / 2))
    if x1 <= x0 + 2 or y1 <= y0 + 2:
        return None
    m = np.zeros((h, w), dtype=bool)
    m[y0:y1, x0:x1] = True
    return m if int(m.sum()) >= _MIN_MASK_PIXELS else None


def _class_name(pred: dict[str, Any]) -> str:
    for key in ("class", "class_name", "label"):
        val = pred.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip().lower()
    return ""


def _keep_prediction(pred: dict[str, Any]) -> bool:
    name = _class_name(pred)
    if name in _SKIP_CLASS_NAMES:
        return False
    if not name:
        return True
    if _is_tooth_class(name):
        return True
    return name not in _SKIP_CLASS_NAMES


def _prediction_to_mask(pred: dict[str, Any], h: int, w: int) -> np.ndarray | None:
    points = pred.get("points")
    if points:
        m = _mask_from_polygon(list(points), h, w)
        if m is not None:
            return m
    seg = pred.get("segmentation")
    if isinstance(seg, list) and seg:
        m = _mask_from_polygon(seg, h, w)
        if m is not None:
            return m
    for key in ("segmentation_mask", "mask"):
        val = pred.get(key)
        if isinstance(val, str) and len(val) > 32:
            arr = _mask_from_base64_png(val, h, w)
            if arr is not None:
                return arr > 0
    return _mask_from_bbox(pred, h, w)


def _mask_from_base64_png(b64: str, h: int, w: int) -> np.ndarray | None:
    """Decode Roboflow semantic segmentation_mask (base64 PNG)."""
    import base64
    import io

    from PIL import Image

    try:
        raw = base64.b64decode(b64)
        img = Image.open(io.BytesIO(raw))
        arr = np.asarray(img)
        if arr.ndim == 3:
            arr = arr[:, :, 0]
        if h > 0 and w > 0 and arr.shape[:2] != (h, w):
            import cv2

            arr = cv2.resize(arr, (w, h), interpolation=cv2.INTER_NEAREST)
        return arr
    except Exception:
        return None


def _decode_rle_mask(pred: dict[str, Any], h: int, w: int) -> np.ndarray | None:
    """Decode COCO RLE from semantic segmentation predictions."""
    rle = pred.get("rle_mask")
    if not isinstance(rle, dict):
        return None
    try:
        import pycocotools.mask as mask_utils

        decoded = mask_utils.decode(rle)
        if decoded.ndim == 3:
            decoded = decoded[:, :, 0]
        if decoded.shape[:2] != (h, w):
            import cv2

            decoded = cv2.resize(
                decoded.astype(np.uint8),
                (w, h),
                interpolation=cv2.INTER_NEAREST,
            )
        return decoded.astype(bool)
    except Exception:
        logger.debug("RLE decode failed for prediction class=%s", pred.get("class"))
        return None


def _connected_components(mask: np.ndarray, *, min_pixels: int | None = None) -> list[np.ndarray]:
    """Split a binary mask into 8-connected components."""
    import cv2

    floor = _MIN_COMPONENT_PIXELS if min_pixels is None else min_pixels
    u8 = mask.astype(np.uint8)
    n, labels = cv2.connectedComponents(u8, connectivity=8)
    out: list[np.ndarray] = []
    for label in range(1, n):
        m = labels == label
        if int(m.sum()) >= floor:
            out.append(m)
    return out


def _arch_seed_xs(ridge: np.ndarray, active: np.ndarray, n_est: int, tooth_w: float) -> list[int]:
    """Place one seed x per estimated crown along the DT ridge (peak per slot)."""
    x0, x1 = int(active[0]), int(active[-1])
    win = max(3, int(0.35 * tooth_w))
    bw = int(ridge.shape[0])
    xs: list[int] = []
    for i in range(n_est):
        cx = int(round(x0 + (i + 0.5) * (x1 - x0) / n_est))
        lo, hi = max(0, cx - win), min(bw - 1, cx + win)
        if hi <= lo:
            continue
        xs.append(lo + int(np.argmax(ridge[lo : hi + 1])))
    # Dedupe seeds that collapsed into the same peak.
    dedup: list[int] = []
    min_gap = max(4, int(0.35 * tooth_w))
    for x in sorted(xs):
        if not dedup or x - dedup[-1] >= min_gap:
            dedup.append(x)
    return dedup


def _split_wide_semantic_blob(mask: np.ndarray) -> list[np.ndarray]:
    """Split a merged semantic tooth blob into per-crown instances.

    YOLO26-sem returns one class mask for all teeth (Roboflow Test tab paints
    that class overlay — not per-tooth instances). Touching crowns stay
    8-connected, so we gently separate with marker-controlled watershed on the
    distance transform. Every original tooth pixel is assigned to a seed —
    union(parts) == mask (no carved 3px valleys that destroy Roboflow edges).
    """
    import cv2

    u8 = mask.astype(np.uint8)
    if int(u8.sum()) < _MIN_MASK_PIXELS:
        return []

    ys, xs = np.nonzero(u8)
    if ys.size == 0:
        return []
    ht = int(ys.max() - ys.min() + 1)
    wd = int(xs.max() - xs.min() + 1)
    # Compact single crown — keep as one instance.
    if wd < 1.35 * max(ht, 1) or wd < 24:
        return [mask] if int(mask.sum()) >= _MIN_COMPONENT_PIXELS else []

    dist = cv2.distanceTransform(u8, cv2.DIST_L2, 5)
    peak = float(dist.max())
    if peak < 2.0:
        return [mask]

    ridge = dist.max(axis=0)
    active = np.where(ridge >= 0.20 * peak)[0]
    if active.size < 8:
        return [mask]

    arch_w = int(active[-1] - active[0] + 1)
    tooth_w = float(
        np.clip(0.48 * ht, 0.06 * u8.shape[1], 0.28 * u8.shape[1])
    )
    n_est = int(np.clip(round(arch_w / max(tooth_w, 1.0)), 1, _MAX_TEETH))
    if n_est < 2:
        return [mask]

    seed_xs = _arch_seed_xs(ridge, active, n_est, tooth_w)
    if len(seed_xs) < 2:
        return [mask]

    bh, bw = u8.shape
    # OpenCV watershed: label 1 = sure background; 2.. = seeds; 0 = unknown.
    markers = np.zeros((bh, bw), dtype=np.int32)
    markers[u8 == 0] = 1
    r = max(2, int(0.18 * peak))
    for i, x in enumerate(seed_xs):
        y = int(np.argmax(dist[:, x]))
        if u8[y, x] == 0:
            # Seed fell off mask — snap to nearest tooth pixel in column.
            col = np.flatnonzero(u8[:, x])
            if col.size == 0:
                continue
            y = int(col[len(col) // 2])
        cv2.circle(markers, (x, y), r, i + 2, thickness=-1)
        markers[u8 == 0] = 1

    if int(markers.max()) < 3:
        return [mask]

    # Topography: inverted DT so watershed floods from crown centers outward.
    topo = (peak - dist).astype(np.float32)
    topo = np.clip(topo * (255.0 / max(peak, 1e-3)), 0, 255).astype(np.uint8)
    topo_color = cv2.cvtColor(topo, cv2.COLOR_GRAY2BGR)
    cv2.watershed(topo_color, markers)

    parts: list[np.ndarray] = []
    for label in range(2, int(markers.max()) + 1):
        m = (markers == label) & (u8 > 0)
        if int(m.sum()) >= _MIN_MASK_PIXELS:
            parts.append(m)

    if len(parts) >= 2:
        # Fidelity: OpenCV marks watershed boundaries as -1 — fold those (and any
        # other leftovers) back onto the nearest instance so union == mask.
        reunited = np.zeros_like(mask, dtype=bool)
        for p in parts:
            reunited |= p
        orphan = (u8 > 0) & ~reunited
        if int(orphan.sum()) > 0:
            label_map = np.zeros((bh, bw), dtype=np.int32)
            for i, p in enumerate(parts):
                label_map[p] = i + 1
            ker = np.ones((3, 3), dtype=np.uint8)
            remaining = orphan.copy()
            for _ in range(64):
                if not np.any(remaining):
                    break
                dilated = cv2.dilate(label_map.astype(np.uint8), ker)
                grow = remaining & (dilated > 0)
                if not np.any(grow):
                    cents = [
                        (i, float(np.nonzero(p)[1].mean()))
                        for i, p in enumerate(parts)
                        if int(p.sum()) > 0
                    ]
                    oys, oxs = np.nonzero(remaining)
                    for y, x in zip(oys, oxs):
                        j = min(cents, key=lambda t: abs(t[1] - x))[0]
                        parts[j][y, x] = True
                    break
                labs = dilated[grow]
                label_map[grow] = labs
                for i in range(len(parts)):
                    sel = grow & (dilated == (i + 1))
                    if np.any(sel):
                        parts[i][sel] = True
                remaining = (u8 > 0) & (label_map == 0)
        logger.info(
            "rfdetr semantic split: wide blob %sx%s → %s instances (n_est=%s, fidelity)",
            wd,
            ht,
            len(parts),
            n_est,
        )
        return parts
    return [mask]


def _split_semantic_tooth_union(union: np.ndarray) -> list[np.ndarray]:
    """CC first (drop dust); further split only arch-wide merged components."""
    comps = _connected_components(union)
    if not comps and int(union.sum()) >= _MIN_COMPONENT_PIXELS:
        comps = [union]
    if not comps:
        return []

    # Drop speckles vs the dominant arch blob before inventing instances.
    areas0 = [int(c.sum()) for c in comps]
    big = float(max(areas0))
    comps = [
        c
        for c, a in zip(comps, areas0)
        if a >= max(_MIN_MASK_PIXELS, 0.04 * big)
    ]
    if not comps:
        return []

    out: list[np.ndarray] = []
    for c in comps:
        ys, xs = np.nonzero(c)
        if ys.size == 0:
            continue
        ht = int(ys.max() - ys.min() + 1)
        wd = int(xs.max() - xs.min() + 1)
        if wd >= 1.35 * max(ht, 1) and wd >= 24:
            out.extend(_split_wide_semantic_blob(c))
        elif int(c.sum()) >= _MIN_COMPONENT_PIXELS:
            out.append(c)
    if len(out) <= 1:
        return out[:_MAX_TEETH]
    # Drop dust vs the typical crown in this photo (edge plaque bleed, etc.)
    areas = np.asarray([int(m.sum()) for m in out], dtype=np.float64)
    ref = float(np.median(np.sort(areas)[::-1][: max(1, len(areas) // 2 + 1)]))
    kept = [m for m, a in zip(out, areas) if a >= max(_MIN_MASK_PIXELS, 0.22 * ref)]
    return (kept or out)[:_MAX_TEETH]


def _expand_semantic_bundle(bundle: dict[str, Any]) -> list[dict[str, Any]]:
    """Turn YOLO26-sem {segmentation_mask, class_map, ...} into per-class preds.

    Roboflow Test tab visualizes this class-id PNG (one color per class). We keep
    those class regions intact — instance split happens later without carving
    pixels out of the tooth class mask.

    class_map is typically {"0": "background", "1": "plaque", "2": "tooth", "3": "ty"}.
    """
    mask_b64 = bundle.get("segmentation_mask")
    if not isinstance(mask_b64, str) or len(mask_b64) < 16:
        logger.info("rfdetr semantic: missing/short segmentation_mask")
        return []

    class_map = bundle.get("class_map") or {}
    if not isinstance(class_map, dict):
        class_map = {}

    id_to_name: dict[int, str] = {}
    for k, v in class_map.items():
        ks, vs = str(k).strip().lower(), str(v).strip().lower()
        if ks.isdigit():
            id_to_name[int(ks)] = vs
        elif vs.isdigit():
            id_to_name[int(vs)] = ks

    present = bundle.get("present_class_ids")
    if not isinstance(present, list):
        present = list(id_to_name.keys())

    # Decode at native mask resolution (API usually matches image HxW; if not,
    # _instances_from_predictions NEAREST-resizes class ids — never bilinear).
    arr = _mask_from_base64_png(mask_b64, 0, 0)
    if arr is None:
        logger.info("rfdetr semantic: failed to decode segmentation_mask")
        return []

    conf_arr: np.ndarray | None = None
    conf_b64 = bundle.get("confidence_mask")
    if isinstance(conf_b64, str) and len(conf_b64) > 16:
        conf_arr = _mask_from_base64_png(conf_b64, 0, 0)
        if conf_arr is not None and conf_arr.shape[:2] != arr.shape[:2]:
            import cv2

            conf_arr = cv2.resize(
                conf_arr.astype(np.uint8),
                (arr.shape[1], arr.shape[0]),
                interpolation=cv2.INTER_LINEAR,
            )

    # Prefer ids that actually appear in the mask (present_class_ids can be stale)
    unique_ids = {int(x) for x in np.unique(arr)}
    candidate_ids = set()
    for cid in present:
        try:
            candidate_ids.add(int(cid))
        except (TypeError, ValueError):
            continue
    candidate_ids |= unique_ids

    out: list[dict[str, Any]] = []
    for cid_i in sorted(candidate_ids):
        name = id_to_name.get(cid_i, f"class_{cid_i}")
        if name in _SKIP_CLASS_NAMES:
            continue
        m = arr == cid_i
        pix = int(m.sum())
        if pix < _MIN_COMPONENT_PIXELS:
            continue
        conf = 0.7
        if conf_arr is not None and pix > 0:
            # Roboflow confidence_mask is 0–255 per-pixel class confidence.
            conf = float(
                np.clip(conf_arr[m].astype(np.float64).mean() / 255.0, 0.05, 0.99)
            )
        out.append({"class": name, "confidence": conf, "_mask": m})

    if not out and int((arr > 0).sum()) >= _MIN_COMPONENT_PIXELS:
        out.append({"class": "tooth", "confidence": 0.55, "_mask": arr > 0})

    logger.info(
        "rfdetr semantic class_map=%s present=%s unique=%s kept=%s mask_hw=%s",
        id_to_name,
        present,
        sorted(unique_ids),
        [
            (p["class"], int(p["_mask"].sum()), round(float(p["confidence"]), 3))
            for p in out
        ],
        arr.shape[:2],
    )
    return out


def _predictions_from_result(result: Any) -> list[dict[str, Any]]:
    if result is None:
        return []
    if isinstance(result, list) and result and isinstance(result[0], dict):
        result = result[0]
    if isinstance(result, dict):
        preds = result.get("predictions")
        if isinstance(preds, list):
            return [p for p in preds if isinstance(p, dict)]
        # YOLO26 semantic bundle: {segmentation_mask, class_map, confidence_mask, ...}
        if isinstance(preds, dict) and "segmentation_mask" in preds:
            return _expand_semantic_bundle(preds)
        if isinstance(preds, dict):
            out: list[dict[str, Any]] = []
            skip = {
                "segmentation_mask",
                "class_map",
                "confidence_mask",
                "present_class_ids",
            }
            for class_name, payload in preds.items():
                if class_name in skip:
                    continue
                if isinstance(payload, dict):
                    item = dict(payload)
                    item.setdefault("class", str(class_name))
                    out.append(item)
                elif payload is not None:
                    out.append({"class": str(class_name), "_mask": payload})
            return out
        if result.get("segmentation_mask"):
            return _expand_semantic_bundle(result)
        return []
    if hasattr(result, "predictions"):
        preds = getattr(result, "predictions", None)
        if isinstance(preds, list):
            out = []
            for p in preds:
                if isinstance(p, dict):
                    out.append(p)
                elif hasattr(p, "model_dump"):
                    out.append(p.model_dump())
                elif hasattr(p, "dict"):
                    out.append(p.dict())
            return out
        if isinstance(preds, dict):
            return _predictions_from_result({"predictions": preds})
    try:
        import supervision as sv

        dets = sv.Detections.from_inference(result)
        if len(dets) == 0:
            return []
        preds = []
        for i in range(len(dets)):
            pred: dict[str, Any] = {"confidence": 0.5}
            if dets.confidence is not None:
                pred["confidence"] = float(dets.confidence[i])
            if dets.data is not None and "class_name" in dets.data:
                pred["class"] = str(dets.data["class_name"][i])
            if dets.mask is not None:
                pred["_mask"] = dets.mask[i]
            elif dets.data is not None and "rle_mask" in dets.data:
                pred["rle_mask"] = dets.data["rle_mask"][i]
            preds.append(pred)
        return preds
    except Exception:
        pass
    return []


def _instances_from_predictions(
    predictions: list[dict[str, Any]], h: int, w: int
) -> list[tuple[np.ndarray, float]]:
    """Build per-tooth instances from instance and/or semantic seg predictions."""
    tooth_union = np.zeros((h, w), dtype=bool)
    other_union = np.zeros((h, w), dtype=bool)
    tooth_conf = 0.0
    other_conf = 0.0
    instance_list: list[tuple[np.ndarray, float, float, float]] = []

    for pred in predictions:
        name = _class_name(pred)
        if name in _SKIP_CLASS_NAMES:
            continue
        conf = float(pred.get("confidence") or pred.get("conf") or 0.5)
        m: np.ndarray | None = None
        if "_mask" in pred:
            m = np.asarray(pred["_mask"])
            if m.dtype != bool:
                m = m.astype(bool)
        elif pred.get("rle_mask"):
            m = _decode_rle_mask(pred, h, w)
        elif pred.get("points") or pred.get("segmentation"):
            m = _prediction_to_mask(pred, h, w)
        if m is None or int(m.sum()) < _MIN_COMPONENT_PIXELS:
            continue
        if m.shape[:2] != (h, w):
            import cv2

            m = (
                cv2.resize(m.astype(np.uint8), (w, h), interpolation=cv2.INTER_NEAREST)
                > 0
            )
        # Instance-style polygon → one blob per prediction.
        if pred.get("points") or pred.get("segmentation"):
            if int(m.sum()) >= _MIN_COMPONENT_PIXELS:
                ys, xs = np.nonzero(m)
                instance_list.append((m, conf, float(ys.mean()), float(xs.mean())))
            continue

        if _is_tooth_class(name) or not name:
            tooth_union |= m
            tooth_conf = max(tooth_conf, conf)
        else:
            # Unknown class — only use if tooth class absent
            other_union |= m
            other_conf = max(other_conf, conf)

    union = tooth_union if int(tooth_union.sum()) >= _MIN_COMPONENT_PIXELS else other_union
    conf_use = tooth_conf if int(tooth_union.sum()) >= _MIN_COMPONENT_PIXELS else other_conf
    if int(union.sum()) >= _MIN_COMPONENT_PIXELS:
        # Prefer instance polygons already collected; only expand semantic union
        # when we have no instance-style predictions.
        if not instance_list:
            comps = _split_semantic_tooth_union(union)
            for m in comps:
                ys, xs = np.nonzero(m)
                instance_list.append(
                    (m, conf_use or 0.5, float(ys.mean()), float(xs.mean()))
                )
        else:
            # Semantic leftover alongside instances — rare; skip to avoid doubles.
            pass

    instance_list.sort(key=lambda t: (t[2], t[3]))
    return [(m, conf) for m, conf, _cy, _cx in instance_list[:_MAX_TEETH]]


def _load_model(model_id: str, api_key: str) -> Any:
    if model_id in _model_cache:
        return _model_cache[model_id]
    from inference import get_model

    model = get_model(model_id=model_id, api_key=api_key)
    _model_cache[model_id] = model
    logger.info("Roboflow Inference model loaded: %s", model_id)
    return model


def _infer_inprocess(
    image_rgb: np.ndarray,
    *,
    model_id: str,
    api_key: str,
    conf: float,
) -> Any:
    model = _load_model(model_id, api_key)
    u8 = np.clip(np.asarray(image_rgb), 0, 255).astype(np.uint8)
    out = model.infer(u8, confidence=conf)
    if isinstance(out, list) and out:
        return out[0]
    return out


def _infer_http_client(
    image_rgb: np.ndarray,
    *,
    model_id: str,
    api_key: str,
    api_url: str,
    conf: float,
) -> Any:
    import cv2
    from inference_sdk import InferenceHTTPClient, InferenceConfiguration

    # confidence is set via InferenceConfiguration when supported; newer SDKs
    # reject confidence= as a kwarg on infer().
    try:
        config = InferenceConfiguration(
            api_key_transport="header",
            confidence_threshold=conf,
        )
    except TypeError:
        config = InferenceConfiguration(api_key_transport="header")

    client = InferenceHTTPClient(
        api_url=api_url,
        api_key=api_key,
    ).configure(config)
    # CRITICAL: inference_sdk encodes numpy via OpenCV JPEG (expects BGR).
    # Passing RGB swaps R/B → model sees wrong colors and returns near-empty
    # tooth masks (Roboflow Test tab uploads JPEG and looks perfect).
    u8 = np.clip(np.asarray(image_rgb), 0, 255).astype(np.uint8)
    bgr = cv2.cvtColor(u8, cv2.COLOR_RGB2BGR)
    return client.infer(bgr, model_id=model_id)


def detect_teeth_rfdetr(
    image_rgb: np.ndarray,
    *,
    model_id: str | None = None,
    conf: float | None = None,
) -> list[ToothMask]:
    """Segment teeth with Roboflow PLAK model; returns ToothMask list."""
    from app.core.config import settings

    status = rfdetr_segment_status()
    if not status.available:
        if status.import_error:
            raise ImportError(
                f"Roboflow Inference SDK not installed: {status.import_error}. "
                "Run: pip install -r requirements-ml.txt"
            )
        raise ValueError(
            "ROBOFLOW_API_KEY not set — add to backend/.env (never commit the key)."
        )

    mid = _normalize_model_id((model_id or status.model_id).strip())
    api_key = _api_key()
    conf_val = float(conf if conf is not None else settings.shade_segment_conf or _DEFAULT_CONF)
    h, w = np.asarray(image_rgb).shape[:2]

    api_url = _inference_api_url()
    raw = _infer_http_client(
        image_rgb,
        model_id=mid,
        api_key=api_key,
        api_url=api_url,
        conf=conf_val,
    )

    predictions = _predictions_from_result(raw)
    pairs = _instances_from_predictions(predictions, h, w)
    if not pairs:
        logger.info("rfdetr segment: no tooth instances model=%s", mid)
        return []

    teeth: list[ToothMask] = []
    for idx, (m, c) in enumerate(pairs):
        teeth.append(
            ToothMask(
                tooth_index=idx,
                mask=m,
                confidence=round(
                    float(np.clip(0.55 * c + 0.45 * mask_confidence(m, h), 0.0, 0.99)),
                    3,
                ),
                rejected=False,
                reject_reason=None,
            )
        )

    teeth = _sanity_check_instances(teeth)
    accepted = sum(1 for t in teeth if not t.rejected)
    logger.info(
        "rfdetr segment teeth=%s accepted=%s model=%s api=%s",
        len(teeth),
        accepted,
        mid,
        api_url or DEFAULT_INFERENCE_API_URL,
    )
    return teeth

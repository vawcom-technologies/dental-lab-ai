"""Debug visualization for per-tooth instance masks.

Use to visually verify instance separation and boundaries while toggling
SegmentConfig stages — not for production API responses.
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence

import numpy as np

from app.ai.shade_segment import SegmentConfig, ToothMask, detect_teeth

# Distinct instance colors (RGB) — cycle if > len
_PALETTE = [
    (0, 200, 255),
    (255, 80, 80),
    (80, 220, 120),
    (255, 180, 40),
    (180, 100, 255),
    (40, 200, 200),
    (255, 100, 180),
    (160, 220, 40),
    (100, 140, 255),
    (255, 140, 100),
    (120, 255, 200),
    (220, 220, 80),
]


def render_instance_overlay(
    image_rgb: np.ndarray,
    teeth: Sequence[ToothMask],
    *,
    alpha: float = 0.45,
    draw_rejected: bool = True,
    draw_outlines: bool = True,
    draw_labels: bool = True,
) -> np.ndarray:
    """Overlay each tooth instance in a distinct color on the photo."""
    import cv2

    base = np.clip(np.asarray(image_rgb), 0, 255).astype(np.uint8).copy()
    if base.ndim != 3:
        raise ValueError("image_rgb must be HxWx3")
    overlay = base.copy()

    for t in teeth:
        if t.rejected and not draw_rejected:
            continue
        color = _PALETTE[t.tooth_index % len(_PALETTE)]
        if t.rejected:
            # Desaturate rejected so they're visually distinct
            color = tuple(int(c * 0.45) for c in color)
        mask = t.mask.astype(bool)
        if mask.shape[:2] != base.shape[:2]:
            continue
        overlay[mask] = (
            (1.0 - alpha) * overlay[mask].astype(np.float64)
            + alpha * np.asarray(color, dtype=np.float64)
        ).astype(np.uint8)

        if draw_outlines:
            u8 = (mask.astype(np.uint8)) * 255
            contours, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            cv2.drawContours(overlay, contours, -1, color, 2)

        if draw_labels and np.any(mask):
            ys, xs = np.nonzero(mask)
            cx, cy = int(xs.mean()), int(max(0, ys.min() - 8))
            label = f"T{t.tooth_index + 1}"
            if t.rejected:
                label += f"✗{t.reject_reason or '?'}"
            cv2.putText(
                overlay,
                label,
                (cx - 12, cy),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.45,
                (255, 255, 255),
                2,
                cv2.LINE_AA,
            )
            cv2.putText(
                overlay,
                label,
                (cx - 12, cy),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.45,
                color,
                1,
                cv2.LINE_AA,
            )

    return overlay


def save_debug_panel(
    image_rgb: np.ndarray,
    out_path: str | Path,
    *,
    config: SegmentConfig | None = None,
    also_compare_no_watershed: bool = True,
) -> Path:
    """Run detect_teeth and write a side-by-side debug PNG.

    Left: input. Middle: default/config overlay. Right (optional): watershed off.
    """
    import cv2

    path = Path(out_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    teeth = detect_teeth(image_rgb, config=config)
    mid = render_instance_overlay(image_rgb, teeth)

    panels = [np.asarray(image_rgb, dtype=np.uint8), mid]
    if also_compare_no_watershed:
        cfg_off = SegmentConfig(watershed_split=False, valley_split=True)
        teeth_off = detect_teeth(image_rgb, config=cfg_off)
        panels.append(render_instance_overlay(image_rgb, teeth_off))

    # Match heights
    h = max(p.shape[0] for p in panels)
    padded = []
    for p in panels:
        if p.shape[0] < h:
            pad = np.zeros((h - p.shape[0], p.shape[1], 3), dtype=np.uint8)
            p = np.vstack([p, pad])
        padded.append(p)
    panel = np.hstack(padded)
    # OpenCV writes BGR
    bgr = cv2.cvtColor(panel, cv2.COLOR_RGB2BGR)
    cv2.imwrite(str(path), bgr)
    return path

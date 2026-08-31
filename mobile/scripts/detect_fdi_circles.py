#!/usr/bin/env python3
"""Find white FDI number badges (red digits) on the chart."""
from __future__ import annotations

import cv2
import numpy as np
from pathlib import Path

img = cv2.imread("assets/clinical/fdi_chart.png")
h, w = img.shape[:2]
hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
bgr = img

# Red digit pixels
m1 = cv2.inRange(hsv, (0, 70, 70), (12, 255, 255))
m2 = cv2.inRange(hsv, (168, 70, 70), (180, 255, 255))
red = cv2.bitwise_or(m1, m2)
k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
red = cv2.dilate(red, k, iterations=2)

n, labels, stats, cents = cv2.connectedComponentsWithStats(red, 8)
badges = []
for i in range(1, n):
    area = int(stats[i, cv2.CC_STAT_AREA])
    if area < 40 or area > 900:
        continue
    x = float(cents[i][0])
    y = float(cents[i][1])
    bw = int(stats[i, cv2.CC_STAT_WIDTH])
    bh = int(stats[i, cv2.CC_STAT_HEIGHT])
    if bw > 55 or bh > 55:
        continue
    # Must sit on a bright badge
    xi, yi = int(x), int(y)
    if yi < 0 or yi >= h or xi < 0 or xi >= w:
        continue
    if float(bgr[yi, xi].mean()) < 160:
        continue
    # Estimate radius from component bbox
    r = 0.55 * max(bw, bh) + 6
    badges.append((x / w, y / h, r / w, xi, yi, int(r), area))

badges.sort(key=lambda t: (t[1], t[0]))
print("red badges", len(badges))
vis = img.copy()
for b in badges:
    cv2.circle(vis, (b[3], b[4]), b[5], (0, 255, 0), 2)

# Split upper/lower by large y gap
ys = sorted(b[1] for b in badges)
best_gap, split_y = 0.0, 0.5
for i in range(len(ys) - 1):
    g = ys[i + 1] - ys[i]
    if g > best_gap:
        best_gap = g
        split_y = 0.5 * (ys[i] + ys[i + 1])
upper = sorted([b for b in badges if b[1] < split_y], key=lambda t: t[0])
lower = sorted([b for b in badges if b[1] >= split_y], key=lambda t: t[0])
print("split", round(split_y, 3), "upper", len(upper), "lower", len(lower))

upper_fdi = list(range(18, 10, -1)) + list(range(21, 29))
lower_fdi = list(range(48, 40, -1)) + list(range(31, 39))


def assign(row, fdis, label):
    if len(row) != len(fdis):
        print(f"WARN {label} count {len(row)} expected {len(fdis)}")
        for i, b in enumerate(row):
            print(f"  {label}[{i}] nx={b[0]:.4f} ny={b[1]:.4f}")
        return {}
    return {f: b for f, b in zip(fdis, row)}


umap = assign(upper, upper_fdi, "U")
lmap = assign(lower, lower_fdi, "L")
mapping = {**umap, **lmap}

for fdi, b in sorted(mapping.items()):
    cv2.putText(
        vis,
        str(fdi),
        (b[3] - 12, b[4] - b[5] - 4),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.45,
        (255, 0, 0),
        1,
        cv2.LINE_AA,
    )

cv2.imwrite("/tmp/fdi_badges_debug.png", vis)
print("wrote /tmp/fdi_badges_debug.png")

print("\n// selectable (x1–x5)")
for fdi in sorted(f for f in mapping if f % 10 <= 5):
    b = mapping[fdi]
    print(f"  {fdi}: Offset({b[0]:.4f}, {b[1]:.4f}), // r≈{b[2]:.4f}")

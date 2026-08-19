"""Per-tooth enamel instance masks — adaptive classic-CV pipeline (no ML).

Current (keep — proven on smile photos):
  Lab-a* enamel on ORIGINAL colors (not CLAHE — CLAHE before mask caused cheek FPs)
  → ROI → dual-arch horizontal cut (open mouth) → DT / opening / arch-spacing
    markers + watershed or luminance cuts
  → GrabCut per tooth (sibling exclusion) → morph cleanup
  → tall-merge split → arch-row(s) + contact reconcile → relative size / sanity

Additive classical extensions (toggleable; do not replace the above):
  • DT 2D local-maxima markers (better seeds for touching crowns)
  • Polynomial arch-curve prior (reject off-arch gum/artifacts)
  • Optional CLAHE only for watershed topography / gray cues (not Lab mask)
  • Optional active-contour snap after GrabCut (off by default)

# ASSUMPTION: No ML model — color + morphology only.
# ASSUMPTION: Tooth IDs are left→right in the image (not FDI).
"""

from __future__ import annotations

from dataclasses import dataclass, replace

import numpy as np

_MAX_TEETH = 12
_ANTERIOR_MAX_PER_ROW = 6  # 2 centrals + up to 2 per side
_ANTERIOR_SIDE = 2
_VALLEY_DEPTH_RATIO = 0.52
_MIN_REL_AREA = 0.35
_MIN_REL_HEIGHT = 0.40
# Watershed: markers from DT ridge peaks; min sep scales with ROI.
_WATERSHED_MIN_PEAK_FRAC = 0.28


@dataclass(frozen=True)
class SegmentConfig:
    """Toggle each stage independently for A/B debugging."""

    preprocess: bool = True  # CLAHE for gray/topo only — never Lab enamel input
    watershed_split: bool = True
    valley_split: bool = False
    dual_arch_split: bool = True  # sever upper/lower at open-mouth gap
    dt_local_max_markers: bool = True  # additive: 2D DT peaks as watershed seeds
    boundary_snap: bool = True
    grabcut_refine: bool = True  # keep — best boundary stage so far
    active_contour_refine: bool = False  # optional post-GrabCut snap (skimage)
    morph_cleanup: bool = True
    merge_halves: bool = True
    reconcile_contacts: bool = True
    arch_curve_prior: bool = True  # additive: poly arch reject off-curve blobs
    relative_size_filter: bool = True
    sanity_reject: bool = True


DEFAULT_CONFIG = SegmentConfig()


@dataclass(frozen=True)
class ToothMask:
    tooth_index: int
    mask: np.ndarray  # bool, full image HxW
    confidence: float
    rejected: bool
    reject_reason: str | None = None


def detect_teeth(
    image_rgb: np.ndarray,
    config: SegmentConfig | None = None,
) -> list[ToothMask]:
    """Detect tooth instances — ROI and thresholds derived from the image."""
    import cv2

    cfg = config or DEFAULT_CONFIG
    if image_rgb.ndim != 3 or image_rgb.shape[2] != 3:
        raise ValueError("image_rgb must be HxWx3")

    arr = np.asarray(image_rgb, dtype=np.float64)
    h, w, _ = arr.shape

    # CRITICAL: enamel mask must run on ORIGINAL colors. CLAHE inflates cheek
    # skin into false enamel (seen on real smile photos).
    enamel_full = _adaptive_enamel_mask(arr)
    if int(enamel_full.sum()) < 80:
        return []

    roi = _dental_roi_from_enamel(enamel_full)
    if roi is None:
        return []
    y0, y1, x0, x1 = roi
    band_raw = arr[y0:y1, x0:x1]
    enamel = enamel_full[y0:y1, x0:x1]
    bh, bw = enamel.shape
    if bh < 12 or bw < 12:
        return []

    u8 = (enamel.astype(np.uint8)) * 255
    open_k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    u8 = cv2.morphologyEx(u8, cv2.MORPH_OPEN, open_k, iterations=1)

    # CLAHE gray for watershed topography / luminance cuts only (not Lab mask).
    gray_roi = None
    if cfg.preprocess:
        gray_roi = _clahe_gray(band_raw)
    lum = (
        gray_roi.astype(np.float64)
        if gray_roi is not None
        else _luma_rgb(band_raw)
    )

    if cfg.valley_split:
        u8 = _split_arch_by_deep_valleys(u8)

    # Open-mouth / both arches: cut the dark horizontal gap so upper and lower
    # crowns never share one watershed instance (T5 tall merge in clinic photos).
    occlusal_gap: tuple[int, int] | None = None
    if cfg.dual_arch_split:
        occlusal_gap = _find_occlusal_gap(u8, luminance=lum)
        if occlusal_gap is not None:
            y_a, y_b = occlusal_gap
            u8 = u8.copy()
            u8[y_a : y_b + 1, :] = 0

    if cfg.watershed_split:
        components = _split_instances_watershed(
            u8,
            luminance=lum,
            use_dt_local_max=cfg.dt_local_max_markers,
        )
    else:
        components = _components_from_binary(u8)

    if not components:
        return []

    # Seed refine → GrabCut (keep) → optional active contour → morph
    seed_list: list[np.ndarray] = []
    for comp in components:
        if int(comp.sum()) < 40:
            continue
        m = _refine_tooth_component(band_raw, comp)
        if cfg.boundary_snap:
            m = _snap_boundary_to_edges(band_raw, m)
        if int(m.sum()) >= 40:
            seed_list.append(m)
    if not seed_list:
        return []

    if cfg.grabcut_refine:
        refined_list = _grabcut_all_teeth(band_raw, seed_list, enamel)
    else:
        refined_list = seed_list

    if cfg.active_contour_refine:
        edge_img = gray_roi if gray_roi is not None else _clahe_gray(band_raw)
        refined_list = [
            m
            for m in (
                _active_contour_refine_one(edge_img, m, enamel) for m in refined_list
            )
            if int(m.sum()) >= 40
        ]

    if cfg.morph_cleanup:
        refined_list = [
            m
            for m in (_morph_cleanup_mask(m) for m in refined_list)
            if int(m.sum()) >= 40
        ]

    if not refined_list:
        return []

    refined_list = _resolve_overlaps(refined_list)
    # GrabCut / morph can regrow across a thin occlusal nick — hard-clip again.
    if occlusal_gap is not None:
        refined_list = _clip_crossing_occlusal(refined_list, occlusal_gap)
    # Safety net: any remaining vertically stacked upper+lower blob → cut.
    refined_list = _split_vertically_merged_components(refined_list, lum)
    refined_list = _filter_to_arch_row(refined_list, band_raw)
    if cfg.arch_curve_prior:
        refined_list = _filter_by_arch_curve(refined_list)

    if cfg.reconcile_contacts:
        refined_list = _reconcile_contacts(refined_list, band_raw)

    if cfg.merge_halves:
        refined_list = _merge_oversegmented_neighbors(refined_list)
    if cfg.relative_size_filter:
        refined_list = _filter_by_relative_size(refined_list)

    refined_list = _resolve_overlaps(refined_list)
    # Shade matching uses the two centrals plus 1–2 teeth on each side.
    # Drop premolars / cheek fragments; do not invent leftover blobs.
    refined_list = _keep_anterior_window(refined_list)
    refined_list = _fill_to_contact_cuts(enamel, refined_list, lum)
    refined_list = _trim_incisal_dark(band_raw, refined_list)
    refined_list = _resolve_overlaps(refined_list)
    # Upper row first (smaller y), then left→right within the row.
    refined_list = sorted(
        refined_list,
        key=lambda m: (
            float(np.nonzero(m)[0].mean()),
            float(np.nonzero(m)[1].mean()),
        ),
    )
    refined_list = refined_list[:_MAX_TEETH]

    out: list[ToothMask] = []
    for idx, refined in enumerate(refined_list):
        full = np.zeros((h, w), dtype=bool)
        full[y0:y1, x0:x1] = refined
        conf = _confidence(refined, bh)
        out.append(
            ToothMask(
                tooth_index=idx,
                mask=full,
                confidence=conf,
                rejected=False,
                reject_reason=None,
            )
        )

    if cfg.sanity_reject:
        out = _sanity_check_instances(out)
    return out


def with_config(**kwargs: bool) -> SegmentConfig:
    """Helper: DEFAULT_CONFIG with selected stage flags overridden."""
    return replace(DEFAULT_CONFIG, **kwargs)


# ---------------------------------------------------------------------------
# 1) Preprocess / shared mask helpers
# ---------------------------------------------------------------------------


def _luma_rgb(band: np.ndarray) -> np.ndarray:
    return 0.299 * band[:, :, 0] + 0.587 * band[:, :, 1] + 0.114 * band[:, :, 2]


def _largest_cc(mask: np.ndarray) -> np.ndarray | None:
    """Largest 8-connected component, or None if empty."""
    import cv2

    u8 = (mask.astype(np.uint8)) * 255
    n, labels, stats, _ = cv2.connectedComponentsWithStats(u8, connectivity=8)
    if n <= 1:
        return None
    best = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return labels == best


def _mask_geom(mask: np.ndarray) -> dict:
    ys, xs = np.nonzero(mask)
    return {
        "mask": mask,
        "x0": int(xs.min()),
        "x1": int(xs.max()),
        "y0": int(ys.min()),
        "y1": int(ys.max()),
        "cx": float(xs.mean()),
        "cy": float(ys.mean()),
        "w": int(xs.max() - xs.min() + 1),
        "h": int(ys.max() - ys.min() + 1),
        "area": int(xs.size),
    }


def _clahe_gray(image_rgb: np.ndarray) -> np.ndarray:
    """CLAHE on luminance only — for watershed cuts / active-contour edges."""
    import cv2

    u8 = np.clip(image_rgb, 0, 255).astype(np.uint8)
    lab = cv2.cvtColor(u8, cv2.COLOR_RGB2LAB)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    return clahe.apply(lab[:, :, 0])


# ---------------------------------------------------------------------------
# 2) Semantic enamel mask
# ---------------------------------------------------------------------------


def _adaptive_enamel_mask(image: np.ndarray) -> np.ndarray:
    """Semantic enamel mask in CIE Lab — rejects pink skin/lips/gingiva.

    Real smile failure mode: RGB luminance + CLAHE treated bright cheek as
    enamel. Lab a* separates them cleanly (enamel a*≈0–8, skin/gum a*≳20).
    """
    import cv2

    u8 = np.clip(image, 0, 255).astype(np.uint8)
    lab = cv2.cvtColor(u8, cv2.COLOR_RGB2LAB).astype(np.float64)
    L = lab[:, :, 0]
    a = lab[:, :, 1] - 128.0
    b = lab[:, :, 2] - 128.0

    useful = L > 40
    if int(useful.sum()) < 200:
        useful = np.ones_like(L, dtype=bool)
    p40 = float(np.percentile(L[useful], 40))
    p60 = float(np.percentile(L[useful], 60))
    p80 = float(np.percentile(L[useful], 80))
    # Bright relative to *this* photo; floor keeps dark rooms from flooding.
    thr = float(np.clip(0.55 * p40 + 0.45 * p60, 95.0, 175.0))
    seed_thr = float(np.clip(max(thr + 8.0, p80 * 0.92), thr + 5.0, 220.0))

    # Enamel: bright, near-neutral a* (not red), mild yellow b* OK.
    # Camera close-ups: lip highlights are bright with mild a* — keep a* tighter.
    body = (
        (L >= thr)
        & (L <= 254)
        & (a < 10.0)
        & (a > -18.0)
        & (b > -8.0)
        & (b < 48.0)
    )
    # Hard ban on pink/red tissue even if bright
    body &= ~((a >= 12.0) | ((a >= 8.0) & (L < seed_thr)))

    seeds = body & (L >= seed_thr)
    if int(seeds.sum()) < 30:
        return body

    dilate_k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    grown = seeds.astype(np.uint8) * 255
    body_u8 = body.astype(np.uint8) * 255
    for _ in range(14):
        nxt = cv2.bitwise_and(cv2.dilate(grown, dilate_k), body_u8)
        if np.array_equal(nxt, grown):
            break
        grown = nxt
    return grown > 0


# ---------------------------------------------------------------------------
# 3) ROI
# ---------------------------------------------------------------------------


def _dental_roi_from_enamel(enamel: np.ndarray) -> tuple[int, int, int, int] | None:
    """Bounding ROI of the main enamel mass, padded — not a fixed % crop."""
    import cv2

    u8 = (enamel.astype(np.uint8)) * 255
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    u8 = cv2.morphologyEx(u8, cv2.MORPH_OPEN, k, iterations=1)
    ys, xs = np.nonzero(u8)
    if ys.size < 80:
        return None

    n, labels, stats, _ = cv2.connectedComponentsWithStats(u8, connectivity=8)
    if n <= 1:
        return None
    areas = [(i, int(stats[i, cv2.CC_STAT_AREA])) for i in range(1, n)]
    areas.sort(key=lambda t: t[1], reverse=True)
    keep = {areas[0][0]}
    for i, a in areas[1:]:
        if a >= 0.25 * areas[0][1]:
            keep.add(i)
    sel = np.isin(labels, list(keep))
    ys, xs = np.nonzero(sel)
    if ys.size < 80:
        return None

    h, w = enamel.shape
    pad_y = max(4, int(0.06 * (ys.max() - ys.min() + 1)))
    pad_x = max(4, int(0.06 * (xs.max() - xs.min() + 1)))
    y0 = max(0, int(ys.min()) - pad_y)
    y1 = min(h, int(ys.max()) + 1 + pad_y)
    x0 = max(0, int(xs.min()) - pad_x)
    x1 = min(w, int(xs.max()) + 1 + pad_x)
    return y0, y1, x0, x1


# ---------------------------------------------------------------------------
# 4) Instance separation
# ---------------------------------------------------------------------------


def _components_from_binary(u8: np.ndarray) -> list[np.ndarray]:
    import cv2

    _n, labels, stats, _ = cv2.connectedComponentsWithStats(u8, connectivity=8)
    out: list[np.ndarray] = []
    for i in range(1, _n):
        if int(stats[i, cv2.CC_STAT_AREA]) < 40:
            continue
        out.append(labels == i)
    return out


def _cut_between_centers(
    binary: np.ndarray,
    cut_score: np.ndarray,
    centers: list[tuple[int, int]],
    *,
    half_width: int,
) -> list[np.ndarray]:
    """Zero vertical seams at luminance/ridge valleys between marker centers."""
    cut_bin = binary.copy()
    for (_i, x_a), (_j, x_b) in zip(centers, centers[1:]):
        if x_b - x_a < 3:
            continue
        seg = cut_score[x_a : x_b + 1]
        cut = x_a + int(np.argmin(seg))
        if half_width <= 0:
            cut_bin[:, cut] = 0
        else:
            cut_bin[:, max(0, cut - half_width) : cut + half_width + 1] = 0
    return _components_from_binary((cut_bin * 255).astype(np.uint8))


def _ridge_peaks_with_prominence(
    ridge: np.ndarray, *, min_sep: int, peak_thr: float, min_prominence: float
) -> list[int]:
    """Local maxima that sit above a real saddle — skips flat-bar plateaus."""
    bw = int(ridge.shape[0])
    raw: list[int] = []
    for x in range(1, bw - 1):
        if ridge[x] < peak_thr:
            continue
        if ridge[x] >= ridge[x - 1] and ridge[x] >= ridge[x + 1]:
            if not raw or x - raw[-1] >= max(2, min_sep // 3):
                raw.append(x)
            elif ridge[x] > ridge[raw[-1]]:
                raw[-1] = x
    if len(raw) <= 1:
        return raw

    kept: list[int] = [raw[0]]
    for x in raw[1:]:
        left = kept[-1]
        valley = float(ridge[left : x + 1].min())
        prom = min(float(ridge[left]), float(ridge[x])) - valley
        if prom < min_prominence:
            if ridge[x] > ridge[kept[-1]]:
                kept[-1] = x
            continue
        if x - kept[-1] < min_sep:
            if ridge[x] > ridge[kept[-1]]:
                kept[-1] = x
            continue
        kept.append(x)
    return kept


def _markers_from_opening(binary: np.ndarray, est_tooth_w: int) -> np.ndarray | None:
    """Separate thin contact necks via opening, then label sure-FG markers.

    Uses a flat horizontal rectangle kernel so tall, narrow interdental necks
    are severed even when vertical ellipse opening would leave them connected.
    """
    import cv2

    if est_tooth_w < 8:
        return None
    kx = max(5, int(0.32 * est_tooth_w) | 1)
    ky = 3
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (kx, ky))
    opened = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel, iterations=1)
    if int(opened.sum()) < 40:
        return None
    n, labels = cv2.connectedComponents(opened)
    if n <= 2:
        return None
    markers = np.zeros_like(labels, dtype=np.int32)
    next_id = 1
    for i in range(1, n):
        m = labels == i
        if int(m.sum()) < 30:
            continue
        markers[m] = next_id
        next_id += 1
    if next_id <= 2:
        return None
    return markers


def _markers_from_arch_spacing(dist: np.ndarray, binary: np.ndarray) -> np.ndarray | None:
    """Place markers by estimated tooth count along the DT ridge.

    When enamel is a continuous bar (touching crowns, no neck in the mask),
    opening and prominence peaks fail. Tooth count ≈ arch_width / (k * arch_height)
    adapts to zoom/framing without hardcoded pixel sizes.

    Skips compact (single-tooth) blobs where width ≲ height.
    """
    import cv2

    ridge = dist.max(axis=0)
    peak_h = float(ridge.max())
    if peak_h < 2.0:
        return None
    active = np.where(ridge >= 0.20 * peak_h)[0]
    if active.size < 8:
        return None
    arch_w = int(active[-1] - active[0] + 1)
    rows = np.where(binary.any(axis=1))[0]
    if rows.size < 4:
        return None
    arch_h = int(rows[-1] - rows[0] + 1)
    # Single crown is roughly square/tall — don't invent multiple markers.
    if arch_w < 1.45 * arch_h:
        return None

    # Anterior crowns are typically a bit taller than wide. Prefer slightly
    # finer estimate so continuous smiles don't under-count (0.60 → ~5 on a
    # 8-tooth smile; 0.48 → ~6–7).
    tooth_w = float(np.clip(0.48 * arch_h, 0.06 * binary.shape[1], 0.26 * binary.shape[1]))
    n_est = int(round(arch_w / max(tooth_w, 1.0)))

    # If the DT ridge has clear prominent peaks, trust that count when higher.
    min_sep = max(6, int(0.55 * tooth_w))
    min_prom = max(1.2, 0.08 * peak_h)
    ridge_peaks = _ridge_peaks_with_prominence(
        ridge,
        min_sep=min_sep,
        peak_thr=_WATERSHED_MIN_PEAK_FRAC * peak_h,
        min_prominence=min_prom,
    )
    if len(ridge_peaks) >= 3 and len(ridge_peaks) <= n_est + 1:
        n_est = max(n_est, len(ridge_peaks))

    n_est = int(np.clip(n_est, 1, _MAX_TEETH))
    if n_est < 2:
        return None

    x0, x1 = int(active[0]), int(active[-1])
    centers = [
        int(round(x0 + (i + 0.5) * (x1 - x0) / n_est)) for i in range(n_est)
    ]
    win = max(3, int(0.35 * tooth_w))
    bh, bw = binary.shape
    markers = np.zeros((bh, bw), dtype=np.int32)
    for i, cx in enumerate(centers, start=1):
        lo, hi = max(0, cx - win), min(bw - 1, cx + win)
        if hi <= lo:
            continue
        x = lo + int(np.argmax(ridge[lo : hi + 1]))
        y = int(np.argmax(dist[:, x]))
        r = max(2, int(0.22 * peak_h))
        cv2.circle(markers, (x, y), r, i, thickness=-1)
    markers[binary == 0] = 0
    if int(markers.max()) < 2:
        return None
    return markers


def _markers_from_ridge(dist: np.ndarray, binary: np.ndarray) -> np.ndarray | None:
    """Fallback markers from DT ridge peaks with prominence filtering."""
    import cv2

    ridge = np.convolve(dist.max(axis=0), np.ones(5) / 5.0, mode="same")
    bh, bw = binary.shape
    peak_h = float(ridge.max())
    if peak_h < 2.0:
        return None
    thr = _WATERSHED_MIN_PEAK_FRAC * peak_h
    min_sep = max(8, int(0.045 * bw), int(0.50 * peak_h))
    min_prom = max(1.25, 0.08 * peak_h)
    peaks = _ridge_peaks_with_prominence(
        ridge, min_sep=min_sep, peak_thr=thr, min_prominence=min_prom
    )
    if len(peaks) < 2:
        return None
    markers = np.zeros((bh, bw), dtype=np.int32)
    for i, x in enumerate(peaks, start=1):
        y = int(np.argmax(dist[:, x]))
        r = max(2, int(0.28 * float(ridge[x])))
        cv2.circle(markers, (x, y), r, i, thickness=-1)
    markers[binary == 0] = 0
    return markers if int((markers > 0).sum()) > 0 else None


def _markers_from_dt_local_maxima(dist: np.ndarray, binary: np.ndarray) -> np.ndarray | None:
    """2D local maxima of the distance transform → one seed per tooth center.

    This is the classic marker-controlled watershed recipe: peaks sit inside
    each crown; contact necks are valleys. Separation adapts to crooked teeth
    better than pure column spacing when DT peaks are distinct.
    """
    import cv2

    peak_h = float(dist.max())
    if peak_h < 2.0:
        return None
    # Min distance between peaks ~ tooth half-width from DT
    min_sep = max(7, int(0.55 * peak_h))
    k = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (max(3, min_sep | 1), max(3, min_sep | 1))
    )
    dilated = cv2.dilate(dist, k)
    thr = _WATERSHED_MIN_PEAK_FRAC * peak_h
    peaks = (dist >= dilated - 1e-6) & (dist >= thr) & (binary > 0)
    # Suppress thin ridges: keep only peaks with enough support
    u8 = (peaks.astype(np.uint8)) * 255
    n, labels, stats, centroids = cv2.connectedComponentsWithStats(u8, connectivity=8)
    if n <= 2:
        return None
    markers = np.zeros(binary.shape, dtype=np.int32)
    next_id = 1
    # Sort components left→right
    order = sorted(
        range(1, n),
        key=lambda i: float(centroids[i][0]),
    )
    for i in order:
        if int(stats[i, cv2.CC_STAT_AREA]) < 2:
            continue
        # Seed a small disk at the component centroid (DT peak cluster)
        cx = int(round(float(centroids[i][0])))
        cy = int(round(float(centroids[i][1])))
        r = max(2, int(0.25 * peak_h))
        cv2.circle(markers, (cx, cy), r, next_id, thickness=-1)
        next_id += 1
    markers[binary == 0] = 0
    if next_id <= 2:
        return None
    return markers


def _split_instances_watershed(
    u8: np.ndarray,
    luminance: np.ndarray | None = None,
    *,
    use_dt_local_max: bool = True,
) -> list[np.ndarray]:
    """Marker-controlled instance split on the semantic enamel mask.

    Marker sources (richest plausible set wins):
      DT 2D local maxima (optional) / arch-spacing / ridge peaks / opening
    Cuts prefer dark interdental columns when luminance is provided.
    """
    import cv2

    binary = (u8 > 0).astype(np.uint8)
    if int(binary.sum()) < 40:
        return []

    dist = cv2.distanceTransform(binary, cv2.DIST_L2, 5)
    peak_h = float(dist.max())
    if peak_h < 2.0:
        return _components_from_binary(u8)

    est_w = max(10, int(2.0 * peak_h))
    markers_open = _markers_from_opening(binary, est_w)
    markers_arch = _markers_from_arch_spacing(dist, binary)
    markers_ridge = _markers_from_ridge(dist, binary)
    markers_dt = (
        _markers_from_dt_local_maxima(dist, binary) if use_dt_local_max else None
    )

    # Prefer proven arch/ridge/opening first. Admit DT local-max only when it
    # agrees (±2) with another source — otherwise it over-segments flat bars.
    base = [m for m in (markers_arch, markers_ridge, markers_open) if m is not None]
    if not base and markers_dt is None:
        return _components_from_binary(u8)
    best_other = max((int(m.max()) for m in base), default=0)
    candidates = list(base)
    if markers_dt is not None:
        n_dt = int(markers_dt.max())
        if best_other < 2 or (n_dt >= best_other and n_dt <= best_other + 2):
            candidates.insert(0, markers_dt)
    if not candidates:
        return _components_from_binary(u8)
    markers = max(candidates, key=lambda m: int(m.max()))

    n_labels = int(markers.max())
    if n_labels < 2:
        return _components_from_binary(u8)

    centers: list[tuple[int, int]] = []
    for i in range(1, n_labels + 1):
        ys, xs = np.nonzero(markers == i)
        if xs.size:
            centers.append((i, int(round(float(xs.mean())))))
    centers.sort(key=lambda t: t[1])

    ridge = dist.max(axis=0)
    if luminance is not None and luminance.shape == binary.shape:
        col_L = np.zeros(binary.shape[1], dtype=np.float64)
        for x in range(binary.shape[1]):
            col = luminance[:, x][binary[:, x] > 0]
            col_L[x] = float(col.mean()) if col.size else 255.0
        cut_score = col_L
    else:
        cut_score = ridge

    if len(centers) >= 3:
        parts = _cut_between_centers(binary, cut_score, centers, half_width=1)
        if len(parts) >= max(2, len(centers) - 1):
            return parts

    use_cuts = False
    if len(centers) >= 2:
        shallow = 0
        for (_i, x_a), (_j, x_b) in zip(centers, centers[1:]):
            if x_b - x_a < 3:
                continue
            seg = ridge[x_a : x_b + 1]
            valley = float(seg.min())
            weaker = min(float(ridge[x_a]), float(ridge[x_b]))
            if weaker < 1e-6 or valley / weaker > 0.85:
                shallow += 1
        use_cuts = shallow >= max(1, len(centers) // 2)

    if use_cuts:
        parts = _cut_between_centers(binary, cut_score, centers, half_width=0)
        if len(parts) >= 2:
            return parts

    sure_fg = (markers > 0).astype(np.uint8)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    sure_bg = cv2.dilate(binary, kernel, iterations=2)
    unknown = cv2.subtract(sure_bg, sure_fg)

    topo = cv2.normalize(dist, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
    topo_color = cv2.cvtColor(topo, cv2.COLOR_GRAY2BGR)

    ws_markers = markers.copy()
    bg_label = n_labels + 1
    ws_markers[sure_bg == 0] = bg_label
    ws_markers[unknown > 0] = 0

    cv2.watershed(topo_color, ws_markers)

    out: list[np.ndarray] = []
    for i in range(1, n_labels + 1):
        m = (ws_markers == i) & (binary > 0)
        if int(m.sum()) >= 40:
            out.append(m)
    if not out:
        return _components_from_binary(u8)
    return out


def _split_arch_by_deep_valleys(u8: np.ndarray) -> np.ndarray:
    """Legacy 1D column-valley cuts — kept for A/B via config.valley_split."""
    _bh, bw = u8.shape
    col_sum = (u8 > 0).sum(axis=0).astype(np.float64)
    if float(col_sum.max()) < 8:
        return u8

    k = max(5, (bw // 28) | 1)
    smooth = np.convolve(col_sum, np.ones(k) / k, mode="same")
    peak_h = float(smooth.max())
    if peak_h < 8:
        return u8

    thr = 0.28 * peak_h
    min_sep = max(10, int(0.06 * bw))

    peaks: list[int] = []
    for x in range(2, bw - 2):
        if smooth[x] < thr:
            continue
        if smooth[x] >= smooth[x - 1] and smooth[x] >= smooth[x + 1]:
            if not peaks or x - peaks[-1] >= min_sep:
                peaks.append(x)
            elif smooth[x] > smooth[peaks[-1]]:
                peaks[-1] = x

    if len(peaks) < 2:
        return u8

    cuts: list[int] = []
    for i in range(len(peaks) - 1):
        left, right = peaks[i], peaks[i + 1]
        if right - left < min_sep:
            continue
        seg = smooth[left : right + 1]
        valley_i = int(np.argmin(seg))
        valley_h = float(seg[valley_i])
        weaker = min(float(smooth[left]), float(smooth[right]))
        if weaker > 1e-6 and valley_h / weaker <= _VALLEY_DEPTH_RATIO:
            cuts.append(left + valley_i)

    if not cuts:
        return u8
    out = u8.copy()
    for c in cuts:
        out[:, c] = 0
    return out


def _enamel_row_runs(
    row_sum: np.ndarray, thr: float, *, min_h: int
) -> list[tuple[int, int]]:
    """Inclusive [lo, hi] runs where row_sum >= thr and height >= min_h."""
    bh = int(row_sum.shape[0])
    runs: list[tuple[int, int]] = []
    i = 0
    while i < bh:
        if row_sum[i] >= thr:
            j = i
            while j < bh and row_sum[j] >= thr:
                j += 1
            if (j - i) >= min_h:
                runs.append((i, j - 1))
            i = j
        else:
            i += 1
    return runs


def _find_occlusal_gap(
    u8: np.ndarray, luminance: np.ndarray | None = None
) -> tuple[int, int] | None:
    """Locate open-mouth gap between maxillary / mandibular enamel.

    Two cases:
      1) Separate enamel bands → clear the strip between the two strongest.
      2) One connected band (bridges) → darkest mid-band enamel+luma valley.
    Never use full-ROI peaks vs lips/chrome (that cleared the wrong strip).
    """
    bh, _bw = u8.shape
    row_sum = (u8 > 0).sum(axis=1).astype(np.float64)
    peak_h = float(row_sum.max())
    if peak_h < 10:
        return None

    thr = 0.22 * peak_h
    min_h = max(6, int(0.04 * bh))
    runs = _enamel_row_runs(row_sum, thr, min_h=min_h)

    if len(runs) >= 2:
        # Strongest two by integrated fill, ordered top→bottom.
        ranked = sorted(
            runs,
            key=lambda r: float(row_sum[r[0] : r[1] + 1].sum()),
            reverse=True,
        )
        top, bot = sorted(ranked[:2], key=lambda r: r[0])
        sep = bot[0] - top[1]
        if sep >= max(6, int(0.06 * bh)):
            y_a = top[1] + 1
            y_b = bot[0] - 1
            if y_b >= y_a:
                return int(y_a), int(y_b)

    if not runs:
        return None

    # Single (or weakly separated) band — column votes beat row-sum valleys
    # when thin bridges keep enamel_row high across the occlusal plane.
    band_lo, band_hi = max(runs, key=lambda r: r[1] - r[0])
    band_h = band_hi - band_lo + 1
    if band_h < max(28, int(0.22 * bh)):
        return None

    col_gap = _occlusal_gap_from_column_votes(u8, luminance, band_lo, band_hi)
    if col_gap is not None:
        return col_gap

    k = max(3, (band_h // 18) | 1)
    e_s = np.convolve(row_sum, np.ones(k) / k, mode="same")

    if luminance is not None:
        l_en = np.empty(bh, dtype=np.float64)
        for y in range(bh):
            cols = np.flatnonzero(u8[y] > 0)
            if cols.size:
                l_en[y] = float(np.mean(luminance[y, cols]))
            else:
                l_en[y] = float(np.mean(luminance[y]))
        l_s = np.convolve(l_en, np.ones(k) / k, mode="same")
    else:
        l_s = e_s.copy()

    e_max = float(e_s[band_lo : band_hi + 1].max()) + 1e-6
    l_max = float(l_s[band_lo : band_hi + 1].max()) + 1e-6
    score = (e_s / e_max) + 0.45 * (l_s / l_max)

    margin = max(4, int(0.18 * band_h))
    mid_lo = band_lo + margin
    mid_hi = band_hi - margin
    if mid_hi <= mid_lo:
        return None

    best_y: int | None = None
    best_sc = 1e9
    for y in range(mid_lo, mid_hi + 1):
        above = float(e_s[band_lo:y].max())
        below = float(e_s[y + 1 : band_hi + 1].max())
        if above < 0.45 * e_max or below < 0.45 * e_max:
            continue
        if score[y] < best_sc:
            best_sc = float(score[y])
            best_y = y

    if best_y is None:
        return None

    above = float(e_s[band_lo:best_y].max())
    below = float(e_s[best_y + 1 : band_hi + 1].max())
    flank = min(above, below)
    # Single-arch smiles have no clear mid-band valley.
    if flank > 1e-6 and e_s[best_y] / flank > 0.92:
        if luminance is None or l_s[best_y] / l_max > 0.90:
            return None

    thr_sc = best_sc + 0.06 * max(0.05, 1.0 - best_sc)
    y_a = best_y
    y_b = best_y
    while y_a > band_lo + 2 and score[y_a - 1] <= thr_sc:
        y_a -= 1
    while y_b < band_hi - 2 and score[y_b + 1] <= thr_sc:
        y_b += 1
    if y_b - y_a < 3:
        y_a = max(band_lo + 1, best_y - 2)
        y_b = min(band_hi - 1, best_y + 2)
    if (y_b - y_a + 1) > 0.35 * band_h:
        pad = max(2, int(0.06 * band_h))
        y_a = max(band_lo + 1, best_y - pad)
        y_b = min(band_hi - 1, best_y + pad)
    return int(y_a), int(y_b)


def _occlusal_gap_from_column_votes(
    u8: np.ndarray,
    luminance: np.ndarray | None,
    band_lo: int,
    band_hi: int,
) -> tuple[int, int] | None:
    """Vote per-column for the dark/empty seam between stacked crowns."""
    bh, bw = u8.shape
    band_h = band_hi - band_lo + 1
    votes: list[int] = []
    for x in range(bw):
        ys = np.flatnonzero(u8[:, x] > 0)
        if ys.size < 20:
            continue
        y0c, y1c = int(ys.min()), int(ys.max())
        # Stay inside the dental band.
        y0c = max(y0c, band_lo)
        y1c = min(y1c, band_hi)
        ht = y1c - y0c + 1
        if ht < max(24, int(0.40 * band_h)):
            continue
        mid0 = y0c + int(0.18 * ht)
        mid1 = y1c - int(0.18 * ht)
        if mid1 <= mid0:
            continue
        empty = [y for y in range(mid0, mid1 + 1) if u8[y, x] == 0]
        if len(empty) >= 2:
            votes.append(int(np.median(empty)))
            continue
        if luminance is None:
            continue
        # Continuous bridge: darkest pixel in the mid span.
        seg = luminance[mid0 : mid1 + 1, x]
        votes.append(mid0 + int(np.argmin(seg)))

    if len(votes) < max(10, int(0.06 * bw)):
        return None
    med = int(np.median(votes))
    tol = max(4, int(0.035 * bh))
    near = sum(1 for v in votes if abs(v - med) <= tol)
    if near < 0.40 * len(votes):
        return None
    if med < band_lo + int(0.15 * band_h) or med > band_hi - int(0.15 * band_h):
        return None
    pad = max(2, int(0.015 * bh))
    y_a = max(band_lo + 1, med - pad)
    y_b = min(band_hi - 1, med + pad)
    return int(y_a), int(y_b)


def _split_dual_arches(
    u8: np.ndarray, luminance: np.ndarray | None = None
) -> np.ndarray:
    """Sever maxillary / mandibular enamel at the dark open-mouth gap."""
    gap = _find_occlusal_gap(u8, luminance=luminance)
    if gap is None:
        return u8
    y_a, y_b = gap
    out = u8.copy()
    out[y_a : y_b + 1, :] = 0
    return out


def _clip_crossing_occlusal(
    components: list[np.ndarray], gap: tuple[int, int]
) -> list[np.ndarray]:
    """Split any mask that still straddles the occlusal gap after refine."""
    y_a, y_b = gap
    out: list[np.ndarray] = []
    for c in components:
        ys = np.nonzero(c)[0]
        if ys.size == 0:
            continue
        if int(ys.min()) < y_a and int(ys.max()) > y_b:
            top = c.copy()
            top[y_a:, :] = False
            bot = c.copy()
            bot[: y_b + 1, :] = False
            if int(top.sum()) >= 40:
                out.append(top)
            if int(bot.sum()) >= 40:
                out.append(bot)
        else:
            out.append(c)
    return out


def _split_vertically_merged_components(
    components: list[np.ndarray],
    luminance: np.ndarray,
) -> list[np.ndarray]:
    """Split remaining tall blobs that still span upper+lower crowns."""
    if not components:
        return components

    heights: list[int] = []
    for c in components:
        ys, _xs = np.nonzero(c)
        if ys.size:
            heights.append(int(ys.max() - ys.min() + 1))
    med_h = float(np.median(heights)) if heights else 0.0

    out: list[np.ndarray] = []
    for c in components:
        ys, xs = np.nonzero(c)
        if ys.size < 40:
            out.append(c)
            continue
        y0, y1 = int(ys.min()), int(ys.max())
        ht = y1 - y0 + 1
        wd = int(xs.max() - xs.min() + 1)
        # Clinic open-mouth merges are often only ~1.6–2.2× taller than wide.
        too_tall = ht >= 1.75 * max(wd, 1) or (
            med_h > 0 and ht >= 1.65 * med_h and ht >= 1.7 * max(wd, 1)
        )
        if not too_tall:
            out.append(c)
            continue

        scores: list[float] = []
        for y in range(y0, y1 + 1):
            cols = np.flatnonzero(c[y])
            if cols.size == 0:
                scores.append(0.0)
                continue
            fill = float(cols.size)
            luma = float(np.mean(luminance[y, cols]))
            scores.append(fill * (0.25 + luma / 255.0))

        margin = max(3, int(0.15 * ht))
        if ht <= 2 * margin + 2:
            out.append(c)
            continue
        search = scores[margin : ht - margin]
        local = int(np.argmin(search)) + margin
        ends = scores[:margin] + scores[ht - margin :]
        peak = max(ends) if ends else 1.0
        if peak < 1e-6 or scores[local] / peak > 0.62:
            out.append(c)
            continue

        cut_y = y0 + local
        top = c.copy()
        top[cut_y:, :] = False
        bot = c.copy()
        bot[: cut_y + 1, :] = False
        if int(top.sum()) >= 40 and int(bot.sum()) >= 40:
            out.append(top)
            out.append(bot)
        else:
            out.append(c)
    return out


# ---------------------------------------------------------------------------
# 5) Boundary refinement
# ---------------------------------------------------------------------------


def _refine_tooth_component(band: np.ndarray, comp: np.ndarray) -> np.ndarray:
    """Remove pink fringe via Lab a*; keep largest contour within original bounds."""
    import cv2

    if not np.any(comp):
        return comp

    u8 = np.clip(band, 0, 255).astype(np.uint8)
    lab = cv2.cvtColor(u8, cv2.COLOR_RGB2LAB).astype(np.float64)
    L = lab[:, :, 0]
    a = lab[:, :, 1] - 128.0

    ys, xs = np.nonzero(comp)
    L_px = L[ys, xs]
    a_px = a[ys, xs]
    floor = max(90.0, float(np.percentile(L_px, 10)))
    keep = (L_px >= floor) & (a_px < 12.0)
    refined = np.zeros_like(comp, dtype=bool)
    if keep.size == ys.size and int(keep.sum()) >= 30:
        refined[ys[keep], xs[keep]] = True
    else:
        refined = comp.copy()

    # Drop pinker uppermost fringe (gingival margin)
    rys, _ = np.nonzero(refined)
    if rys.size:
        y_min, y_max = int(rys.min()), int(rys.max())
        span = max(1, y_max - y_min + 1)
        cut = y_min + max(2, int(0.1 * span))
        top = refined.copy()
        top[cut:, :] = False
        body = refined.copy()
        body[:cut, :] = False
        if int(top.sum()) > 20 and int(body.sum()) > 40:
            top_a = float(np.median(a[top]))
            body_a = float(np.median(a[body]))
            if top_a >= body_a + 4.0:
                refined = body

    u8m = (refined.astype(np.uint8)) * 255
    u8m = cv2.morphologyEx(
        u8m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)), 1
    )
    contours, _ = cv2.findContours(u8m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return u8m > 0
    largest = max(contours, key=cv2.contourArea)
    out = np.zeros_like(u8m)
    cv2.drawContours(out, [largest], -1, 255, thickness=-1)
    allow = cv2.dilate(
        (comp.astype(np.uint8)) * 255,
        cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)),
        iterations=1,
    )
    return (out > 0) & (allow > 0)


def _snap_boundary_to_edges(band: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Snap loose borders using Lab a* / L — shrink pink/dark fringe only."""
    import cv2

    if not np.any(mask):
        return mask

    u8 = np.clip(band, 0, 255).astype(np.uint8)
    lab = cv2.cvtColor(u8, cv2.COLOR_RGB2LAB).astype(np.float64)
    L = lab[:, :, 0]
    a = lab[:, :, 1] - 128.0

    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    m_u8 = (mask.astype(np.uint8)) * 255
    eroded = cv2.erode(m_u8, k, iterations=1) > 0
    ring_in = mask & ~eroded

    out = mask.copy()
    drop = ring_in & ((a >= 11.0) | (L < 100))
    out[drop] = False
    return out


def _grabcut_all_teeth(
    band: np.ndarray, seeds: list[np.ndarray], enamel: np.ndarray
) -> list[np.ndarray]:
    """Per-tooth GrabCut with sibling exclusion — adapts boundary to THIS tooth."""
    out: list[np.ndarray] = []
    for i, seed in enumerate(seeds):
        siblings = np.zeros_like(seed, dtype=bool)
        for j, other in enumerate(seeds):
            if i != j:
                siblings |= other
        refined = _grabcut_one_tooth(band, seed, siblings, enamel)
        if int(refined.sum()) >= 40:
            out.append(refined)
        elif int(seed.sum()) >= 40:
            out.append(seed)
    return out


def _grabcut_one_tooth(
    band: np.ndarray,
    seed: np.ndarray,
    siblings: np.ndarray,
    enamel: np.ndarray,
) -> np.ndarray:
    """GrabCut in a padded crop around one seed; siblings are hard background.

    Why this adapts to any mouth: color models are fit on *this* tooth's pixels
    vs local non-tooth, so crooked / rotated crowns get their own edge model
    instead of a global RGB rule.
    """
    import cv2

    if not np.any(seed):
        return seed

    ys, xs = np.nonzero(seed)
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    pad = max(6, int(0.14 * max(y1 - y0, x1 - x0)))
    h, w = seed.shape
    y0p, y1p = max(0, y0 - pad), min(h, y1 + pad)
    x0p, x1p = max(0, x0 - pad), min(w, x1 + pad)

    crop = np.clip(band[y0p:y1p, x0p:x1p], 0, 255).astype(np.uint8)
    if crop.shape[0] < 8 or crop.shape[1] < 8:
        return seed

    seed_c = seed[y0p:y1p, x0p:x1p]
    sib_c = siblings[y0p:y1p, x0p:x1p]
    enamel_c = enamel[y0p:y1p, x0p:x1p]

    # OpenCV GrabCut mask codes
    gc = np.full(seed_c.shape, cv2.GC_BGD, dtype=np.uint8)
    # Probable FG: enamel in crop that isn't a sibling
    gc[enamel_c & ~sib_c] = cv2.GC_PR_FGD
    # Probable BG: everything else in crop
    # Sure FG: eroded seed
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    sure_fg = cv2.erode(seed_c.astype(np.uint8) * 255, k, iterations=1) > 0
    if int(sure_fg.sum()) < 20:
        sure_fg = seed_c
    gc[sure_fg] = cv2.GC_FGD
    # Sure BG: siblings + clearly non-enamel / pink fringe
    lab = cv2.cvtColor(crop, cv2.COLOR_RGB2LAB).astype(np.float64)
    a = lab[:, :, 1] - 128.0
    L = lab[:, :, 0]
    seed_L = float(np.median(L[seed_c])) if np.any(seed_c) else 140.0
    dark = L < max(62.0, 0.55 * seed_L)
    sure_bg = sib_c | (~enamel_c & (a >= 10.0)) | (a >= 16.0) | dark
    gc[sure_bg] = cv2.GC_BGD

    try:
        bgd = np.zeros((1, 65), np.float64)
        fgd = np.zeros((1, 65), np.float64)
        cv2.grabCut(crop, gc, None, bgd, fgd, 3, cv2.GC_INIT_WITH_MASK)
    except cv2.error:
        return seed

    result = np.zeros_like(seed, dtype=bool)
    fg = (gc == cv2.GC_FGD) | (gc == cv2.GC_PR_FGD)
    # Stay inside enamel and out of siblings
    fg &= enamel_c & ~sib_c
    if int(fg.sum()) < 30:
        return seed
    result[y0p:y1p, x0p:x1p] = fg
    # Keep largest component only
    kept = _largest_cc(result)
    return seed if kept is None else kept


def _contact_valley_strength(
    band: np.ndarray,
    mask_a: np.ndarray,
    mask_b: np.ndarray,
) -> float:
    """0 = no contact valley (likely one tooth); 1 = strong dark seam (two teeth).

    Samples along the line between centroids — works for crooked teeth because
    the seam direction follows the actual pair, not a vertical image column.
    """
    ys_a, xs_a = np.nonzero(mask_a)
    ys_b, xs_b = np.nonzero(mask_b)
    if ys_a.size == 0 or ys_b.size == 0:
        return 0.0
    c1 = np.array([ys_a.mean(), xs_a.mean()])
    c2 = np.array([ys_b.mean(), xs_b.mean()])
    delta = c2 - c1
    dist = float(np.linalg.norm(delta))
    if dist < 4:
        return 0.0

    lum = _luma_rgb(band)
    n_samples = max(8, int(dist))
    ts = np.linspace(0.15, 0.85, n_samples)
    vals = []
    h, w = lum.shape
    for t in ts:
        y, x = c1 + t * delta
        yi, xi = int(round(y)), int(round(x))
        if 0 <= yi < h and 0 <= xi < w:
            vals.append(float(lum[yi, xi]))
    if len(vals) < 5:
        return 0.0
    vals_a = np.array(vals, dtype=np.float64)
    ends = 0.5 * (float(np.median(vals_a[:2])) + float(np.median(vals_a[-2:])))
    mid = float(np.min(vals_a[len(vals_a) // 4 : 3 * len(vals_a) // 4]))
    if ends < 1e-3:
        return 0.0
    # Strong valley when mid is clearly darker than tooth bodies
    drop = (ends - mid) / ends
    return float(np.clip(drop / 0.25, 0.0, 1.0))  # 25% drop → strength 1


def _reconcile_contacts(
    components: list[np.ndarray],
    band: np.ndarray,
) -> list[np.ndarray]:
    """Prevent 1↔2 errors using contact valleys between neighbors.

    - Two adjacent pieces with NO dark seam → merge (over-split of one tooth)
    - One piece much wider than peers WITH an internal dark seam → split
    Seam direction follows centroids (crooked-tooth safe), not fixed columns.
    """
    if len(components) == 0:
        return components

    # --- Pass 1: split too-wide masks that contain an internal valley ---
    widths = []
    for c in components:
        xs = np.nonzero(c)[1]
        widths.append(int(xs.max() - xs.min() + 1) if xs.size else 0)
    med_w = float(np.median(widths)) if widths else 1.0

    split_out: list[np.ndarray] = []
    for c, wd in zip(components, widths):
        if wd < 1.55 * med_w or wd < 12:
            split_out.append(c)
            continue
        ys, xs = np.nonzero(c)
        # Search for darkest vertical-ish cut inside this mask using luminance
        lum = _luma_rgb(band)
        x0, x1 = int(xs.min()), int(xs.max())
        best_x, best_score = None, -1.0
        for x in range(x0 + max(3, wd // 5), x1 - max(3, wd // 5)):
            col = lum[:, x][c[:, x]]
            if col.size < 4:
                continue
            # Prefer cuts where column is both dark and thin (contact neck)
            score = (255.0 - float(col.mean())) * (1.0 + 4.0 / max(1, col.size))
            left = int(c[:, x0:x].sum())
            right = int(c[:, x + 1 : x1 + 1].sum())
            if min(left, right) < 0.22 * int(c.sum()):
                continue
            if score > best_score:
                best_score = score
                best_x = x
        if best_x is None:
            split_out.append(c)
            continue
        # Confirm valley vs left/right body brightness
        left_m0 = c.copy()
        left_m0[:, best_x:] = False
        right_m0 = c.copy()
        right_m0[:, : best_x + 1] = False
        left_L = float(lum[left_m0].mean()) if np.any(left_m0) else 0.0
        right_L = float(lum[right_m0].mean()) if np.any(right_m0) else 0.0
        cut_L = float(lum[:, best_x][c[:, best_x]].mean()) if np.any(c[:, best_x]) else 255.0
        body = 0.5 * (left_L + right_L)
        if body > 1 and (body - cut_L) / body >= 0.08:
            if int(left_m0.sum()) >= 40 and int(right_m0.sum()) >= 40:
                split_out.append(left_m0)
                split_out.append(right_m0)
                continue
        split_out.append(c)

    components = split_out
    if len(components) <= 1:
        return components

    # --- Pass 2: merge neighbors with no contact valley (over-split) ---
    items = [_mask_geom(comp) for comp in components]
    items.sort(key=lambda d: d["cx"])
    merged = [items[0]]
    for item in items[1:]:
        prev = merged[-1]
        gap = item["x0"] - prev["x1"]
        valley = _contact_valley_strength(band, prev["mask"], item["mask"])
        area_ratio = min(prev["area"], item["area"]) / max(prev["area"], item["area"])
        combined_w = item["x1"] - prev["x0"] + 1
        # Merge only when: close/overlapping, weak seam, and not building an arch
        close = gap <= max(4, int(0.08 * med_w))
        looks_one = combined_w <= 1.35 * max(prev["w"], item["w"]) + 4
        if close and valley < 0.35 and looks_one and area_ratio > 0.25:
            prev["mask"] = prev["mask"] | item["mask"]
            prev.update(_mask_geom(prev["mask"]))
        else:
            merged.append(item)
    return [m["mask"] for m in merged]


def _resolve_overlaps(components: list[np.ndarray]) -> list[np.ndarray]:
    """Assign contested pixels to the nearest instance centroid (no re-merge)."""
    if len(components) <= 1:
        return components
    centroids = []
    for c in components:
        ys, xs = np.nonzero(c)
        if ys.size:
            centroids.append((float(ys.mean()), float(xs.mean())))
        else:
            centroids.append((0.0, 0.0))

    claim = np.zeros(components[0].shape, dtype=np.int16)
    for c in components:
        claim += c.astype(np.int16)
    if int((claim > 1).sum()) == 0:
        return components

    out = [c.copy() for c in components]
    ys, xs = np.nonzero(claim > 1)
    for y, x in zip(ys.tolist(), xs.tolist()):
        owners = [i for i, c in enumerate(components) if c[y, x]]
        best = min(
            owners,
            key=lambda i: (y - centroids[i][0]) ** 2 + (x - centroids[i][1]) ** 2,
        )
        for i in owners:
            if i != best:
                out[i][y, x] = False
    return [m for m in out if int(m.sum()) >= 40] or components


# ---------------------------------------------------------------------------
# 6) Morph cleanup
# ---------------------------------------------------------------------------


def _morph_cleanup_mask(mask: np.ndarray) -> np.ndarray:
    """Fill small holes, drop dust, light contour smooth — after boundary snap."""
    import cv2

    if not np.any(mask):
        return mask
    u8 = (mask.astype(np.uint8)) * 255
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    u8 = cv2.morphologyEx(u8, cv2.MORPH_OPEN, k, iterations=1)
    u8 = cv2.morphologyEx(u8, cv2.MORPH_CLOSE, k, iterations=1)
    contours, _ = cv2.findContours(u8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not contours:
        return u8 > 0
    largest = max(contours, key=cv2.contourArea)
    filled = np.zeros_like(u8)
    # Light smooth only — heavy approxPolyDP made coarse hexagons that
    # ignored cervical scallop / contact curves on clinic photos.
    eps = max(0.4, 0.003 * cv2.arcLength(largest, True))
    approx = cv2.approxPolyDP(largest, eps, True)
    cv2.drawContours(filled, [approx], -1, 255, thickness=-1)
    allow = cv2.dilate(u8, k, iterations=1)
    return (filled > 0) & (allow > 0) & mask


# ---------------------------------------------------------------------------
# 7) Merge / relative filter
# ---------------------------------------------------------------------------


def _merge_oversegmented_neighbors(components: list[np.ndarray]) -> list[np.ndarray]:
    if len(components) <= 1:
        return components
    items = [_mask_geom(comp) for comp in components]
    items.sort(key=lambda d: d["cx"])
    merged = [items[0]]
    for item in items[1:]:
        prev = merged[-1]
        gap = item["x0"] - prev["x1"]
        oy0 = max(prev["y0"], item["y0"])
        oy1 = min(prev["y1"], item["y1"])
        overlap_h = max(0, oy1 - oy0 + 1)
        min_h = max(1, min(prev["h"], item["h"]))
        y_overlap = overlap_h / float(min_h)
        combined_w = item["x1"] - prev["x0"] + 1
        area_ratio = min(prev["area"], item["area"]) / max(prev["area"], item["area"])
        prev_w, item_w = prev["w"], item["w"]
        prev_h, item_h = prev["h"], item["h"]
        # Only reunite accidental halves — NEVER two similar-sized teeth.
        fragment = area_ratio < 0.35
        looks_one_crown = combined_w <= int(1.15 * max(prev_w, item_w)) + 4
        # If the larger piece is already arch-wide (w >> h), it is merged junk —
        # do not absorb neighbors into it.
        larger_w, larger_h = (prev_w, prev_h) if prev_w >= item_w else (item_w, item_h)
        larger_is_arch = larger_w > 1.25 * larger_h
        should_merge = (
            fragment
            and looks_one_crown
            and (not larger_is_arch)
            and y_overlap >= 0.5
            and gap <= 6
        )
        if should_merge:
            prev["mask"] = prev["mask"] | item["mask"]
            prev.update(_mask_geom(prev["mask"]))
        else:
            merged.append(item)
    return [m["mask"] for m in merged]


def _filter_by_relative_size(components: list[np.ndarray]) -> list[np.ndarray]:
    """Drop fragments that are tiny vs the typical tooth in *this* photo."""
    if len(components) <= 1:
        return components

    areas = np.array([int(c.sum()) for c in components], dtype=np.float64)
    heights = np.array(
        [int(np.nonzero(c)[0].max() - np.nonzero(c)[0].min() + 1) for c in components],
        dtype=np.float64,
    )
    widths = np.array(
        [int(np.nonzero(c)[1].max() - np.nonzero(c)[1].min() + 1) for c in components],
        dtype=np.float64,
    )

    order = np.argsort(areas)[::-1]
    top = order[: max(1, len(order) // 2 + 1)]
    ref_area = float(np.median(areas[top]))
    ref_h = float(np.median(heights[top]))
    ref_w = float(np.median(widths[top]))

    kept = []
    for c, a, ht, wd in zip(components, areas, heights, widths):
        if a < _MIN_REL_AREA * ref_area:
            continue
        if ht < _MIN_REL_HEIGHT * ref_h:
            continue
        if wd > max(ref_w * 2.8, ref_w + 1):
            continue
        kept.append(c)

    if kept:
        return kept
    return [components[int(np.argmax(areas))]]


def _drop_lip_above_smile(
    rows: list[dict], band_h: int
) -> list[dict]:
    """Drop blobs that sit on the upper lip above the bright crown row.

    Camera frontal crops include a lot of lip; bright gloss often survives the
    Lab-a* gate as a fake "tooth" floating above the smile (clinic T1).
    """
    if len(rows) < 2 or band_h < 16:
        return rows

    # Brightest / largest crowns define the smile line — not lip patches.
    ranked = sorted(
        rows,
        key=lambda d: (float(d["med_L"]) * 0.6 + float(d["area"]) ** 0.5),
        reverse=True,
    )
    smile = ranked[: max(2, (len(ranked) + 1) // 2)]
    smile_top = min(float(d["y0"]) for d in smile)
    smile_cy = float(np.median([d["cy"] for d in smile]))
    med_h = float(np.median([d["h"] for d in smile]))

    kept: list[dict] = []
    for d in rows:
        # Entirely above the smile band → lip / mustache / nostril.
        if float(d["cy"]) < smile_cy - 0.85 * max(med_h, 1.0) and float(
            d["y0"]
        ) < smile_top - 0.04 * band_h:
            continue
        # Small + redder + above midline of smile → lip highlight.
        if (
            float(d["cy"]) < smile_cy - 0.55 * max(med_h, 1.0)
            and float(d["med_a"]) >= 6.0
            and float(d["area"]) < 0.55 * float(np.median([r["area"] for r in smile]))
        ):
            continue
        kept.append(d)
    return kept if kept else rows


def _filter_to_arch_row(
    components: list[np.ndarray], band_rgb: np.ndarray
) -> list[np.ndarray]:
    """Keep tooth row(s); drop cheek/lip blobs and vertical outliers.

    Single-arch smiles: keep one horizontal row (legacy behavior).
    Open-mouth / both arches: keep upper AND lower rows when cy is bimodal.
    """
    import cv2

    if len(components) <= 1:
        return components

    u8 = np.clip(band_rgb, 0, 255).astype(np.uint8)
    lab = cv2.cvtColor(u8, cv2.COLOR_RGB2LAB).astype(np.float64)
    a_img = lab[:, :, 1] - 128.0
    L_img = lab[:, :, 0]

    rows = []
    for c in components:
        ys, xs = np.nonzero(c)
        if ys.size < 40:
            continue
        med_a = float(np.median(a_img[c]))
        med_L = float(np.median(L_img[c]))
        # Skin/lip false positives are redder (high a*) even if bright.
        # Camera close-ups: pale lip gloss often sits ~9–12 a*.
        if med_a >= 10.0:
            continue
        ht = int(ys.max() - ys.min() + 1)
        wd = int(xs.max() - xs.min() + 1)
        # Cheek patches are often wide and short relative to a crown.
        if wd > 2.4 * ht and ht < 0.35 * band_rgb.shape[0]:
            continue
        rows.append(
            {
                "mask": c,
                "cy": float(ys.mean()),
                "cx": float(xs.mean()),
                "y0": float(ys.min()),
                "h": ht,
                "w": wd,
                "area": int(ys.size),
                "med_a": med_a,
                "med_L": med_L,
            }
        )
    if not rows:
        return components[:1]

    rows = _drop_lip_above_smile(rows, band_rgb.shape[0])
    if not rows:
        return components[:1]

    rows.sort(key=lambda d: d["area"], reverse=True)
    ref = rows[: max(1, len(rows) // 2 + 1)]
    med_h = float(np.median([d["h"] for d in ref]))
    cys = [d["cy"] for d in rows]
    cy_span = float(max(cys) - min(cys))

    # Dual arch: two populated rows with a clear vertical gap between them.
    if cy_span > 1.5 * max(med_h, 1.0) and len(rows) >= 4:
        mid = 0.5 * (min(cys) + max(cys))
        upper = [d for d in rows if d["cy"] < mid]
        lower = [d for d in rows if d["cy"] >= mid]
        if len(upper) >= 2 and len(lower) >= 2:
            sep = min(d["cy"] for d in lower) - max(d["cy"] for d in upper)
            if sep >= 0.45 * med_h:
                kept: list[dict] = []
                for group in (upper, lower):
                    g_cy = float(np.median([d["cy"] for d in group]))
                    g_h = float(np.median([d["h"] for d in group]))
                    y_tol = max(8.0, 0.55 * g_h)
                    kept.extend(d for d in group if abs(d["cy"] - g_cy) <= y_tol)
                if kept:
                    kept.sort(key=lambda d: (d["cy"], d["cx"]))
                    return [d["mask"] for d in kept]

    med_cy = float(np.median([d["cy"] for d in ref]))
    # Vertical gate: same smile row (adaptive to tooth height in this photo)
    y_tol = max(8.0, 0.72 * med_h)
    kept = [d for d in rows if abs(d["cy"] - med_cy) <= y_tol]
    if not kept:
        kept = ref[:1]
    kept.sort(key=lambda d: d["cx"])
    return [d["mask"] for d in kept]


def _filter_by_arch_curve(components: list[np.ndarray]) -> list[np.ndarray]:
    """Reject blobs that sit far from a polynomial fit through tooth centroids.

    Extends the horizontal arch-row gate: crooked smiles still form a smooth
    curve; gum/artifacts often sit off that curve. Dual-arch photos are fit
    per row so lower teeth are not treated as outliers of the upper curve.
    """
    if len(components) < 3:
        return components

    items = [_mask_geom(c) for c in components]
    cys = [d["cy"] for d in items]
    heights = [d["h"] for d in items]
    cy_span = float(max(cys) - min(cys))
    med_h = float(np.median(heights)) if heights else 1.0

    if cy_span > 1.5 * max(med_h, 1.0) and len(items) >= 4:
        mid = 0.5 * (min(cys) + max(cys))
        upper = [d for d in items if d["cy"] < mid]
        lower = [d for d in items if d["cy"] >= mid]
        if len(upper) >= 2 and len(lower) >= 2:
            sep = min(d["cy"] for d in lower) - max(d["cy"] for d in upper)
            if sep >= 0.45 * med_h:
                kept: list[np.ndarray] = []
                for group in (upper, lower):
                    masks = [d["mask"] for d in group]
                    if len(masks) >= 3:
                        kept.extend(_filter_by_arch_curve_one_row(masks))
                    else:
                        kept.extend(masks)
                return kept if kept else components

    return _filter_by_arch_curve_one_row(components)


def _filter_by_arch_curve_one_row(components: list[np.ndarray]) -> list[np.ndarray]:
    if len(components) < 3:
        return components

    items = [_mask_geom(c) for c in components]
    # Fit on the largest majority so one outlier doesn't warp the curve
    items_sorted = sorted(items, key=lambda d: d["area"], reverse=True)
    fit_n = max(3, (len(items_sorted) * 2 + 2) // 3)
    fit = items_sorted[:fit_n]
    x = np.asarray([d["cx"] for d in fit], dtype=np.float64)
    y = np.asarray([d["cy"] for d in fit], dtype=np.float64)
    deg = 2 if len(fit) >= 4 else 1
    try:
        coeffs = np.polyfit(x, y, deg)
    except np.linalg.LinAlgError:
        return components

    all_x = np.asarray([d["cx"] for d in items], dtype=np.float64)
    all_y = np.asarray([d["cy"] for d in items], dtype=np.float64)
    resid = np.abs(all_y - np.polyval(coeffs, all_x))
    fit_resid = np.abs(y - np.polyval(coeffs, x))
    med = float(np.median(fit_resid))
    med_h = float(np.median([d["h"] for d in items]))
    # Laterals/canines sit on a smile curve; keep them, still drop far lip blobs.
    thr = max(0.32 * med_h, 3.0 * med + 4.0)
    kept = [d["mask"] for d, r in zip(items, resid) if r <= thr]
    return kept if kept else components


def _cluster_masks_by_row(geoms: list[dict]) -> list[list[dict]]:
    if not geoms:
        return []
    med_h = float(np.median([g["h"] for g in geoms]))
    y_tol = max(8.0, 0.70 * med_h)
    rows: list[list[dict]] = []
    for g in sorted(geoms, key=lambda d: d["cy"]):
        placed = False
        for row in rows:
            rcy = float(np.median([x["cy"] for x in row]))
            if abs(g["cy"] - rcy) <= y_tol:
                row.append(g)
                placed = True
                break
        if not placed:
            rows.append([g])
    return [sorted(row, key=lambda d: d["cx"]) for row in rows]


def _pick_central_pair(geoms: list[dict], center_x: float) -> tuple[int, int] | None:
    """Adjacent pair most likely to be the two central incisors."""
    best_i: int | None = None
    best_score = -1.0
    for i in range(len(geoms) - 1):
        a, b = geoms[i], geoms[i + 1]
        area_r = min(a["area"], b["area"]) / max(a["area"], b["area"], 1)
        h_r = min(a["h"], b["h"]) / max(a["h"], b["h"], 1)
        if area_r < 0.38 or h_r < 0.45:
            continue
        gap = b["x0"] - a["x1"]
        if gap > 0.9 * max(a["w"], b["w"], 1):
            continue
        mid = 0.5 * (a["cx"] + b["cx"])
        dist = abs(mid - center_x) / max(abs(center_x), 1.0)
        size = 0.5 * (a["area"] + b["area"])
        score = (
            area_r
            * h_r
            * size
            / (1.0 + 4.0 * dist)
            / (1.0 + max(0, gap) / 24.0)
        )
        if score > best_score:
            best_score = score
            best_i = i
    if best_i is None:
        return None
    return best_i, best_i + 1


def _keep_anterior_row(geoms: list[dict]) -> list[dict]:
    """Two centrals plus up to two neighbours on each side."""
    if len(geoms) <= 2:
        return geoms
    areas = [g["area"] for g in geoms]
    ref_area = float(np.median(sorted(areas, reverse=True)[: max(2, len(geoms) // 2 + 1)]))
    ref_h = float(np.median([g["h"] for g in geoms]))
    plausible = [
        g
        for g in geoms
        if g["area"] >= 0.38 * ref_area and g["h"] >= 0.45 * ref_h
    ] or geoms
    # Already in the shade window — do not drop laterals/canines.
    if len(plausible) <= _ANTERIOR_MAX_PER_ROW:
        return plausible

    center_x = 0.5 * (
        float(np.median([g["cx"] for g in plausible]))
        + 0.5 * (plausible[0]["cx"] + plausible[-1]["cx"])
    )
    pair = _pick_central_pair(plausible, center_x)
    if pair is None:
        ranked = sorted(plausible, key=lambda g: abs(g["cx"] - center_x))
        picked = ranked[: _ANTERIOR_MAX_PER_ROW]
        return sorted(picked, key=lambda g: g["cx"])

    i0, i1 = pair
    centrals = [plausible[i0], plausible[i1]]
    min_area = 0.38 * min(centrals[0]["area"], centrals[1]["area"])
    min_h = 0.45 * min(centrals[0]["h"], centrals[1]["h"])

    left: list[dict] = []
    for g in reversed(plausible[:i0]):
        if g["area"] < min_area or g["h"] < min_h:
            continue
        left.append(g)
        if len(left) >= _ANTERIOR_SIDE:
            break
    left.reverse()

    right: list[dict] = []
    for g in plausible[i1 + 1 :]:
        if g["area"] < min_area or g["h"] < min_h:
            continue
        right.append(g)
        if len(right) >= _ANTERIOR_SIDE:
            break
    return left + centrals + right


def _keep_anterior_window(masks: list[np.ndarray]) -> list[np.ndarray]:
    """Keep the shade-relevant anterior group; drop far premolars and cheek junk."""
    geoms = [_mask_geom(m) for m in masks if np.any(m) and int(m.sum()) >= 40]
    if len(geoms) <= 2:
        return [g["mask"] for g in geoms] or masks
    out: list[np.ndarray] = []
    for row in _cluster_masks_by_row(geoms):
        out.extend(g["mask"] for g in _keep_anterior_row(row))
    return out or masks


def _column_enamel_luma(enamel: np.ndarray, lum: np.ndarray) -> np.ndarray:
    counts = enamel.astype(np.float64).sum(axis=0)
    sums = (lum.astype(np.float64) * enamel.astype(np.float64)).sum(axis=0)
    out = np.full(enamel.shape[1], 255.0, dtype=np.float64)
    nz = counts > 0
    out[nz] = sums[nz] / np.maximum(counts[nz], 1.0)
    return out


def _fill_row_to_contact_cuts(
    enamel: np.ndarray,
    geoms: list[dict],
    col_L: np.ndarray,
) -> list[np.ndarray]:
    if len(geoms) == 1:
        return [geoms[0]["mask"]]
    h, w = enamel.shape
    cuts: list[int] = []
    for a, b in zip(geoms, geoms[1:]):
        x_lo = int(np.clip(min(a["cx"], a["x1"]), 0, w - 1))
        x_hi = int(np.clip(max(b["cx"], b["x0"]), 0, w - 1))
        if x_hi <= x_lo + 1:
            cuts.append(int(round(0.5 * (a["cx"] + b["cx"]))))
        else:
            cuts.append(x_lo + int(np.argmin(col_L[x_lo : x_hi + 1])))

    out: list[np.ndarray] = []
    for i, g in enumerate(geoms):
        x_left = 0 if i == 0 else cuts[i - 1]
        x_right = w if i == len(geoms) - 1 else cuts[i]
        m = g["mask"].copy()
        if i > 0:
            m[:, :x_left] = False
        if i < len(geoms) - 1:
            m[:, x_right:] = False

        y0 = max(0, g["y0"] - int(0.08 * g["h"]))
        y1 = min(h, g["y1"] + int(0.08 * g["h"]))
        if i > 0:
            y0 = min(y0, geoms[i - 1]["y0"])
            y1 = max(y1, geoms[i - 1]["y1"])
        if i < len(geoms) - 1:
            y0 = min(y0, geoms[i + 1]["y0"])
            y1 = max(y1, geoms[i + 1]["y1"])
        y0, y1 = max(0, y0), min(h, y1)

        inner_lo, inner_hi = x_left, x_right
        if i == 0:
            inner_lo = max(x_left, g["x0"])
        if i == len(geoms) - 1:
            inner_hi = min(x_right, g["x1"] + 1)

        fill = np.zeros_like(enamel, dtype=bool)
        if inner_hi > inner_lo:
            fill[y0:y1, inner_lo:inner_hi] = enamel[y0:y1, inner_lo:inner_hi]
        grown = m | fill
        kept = _largest_cc(grown)
        if kept is not None and int(kept.sum()) >= 40:
            out.append(kept)
        elif int(m.sum()) >= 40:
            out.append(m)
        else:
            out.append(g["mask"])
    return out


def _fill_to_contact_cuts(
    enamel: np.ndarray,
    masks: list[np.ndarray],
    lum: np.ndarray,
) -> list[np.ndarray]:
    """Clip neighbour spill at dark contacts; fill inward only (no cheek growth)."""
    if len(masks) < 2 or lum.shape[:2] != enamel.shape:
        return masks
    geoms = [_mask_geom(m) for m in masks if np.any(m)]
    if len(geoms) < 2:
        return masks
    col_L = _column_enamel_luma(enamel, lum)
    out: list[np.ndarray] = []
    for row in _cluster_masks_by_row(geoms):
        out.extend(_fill_row_to_contact_cuts(enamel, row, col_L))
    return out


def _trim_incisal_dark(
    band: np.ndarray, masks: list[np.ndarray]
) -> list[np.ndarray]:
    """Peel only dark oral-cavity pixels on the biting-edge fringe."""
    import cv2

    if not masks:
        return masks
    u8 = np.clip(band, 0, 255).astype(np.uint8)
    lab = cv2.cvtColor(u8, cv2.COLOR_RGB2LAB).astype(np.float64)
    L = lab[:, :, 0]
    h = L.shape[0]
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    out: list[np.ndarray] = []
    for mask in masks:
        if not np.any(mask):
            continue
        eroded = cv2.erode((mask.astype(np.uint8)) * 255, k, iterations=1) > 0
        body = eroded if int(eroded.sum()) >= 25 else mask
        body_L = float(np.median(L[body]))
        ys, _xs = np.nonzero(mask)
        y0, y1 = int(ys.min()), int(ys.max())
        cy = float(ys.mean())
        incisal_down = cy < 0.58 * h
        span = max(1, y1 - y0 + 1)
        fringe_h = max(2, int(0.16 * span))
        trimmed = mask.copy()
        fringe = mask.copy()
        if incisal_down:
            fringe[: y1 - fringe_h + 1, :] = False
        else:
            fringe[y0 + fringe_h :, :] = False
        drop = fringe & (L < max(68.0, 0.60 * body_L))
        trimmed[drop] = False
        if int(trimmed.sum()) >= 40:
            out.append(trimmed)
        else:
            out.append(mask)
    return out


def _active_contour_refine_one(
    gray: np.ndarray, mask: np.ndarray, enamel: np.ndarray
) -> np.ndarray:
    """Optional morph-GAC snap to image edges after GrabCut (does not replace it)."""
    if not np.any(mask):
        return mask
    try:
        from skimage.segmentation import (
            inverse_gaussian_gradient,
            morphological_geodesic_active_contour,
        )
    except ImportError:
        return mask

    g = gray.astype(np.float64)
    if g.max() > 1.0:
        g = g / 255.0
    # Restrict energy to enamel neighborhood so snakes don't leak onto skin
    import cv2

    allow = enamel.astype(bool) | mask
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    allow = cv2.dilate(allow.astype(np.uint8), k, iterations=1) > 0
    edge = inverse_gaussian_gradient(g)
    edge = np.where(allow, edge, 1.0)  # high cost outside → snake stays in
    init = mask.astype(np.int8)
    try:
        ls = morphological_geodesic_active_contour(
            edge,
            num_iter=35,
            init_level_set=init,
            smoothing=1,
            balloon=-1,
        )
    except Exception:
        return mask
    out = (ls > 0) & allow
    if int(out.sum()) < 40:
        return mask
    # Keep largest blob
    kept = _largest_cc(out)
    return mask if kept is None else kept


# ---------------------------------------------------------------------------
# 8) Sanity rejects
# ---------------------------------------------------------------------------


def _sanity_check_instances(teeth: list[ToothMask]) -> list[ToothMask]:
    """Flag implausible masks instead of silently accepting them."""
    if not teeth:
        return teeth

    areas = [int(t.mask.sum()) for t in teeth]
    widths = []
    heights = []
    for t in teeth:
        ys, xs = np.nonzero(t.mask)
        widths.append(int(xs.max() - xs.min() + 1) if xs.size else 0)
        heights.append(int(ys.max() - ys.min() + 1) if ys.size else 0)
    med_a = float(np.median(areas)) if areas else 1.0
    med_w = float(np.median(widths)) if widths else 1.0
    med_h = float(np.median(heights)) if heights else 1.0

    # Pairwise overlap
    overlaps: set[int] = set()
    for i in range(len(teeth)):
        for j in range(i + 1, len(teeth)):
            inter = int(np.logical_and(teeth[i].mask, teeth[j].mask).sum())
            if inter <= 0:
                continue
            union_min = min(areas[i], areas[j])
            if union_min > 0 and inter / float(union_min) > 0.15:
                overlaps.add(i)
                overlaps.add(j)

    out: list[ToothMask] = []
    for i, t in enumerate(teeth):
        reason = None
        ys, xs = np.nonzero(t.mask)
        ht = int(ys.max() - ys.min() + 1) if ys.size else 0
        wd = int(xs.max() - xs.min() + 1) if xs.size else 0
        if areas[i] < 0.2 * med_a:
            reason = "too_small"
        elif widths[i] > 2.5 * med_w and widths[i] > med_w + 4:
            reason = "too_wide_merged"
        elif (
            med_h > 0
            and ht >= 1.85 * med_h
            and ht >= 2.6 * max(wd, 1)
        ):
            reason = "too_tall_merged"
        elif i in overlaps:
            reason = "overlap"
        if reason:
            out.append(
                ToothMask(
                    tooth_index=t.tooth_index,
                    mask=t.mask,
                    confidence=min(t.confidence, 0.25),
                    rejected=True,
                    reject_reason=reason,
                )
            )
        else:
            out.append(t)
    return out


def mask_confidence(refined: np.ndarray, band_h: int) -> float:
    """Segmentation quality from mask fill + height vs gum band (not shade ΔE)."""
    ys, xs = np.nonzero(refined)
    if ys.size == 0:
        return 0.0
    area = int(ys.size)
    bw_box = int(xs.max() - xs.min() + 1)
    bh_box = int(ys.max() - ys.min() + 1)
    fill = area / float(max(1, bw_box * bh_box))
    return float(
        round(
            np.clip(
                0.35 * min(1.0, fill / 0.55)
                + 0.65 * min(1.0, bh_box / max(12.0, 0.25 * band_h)),
                0.0,
                0.99,
            ),
            3,
        )
    )


def _confidence(refined: np.ndarray, band_h: int) -> float:
    return mask_confidence(refined, band_h)

"""Regression: KAIST scikit-fmm contiguous-slice compat patch."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np


def test_skfmm_stacked_slices_stay_independent():
    backend = Path(__file__).resolve().parents[2]
    vendor = backend / "vendor" / "individual_tooth_segmentation"
    if not (vendor / "src" / "reinitial.py").is_file():
        return  # vendor not checked out

    sys.path.insert(0, str(vendor))
    from app.ai.kaist_compat import patch_kaist_vendor

    patch_kaist_vendor()
    from src.reinitial import Reinitial

    h, w = 64, 80
    stack = np.ones((3, h, w), dtype=float)
    # three different negative regions
    stack[0, 10:30, 10:25] = -1
    stack[1, 20:40, 40:55] = -1
    stack[2, 35:50, 15:35] = -1

    rein = Reinitial(width=5, dim_stack=0, fmm=True)
    out = rein.getSDF(stack)
    masks = [(out[i] < 0) for i in range(3)]
    assert all(m.any() for m in masks)
    # Without the patch all channels collapse to the same region
    assert not np.array_equal(masks[0], masks[1])
    assert not np.array_equal(masks[1], masks[2])
    assert not np.array_equal(masks[0], masks[2])

    import src.myTools as mts

    assert mts.saveFile({"x": 1}, "/no/such.pth") == 0

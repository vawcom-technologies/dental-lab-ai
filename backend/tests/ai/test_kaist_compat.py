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


def test_torch_numpy_bridge_roundtrip():
    from app.ai.kaist_compat import patch_torch_numpy_bridge

    patch_torch_numpy_bridge()
    import torch
    import torchvision.transforms.functional as TF
    from PIL import Image

    src = np.arange(24, dtype=np.uint8).reshape(2, 4, 3)
    tensor = torch.from_numpy(src)
    assert tuple(tensor.shape) == (2, 4, 3)
    back = tensor.numpy()
    assert back.dtype == np.uint8
    assert np.array_equal(back, src)

    if torch.backends.mps.is_available():
        mps = tensor.to("mps").float()
        arr = mps.numpy()
        assert arr.shape == (2, 4, 3)

    pic = Image.fromarray(np.zeros((16, 20, 3), dtype=np.uint8))
    t = TF.to_tensor(pic)
    assert tuple(t.shape) == (3, 16, 20)
    assert t.dtype == torch.float32
    hwc = t.permute(1, 2, 0).numpy()
    assert hwc.shape == (16, 20, 3)


def test_tem_remove_side_empty_labels():
    backend = Path(__file__).resolve().parents[2]
    vendor = backend / "vendor" / "individual_tooth_segmentation"
    if not (vendor / "src" / "teethSeg.py").is_file():
        return

    sys.path.insert(0, str(vendor))
    from app.ai.kaist_compat import patch_kaist_vendor

    patch_kaist_vendor()
    from src.teethSeg import TEM

    img = np.zeros((8, 8, 3), dtype=float)
    lbl = np.zeros((8, 8), dtype=float)
    out = TEM.removeSide(img, lbl)
    assert out.shape == (8, 8)
    assert np.array_equal(out, lbl)

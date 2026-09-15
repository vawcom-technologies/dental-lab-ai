"""Compatibility shims for KAIST upstream on modern deps.

1) scikit-fmm contiguous channel slices (getSDF)
2) Configurable Snake / InitContour iteration caps (speed)
3) Cache ResNeSt weights in memory (skip 1.5GB reload every photo)
4) Skip pickle / matplotlib / contour-viz IO (not used by the API)
5) Torch 2.2 ↔ NumPy 2 bridge (from_numpy / Tensor.numpy)
"""

from __future__ import annotations

import ctypes
import logging
from typing import Any

import numpy as np

logger = logging.getLogger(__name__)

_model_cache: dict[tuple[str, str], Any] = {}

_NP_TO_TH = {
    np.dtype(np.float32): "float32",
    np.dtype(np.float64): "float64",
    np.dtype(np.float16): "float16",
    np.dtype(np.uint8): "uint8",
    np.dtype(np.int8): "int8",
    np.dtype(np.int16): "int16",
    np.dtype(np.int32): "int32",
    np.dtype(np.int64): "int64",
    np.dtype(np.bool_): "bool",
}
_TH_TO_CT = {
    "uint8": (ctypes.c_uint8, np.uint8),
    "int8": (ctypes.c_int8, np.int8),
    "int16": (ctypes.c_int16, np.int16),
    "int32": (ctypes.c_int32, np.int32),
    "int64": (ctypes.c_int64, np.int64),
    "float32": (ctypes.c_float, np.float32),
    "float64": (ctypes.c_double, np.float64),
    "float16": (ctypes.c_uint16, np.uint16),
    "bool": (ctypes.c_uint8, np.uint8),
}


def ensure_kaist_numpy_shims() -> None:
    """Vendor myTools.py imports numpy.lib.function_base (removed in NumPy 2.3+)."""
    import sys
    import types

    import numpy as np

    if "numpy.lib.function_base" in sys.modules:
        return
    try:
        import numpy.lib.function_base  # noqa: F401
        return
    except ModuleNotFoundError:
        pass

    mod = types.ModuleType("numpy.lib.function_base")
    mod.iterable = getattr(np, "iterable", lambda x: True)
    sys.modules["numpy.lib.function_base"] = mod
    lib = sys.modules.get("numpy.lib")
    if lib is not None and not hasattr(lib, "function_base"):
        lib.function_base = mod  # type: ignore[attr-defined]


def _ndarray_to_tensor(arr: np.ndarray) -> Any:
    """np.ndarray → torch.Tensor without Torch's broken NumPy 2 C API."""
    import torch

    arr = np.ascontiguousarray(arr)
    name = _NP_TO_TH.get(arr.dtype)
    if name is None:
        arr = np.ascontiguousarray(arr, dtype=np.float32)
        name = "float32"
    dtype = getattr(torch, name)
    if arr.size == 0:
        return torch.empty(arr.shape, dtype=dtype)
    tensor = torch.frombuffer(memoryview(arr), dtype=dtype).reshape(arr.shape)
    return tensor.clone()


def _tensor_to_ndarray(tensor: Any) -> np.ndarray:
    """torch.Tensor → np.ndarray without Torch's broken NumPy 2 C API."""
    import torch

    t = tensor.detach()
    if t.device.type != "cpu":
        t = t.cpu()
    t = t.contiguous()
    name = str(t.dtype).removeprefix("torch.")
    if name not in _TH_TO_CT:
        t = t.to(dtype=torch.float32)
        name = "float32"
    ctype, np_dtype = _TH_TO_CT[name]
    if t.numel() == 0:
        return np.empty(tuple(t.shape), dtype=np.bool_ if name == "bool" else np_dtype)
    buf = (ctype * t.numel()).from_address(t.data_ptr())
    out = np.ctypeslib.as_array(buf).reshape(tuple(t.shape)).copy()
    if name == "bool":
        return out.astype(np.bool_, copy=False)
    if name == "float16":
        return out.view(np.float16)
    return out


def patch_torch_numpy_bridge() -> None:
    """Torch 2.2 was built against NumPy 1.x; from_numpy / Tensor.numpy raise.

    KAIST's torchvision `to_tensor` and PseudoER `.numpy()` both need this.
    """
    import warnings

    with warnings.catch_warnings():
        warnings.filterwarnings("ignore")
        import torch

    if getattr(torch, "_dental_lab_numpy_bridge", False):
        return

    _orig_from_numpy = torch.from_numpy
    _orig_tensor_numpy = torch.Tensor.numpy

    def from_numpy(arr):  # noqa: ANN001
        try:
            return _orig_from_numpy(arr)
        except RuntimeError:
            return _ndarray_to_tensor(np.asarray(arr))

    def tensor_numpy(self, *args, **kwargs):  # noqa: ANN001
        try:
            return _orig_tensor_numpy(self, *args, **kwargs)
        except RuntimeError:
            return _tensor_to_ndarray(self)

    torch.from_numpy = from_numpy  # type: ignore[method-assign]
    torch.Tensor.numpy = tensor_numpy  # type: ignore[method-assign]
    torch._dental_lab_numpy_bridge = True
    logger.info("kaist torch↔numpy bridge enabled (Torch 2.2 / NumPy 2)")


def clear_kaist_model_cache() -> None:
    _model_cache.clear()


def _silence_kaist_io() -> None:
    """Drop disk/matplotlib side effects — API only needs TEM labels."""
    import src.myTools as mts
    from src.makeup import TeethSeg
    from src.teethSeg import TEM

    if getattr(mts, "_dental_lab_io_silent", False):
        return

    mts.saveFile = lambda *_a, **_k: 0
    mts.SaveTools.saveFile = lambda *_a, **_k: 0
    mts.SaveTools.imwrite = lambda *_a, **_k: None
    mts.SaveTools.imshow = lambda *_a, **_k: None
    mts.SaveTools.imshows = lambda *_a, **_k: None
    mts.SaveTools.imcontour = lambda *_a, **_k: None
    mts.SaveTools.savecfg = lambda *_a, **_k: None

    def tem(self):
        img, phi_res = self._dt["img"], self._dt["phi_res"]
        ir = TEM(img, phi_res)
        self._dt.update({"lbl_reg": ir.lbl_reg, "res": ir.res})

    TeethSeg.tem = tem

    if not getattr(TEM, "_dental_lab_remove_side", False):
        _remove_side = TEM.removeSide

        @staticmethod
        def removeSide(img, lbl):  # noqa: N802
            idx = np.where(lbl > 0)
            if idx[0].size == 0:
                return np.copy(lbl)
            return _remove_side(img, lbl)

        TEM.removeSide = removeSide
        TEM._dental_lab_remove_side = True

    mts._dental_lab_io_silent = True


def patch_kaist_vendor(
    *,
    snake_iters: int | None = None,
    bring_back_iters: int | None = None,
    evolve_iters: int | None = None,
) -> None:
    ensure_kaist_numpy_shims()
    patch_torch_numpy_bridge()
    import skfmm
    from src.reinitial import Reinitial
    from src.teethSeg import InitContour, PseudoER, Snake

    if not getattr(Reinitial, "_dental_lab_patched", False):
        _orig = Reinitial.getSDF

        def getSDF(self, img):  # noqa: N802
            if not self.fmm:
                return _orig(self, img)

            x = np.asarray(img)
            if self.dim_stack == 0 and x.ndim == 3:
                x = x.transpose((1, 2, 0))

            if self.dim == 2 and x.ndim == 3:
                phi = np.empty(x.shape, dtype=float)
                for i in range(x.shape[-1]):
                    sl = np.ascontiguousarray(x[..., i], dtype=float)
                    if np.any(sl < 0):
                        phi[..., i] = np.asarray(
                            skfmm.distance(sl, dx=1), dtype=float
                        )
                    else:
                        phi[..., i] = sl
                if self.dim_stack == 0:
                    phi = phi.transpose((2, 0, 1))
                return phi

            sl = np.ascontiguousarray(x, dtype=float)
            if np.any(sl < 0):
                return np.asarray(skfmm.distance(sl, dx=1), dtype=float)
            return sl

        Reinitial.getSDF = getSDF
        Reinitial._dental_lab_patched = True

    _silence_kaist_io()

    if not getattr(PseudoER, "_dental_lab_model_cache", False):
        _set_model = PseudoER.setModel

        def setModel(self):  # noqa: N802
            key = (
                str(self.config.get("MODEL", {}).get("WEIGHTS", "")),
                str(self.dvc_main),
            )
            cached = _model_cache.get(key)
            if cached is not None:
                return cached
            net = _set_model(self)
            _model_cache[key] = net
            logger.info("kaist model cached key=%s", key[0][-48:])
            return net

        PseudoER.setModel = setModel
        PseudoER._dental_lab_model_cache = True

    if snake_iters is not None and snake_iters > 0:
        iters = int(snake_iters)
        if getattr(Snake, "_dental_lab_snake_iters", None) != iters:
            _snake_orig = getattr(Snake, "_dental_lab_snake_orig", None)
            if _snake_orig is None:
                _snake_orig = Snake.snake
                Snake._dental_lab_snake_orig = _snake_orig

            def snake(self, dt=0.2, mu=2, tol=2, dist=1, max_iter=iters, reinterm=5):
                return _snake_orig(
                    self,
                    dt=dt,
                    mu=mu,
                    tol=tol,
                    dist=dist,
                    max_iter=max_iter,
                    reinterm=reinterm,
                )

            Snake.snake = snake
            Snake._dental_lab_snake_iters = iters

    bb = int(bring_back_iters) if bring_back_iters else 200
    ev = int(evolve_iters) if evolve_iters else 60
    key = (bb, ev)
    if getattr(InitContour, "_dental_lab_init_iters", None) != key:
        _init_orig = getattr(InitContour, "_dental_lab_init_orig", None)
        if _init_orig is None:
            _init_orig = InitContour.__init__
            InitContour._dental_lab_init_orig = _init_orig

        def __init__(self, img, per0):
            self.img = img
            self.per0 = per0
            self.m, self.n = self.per0.shape
            self.preset()
            import src.myTools as mts
            from src.reinitial import Reinitial as Rein

            self.per = mts.imDilErod(
                self.per,
                rad=max(round(self.wid_er / 2), 1),
                kernel_type="circular",
            )
            rein_all = Rein(width=None, fmm=True)
            self.rein_w5 = Rein(width=5, dim_stack=0, fmm=False)
            self.rein_w5_fmm = Rein(width=5, dim_stack=0, fmm=True)
            self.phi_per = rein_all.getSDF(self.per - 0.5)
            lmk = self.getLandMarks(self.phi_per)
            self.phi_lmk = self.rein_w5_fmm.getSDF(
                0.5 - (lmk[np.newaxis, ...] < 0)
            )
            self.phi_back = self.bringBack(
                self.phi_lmk,
                self.per,
                gap=8,
                dt=0.3,
                mu=2,
                nu=1,
                reinterm=3,
                tol=2,
                max_iter=bb,
            )
            reg_sep = self.sepRegions(self.phi_back)
            phi_sep = self.rein_w5.getSDF(0.5 - np.array(reg_sep))
            self.phi0 = self.evolve(
                phi_sep,
                self.per,
                dt=0.3,
                mu=2,
                nu=1,
                reinterm=3,
                tol=2,
                max_iter=ev,
            )

        InitContour.__init__ = __init__
        InitContour._dental_lab_init_iters = key

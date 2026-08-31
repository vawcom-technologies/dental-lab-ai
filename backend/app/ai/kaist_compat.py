"""Compatibility shims for KAIST upstream on modern deps.

1) scikit-fmm contiguous channel slices (getSDF)
2) Configurable Snake / InitContour iteration caps (speed)
3) Cache ResNeSt weights in memory (skip 1.5GB reload every photo)
4) Skip pickle / matplotlib / contour-viz IO (not used by the API)
"""

from __future__ import annotations

import logging
from typing import Any

import numpy as np

logger = logging.getLogger(__name__)

_model_cache: dict[tuple[str, str], Any] = {}


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
    mts._dental_lab_io_silent = True


def patch_kaist_vendor(
    *,
    snake_iters: int | None = None,
    bring_back_iters: int | None = None,
    evolve_iters: int | None = None,
) -> None:
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

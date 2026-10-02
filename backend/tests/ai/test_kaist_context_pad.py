import numpy as np

from app.ai import shade_segment_kaist as k
from app.ai.shade_segment import ToothMask


def _tooth(shape, rejected=False):
    m = np.zeros(shape, bool)
    m[30:60, 40:90] = True
    return ToothMask(0, m, 1.0, rejected)


def test_camera_path_keeps_variant_with_most_usable_teeth(monkeypatch):
    calls = []

    def fake(img, **kw):
        calls.append((img.shape[:2], kw.get("crop", True)))
        if img.shape[:2] == (150, 300):  # padded run: finds 3 teeth
            return [_tooth(img.shape[:2]) for _ in range(3)]
        if not kw.get("crop", True):  # no-ROI run: 1 usable + 1 rejected
            return [_tooth(img.shape[:2]), _tooth(img.shape[:2], rejected=True)]
        return [_tooth(img.shape[:2])]  # plain

    monkeypatch.setattr(k, "detect_teeth_kaist", fake)
    out = k._detect_best_of_variants(np.zeros((100, 200, 3), np.uint8))
    assert len(out) == 3
    assert all(t.mask.shape == (100, 200) for t in out)  # un-padded back
    assert len(calls) == 3


def test_camera_path_survives_a_failing_variant(monkeypatch):
    def fake(img, **kw):
        if kw.get("crop", True) and img.shape[:2] == (100, 200):
            raise RuntimeError("boom")
        return [_tooth(img.shape[:2])]

    monkeypatch.setattr(k, "detect_teeth_kaist", fake)
    assert len(k._detect_best_of_variants(np.zeros((100, 200, 3), np.uint8))) == 1

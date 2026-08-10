"""Smoke check: Camera/GDPR photo cap stays at 12 (no heavy imports)."""

from pathlib import Path

_ROOT = Path(__file__).resolve().parents[2]


def test_photo_cap_is_twelve():
    gdpr = (_ROOT / "app/api/patients_gdpr.py").read_text(encoding="utf-8")
    legacy = (_ROOT / "app/api/photos.py").read_text(encoding="utf-8")
    assert "_MAX_PATIENT_PHOTOS = 12" in gdpr
    assert "MAX_PHOTOS = 12" in legacy


if __name__ == "__main__":
    test_photo_cap_is_twelve()
    print("ok")

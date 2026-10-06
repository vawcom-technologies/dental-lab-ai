from pathlib import Path

import pytest
from fastapi import HTTPException

from app.services.r2 import LOCAL_PHOTO_URL_PREFIX, LOCAL_PHOTO_ROOT
from app.services.shade_media import load_media_bytes


def test_camera_photo_from_local_disk(tmp_path, monkeypatch):
    pid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    name = "photo.jpg"
    dest = LOCAL_PHOTO_ROOT / pid
    dest.mkdir(parents=True, exist_ok=True)
    payload = b"\xff\xd8\xfffake-jpeg"
    (dest / name).write_bytes(payload)
    try:
        row = {
            "patient_id": pid,
            "file_url": f"{LOCAL_PHOTO_URL_PREFIX}/{pid}/{name}",
            "file_key": f"{pid}/{name}",
        }
        assert load_media_bytes("photos", row) == payload
    finally:
        (dest / name).unlink(missing_ok=True)


def test_missing_local_camera_photo_is_404():
    row = {
        "patient_id": "missing-patient",
        "file_url": f"{LOCAL_PHOTO_URL_PREFIX}/missing-patient/nope.jpg",
        "file_key": "missing-patient/nope.jpg",
    }
    with pytest.raises(HTTPException) as exc:
        load_media_bytes("photos", row)
    assert exc.value.status_code == 404

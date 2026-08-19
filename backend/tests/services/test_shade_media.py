from pathlib import Path

import pytest
from fastapi import HTTPException

from app.services.r2 import LOCAL_PHOTO_URL_PREFIX, LOCAL_PHOTO_ROOT
from app.services.shade_media import load_shade_detection_bytes


def test_load_shade_detection_bytes_from_local_disk(tmp_path, monkeypatch):
    pid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    name = "photo.jpg"
    dest = LOCAL_PHOTO_ROOT / pid
    dest.mkdir(parents=True, exist_ok=True)
    payload = b"\xff\xd8\xfffake-jpeg"
    (dest / name).write_bytes(payload)
    try:
        row = {
            "file_url": f"{LOCAL_PHOTO_URL_PREFIX}/{pid}/{name}",
            "file_key": f"{pid}/{name}",
        }
        assert load_shade_detection_bytes(row) == payload
    finally:
        (dest / name).unlink(missing_ok=True)


def test_load_shade_detection_bytes_missing_local_file():
    row = {
        "file_url": f"{LOCAL_PHOTO_URL_PREFIX}/missing-patient/nope.jpg",
        "file_key": "missing-patient/nope.jpg",
    }
    with pytest.raises(HTTPException) as exc:
        load_shade_detection_bytes(row)
    assert exc.value.status_code == 404

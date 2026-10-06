"""Shade save: content-hash dedupe + camera photo copied into the shades bucket."""

import json

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import shade_detections as sd
from app.core.security import AuthUser, get_current_user
from app.services import patient_media as pm
from app.services import r2

PHOTO = {"id": "ph1", "patient_id": "p1", "filename": "front.jpg", "file_url": "https://img/patients/p1/photos/a.jpg"}


@pytest.fixture
def env(monkeypatch):
    rows, puts = [], []
    monkeypatch.setattr(r2, "bucket_for", lambda k: f"bucket-{k}")
    monkeypatch.setattr(r2, "get_r2_client", lambda: type("C", (), {"put_object": lambda self, **kw: puts.append(kw)})())
    monkeypatch.setattr(pm, "require_patient_access", lambda p, u: {})
    monkeypatch.setattr(pm, "find_row_by_key", lambda t, p, k: next((r for r in rows if (r["patient_id"], r["file_key"]) == (p, k)), None))
    monkeypatch.setattr(pm, "insert_row", lambda t, r: rows.append({**r, "id": f"s{len(rows)}"}) or rows[-1])
    monkeypatch.setattr(pm, "update_row", lambda t, i, patch: next(r for r in rows if r["id"] == i).update(patch) or next(r for r in rows if r["id"] == i))
    monkeypatch.setattr(pm, "fetch_row", lambda t, i: PHOTO if (t, i) == ("patient_photos", "ph1") else None)
    monkeypatch.setattr(sd, "load_media_bytes", lambda kind, row: b"CAMERA-JPEG")
    monkeypatch.setattr(pm.pa, "fetch_patient", lambda p: {})
    monkeypatch.setattr("app.services.notify.notify_clinical_upload", lambda *a, **k: None)
    app = FastAPI()
    app.include_router(sd.patients_router, prefix="/api/patients")
    app.dependency_overrides[get_current_user] = lambda: AuthUser("u1", "a@b.c", "A", "dentist")
    return TestClient(app), rows, puts


def test_same_image_twice_is_one_record_with_latest_analysis(env):
    client, rows, puts = env
    url = "/api/patients/p1/shade-detections"
    a = client.post(url, files={"file": ("t.jpg", b"JPEG", "image/jpeg")})
    b = client.post(url, files={"file": ("t.jpg", b"JPEG", "image/jpeg")}, data={"analysis": json.dumps({"final_shade": "A2"})})
    assert a.status_code == b.status_code == 201
    assert a.json()["id"] == b.json()["id"] and len(rows) == 1
    assert rows[0]["analysis"]["final_shade"] == "A2"
    assert rows[0]["file_key"].startswith("patients/p1/shades/")


def test_camera_photo_is_copied_into_shades_bucket(env):
    client, rows, puts = env
    r = client.post("/api/patients/p1/shade-detections", data={"photo_id": "ph1"})
    assert r.status_code == 201
    assert puts[0]["Bucket"] == "bucket-shades" and puts[0]["Body"] == b"CAMERA-JPEG"
    assert "/photos/" not in rows[0]["file_key"]


def test_other_patients_photo_and_empty_request_rejected(env):
    client, rows, _ = env
    assert client.post("/api/patients/p2/shade-detections", data={"photo_id": "ph1"}).status_code == 404
    assert client.post("/api/patients/p1/shade-detections").status_code == 400
    assert rows == []


def test_old_build_copy_to_shade_makes_a_real_copy_once(env, monkeypatch):
    from app.api import camera_photos as cp

    client, rows, puts = env
    monkeypatch.setattr(cp, "_fetch_photo", lambda i: PHOTO)
    monkeypatch.setattr(cp, "load_media_bytes", lambda kind, row: b"CAMERA-JPEG")
    app = FastAPI()
    app.include_router(cp.router, prefix="/api/patient-photos")
    app.dependency_overrides[get_current_user] = lambda: AuthUser("u1", "a@b.c", "A", "dentist")
    old_build = TestClient(app)
    a = old_build.post("/api/patient-photos/ph1/copy-to-shade")
    b = old_build.post("/api/patient-photos/ph1/copy-to-shade")
    assert a.status_code == b.status_code == 201 and a.json()["id"] == b.json()["id"]
    assert len(rows) == 1 and rows[0]["file_key"].startswith("patients/p1/shades/")
    assert puts[0]["Bucket"] == "bucket-shades"

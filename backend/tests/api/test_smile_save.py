"""Smile save: composite + base photo + placements; update swaps the composite;
delete keeps a base photo another saved smile still uses."""

import json

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import smile_previews as sp
from app.core.security import AuthUser, get_current_user
from app.services import patient_media as pm
from app.services import r2

PHOTO = {"id": "ph1", "patient_id": "p1", "filename": "front.jpg", "file_url": "https://img/patients/p1/photos/a.jpg"}
OVERLAY = {"shapes": [{"shape_id": "shape_03", "x": 0.4, "y": 0.5}]}


@pytest.fixture
def env(monkeypatch):
    rows, objects, deleted = [], set(), []
    monkeypatch.setattr(r2, "bucket_for", lambda k: (f"bucket-{k}", "https://pub"))
    monkeypatch.setattr(r2, "get_r2_client", lambda: type("C", (), {"put_object": lambda self, **kw: objects.add(kw["Key"])})())
    monkeypatch.setattr(pm, "delete_patient_asset", lambda kind, file_key: deleted.append(file_key))
    monkeypatch.setattr(pm, "require_patient_access", lambda p, u: {})
    monkeypatch.setattr(pm, "list_rows", lambda t, p: [r for r in rows if r["patient_id"] == p])
    monkeypatch.setattr(pm, "find_row_by_key", lambda t, p, k: next((r for r in rows if (r["patient_id"], r["file_key"]) == (p, k)), None))
    monkeypatch.setattr(pm, "insert_row", lambda t, r: rows.append({**r, "id": f"s{len(rows)}"}) or rows[-1])

    def update(t, i, patch):
        row = next(r for r in rows if r["id"] == i)
        row.update(patch)
        return row

    def fetch(t, i):
        if t == "patient_photos":
            return PHOTO if i == "ph1" else None
        return next((r for r in rows if r["id"] == i), None)

    def delete_row(t, i):
        rows[:] = [r for r in rows if r["id"] != i]

    monkeypatch.setattr(pm, "update_row", update)
    monkeypatch.setattr(pm, "fetch_row", fetch)
    monkeypatch.setattr(pm, "delete_row", delete_row)
    monkeypatch.setattr(sp, "load_media_bytes", lambda kind, row: b"CAMERA-JPEG")
    monkeypatch.setattr(pm.pa, "fetch_patient", lambda p: {})
    monkeypatch.setattr("app.services.notify.notify_clinical_upload", lambda *a, **k: None)
    app = FastAPI()
    app.include_router(sp.patients_router, prefix="/api/patients")
    app.include_router(sp.smiles_router, prefix="/api/smile-previews")
    app.dependency_overrides[get_current_user] = lambda: AuthUser("u1", "a@b.c", "A", "dentist")
    return TestClient(app), rows, deleted


def _create(client, composite=b"COMPOSITE"):
    return client.post(
        "/api/patients/p1/smile-previews",
        files={"file": ("smile.jpg", composite, "image/jpeg")},
        data={"base_photo_id": "ph1", "overlay": json.dumps(OVERLAY)},
    )


def test_save_stores_composite_base_and_placements(env):
    client, rows, _ = env
    r = _create(client)
    assert r.status_code == 201
    row = rows[0]
    assert row["file_key"].startswith("patients/p1/smiles/")
    assert row["base_file_key"].startswith("patients/p1/smiles/") and row["base_file_key"] != row["file_key"]
    assert r.json()["overlay"] == OVERLAY


def test_update_swaps_composite_and_drops_old_one(env):
    client, rows, deleted = env
    _create(client)
    old = rows[0]["file_key"]
    r = client.patch(
        f"/api/smile-previews/{rows[0]['id']}",
        files={"file": ("smile.jpg", b"COMPOSITE-2", "image/jpeg")},
        data={"overlay": json.dumps({"shapes": []})},
    )
    assert r.status_code == 200 and len(rows) == 1
    assert rows[0]["file_key"] != old and rows[0]["overlay"] == {"shapes": []}
    assert deleted == [old]


def test_first_save_of_earlier_photo_keeps_it_as_base(env):
    client, rows, deleted = env
    rows.append({"id": "old", "patient_id": "p1", "uploaded_by": "u1", "file_key": "patients/p1/smiles/photo.jpg", "file_url": "x", "file_name": "photo.jpg"})
    r = client.patch(
        "/api/smile-previews/old",
        files={"file": ("smile.jpg", b"COMPOSITE", "image/jpeg")},
        data={"overlay": json.dumps(OVERLAY)},
    )
    assert r.status_code == 200
    assert rows[0]["base_file_key"] == "patients/p1/smiles/photo.jpg"
    assert rows[0]["file_key"] != "patients/p1/smiles/photo.jpg" and deleted == []


def test_delete_keeps_base_shared_with_another_smile(env):
    client, rows, deleted = env
    _create(client, b"A")
    _create(client, b"B")  # same camera photo, different overlay
    base = rows[0]["base_file_key"]
    assert client.delete(f"/api/smile-previews/{rows[0]['id']}").status_code == 200
    assert base not in deleted
    assert client.delete(f"/api/smile-previews/{rows[0]['id']}").status_code == 200
    assert base in deleted

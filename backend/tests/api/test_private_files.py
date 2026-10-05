"""Private patient files: URL switch + access-checked download endpoint."""

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from app.api import files
from app.core.config import settings
from app.core.security import AuthUser, get_current_user
from app.services import file_urls

ROW = {"id": "r1", "patient_id": "p1", "file_url": "https://pub.example/k.ply", "file_key": "k.ply", "file_name": "scan.ply"}


def test_client_file_url_switches_per_kind(monkeypatch):
    monkeypatch.setattr(settings, "private_file_kinds", "scans, smiles")
    assert file_urls.client_file_url("scans", ROW) == "/api/files/scans/r1"
    assert file_urls.client_file_url("photos", ROW) == ROW["file_url"]  # not switched on
    monkeypatch.setattr(settings, "private_file_kinds", "")
    assert file_urls.client_file_url("scans", ROW) == ROW["file_url"]  # rollback


@pytest.fixture
def client(monkeypatch):
    app = FastAPI()
    app.include_router(files.router, prefix="/api/files")
    app.dependency_overrides[get_current_user] = lambda: AuthUser("u1", "a@b.c", "A", "dentist")
    monkeypatch.setattr(files.pm, "fetch_row", lambda t, i: ROW if i == "r1" else None)
    monkeypatch.setattr(files, "_require_patient_bucket", lambda k: ("bucket", "https://pub.example"))
    monkeypatch.setattr(files, "download_r2_object_bytes", lambda b, k: b"MESH" if (b, k) == ("bucket", "k.ply") else b"")
    monkeypatch.setattr(files.pm, "require_patient_access", lambda p, u: {})
    return TestClient(app)


def test_owner_gets_file(client):
    r = client.get("/api/files/scans/r1")
    assert r.status_code == 200 and r.content == b"MESH"


def test_no_access_is_forbidden(client, monkeypatch):
    def deny(p, u):
        raise HTTPException(403, "no")

    monkeypatch.setattr(files.pm, "require_patient_access", deny)
    assert client.get("/api/files/scans/r1").status_code == 403


def test_unknown_kind_and_missing_row_404(client):
    assert client.get("/api/files/nope/r1").status_code == 404
    assert client.get("/api/files/scans/missing").status_code == 404


def test_smile_copied_from_camera_photo_reads_patient_images_bucket(client, monkeypatch):
    row = {**ROW, "file_url": "https://img.example/patients/p1/photos/a.jpg", "file_key": "patients/p1/photos/a.jpg", "file_name": "a.jpg"}
    monkeypatch.setattr(files.pm, "fetch_row", lambda t, i: row)
    monkeypatch.setattr(files, "is_patient_images_url", lambda u: u.startswith("https://img.example"))
    monkeypatch.setattr(files, "load_shade_detection_bytes", lambda r: b"PHOTO")
    # smiles bucket would 502 for this key; must not be consulted
    monkeypatch.setattr(files, "download_r2_object_bytes", lambda b, k: (_ for _ in ()).throw(AssertionError("wrong bucket")))
    r = client.get("/api/files/smiles/r1")
    assert r.status_code == 200 and r.content == b"PHOTO"

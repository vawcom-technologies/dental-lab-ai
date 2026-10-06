"""Private patient files: URL switch + access-checked download endpoint."""

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from app.api import files
from app.core.config import settings
from app.core.security import AuthUser, get_current_user
from app.services import file_urls, shade_media

ROW = {"id": "r1", "patient_id": "p1", "file_url": "https://pub.example/k.ply", "file_key": "patients/p1/scans/k.ply", "file_name": "scan.ply"}


def test_client_file_url_switches_per_kind(monkeypatch):
    monkeypatch.setattr(settings, "private_file_kinds", "scans, smiles")
    assert file_urls.client_file_url("scans", ROW) == "/api/files/scans/r1"
    assert file_urls.client_file_url("photos", ROW) == ROW["file_url"]  # not switched on
    monkeypatch.setattr(settings, "private_file_kinds", "")
    assert file_urls.client_file_url("scans", ROW) == ROW["file_url"]  # rollback


@pytest.fixture
def store(monkeypatch):
    """{(bucket, key): bytes}; buckets are named after their kind."""
    objects = {("bucket-scans", ROW["file_key"]): b"MESH"}
    monkeypatch.setattr(shade_media, "bucket_for", lambda k: (f"bucket-{k}", "https://pub"))

    def download(bucket, key):
        if (bucket, key) not in objects:
            raise HTTPException(404, "File not found")
        return objects[(bucket, key)]

    monkeypatch.setattr(shade_media, "download_r2_object_bytes", download)
    return objects


@pytest.fixture
def client(monkeypatch, store):
    app = FastAPI()
    app.include_router(files.router, prefix="/api/files")
    app.dependency_overrides[get_current_user] = lambda: AuthUser("u1", "a@b.c", "A", "dentist")
    monkeypatch.setattr(files.pm, "fetch_row", lambda t, i: ROW if i == "r1" else None)
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


def test_legacy_camera_pointer_reads_camera_bucket(store):
    store[("bucket-photos", "patients/p1/photos/a.jpg")] = b"PHOTO"
    row = {**ROW, "file_key": "patients/p1/photos/a.jpg"}
    assert shade_media.load_media_bytes("smiles", row) == b"PHOTO"


def test_key_outside_patient_folder_is_refused(store):
    # Another patient's file, even if it exists, is never read through this row.
    store[("bucket-scans", "patients/p2/scans/k.ply")] = b"OTHER"
    for key in ("patients/p2/scans/k.ply", "k.ply", ""):
        with pytest.raises(HTTPException) as exc:
            shade_media.load_media_bytes("scans", {**ROW, "file_key": key})
        assert exc.value.status_code == 404

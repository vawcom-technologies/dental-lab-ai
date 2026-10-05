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

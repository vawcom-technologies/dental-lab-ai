"""Scan quality is computed once server-side, stored on the row, and reused."""

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from app.ai.scan_quality import QUALITY_VERSION
from app.api import patient_scans
from app.core.security import AuthUser, get_current_user

KEY = "patients/p1/scans/k.ply"
GARBAGE = b"not a mesh at all"  # parses as "bad", so a result always exists


@pytest.fixture
def env(monkeypatch):
    rows = {"s1": {"id": "s1", "patient_id": "p1", "uploaded_by": "u1", "file_key": KEY,
                   "file_url": "x", "file_name": "scan.ply", "quality": None}}
    files = {KEY: GARBAGE}
    saved = []
    reads = []

    def load(kind, row):
        reads.append(row["file_key"])
        if row["file_key"] not in files:
            raise HTTPException(404, "File not found")
        return files[row["file_key"]]

    def update(table, row_id, patch):
        saved.append(patch)
        rows[row_id].update(patch)
        return rows[row_id]

    monkeypatch.setattr(patient_scans, "load_media_bytes", load)
    monkeypatch.setattr(patient_scans.pm, "fetch_row", lambda t, i: rows.get(i))
    monkeypatch.setattr(patient_scans.pm, "list_rows", lambda t, p: list(rows.values()))
    monkeypatch.setattr(patient_scans.pm, "update_row", update)
    monkeypatch.setattr(patient_scans.pm, "require_patient_access", lambda p, u: {})
    app = FastAPI()
    app.include_router(patient_scans.scans_router, prefix="/api/scans")
    app.include_router(patient_scans.patients_router, prefix="/api/patients")
    app.dependency_overrides[get_current_user] = lambda: AuthUser("u1", "a@b.c", "A", "dentist")
    return TestClient(app), rows, saved, reads


def test_unchecked_scan_is_validated_from_storage_and_saved(env):
    client, rows, saved, reads = env
    assert client.get("/api/patients/p1/scans").json()[0]["validation_result"] is None
    r = client.post("/api/scans/s1/validate").json()
    assert r["validation_result"] == "bad" and r["issues"]
    assert reads == [KEY] and saved[0]["quality"]["v"] == QUALITY_VERSION
    # Now the list carries it, with no further file reads.
    assert client.get("/api/patients/p1/scans").json()[0]["validation_result"] == "bad"
    client.post("/api/scans/s1/validate")
    assert reads == [KEY]


def test_result_from_older_checks_is_recomputed(env):
    client, rows, saved, reads = env
    rows["s1"]["quality"] = {"v": QUALITY_VERSION - 1, "result": "good"}
    assert client.get("/api/patients/p1/scans").json()[0]["validation_result"] is None
    assert client.post("/api/scans/s1/validate").json()["validation_result"] == "bad"
    assert reads == [KEY]


def test_failed_save_still_returns_the_result(env, monkeypatch):
    client, *_ = env

    def boom(*a):
        raise RuntimeError("column quality does not exist")

    monkeypatch.setattr(patient_scans.pm, "update_row", boom)
    r = client.post("/api/scans/s1/validate")
    assert r.status_code == 200 and r.json()["validation_result"] == "bad"


def test_missing_scan_is_404(env):
    client, *_ = env
    assert client.post("/api/scans/nope/validate").status_code == 404

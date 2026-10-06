"""Scan inbox: owner-only access, upload validation, assign keeps/loses the row correctly."""

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from app.api import scan_inbox as si
from app.core.security import AuthUser, get_current_user

ROW = {"id": "i1", "uploaded_by": "u1", "file_key": "u1/abc.ply", "file_name": "a.ply", "format": "ply", "byte_size": 3}


@pytest.fixture
def env(monkeypatch):
    s = {"rows": {"i1": dict(ROW)}, "scans": [], "copied": [], "deleted": [], "inbox_rows_deleted": []}
    app = FastAPI()
    app.include_router(si.router, prefix="/api/scan-inbox")
    app.dependency_overrides[get_current_user] = lambda: AuthUser("u1", "a@b.c", "A", "dentist")
    monkeypatch.setattr(si.pm, "fetch_row", lambda t, i: s["rows"].get(i))
    monkeypatch.setattr(si.pm, "require_patient_access", lambda p, u: {})
    monkeypatch.setattr(si, "copy_inbox_to", lambda kind, src_key, dst_key: s["copied"].append(dst_key))
    monkeypatch.setattr(si.pm, "find_row_by_key", lambda t, p, k: None)
    monkeypatch.setattr(si.pm, "insert_row", lambda t, row: s["scans"].append(row) or {"id": "s1", **row})
    monkeypatch.setattr(si, "delete_patient_asset", lambda kind, file_key: s["deleted"].append(file_key))
    monkeypatch.setattr(si.pm, "delete_row", lambda t, i: s["inbox_rows_deleted"].append(i))
    s["client"] = TestClient(app)
    return s


def test_assign_copies_to_patient_folder_then_removes_inbox_item(env):
    r = env["client"].post("/api/scan-inbox/i1/assign", json={"patient_id": "p1"})
    assert r.status_code == 200
    assert env["copied"] == ["patients/p1/scans/i1.ply"]
    assert env["scans"][0]["file_key"] == "patients/p1/scans/i1.ply"
    assert env["deleted"] == ["u1/abc.ply"] and env["inbox_rows_deleted"] == ["i1"]


def test_failed_assign_keeps_inbox_item(env, monkeypatch):
    def boom(t, row):
        raise HTTPException(502, "db")

    monkeypatch.setattr(si.pm, "insert_row", boom)
    r = env["client"].post("/api/scan-inbox/i1/assign", json={"patient_id": "p1"})
    assert r.status_code == 502
    assert env["deleted"] == ["patients/p1/scans/i1.ply"]  # copy rolled back, inbox object untouched
    assert env["inbox_rows_deleted"] == []


def test_other_users_item_is_404(env):
    env["rows"]["i1"]["uploaded_by"] = "someone-else"
    c = env["client"]
    assert c.post("/api/scan-inbox/i1/assign", json={"patient_id": "p1"}).status_code == 404
    assert c.delete("/api/scan-inbox/i1").status_code == 404
    assert c.get("/api/scan-inbox/i1/file").status_code == 404


def test_no_patient_access_blocks_assign(env, monkeypatch):
    def deny(p, u):
        raise HTTPException(403, "no")

    monkeypatch.setattr(si.pm, "require_patient_access", deny)
    assert env["client"].post("/api/scan-inbox/i1/assign", json={"patient_id": "p1"}).status_code == 403
    assert env["copied"] == []


def test_upload_rejects_bad_type_and_streams_valid(env, monkeypatch):
    c = env["client"]
    assert c.post("/api/scan-inbox", files={"file": ("x.exe", b"MZ")}).status_code == 400
    assert c.post("/api/scan-inbox", files={"file": ("x.pdf", b"%PDF")}).status_code == 400
    assert c.post("/api/scan-inbox", files={"file": ("renamed.jpg", b"MZ\x90\x00")}).status_code == 400
    assert c.post("/api/scan-inbox", files={"file": ("renamed.stl", b"MZ\x90\x00")}).status_code == 400
    sent = {}

    class C:
        def upload_fileobj(self, f, bucket, key, ExtraArgs=None):
            sent["data"], sent["key"] = f.read(), key

    from app.services import r2

    monkeypatch.setattr(r2, "get_r2_client", lambda: C())
    monkeypatch.setattr(r2, "bucket_for", lambda k: "b")
    r = c.post("/api/scan-inbox", files={"file": ("scan.ply", b"ply\nformat ascii 1.0\n")})
    assert r.status_code == 201, r.text
    assert sent["data"] == b"ply\nformat ascii 1.0\n" and sent["key"].startswith("u1/") and sent["key"].endswith(".ply")
    assert [r["file_key"] for r in env["scans"]] == [sent["key"]]  # one inbox row, no patient record


def test_photo_assign_goes_to_patient_photos(env, monkeypatch):
    env["rows"]["i1"].update(file_key="u1/abc.jpg", file_name="smile.jpg", format="jpg")

    class Q:  # patient_photos: no duplicate, 0 photos so far
        def __getattr__(self, n):
            return lambda *a, **k: self
        data = []

    monkeypatch.setattr(si, "get_supabase_admin", lambda: Q())
    monkeypatch.setattr(si.pa, "write_audit_log", lambda **k: None)
    r = env["client"].post("/api/scan-inbox/i1/assign", json={"patient_id": "p1", "angle": "left"})
    assert r.status_code == 200 and r.json()["kind"] == "photo"
    assert env["copied"] == ["patients/p1/photos/i1.jpg"]
    row = env["scans"][0]
    assert row["file_url"] == "patients/p1/photos/i1.jpg" and row["angle"] == "left"
    assert env["inbox_rows_deleted"] == ["i1"]

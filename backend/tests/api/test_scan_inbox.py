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
    monkeypatch.setattr(si, "copy_inbox_to_scans", lambda src_key, dst_key: s["copied"].append(dst_key))
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
    sent = {}

    class C:
        def upload_fileobj(self, f, bucket, key):
            sent["data"], sent["key"] = f.read(), key

    from app.services import r2

    monkeypatch.setattr(r2, "get_r2_client", lambda: C())
    monkeypatch.setattr(r2, "bucket_for", lambda k: "b")
    r = c.post("/api/scan-inbox", files={"file": ("scan.ply", b"PLYDATA")})
    assert r.status_code == 201, r.text
    assert sent["data"] == b"PLYDATA" and sent["key"].startswith("u1/") and sent["key"].endswith(".ply")
    assert [r["file_key"] for r in env["scans"]] == [sent["key"]]  # one inbox row, no patient record

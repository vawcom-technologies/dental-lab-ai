"""Admin phase rules: reject list, delete never loses patients, leaving a lab, status override."""

import base64

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import admin, auth
from app.core.security import AuthUser, require_admin
from app.services import account_deletion, avatars, labs

JPEG = b"\xff\xd8\xff\xe0" + b"0" * 32
SIGNUP = {"email": "no@x.de", "password": "Secret123!", "name": "N", "phone": "+4915112345678",
          "avatar": base64.b64encode(JPEG).decode(), "avatar_content_type": "image/jpeg"}


class FakeDB:
    """Records every query chain; `data[table]` is what each execute() returns."""

    def __init__(self, data=None):
        self.data, self.calls, self.auth_updates = data or {}, [], []
        db = self

        class _Admin:
            def update_user_by_id(self, uid, attrs):
                db.auth_updates.append((uid, attrs))

        self.auth = type("A", (), {"admin": _Admin()})()

    def table(self, name):
        return _Query(self, name)

    def ops(self, table, op):
        return [ops for t, ops in self.calls if t == table and any(o[0] == op for o in ops)]


class _Query:
    def __init__(self, db, table):
        self.db, self.table, self.ops = db, table, []

    def __getattr__(self, op):
        def call(*a, **k):
            self.ops.append((op, a))
            return self

        return call

    def execute(self):
        self.db.calls.append((self.table, self.ops))
        return type("R", (), {"data": self.db.data.get(self.table, []), "count": 0})()


# ── reject list ──────────────────────────────────────────────────────────────


@pytest.fixture
def auth_client(monkeypatch):
    app = FastAPI()
    app.include_router(auth.router, prefix="/api/auth")
    monkeypatch.setattr(auth, "is_rejected_email", lambda e: e == "no@x.de")
    return TestClient(app)


def test_rejected_email_cannot_sign_up(auth_client, monkeypatch):
    monkeypatch.setattr(auth, "get_supabase", lambda: pytest.fail("must not reach Supabase"))
    r = auth_client.post("/api/auth/signup", json=SIGNUP)
    assert r.status_code == 403 and r.json()["detail"] == "REGISTRATION_REJECTED"


def test_rejected_email_sign_in_says_why(auth_client, monkeypatch):
    class Auth:
        def sign_in_with_password(self, _):
            raise Exception("Invalid login credentials")

    monkeypatch.setattr(auth, "get_supabase", lambda: type("C", (), {"auth": Auth()})())
    r = auth_client.post("/api/auth/signin", json={"email": "no@x.de", "password": "x"})
    assert r.status_code == 403 and r.json()["detail"] == "REGISTRATION_REJECTED"
    r = auth_client.post("/api/auth/signin", json={"email": "ok@x.de", "password": "x"})
    assert r.status_code == 401


# ── delete never loses patients ──────────────────────────────────────────────


def test_unapproved_signup_is_purged(monkeypatch):
    db = FakeDB({"profiles": [{"id": "u1", "verified": False}]})
    monkeypatch.setattr(account_deletion, "get_supabase_admin", lambda: db)
    purged = []
    monkeypatch.setattr(account_deletion, "purge_user_account", purged.append)
    account_deletion.delete_account("u1", actor_id="admin")
    assert purged == ["u1"] and db.auth_updates == []


def test_approved_dentist_is_tombstoned_and_patients_kept(monkeypatch):
    db = FakeDB({"profiles": [{"id": "d1", "verified": True, "role": "dentist", "avatar_url": "/a/old.jpg"}]})
    monkeypatch.setattr(account_deletion, "get_supabase_admin", lambda: db)
    photos = []
    monkeypatch.setattr(account_deletion.avatars, "delete", photos.append)
    monkeypatch.setattr(account_deletion, "purge_user_account", lambda u: pytest.fail("purged"))
    monkeypatch.setattr(account_deletion, "_purge_inbox_for_user", lambda u: None)
    account_deletion.delete_account("d1", actor_id="admin")

    assert db.auth_updates[0][1]["email"] == "deleted-d1@deleted.invalid"
    assert db.ops("patients", "delete") == []
    [unassign] = db.ops("patients", "update")
    assert ("eq", ("created_by", "d1")) in unassign
    [profile] = [o for o in db.ops("profiles", "update")]
    patch = profile[0][1][0]
    assert patch["email"] is None and patch["deleted"] is True and patch["anonymized_at"]
    assert patch["avatar_url"] is None and photos == ["/a/old.jpg"]  # photo is personal data


# ── leaving a lab ────────────────────────────────────────────────────────────


def test_leaving_lab_reverts_review_and_keeps_completed(monkeypatch):
    patients = [
        {"id": "p1", "status": "in_review"},
        {"id": "p2", "status": "completed"},
        {"id": "p3", "status": "in_progress"},
    ]
    db = FakeDB({"patients": patients})
    monkeypatch.setattr(labs, "get_supabase_admin", lambda: db)
    moved = []
    monkeypatch.setattr(
        labs.case_status, "set_status", lambda p, to, **k: moved.append((p["id"], to, k["type"]))
    )
    out = labs.set_lab({"id": "d1", "lab_id": "L1"}, None, actor_id="admin", reason="removed")

    assert moved == [("p1", "in_progress", "lab_left")]
    [revoke] = db.ops("patient_access", "delete")
    assert ("in_", ("patient_id", ["p1", "p3"])) in revoke  # completed p2 stays view-only
    assert out["lab_id"] is None and out["unassigned_reason"] == "removed"


# ── status override ──────────────────────────────────────────────────────────


@pytest.fixture
def admin_client(monkeypatch):
    app = FastAPI()
    app.include_router(admin.router, prefix="/api/admin")
    app.dependency_overrides[require_admin] = lambda: AuthUser("admin", "a@x.de", "A", "admin")
    s = {"set": [], "notified": []}
    monkeypatch.setattr(
        admin.pa, "fetch_patient", lambda pid: {"id": pid, "status": "in_review", "created_by": "d1"}
    )
    monkeypatch.setattr(admin.case_status, "set_status", lambda p, to, **k: s["set"].append((to, k)))
    monkeypatch.setattr(admin, "_reviewing_lab", lambda p: "L1")
    monkeypatch.setattr(admin, "notify", lambda **k: s["notified"].append(k["user_id"]))
    s["client"] = TestClient(app)
    return s


def test_override_to_rejected_turns_auto_submit_off_and_notifies(admin_client):
    r = admin_client["client"].patch(
        "/api/admin/patients/p1/status", json={"status": "rejected", "note": "Bite is off"}
    )
    assert r.status_code == 200
    [(to, k)] = admin_client["set"]
    assert to == "rejected" and k["auto_submit"] is False and k["remarks"] == "Bite is off"
    assert k["type"] == "admin_override"
    assert sorted(admin_client["notified"]) == ["L1", "d1"]


def test_override_needs_a_note_and_a_real_status(admin_client):
    c = admin_client["client"]
    assert c.patch("/api/admin/patients/p1/status", json={"status": "completed", "note": "  "}).status_code == 400
    assert c.patch("/api/admin/patients/p1/status", json={"status": "done", "note": "x"}).status_code == 400
    assert c.patch("/api/admin/patients/p1/status", json={"status": "in_review", "note": "x"}).status_code == 409
    assert admin_client["set"] == []


# ── profile photos ───────────────────────────────────────────────────────────


def test_photo_must_really_be_jpeg_or_png():
    assert avatars.sniff(JPEG) == "image/jpeg"
    assert avatars.sniff(b"\x89PNG\r\n\x1a\n...", "image/png") == "image/png"
    for data, declared in [(b"GIF89a", None), (JPEG, "image/png"), (b"", None)]:
        with pytest.raises(Exception) as e:
            avatars.sniff(data, declared)
        assert e.value.status_code == 400
    with pytest.raises(Exception) as e:
        avatars.sniff(b"\xff\xd8\xff" + b"0" * avatars.MAX_BYTES)
    assert e.value.status_code == 413


def test_signup_needs_a_valid_photo_before_creating_anything(auth_client, monkeypatch):
    monkeypatch.setattr(auth, "get_supabase", lambda: pytest.fail("must not reach Supabase"))
    ok = {**SIGNUP, "email": "ok@x.de"}
    assert auth_client.post("/api/auth/signup", json={k: v for k, v in ok.items() if k != "avatar"}).status_code == 422
    assert auth_client.post("/api/auth/signup", json={**ok, "avatar": "%%%"}).status_code == 400
    gif = base64.b64encode(b"GIF89a").decode()
    assert auth_client.post("/api/auth/signup", json={**ok, "avatar": gif}).status_code == 400


def test_failed_photo_upload_removes_the_new_account(auth_client, monkeypatch):
    from fastapi import HTTPException

    user = type("U", (), {"id": "new1", "identities": [1]})()
    monkeypatch.setattr(
        auth, "get_supabase",
        lambda: type("C", (), {"auth": type("A", (), {"sign_up": lambda self, _: type("R", (), {"user": user, "session": None})()})()})(),
    )
    removed = []
    admin_db = type("D", (), {"auth": type("A", (), {"admin": type("X", (), {"delete_user": lambda self, uid: removed.append(uid)})()})()})()
    monkeypatch.setattr(auth, "get_supabase_admin", lambda: admin_db)

    def boom(*a):
        raise HTTPException(502, "r2 down")

    monkeypatch.setattr(auth.avatars, "store", boom)
    monkeypatch.setattr(auth, "persist_signup_profile", lambda **k: pytest.fail("profile written"))
    r = auth_client.post("/api/auth/signup", json={**SIGNUP, "email": "ok@x.de"})
    assert r.status_code == 502 and removed == ["new1"]

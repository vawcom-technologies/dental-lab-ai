"""Phase 3 lab rules: who may share, who acts for a lab, transfers step by step."""

import pytest
from fastapi import HTTPException

from app.core.security import AuthUser
from app.services import labs

OWNER = AuthUser("d1", "d@x.de", "D", "dentist")
SHARED = AuthUser("d9", "s@x.de", "S", "dentist")  # got the patient shared in from another lab
ADMIN = AuthUser("a", "a@x.de", "A", "admin")
PATIENT = {"id": "p1", "created_by": "d1", "first_name": "P"}
PROFILES = {
    "d1": {"id": "d1", "role": "dentist", "lab_id": "L1", "verified": True},
    "d2": {"id": "d2", "role": "dentist", "lab_id": "L1", "verified": True},
    "d3": {"id": "d3", "role": "dentist", "lab_id": "L2", "verified": True},
    "d9": {"id": "d9", "role": "dentist", "lab_id": "L2", "verified": True},
    "L1": {"id": "L1", "role": "laboratory", "verified": True},
    "L2": {"id": "L2", "role": "laboratory", "verified": True},
}


class Recorder:
    """Chainable fake Supabase client; remembers (table, ops) per execute()."""

    def __init__(self):
        self.calls = []

    def table(self, name):
        q = type("Q", (), {})()
        ops = []

        def chain(op):
            def f(*a, **k):
                ops.append((op, a))
                return q
            return f

        for op in ("select", "insert", "update", "upsert", "delete", "eq", "in_", "limit", "or_", "is_", "order"):
            setattr(q, op, chain(op))
        def execute():
            self.calls.append((name, ops))
            return type("R", (), {"data": [] if ops[0][0] in ("update", "select") else [{"id": "t1"}]})()

        q.execute = execute
        return q

    def ops(self, table, op):
        return [o for t, o in self.calls if t == table and o and o[0][0] == op]


@pytest.fixture
def env(monkeypatch):
    db = Recorder()
    s = {"db": db, "notified": [], "events": [], "assigned": [], "shared": set()}
    monkeypatch.setattr(labs, "get_supabase_admin", lambda: db)
    monkeypatch.setattr(labs, "fetch_profile", lambda uid: PROFILES.get(uid))
    monkeypatch.setattr(labs, "require_lab", lambda lid: PROFILES[lid])
    monkeypatch.setattr(labs, "notify", lambda **k: s["notified"].append(k["user_id"]))
    monkeypatch.setattr(labs.case_status, "log_event", lambda pid, **k: s["events"].append(k["type"]))
    monkeypatch.setattr(labs.pa, "fetch_patient", lambda pid: dict(PATIENT))
    monkeypatch.setattr(labs.pa, "has_shared_access", lambda pid, uid: uid in s["shared"])
    return s


# ── sharing ──────────────────────────────────────────────────────────────────


def test_only_the_owner_can_pass_a_patient_on(env):
    with pytest.raises(HTTPException) as e:
        labs.share_rule(SHARED, PATIENT, PROFILES["d3"])  # d9 → colleague in their own lab
    assert e.value.status_code == 403


def test_owner_shares_with_own_lab_now_and_a_colleague_via_ticket(env):
    assert labs.share_rule(OWNER, PATIENT, PROFILES["L1"]) == ("approved", None)
    assert labs.share_rule(OWNER, PATIENT, PROFILES["d2"]) == ("pending", "L1")


def test_anyone_outside_the_lab_needs_a_transfer(env):
    for target in (PROFILES["d3"], PROFILES["L2"]):
        with pytest.raises(HTTPException) as e:
            labs.share_rule(OWNER, PATIENT, target)
        assert e.value.detail["code"] == "USE_TRANSFER"


def test_admin_shares_with_anyone(env):
    assert labs.share_rule(ADMIN, PATIENT, PROFILES["d3"]) == ("approved", None)


# ── acting for a lab ─────────────────────────────────────────────────────────


def test_a_lab_acts_only_for_itself(env):
    labs.caller_lab(AuthUser("L1", "l", "L", "laboratory"), "L1")
    labs.caller_lab(ADMIN, "L2")
    with pytest.raises(HTTPException) as e:
        labs.caller_lab(AuthUser("L1", "l", "L", "laboratory"), "L2")
    assert e.value.status_code == 403


def test_lab_moves_only_patients_it_was_given(env):
    lab = AuthUser("L1", "l", "L", "laboratory")
    assert not labs.can_assign(lab, PATIENT, "L1")
    env["shared"].add("L1")
    assert labs.can_assign(lab, PATIENT, "L1")
    assert labs.can_assign(lab, {**PATIENT, "waiting_lab_id": "L1"}, "L1")


# ── transfers ────────────────────────────────────────────────────────────────

SHARE = {"id": "t1", "kind": "share", "patient_id": "p1", "from_lab_id": "L1", "to_lab_id": "L2",
         "requested_by": "d1", "status": "awaiting_sender"}


def test_share_transfer_needs_sender_lab_then_receiving_lab(env):
    l1, l2 = AuthUser("L1", "l", "L", "laboratory"), AuthUser("L2", "l", "L", "laboratory")
    with pytest.raises(HTTPException) as e:
        labs.decide_transfer(SHARE, l2, action="accept", dentist_id="d3")  # not forwarded yet
    assert e.value.status_code == 403
    assert labs.decide_transfer(SHARE, l1, action="forward")["status"] == "awaiting_recipient"
    assert env["notified"] == ["L2"]

    forwarded = {**SHARE, "status": "awaiting_recipient"}
    with pytest.raises(HTTPException) as e:
        labs.decide_transfer(forwarded, l2, action="accept", dentist_id="d1")  # not L2's dentist
    assert e.value.status_code == 400
    out = labs.decide_transfer(forwarded, l2, action="accept", dentist_id="d3")
    assert out["status"] == "accepted" and out["dentist_id"] == "d3"
    [grant] = env["db"].ops("patient_access", "upsert")
    assert grant[0][1][0]["user_id"] == "d3"  # the chosen dentist gets access, not the lab
    assert "shared" in env["events"]


def test_rejected_handover_goes_back_unassigned(env):
    handover = {**SHARE, "kind": "handover", "status": "awaiting_recipient"}
    labs.decide_transfer(handover, AuthUser("L2", "l", "L", "laboratory"), action="reject", reason="Full")
    [clear] = env["db"].ops("patients", "update")
    assert clear[0][1][0] == {"waiting_lab_id": None}


def test_assigning_an_owner_moves_not_shares(env):
    labs.assign_owner(PATIENT, PROFILES["d2"], lab_id="L1", actor_id="L1")
    [owner] = env["db"].ops("patients", "update")
    assert owner[0][1][0]["created_by"] == "d2" and owner[0][1][0]["waiting_lab_id"] is None
    [lab_access] = env["db"].ops("patient_access", "upsert")
    assert lab_access[0][1][0]["user_id"] == "L1"
    [cancel] = env["db"].ops("lab_transfers", "update")
    assert cancel[0][1][0]["status"] == "cancelled"
    assert sorted(env["notified"]) == ["d1", "d2"]  # new owner + previous owner told


# ── messaging ────────────────────────────────────────────────────────────────


def test_who_may_message_whom(env, monkeypatch):
    people = {**PROFILES, "a": {"id": "a", "role": "admin"}, "x": {"id": "x", "role": "dentist", "lab_id": "L2", "deleted": True}}
    monkeypatch.setattr(labs, "fetch_profile", lambda uid: people.get(uid))
    shared = {"d1": {"d9"}}  # d1's patient was shared with d9 (other lab)
    monkeypatch.setattr(labs, "_patients_of", lambda uid: {uid})
    monkeypatch.setattr(labs, "_people_on", lambda pids: shared.get(next(iter(pids)), set()))
    ok = labs.can_message
    assert ok("d1", "d2")  # same lab
    assert ok("d1", "L1") and ok("L1", "d1")  # dentist ↔ own lab
    assert not ok("d1", "L2")  # another lab
    assert ok("L1", "L2")  # lab ↔ lab
    assert ok("a", "d3") and ok("d3", "a")  # admin ↔ anyone
    assert not ok("d1", "d3")  # other lab, nothing shared
    assert ok("d1", "d9")  # other lab, but they share a patient
    assert not ok("d1", "x")  # deactivated account

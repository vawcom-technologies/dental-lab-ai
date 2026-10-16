"""Status flow rules (docs/roadmap.md → Status flow), one test per rule."""

import pytest
from fastapi import HTTPException

from app.core.security import AuthUser
from app.services import case_flow as cf

DENTIST = AuthUser("d1", "d@x.de", "D", "dentist")
LAB = AuthUser("L1", "l@x.de", "L", "laboratory")
ALL = {"scan": True, "shade": True, "smile": True}


@pytest.fixture
def case(monkeypatch):
    """One patient owned by d1, whose lab is L1. Tweak s[...] per test."""
    s = {
        "patient": {"id": "p1", "status": "pending", "auto_submit": True, "created_by": "d1"},
        "items": dict(ALL),
        "shared": True,
        "lab": "L1",
        "moves": [],
        "events": [],
        "notified": [],
        "shared_with": [],
    }

    def set_status(p, to, **k):
        s["moves"].append((to, k.get("type")))
        s["patient"] = {**p, "status": to, **({"auto_submit": k["auto_submit"]} if k.get("auto_submit") is not None else {})}
        return s["patient"]

    monkeypatch.setattr(cf.pa, "fetch_patient", lambda pid: dict(s["patient"]))
    monkeypatch.setattr(cf, "items", lambda pid: s["items"])
    monkeypatch.setattr(cf, "owner_lab", lambda p: s["lab"])
    monkeypatch.setattr(cf.pa, "has_shared_access", lambda pid, uid: s["shared"] and uid == s["lab"])
    monkeypatch.setattr(cf.case_status, "set_status", set_status)
    monkeypatch.setattr(cf.case_status, "log_event", lambda pid, **k: s["events"].append(k["type"]))
    monkeypatch.setattr(cf, "notify", lambda **k: s["notified"].append(k["user_id"]))

    class DB:
        def table(self, _):
            return self

        def upsert(self, row, **_):
            s["shared_with"].append(row["user_id"])
            return self

        def execute(self):
            return self

    monkeypatch.setattr(cf, "get_supabase_admin", DB)
    return s


def test_first_scan_starts_work_and_complete_case_goes_to_the_lab(case):
    cf.after_change("p1", "d1", scan=True)
    assert case["moves"] == [("in_progress", "scan_added"), ("in_review", "submitted")]
    assert case["notified"] == ["L1"]


def test_only_a_scan_moves_a_case_out_of_awaiting_scans(case):
    cf.after_change("p1", "d1")  # shade or smile saved first
    assert case["moves"] == [] and case["patient"]["status"] == "pending"


def test_no_automatic_submit_until_shared_with_the_lab(case):
    case["shared"] = False
    cf.after_change("p1", "d1", scan=True)
    assert case["moves"] == [("in_progress", "scan_added")]
    case["shared"] = True
    cf.after_share("p1", "L1", "d1")  # sharing completes the conditions
    assert case["moves"][-1] == ("in_review", "submitted")


def test_no_automatic_submit_with_an_item_missing(case):
    case["items"]["smile"] = False
    cf.after_change("p1", "d1", scan=True)
    assert case["patient"]["status"] == "in_progress"


def test_first_change_after_rejection_resumes_work_but_never_resubmits(case):
    case["patient"].update(status="rejected", auto_submit=False)
    cf.after_change("p1", "d1")
    assert case["moves"] == [("in_progress", "updated")]
    cf.after_change("p1", "d1")  # everything present and shared, still no auto-submit
    assert case["patient"]["status"] == "in_progress"


def test_change_under_review_keeps_status_and_tells_the_lab(case):
    case["patient"]["status"] = "in_review"
    cf.after_change("p1", "d1")
    assert case["moves"] == [] and case["events"] == ["updated"] and case["notified"] == ["L1"]


def test_change_after_completion_reopens_for_review(case):
    case["patient"]["status"] = "completed"
    cf.after_change("p1", "d1")
    assert case["moves"] == [("in_review", "reopened")] and case["notified"] == ["L1"]


def test_manual_submit_warns_about_missing_items_then_shares_and_submits(case):
    case.update(shared=False)
    case["items"]["shade"] = False
    case["patient"]["status"] = "in_progress"
    with pytest.raises(HTTPException) as e:
        cf.submit(case["patient"], DENTIST, confirm_incomplete=False)
    assert e.value.status_code == 409 and e.value.detail["missing"] == ["shade"]
    cf.submit(case["patient"], DENTIST, confirm_incomplete=True)
    assert case["shared_with"] == ["L1"] and case["moves"] == [("in_review", "submitted")]
    assert case["patient"]["auto_submit"] is True  # resubmitting turns it back on


def test_submit_needs_a_lab(case):
    case["lab"] = None
    with pytest.raises(HTTPException) as e:
        cf.submit(case["patient"], DENTIST, confirm_incomplete=True)
    assert e.value.status_code == 400


def test_lab_rejects_only_with_remarks_and_auto_submit_goes_off(case):
    case["patient"]["status"] = "in_review"
    with pytest.raises(HTTPException) as e:
        cf.review(case["patient"], LAB, approve=False, remarks="  ")
    assert e.value.status_code == 400
    cf.review(case["patient"], LAB, approve=False, remarks="Margin unclear")
    assert case["moves"] == [("rejected", "rejected")] and case["patient"]["auto_submit"] is False
    assert case["notified"] == ["d1"]


def test_only_the_owners_lab_reviews(case):
    case["patient"]["status"] = "in_review"
    other_lab = AuthUser("L2", "o@x.de", "O", "laboratory")
    for user in (other_lab, DENTIST):
        with pytest.raises(HTTPException) as e:
            cf.review(case["patient"], user, approve=True, remarks=None)
        assert e.value.status_code == 403
    cf.review(case["patient"], AuthUser("a", "a@x.de", "A", "admin"), approve=True, remarks=None)
    assert case["moves"] == [("completed", "approved")]


def test_labs_cannot_change_items_and_locked_cases_cannot_lose_them(case):
    with pytest.raises(HTTPException) as e:
        cf.require_can_change(LAB)
    assert e.value.status_code == 403
    cf.require_can_change(DENTIST)
    case["patient"]["status"] = "in_review"
    with pytest.raises(HTTPException) as e:
        cf.require_unlocked("p1")
    assert e.value.status_code == 409 and e.value.detail["code"] == "CASE_LOCKED"


def test_rejection_banner_disappears_once_resubmitted_or_approved(case, monkeypatch):
    def with_events(*events):
        class DB:
            def __getattr__(self, _):
                return lambda *a, **k: self

            def execute(self):
                return type("R", (), {"data": [dict(type=t, to_status=to, remarks="fix margin") for t, to in events]})()

        monkeypatch.setattr(cf, "get_supabase_admin", DB)
        monkeypatch.setattr(cf, "fetch_profile", lambda uid: None)
        return cf.summary(case["patient"], DENTIST)["last_rejection"]

    case["patient"]["status"] = "in_progress"
    assert with_events(("submitted", "in_review"), ("rejected", "rejected"), ("updated", "in_progress"))["remarks"] == "fix margin"
    assert with_events(("rejected", "rejected"), ("submitted", "in_review")) is None
    # completed → reopened while not shared lands in progress: the old remarks stay hidden
    assert with_events(("rejected", "rejected"), ("submitted", "in_review"), ("approved", "completed"), ("reopened", "in_progress")) is None

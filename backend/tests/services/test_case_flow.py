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


def test_first_scan_on_case_starts_work_but_does_not_silent_submit(case):
    cf.after_change("p1", "d1", scan=True)
    assert case["moves"] == [("in_progress", "scan_added")]
    assert case["notified"] == []
    assert cf.ready_to_submit(case["patient"]) is True


def test_only_a_scan_moves_a_case_out_of_awaiting_scans(case):
    cf.after_change("p1", "d1")  # shade or smile saved first
    assert case["moves"] == [] and case["patient"]["status"] == "pending"


def test_ready_to_submit_needs_share_with_lab(case):
    case["shared"] = False
    case["patient"]["status"] = "in_progress"
    assert cf.ready_to_submit(case["patient"]) is False
    case["shared"] = True
    assert cf.ready_to_submit(case["patient"]) is True


def test_ready_to_submit_false_with_an_item_missing(case):
    case["items"]["smile"] = False
    case["patient"]["status"] = "in_progress"
    assert cf.ready_to_submit(case["patient"]) is False


def test_change_after_rejection_stays_rejected_and_tells_the_lab(case, monkeypatch):
    monkeypatch.setattr(cf, "_touch", lambda pid, **k: None)
    case["patient"].update(status="rejected", auto_submit=False)
    cf.after_change("p1", "d1")
    assert case["moves"] == [] and case["events"] == ["updated"] and case["notified"] == ["L1"]
    assert cf.ready_to_submit(case["patient"]) is False  # nothing changed yet
    assert cf.ready_to_submit(case["patient"], updated_since_rejection=True) is True  # ask to resubmit
    cf.submit(case["patient"], DENTIST, confirm_incomplete=False)
    assert case["moves"] == [("in_review", "submitted")]


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


def test_lab_reject_per_item_feedback_requires_notes_and_packs_remarks(case, monkeypatch):
    case["patient"]["status"] = "in_review"
    stored = []

    def set_status(p, to, **k):
        stored.append(k.get("remarks"))
        case["patient"] = {**p, "status": to, "auto_submit": False}
        case["moves"].append((to, k.get("type")))
        return case["patient"]

    monkeypatch.setattr(cf.case_status, "set_status", set_status)
    with pytest.raises(HTTPException) as e:
        cf.review(
            case["patient"],
            LAB,
            approve=False,
            remarks="Please fix",
            items=[{"item": "scan", "status": "needs_work", "note": ""}],
        )
    assert e.value.status_code == 400
    cf.review(
        case["patient"],
        LAB,
        approve=False,
        remarks="Please fix",
        items=[
            {"item": "scan", "status": "needs_work", "note": "Blurry bite"},
            {"item": "shade", "status": "ok", "note": None},
            {"item": "smile", "status": "needs_work", "note": "Wrong overlay"},
        ],
    )
    text, items = cf.unpack_rejection(stored[-1])
    assert text == "Please fix"
    assert items[0]["item"] == "scan" and items[0]["note"] == "Blurry bite"
    assert items[1]["status"] == "ok"
    assert items[2]["note"] == "Wrong overlay"


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
    cf.require_can_change(DENTIST, case["patient"])
    with pytest.raises(HTTPException) as e:  # shared with, but not the owner
        cf.require_can_change(AuthUser("d2", "o@x.de", "O", "dentist"), case["patient"])
    assert e.value.status_code == 403
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


@pytest.fixture
def review(case, monkeypatch):
    """Case under review with lab_review stored on the patient."""
    case["patient"].update(status="in_review", lab_review={})

    def patch(pid, path, value, bump=False):  # what lab_review_set does in SQL
        node = case["patient"].setdefault("lab_review", {})
        for key in path[:-1]:
            node = node.setdefault(key, {})
        if value is None:
            node.pop(path[-1], None)
        else:
            node[path[-1]] = value

    monkeypatch.setattr(cf, "_patch_lab_review", patch)
    monkeypatch.setattr(cf, "_drop_files", lambda *a, **k: None)
    monkeypatch.setattr(cf, "_touch", lambda pid, **k: None)
    return case


def test_reviewing_lab_suggests_and_others_cannot(review):
    assert cf.edit_mode(LAB, review["patient"]) == "suggest"
    assert cf.edit_mode(DENTIST, review["patient"]) == "edit"
    review["patient"]["status"] = "completed"
    with pytest.raises(HTTPException):
        cf.edit_mode(LAB, review["patient"])  # only while under review


def test_lab_suggestion_forces_reject_and_dentist_must_resolve_it(review, monkeypatch):
    row = cf.suggest(review["patient"], LAB, "shade", for_id="sh1", file_key="k", file_name="a.png")
    assert row["id"] == "s-p1-shade" and row["suggestion_for"] == "sh1"
    assert cf.parse_suggestion_id(row["id"]) == ("p1", "shade")
    assert cf.with_suggestion(review["patient"], LAB, "shade", [{"id": "sh1"}, {"id": "sh2"}]) == [row, {"id": "sh2"}]
    with pytest.raises(HTTPException) as e:
        cf.review(review["patient"], LAB, approve=True, remarks=None)
    assert e.value.detail["code"] == "SUGGESTIONS_PENDING"
    stored = []
    real = cf.case_status.set_status
    monkeypatch.setattr(cf.case_status, "set_status", lambda p, to, **k: stored.append(k["remarks"]) or real(p, to, **k))
    cf.review(review["patient"], LAB, approve=False, remarks=None)
    text, items = cf.unpack_rejection(stored[-1])
    assert text == "Lab made changes, please confirm." and items[0]["item"] == "shade" and items[0]["status"] == "needs_work"
    with pytest.raises(HTTPException) as e:
        cf.submit(review["patient"], DENTIST, confirm_incomplete=True)
    assert e.value.detail["code"] == "SUGGESTIONS_PENDING"
    applied = []
    monkeypatch.setattr(cf, "_apply", lambda pid, item, s: applied.append(item))
    cf.resolve_suggestion(review["patient"], DENTIST, "shade", accept=True)
    assert applied == ["shade"] and cf.suggestions(review["patient"]) == {}
    assert "suggestion_accepted" in review["events"] and "updated" in review["events"]
    cf.submit(review["patient"], DENTIST, confirm_incomplete=True)
    assert review["patient"]["status"] == "in_review"


def test_feedback_and_suggestion_patch_separate_keys(review):
    """Feedback and suggestions write their own key, never the whole lab_review."""
    cf.suggest(review["patient"], LAB, "smile", for_id=None, file_key="k", file_name="s.png")
    stale = {**review["patient"], "lab_review": {}}  # request read before the suggestion
    cf.set_feedback(stale, LAB, "shade", "needs_work", "too warm")
    lr = review["patient"]["lab_review"]
    assert "smile" in lr["suggestions"] and lr["feedback"]["shade"]["note"] == "too warm"

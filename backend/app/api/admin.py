"""Admin: signups, reject list, labs and dentists, every patient (docs/roadmap.md)."""

from __future__ import annotations

import logging
import re
from collections import Counter
from typing import Any

from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, Query, UploadFile, status
from pydantic import BaseModel, Field

from app.core.security import AuthUser, clear_auth_cache, require_admin
from app.core.supabase_client import get_supabase_admin
from app.schemas import ProfileActionOut, ProfileOut
from app.services import avatars, case_status, labs
from app.services import patient_access as pa
from app.services.account_deletion import delete_account, purge_user_account
from app.services.email import send_account_verified_email, send_signup_rejected_email
from app.services.notify import notify
from app.services.profiles import public_id_from_profile

router = APIRouter()
logger = logging.getLogger("app.api.admin")

_PROFILE_COLS_CORE = (
    "id,name,email,phone,role,clinic_name,verified,deleted,created_at,updated_at,"
    "lab_id,hidden_from_labs,hide_dentists,unassigned_reason,unassigned_at,"
    "anonymized_at,avatar_url"
)
# Optional until migration 027 is applied.
_PROFILE_COLS = _PROFILE_COLS_CORE + ",public_number"
# None = unknown, True = column present, False = missing (skip forever this process).
_HAVE_PUBLIC_NUMBER: bool | None = None
_STATUS_LABELS = {
    "pending": "awaiting scan",
    "in_progress": "in progress",
    "in_review": "under review",
    "completed": "completed",
    "rejected": "rejected",
}


# ── helpers ──────────────────────────────────────────────────────────────────


def _db():
    return get_supabase_admin()


def _rows(query: Any) -> list[dict[str, Any]]:
    try:
        return list(getattr(query.execute(), "data", None) or [])
    except Exception as exc:
        raise pa.db_error(exc) from exc


def _count(query: Any) -> int:
    try:
        return int(getattr(query.execute(), "count", None) or 0)
    except Exception as exc:
        raise pa.db_error(exc) from exc


def _missing_public_number(exc: BaseException) -> bool:
    text = str(exc).lower()
    return "public_number" in text and (
        "does not exist" in text or "42703" in text or "column" in text
    )


def _profile_cols() -> str:
    return _PROFILE_COLS if _HAVE_PUBLIC_NUMBER is not False else _PROFILE_COLS_CORE


def _profile_rows(build) -> list[dict[str, Any]]:
    """Run a profiles select; retry without public_number if migration 027 is pending."""
    global _HAVE_PUBLIC_NUMBER
    cols = _profile_cols()
    try:
        rows = _rows(build(cols))
        if _HAVE_PUBLIC_NUMBER is None and cols.endswith("public_number"):
            _HAVE_PUBLIC_NUMBER = True
        return rows
    except Exception as exc:
        if _HAVE_PUBLIC_NUMBER is not False and _missing_public_number(exc):
            logger.warning(
                "profiles.public_number missing — apply migrations/027_profile_public_ids.sql"
            )
            _HAVE_PUBLIC_NUMBER = False
            return _rows(build(_PROFILE_COLS_CORE))
        raise


def _q(raw: str | None) -> str:
    """Search text safe to embed in a PostgREST or=(...) filter."""
    return re.sub(r"[,()*%\\\"]", " ", raw or "").strip()


def _opt(raw: str | None) -> str | None:
    """The app sends empty strings for unset filters."""
    return (raw or "").strip() or None


def _profile(user_id: str) -> dict[str, Any] | None:
    rows = _profile_rows(
        lambda cols: _db().table("profiles").select(cols).eq("id", user_id).limit(1)
    )
    return rows[0] if rows else None


def _require_profile(user_id: str, role: str) -> dict[str, Any]:
    p = _profile(user_id)
    if p is None or p.get("anonymized_at") or p.get("role") != role:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    return p


def _names(ids: set[str]) -> dict[str, dict[str, Any]]:
    """id → profile (name, role, lab_id), including deactivated and deleted accounts."""
    ids = {i for i in ids if i}
    if not ids:
        return {}
    rows = _rows(_db().table("profiles").select("id,name,email,role,lab_id").in_("id", list(ids)))
    return {str(r["id"]): r for r in rows}


def _name(p: dict[str, Any] | None) -> str | None:
    return pa.profile_display_name(p, fallback="") or None if p else None


def _require_patient(patient_id: str) -> dict[str, Any]:
    patient = pa.fetch_patient(patient_id)
    if patient is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Patient not found")
    return patient


def _pending_signups(query: Any) -> Any:
    return (
        query.eq("verified", False)
        .eq("deleted", False)
        .is_("anonymized_at", "null")
        .neq("role", "admin")
    )


def _approved(query: Any, role: str) -> Any:
    return query.eq("role", role).eq("verified", True).is_("anonymized_at", "null")


# ── dashboard ────────────────────────────────────────────────────────────────


@router.get("/summary")
def summary(_: AuthUser = Depends(require_admin)):
    def head(table: str) -> Any:
        return _db().table(table).select("id", count="exact", head=True)

    patients = lambda: head("patients").eq("deleted", False)  # noqa: E731
    return {
        "pending_signups": _count(_pending_signups(head("profiles"))),
        "dentists": _count(_approved(head("profiles"), "dentist")),
        "labs": _count(_approved(head("profiles"), "laboratory")),
        "unassigned_dentists": _count(
            _approved(head("profiles"), "dentist").is_("lab_id", "null")
        ),
        "unassigned_patients": _count(patients().not_.is_("unassigned_at", "null")),
        "pending_removals": _count(
            head("lab_requests").eq("kind", "remove").eq("status", "pending")
        ),
        "cases": {s: _count(patients().eq("status", s)) for s in case_status.STATUSES},
    }


# ── signups and the reject list ──────────────────────────────────────────────


class ApproveIn(BaseModel):
    lab_id: str | None = None


class RejectIn(BaseModel):
    reason: str | None = Field(default=None, max_length=1000)


def _require_pending(user_id: str) -> dict[str, Any]:
    p = _profile(user_id)
    if p is None or p.get("anonymized_at") or p.get("deleted"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Signup not found")
    if p.get("verified"):
        raise HTTPException(status.HTTP_409_CONFLICT, "This account is already approved")
    return p


@router.get("/signups")
def list_signups(_: AuthUser = Depends(require_admin)):
    rows = _profile_rows(
        lambda cols: _pending_signups(_db().table("profiles").select(cols)).order(
            "created_at", desc=True
        )
    )
    return [
        {
            "user_id": str(r["id"]),
            "public_id": public_id_from_profile(r),
            "name": r.get("name"),
            "email": r.get("email"),
            "phone": r.get("phone"),
            "role": r.get("role"),
            "clinic_name": r.get("clinic_name"),
            "created_at": r.get("created_at"),
            "avatar_url": r.get("avatar_url"),
        }
        for r in rows
    ]


@router.post("/signups/{user_id}/approve")
def approve_signup(
    user_id: str,
    body: ApproveIn,
    background_tasks: BackgroundTasks,
    admin: AuthUser = Depends(require_admin),
):
    p = _require_pending(user_id)
    lab_id = _opt(body.lab_id) if p.get("role") == "dentist" else None
    if lab_id:
        labs.require_lab(lab_id)
    now = pa.utc_now_iso()
    patch: dict[str, Any] = {"verified": True, "updated_at": now}
    if p.get("role") == "dentist":
        patch |= {
            "lab_id": lab_id,
            "unassigned_reason": None if lab_id else "no_lab",
            "unassigned_at": None if lab_id else now,
        }
    try:
        # Admin approval is the verification step: confirm the email in Supabase Auth
        # too, or sign-in stays blocked with "email not confirmed".
        _db().auth.admin.update_user_by_id(user_id, {"email_confirm": True})
    except Exception as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Could not activate the login; try again") from exc
    _rows(_db().table("profiles").update(patch).eq("id", user_id))
    background_tasks.add_task(send_account_verified_email, p.get("name") or "", p.get("email") or "")
    logger.info("signup approved user_id=%s by=%s lab_id=%s", user_id, admin.id, lab_id)
    return {"ok": True}


@router.post("/signups/{user_id}/reject")
def reject_signup(
    user_id: str,
    body: RejectIn,
    background_tasks: BackgroundTasks,
    admin: AuthUser = Depends(require_admin),
):
    p = _require_pending(user_id)
    email = str(p.get("email") or "").strip().lower()
    if not email:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Signup has no email")
    # List first: if the purge fails the account is still unapproved (can't sign in),
    # and rejecting again just retries.
    _rows(
        _db()
        .table("rejected_signups")
        .upsert(
            {
                "email": email,
                "name": p.get("name"),
                "role": p.get("role"),
                "reason": _opt(body.reason),
                "rejected_by": admin.id,
                "rejected_at": pa.utc_now_iso(),
            },
            on_conflict="email",
        )
    )
    purge_user_account(user_id)
    background_tasks.add_task(send_signup_rejected_email, p.get("name") or "", email, _opt(body.reason))
    logger.info("signup rejected user_id=%s by=%s", user_id, admin.id)
    return {"ok": True}


@router.get("/rejected")
def list_rejected(_: AuthUser = Depends(require_admin)):
    rows = _rows(_db().table("rejected_signups").select("*").order("rejected_at", desc=True))
    by = _names({str(r.get("rejected_by") or "") for r in rows})
    return [
        {
            "id": str(r["id"]),
            "email": r.get("email"),
            "name": r.get("name"),
            "role": r.get("role"),
            "reason": r.get("reason"),
            "rejected_at": r.get("rejected_at"),
            "rejected_by_name": _name(by.get(str(r.get("rejected_by") or ""))),
        }
        for r in rows
    ]


@router.delete("/rejected/{rejected_id}")
def remove_rejected(rejected_id: str, _: AuthUser = Depends(require_admin)):
    """Lets that email sign up again; it does not approve anyone."""
    if not _rows(_db().table("rejected_signups").delete().eq("id", rejected_id)):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not on the reject list")
    return {"ok": True}


# ── labs and dentists ────────────────────────────────────────────────────────


class SetLabIn(BaseModel):
    lab_id: str | None = None
    patient_ids: list[str] = []


@router.get("/labs")
def list_labs(_: AuthUser = Depends(require_admin)):
    rows = _profile_rows(
        lambda cols: _approved(
            _db().table("profiles").select(cols), "laboratory"
        ).order("name")
    )
    counts = Counter(
        str(r["lab_id"])
        for r in _rows(
            _approved(_db().table("profiles").select("lab_id"), "dentist").not_.is_(
                "lab_id", "null"
            )
        )
    )
    return [
        {
            "id": str(r["id"]),
            "public_id": public_id_from_profile(r),
            "name": r.get("name"),
            "email": r.get("email"),
            "phone": r.get("phone"),
            "dentist_count": counts[str(r["id"])],
            "hidden_from_labs": bool(r.get("hidden_from_labs")),
            "hide_dentists": bool(r.get("hide_dentists")),
            "deleted": bool(r.get("deleted")),
            "avatar_url": r.get("avatar_url"),
        }
        for r in rows
    ]


@router.get("/dentists")
def list_dentists(
    lab_id: str | None = None,
    unassigned: str | None = None,
    _: AuthUser = Depends(require_admin),
):
    def _dentists(cols: str) -> Any:
        query = _approved(_db().table("profiles").select(cols), "dentist")
        if _opt(lab_id):
            query = query.eq("lab_id", _opt(lab_id))
        if unassigned == "true":
            query = query.is_("lab_id", "null")
        return query.order("name")

    rows = _profile_rows(_dentists)
    lab_names = _names({str(r.get("lab_id") or "") for r in rows})
    return [
        {
            "id": str(r["id"]),
            "public_id": public_id_from_profile(r),
            "name": r.get("name"),
            "email": r.get("email"),
            "phone": r.get("phone"),
            "clinic_name": r.get("clinic_name"),
            "lab_id": r.get("lab_id"),
            "lab_name": _name(lab_names.get(str(r.get("lab_id") or ""))),
            "unassigned_reason": r.get("unassigned_reason"),
            "unassigned_at": r.get("unassigned_at"),
            "verified": True,
            "deleted": bool(r.get("deleted")),
            "created_at": r.get("created_at"),
            "avatar_url": r.get("avatar_url"),
        }
        for r in rows
    ]


@router.put("/dentists/{dentist_id}/lab")
def set_dentist_lab(dentist_id: str, body: SetLabIn, admin: AuthUser = Depends(require_admin)):
    """Force-move a dentist to a lab (or clear lab). Optional patient_ids auto-share with the new lab."""
    dentist = _require_profile(dentist_id, "dentist")
    lab_id = _opt(body.lab_id)
    if lab_id:
        labs.require_lab(lab_id)
    labs.clear_pending_lab_moves(dentist_id)
    labs.set_lab(dentist, lab_id, actor_id=admin.id, reason="removed")
    if lab_id:
        labs.share_owned_with_lab(dentist_id, lab_id, body.patient_ids, actor_id=admin.id)
    return {"ok": True}


@router.get("/lab-requests")
def list_lab_requests(
    kind: str | None = None,
    status_: str | None = Query(default="pending", alias="status"),
    _: AuthUser = Depends(require_admin),
):
    query = _db().table("lab_requests").select("*")
    if _opt(kind):
        query = query.eq("kind", _opt(kind))
    if _opt(status_):
        query = query.eq("status", _opt(status_))
    rows = _rows(query.order("created_at", desc=True))
    names = _names({str(r[k]) for r in rows for k in ("lab_id", "dentist_id")})
    return [
        {
            "id": str(r["id"]),
            "kind": r.get("kind"),
            "lab_id": str(r["lab_id"]),
            "lab_name": _name(names.get(str(r["lab_id"]))),
            "dentist_id": str(r["dentist_id"]),
            "dentist_name": _name(names.get(str(r["dentist_id"]))),
            "reason": r.get("reason"),
            "status": r.get("status"),
            "created_at": r.get("created_at"),
        }
        for r in rows
    ]


def _decide_lab_request(request_id: str, approve: bool, admin: AuthUser) -> dict[str, Any]:
    rows = _rows(_db().table("lab_requests").select("*").eq("id", request_id).limit(1))
    req = rows[0] if rows else None
    if req is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Request not found")
    if req.get("status") != "pending":
        raise HTTPException(status.HTTP_409_CONFLICT, "Request was already decided")
    if approve:
        dentist = _require_profile(str(req["dentist_id"]), "dentist")
        lab_id = str(req["lab_id"])
        pids = req.get("patient_ids") or []
        if req.get("kind") == "join":
            labs.require_lab(lab_id)
            labs.set_lab(dentist, lab_id, actor_id=admin.id)
            labs.share_owned_with_lab(str(dentist["id"]), lab_id, pids, actor_id=admin.id)
        elif req.get("kind") == "transfer":
            labs.apply_transfer(dentist, str(req["to_lab_id"]), pids, actor_id=admin.id)
        elif str(dentist.get("lab_id") or "") == lab_id:
            # Already moved elsewhere → nothing left to remove.
            labs.set_lab(dentist, None, actor_id=admin.id, reason="removed")
    _rows(
        _db()
        .table("lab_requests")
        .update(
            {
                "status": "approved" if approve else "rejected",
                "decided_by": admin.id,
                "decided_at": pa.utc_now_iso(),
            }
        )
        .eq("id", request_id)
    )
    return {"ok": True}


@router.post("/lab-requests/{request_id}/approve")
def approve_lab_request(request_id: str, admin: AuthUser = Depends(require_admin)):
    return _decide_lab_request(request_id, True, admin)


@router.post("/lab-requests/{request_id}/deny")
def deny_lab_request(request_id: str, admin: AuthUser = Depends(require_admin)):
    return _decide_lab_request(request_id, False, admin)


# ── patients ─────────────────────────────────────────────────────────────────


class StatusIn(BaseModel):
    status: str
    note: str = Field(min_length=1, max_length=2000)


class ReassignIn(BaseModel):
    lab_id: str
    dentist_id: str | None = None


def _patient_row(p: dict[str, Any], people: dict[str, dict[str, Any]]) -> dict[str, Any]:
    owner = people.get(str(p.get("created_by") or ""))
    waiting = str(p.get("waiting_lab_id") or "")
    if waiting:
        lab_id, reason = waiting, "waiting_for_lab"
    else:
        reason = "owner_deleted" if p.get("unassigned_at") else None
        is_lab = owner and owner.get("role") == "laboratory"
        lab_id = str(owner["id"]) if is_lab else str((owner or {}).get("lab_id") or "")
    return {
        "id": str(p["id"]),
        "first_name": p.get("first_name"),
        "last_name": p.get("last_name"),
        "status": p.get("status") or "pending",
        "owner_id": str(p.get("created_by") or ""),
        "owner_name": _name(owner),
        "lab_id": lab_id or None,
        "lab_name": _name(people.get(lab_id)) if lab_id else None,
        "unassigned_reason": reason,
        "updated_at": p.get("updated_at"),
    }


def _people_for(patients: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    people = _names(
        {str(p.get(k) or "") for p in patients for k in ("created_by", "waiting_lab_id")}
    )
    lab_ids = {str(o.get("lab_id") or "") for o in people.values()} - people.keys()
    return people | _names(lab_ids)


@router.get("/patients")
def list_patients(
    status_: str | None = Query(default=None, alias="status"),
    lab_id: str | None = None,
    unassigned: str | None = None,
    q: str | None = None,
    _: AuthUser = Depends(require_admin),
):
    """Most recently updated first. `lab_id` matches the owner's lab or the lab
    a patient is waiting for.
    ponytail: no paging (the app loads the whole list); add limit/offset when the app pages."""
    cols = "id,first_name,last_name,status,created_by,unassigned_at,waiting_lab_id,updated_at"
    query = _db().table("patients").select(cols).eq("deleted", False)
    if _opt(status_):
        query = query.eq("status", _opt(status_))
    if unassigned == "true":
        query = query.not_.is_("unassigned_at", "null")
    groups = []
    term = _q(q)
    if term:
        groups.append(f'first_name.ilike."*{term}*",last_name.ilike."*{term}*"')
    if _opt(lab_id):
        lab = _opt(lab_id)
        owners = [
            str(r["id"])
            for r in _rows(_db().table("profiles").select("id").eq("lab_id", lab))
        ] + [lab]
        groups.append(f"created_by.in.({','.join(owners)}),waiting_lab_id.eq.{lab}")
    if len(groups) == 1:
        query = query.or_(groups[0])
    elif groups:
        # postgrest-py adds a second `or` param instead of AND-ing; nest them instead.
        query = query.or_(f"and(or({groups[0]}),or({groups[1]}))")
    rows = _rows(query.order("updated_at", desc=True))
    people = _people_for(rows)
    return [_patient_row(p, people) for p in rows]


@router.get("/patients/{patient_id}")
def get_patient(patient_id: str, _: AuthUser = Depends(require_admin)):
    patient = _require_patient(patient_id)
    shares = _rows(
        _db()
        .table("patient_access")
        .select("user_id")
        .eq("patient_id", patient_id)
        .eq("status", "approved")
    )
    events = _rows(
        _db().table("case_events").select("*").eq("patient_id", patient_id).order("created_at")
    )
    people = _people_for([patient]) | _names(
        {str(s["user_id"]) for s in shares} | {str(e.get("actor_id") or "") for e in events}
    )
    return _patient_row(patient, people) | {
        "date_of_birth": patient.get("date_of_birth"),
        "email": patient.get("email"),
        "phone": patient.get("phone"),
        "created_at": patient.get("created_at"),
        "shared_with": [
            {
                "user_id": str(s["user_id"]),
                "name": _name(people.get(str(s["user_id"]))),
                "role": (people.get(str(s["user_id"])) or {}).get("role"),
            }
            for s in shares
        ],
        "events": [
            {
                "type": e.get("type"),
                "actor_name": _name(people.get(str(e.get("actor_id") or ""))),
                "remarks": e.get("remarks"),
                "from_status": e.get("from_status"),
                "to_status": e.get("to_status"),
                "created_at": e.get("created_at"),
            }
            for e in events
        ],
    }


def _reviewing_lab(patient: dict[str, Any]) -> str | None:
    """The owner's lab, but only if the patient is shared with it."""
    owner = _profile(str(patient.get("created_by") or ""))
    lab = str((owner or {}).get("lab_id") or "")
    return lab if lab and pa.has_shared_access(str(patient["id"]), lab) else None


@router.patch("/patients/{patient_id}/status")
def override_status(patient_id: str, body: StatusIn, admin: AuthUser = Depends(require_admin)):
    """Same effect as the matching normal action; the note is the event's remarks
    (and the rejection remarks when setting `rejected`). Automatic rules are not re-run."""
    if body.status not in case_status.STATUSES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Unknown status")
    note = body.note.strip()
    if not note:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "A note is required")
    patient = _require_patient(patient_id)
    if patient.get("status") == body.status:
        raise HTTPException(status.HTTP_409_CONFLICT, "The case already has this status")
    case_status.set_status(
        patient,
        body.status,
        actor_id=admin.id,
        type="admin_override",
        remarks=note,
        auto_submit=False if body.status == "rejected" else None,
    )
    msg = (
        f"An administrator set {pa.patient_display_name(patient)} to "
        f"{_STATUS_LABELS[body.status]}: {note}"
    )
    for uid in {str(patient.get("created_by") or ""), _reviewing_lab(patient) or ""} - {""}:
        notify(user_id=uid, type="case_status", message=msg, patient_id=patient_id, actor_id=admin.id)
    return {"ok": True}


@router.post("/patients/{patient_id}/reassign")
def reassign_patient(patient_id: str, body: ReassignIn, admin: AuthUser = Depends(require_admin)):
    """To a dentist in `lab_id`, or (no dentist) to the lab, which then chooses one."""
    patient = _require_patient(patient_id)
    lab_id = str(labs.require_lab(body.lab_id)["id"])
    dentist_id = _opt(body.dentist_id)
    if dentist_id:
        labs.assign_owner(patient, labs.require_active_dentist(dentist_id, lab_id), lab_id=lab_id, actor_id=admin.id)
        return {"ok": True}
    _rows(
        _db().table("patients").update(
            {"waiting_lab_id": lab_id, "unassigned_at": patient.get("unassigned_at") or pa.utc_now_iso(),
             "updated_at": pa.utc_now_iso()}
        ).eq("id", patient_id)
    )
    labs.open_transfer(patient, kind="handover", from_lab=None, to_lab=lab_id, actor_id=admin.id, status_="awaiting_recipient")
    case_status.log_event(patient_id, actor_id=admin.id, type="reassigned", remarks="Waiting for the lab to choose a dentist")
    return {"ok": True}


# ── accounts ─────────────────────────────────────────────────────────────────


def _row_to_profile(row: dict[str, Any]) -> ProfileOut:
    return ProfileOut(
        id=str(row.get("id")),
        name=row.get("name"),
        email=row.get("email"),
        phone=row.get("phone"),
        role=row.get("role"),
        clinic_name=row.get("clinic_name"),
        verified=bool(row.get("verified") or False),
        deleted=bool(row.get("deleted") or False),
        updated_at=row.get("updated_at"),
    )


def _set_deleted(user_id: str, deleted: bool) -> ProfileOut:
    existing = _profile(user_id)
    if existing is None or existing.get("anonymized_at"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    rows = _rows(
        _db()
        .table("profiles")
        .update({"deleted": deleted, "updated_at": pa.utc_now_iso()})
        .eq("id", user_id)
    )
    clear_auth_cache()
    return _row_to_profile(rows[0] if rows else existing)


@router.delete("/users/{user_id}/soft-delete", response_model=ProfileActionOut)
def deactivate_user(user_id: str, _: AuthUser = Depends(require_admin)):
    """Deactivate: can't sign in; lab, patients and shares are kept. Reversible."""
    user = _set_deleted(user_id, True)
    # Cached sessions would keep working for up to a minute otherwise.
    clear_auth_cache()
    return ProfileActionOut(message="User deactivated", user=user)


@router.patch("/users/{user_id}/reactivate", response_model=ProfileActionOut)
def reactivate_user(user_id: str, _: AuthUser = Depends(require_admin)):
    return ProfileActionOut(message="User reactivated", user=_set_deleted(user_id, False))


@router.put("/users/{user_id}/avatar")
async def set_user_avatar(
    user_id: str,
    file: UploadFile = File(...),
    _: AuthUser = Depends(require_admin),
):
    """Only the admin changes profile photos (any account, including their own)."""
    profile = _profile(user_id)
    if profile is None or profile.get("anonymized_at"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    data = await file.read(avatars.MAX_BYTES + 1)
    return {"avatar_url": avatars.replace(profile, data)}


@router.delete("/users/{user_id}/hard-delete", response_model=ProfileActionOut)
def delete_user(user_id: str, admin: AuthUser = Depends(require_admin)):
    """Delete permanently. Patients are never deleted (see delete_account)."""
    if user_id == admin.id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "You can't delete the admin account")
    delete_account(user_id, actor_id=admin.id)
    clear_auth_cache()
    return ProfileActionOut(message="User permanently deleted", user=None)

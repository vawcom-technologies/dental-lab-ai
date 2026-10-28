"""Lab side (Phase 3): directory, dentists, settings, join / removal requests,
assigning patients, transfers between labs. Every lab route also accepts the admin."""

from __future__ import annotations

import re
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.core.security import AuthUser, canonicalize_role, get_current_user
from app.core.supabase_client import get_supabase_admin
from app.services import labs
from app.services import patient_access as pa
from app.services.notify import notify
from app.services.profiles import fetch_profile, fetch_profiles_by_ids

router = APIRouter()  # /api/labs
patients_router = APIRouter()  # /api/patients
transfers_router = APIRouter()  # /api/transfers

_PUBLIC = "id,name,clinic_name,avatar_url"


def _rows(query: Any) -> list[dict[str, Any]]:
    try:
        return list(getattr(query.execute(), "data", None) or [])
    except Exception as exc:
        raise pa.db_error(exc) from exc


def _is_admin(user: AuthUser) -> bool:
    return canonicalize_role(user.role, default="") == "admin"


def _admins() -> list[str]:
    return [str(r["id"]) for r in _rows(get_supabase_admin().table("profiles").select("id").eq("role", "admin"))]


def _name(p: dict[str, Any] | None) -> str | None:
    return pa.profile_display_name(p, fallback="") or None if p else None


# ── directory, dentists, settings ────────────────────────────────────────────


class SettingsIn(BaseModel):
    hidden_from_labs: bool | None = None
    hide_dentists: bool | None = None


@router.get("", summary="Labs you can pick (hidden labs left out, except for the admin)")
def list_labs(q: str | None = None, user: AuthUser = Depends(get_current_user)):
    query = (
        get_supabase_admin().table("profiles").select(_PUBLIC)
        .eq("role", "laboratory").eq("verified", True).eq("deleted", False).is_("anonymized_at", "null")
    )
    if not _is_admin(user):
        query = query.eq("hidden_from_labs", False)
    term = re.sub(r"[%*,()\\]", " ", q or "").strip()
    if term:
        query = query.ilike("name", f"%{term}%")
    return [
        {"id": str(r["id"]), "name": r.get("name"), "avatar_url": r.get("avatar_url")}
        for r in _rows(query.order("name"))
        if str(r["id"]) != user.id
    ]


@router.get("/{lab_id}/dentists")
def lab_dentists(lab_id: str, user: AuthUser = Depends(get_current_user)):
    labs.caller_lab(user, lab_id)
    rows = _rows(
        get_supabase_admin().table("profiles")
        .select("id,name,email,phone,clinic_name,avatar_url,deleted")
        .eq("role", "dentist").eq("lab_id", lab_id).is_("anonymized_at", "null").order("name")
    )
    return [{**r, "id": str(r["id"]), "deleted": bool(r.get("deleted"))} for r in rows]


@router.get("/{lab_id}/settings")
def get_lab_settings(lab_id: str, user: AuthUser = Depends(get_current_user)):
    lab = labs.caller_lab(user, lab_id)
    return {"hidden_from_labs": bool(lab.get("hidden_from_labs")), "hide_dentists": bool(lab.get("hide_dentists"))}


@router.patch("/{lab_id}/settings")
def lab_settings(lab_id: str, body: SettingsIn, user: AuthUser = Depends(get_current_user)):
    labs.caller_lab(user, lab_id)
    patch = body.model_dump(exclude_none=True)
    if patch:
        _rows(get_supabase_admin().table("profiles").update(patch).eq("id", lab_id))
    lab = labs.require_lab(lab_id)
    return {"hidden_from_labs": bool(lab.get("hidden_from_labs")), "hide_dentists": bool(lab.get("hide_dentists"))}


# ── join / removal / transfer requests ───────────────────────────────────────


class RemovalIn(BaseModel):
    dentist_id: str
    reason: str = Field(min_length=1, max_length=1000)


class JoinIn(BaseModel):
    patient_ids: list[str] = Field(default_factory=list)


class DentistTransferIn(BaseModel):
    to_lab_id: str
    patient_ids: list[str] = Field(default_factory=list)


@router.post("/{lab_id}/join-requests", status_code=status.HTTP_201_CREATED)
def request_to_join(
    lab_id: str,
    body: JoinIn | None = None,
    user: AuthUser = Depends(get_current_user),
):
    """A dentist without a lab asks to join. Optional patient_ids to bring (auto-share on accept)."""
    me = labs.require_active_dentist(user.id)
    if me.get("lab_id"):
        raise HTTPException(status.HTTP_409_CONFLICT, "You're already in a lab")
    lab = labs.require_lab(lab_id)
    if lab.get("hidden_from_labs"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lab not found")
    db = get_supabase_admin()
    if _rows(db.table("lab_requests").select("id").eq("dentist_id", user.id).eq("kind", "join").eq("status", "pending")):
        raise HTTPException(status.HTTP_409_CONFLICT, "You already have a pending request")
    pids = (body or JoinIn()).patient_ids
    row = _rows(db.table("lab_requests").insert({"kind": "join", "lab_id": lab_id, "dentist_id": user.id, "patient_ids": pids}))[0]
    notify(user_id=lab_id, type="case_status", message=f"{_name(me)} asked to join your lab.", actor_id=user.id)
    return {"id": str(row["id"]), "status": "pending", "patient_ids": pids}


@router.post("/transfer-requests", status_code=status.HTTP_201_CREATED)
def request_lab_transfer(body: DentistTransferIn, user: AuthUser = Depends(get_current_user)):
    """Dentist asks their current lab to move them to another lab."""
    me = labs.require_active_dentist(user.id)
    current = str(me.get("lab_id") or "")
    if not current:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Join a lab before requesting a transfer")
    to_lab_id = str(body.to_lab_id).strip()
    if to_lab_id == current:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Pick a different lab")
    dest = labs.require_lab(to_lab_id)
    if dest.get("hidden_from_labs"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lab not found")
    db = get_supabase_admin()
    if _rows(db.table("lab_requests").select("id").eq("dentist_id", user.id).eq("kind", "transfer").eq("status", "pending")):
        raise HTTPException(status.HTTP_409_CONFLICT, "You already have a pending transfer")
    pids = body.patient_ids
    row = _rows(
        db.table("lab_requests").insert(
            {"kind": "transfer", "lab_id": current, "to_lab_id": to_lab_id, "dentist_id": user.id, "patient_ids": pids}
        )
    )[0]
    notify(user_id=current, type="case_status", message=f"{_name(me)} asked to transfer to {_name(dest)}.", actor_id=user.id)
    return {"id": str(row["id"]), "status": "pending", "to_lab_id": to_lab_id, "patient_ids": pids}


@router.delete("/transfer-requests/mine", summary="Dentist withdraws their pending transfer")
def cancel_transfer_request(user: AuthUser = Depends(get_current_user)):
    rows = _rows(
        get_supabase_admin().table("lab_requests").delete()
        .eq("dentist_id", user.id).eq("kind", "transfer").eq("status", "pending")
    )
    if not rows:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No pending transfer")
    return {"ok": True}


@router.delete("/join-requests/mine", summary="Dentist withdraws their pending join request")
def cancel_join_request(user: AuthUser = Depends(get_current_user)):
    rows = _rows(
        get_supabase_admin().table("lab_requests").delete()
        .eq("dentist_id", user.id).eq("kind", "join").eq("status", "pending")
    )
    if not rows:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No pending request")
    return {"ok": True}


@router.get("/{lab_id}/requests", summary="Join / transfer requests to this lab and removal requests it filed")
def lab_requests(lab_id: str, user: AuthUser = Depends(get_current_user)):
    labs.caller_lab(user, lab_id)
    rows = _rows(get_supabase_admin().table("lab_requests").select("*").eq("lab_id", lab_id).order("created_at", desc=True))
    people_ids = {str(r["dentist_id"]) for r in rows}
    people_ids |= {str(r["to_lab_id"]) for r in rows if r.get("to_lab_id")}
    people = fetch_profiles_by_ids(people_ids)
    return [
        {
            "id": str(r["id"]),
            "kind": r.get("kind"),
            "status": r.get("status"),
            "reason": r.get("reason"),
            "created_at": r.get("created_at"),
            "patient_ids": r.get("patient_ids") or [],
            "to_lab_id": r.get("to_lab_id"),
            "to_lab_name": (people.get(str(r.get("to_lab_id"))) or {}).get("name"),
            "dentist": {k: (people.get(str(r["dentist_id"])) or {}).get(k) for k in ("name", "email", "clinic_name", "avatar_url")}
            | {"id": str(r["dentist_id"])},
        }
        for r in rows
    ]


def _decide_request(lab_id: str, request_id: str, user: AuthUser, accept: bool) -> dict:
    labs.caller_lab(user, lab_id)
    rows = _rows(get_supabase_admin().table("lab_requests").select("*").eq("id", request_id).eq("lab_id", lab_id))
    req = rows[0] if rows else None
    if req is None or req.get("kind") not in ("join", "transfer"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Request not found")
    if req.get("status") != "pending":
        raise HTTPException(status.HTTP_409_CONFLICT, "Request was already decided")
    dentist = labs.require_active_dentist(str(req["dentist_id"]))
    kind = req.get("kind")
    pids = req.get("patient_ids") or []
    if accept:
        if kind == "join":
            if dentist.get("lab_id"):
                raise HTTPException(status.HTTP_409_CONFLICT, "This dentist is already in a lab")
            labs.set_lab(dentist, lab_id, actor_id=user.id)
            labs.share_owned_with_lab(str(dentist["id"]), lab_id, pids, actor_id=user.id)
        else:
            # transfer: current lab (lab_id) releases; move to to_lab_id
            if str(dentist.get("lab_id") or "") != lab_id:
                raise HTTPException(status.HTTP_409_CONFLICT, "This dentist is no longer in your lab")
            to_lab_id = str(req["to_lab_id"])
            labs.apply_transfer(dentist, to_lab_id, pids, actor_id=user.id)
            notify(user_id=to_lab_id, type="case_status", message=f"{_name(dentist)} joined your lab (transferred).", actor_id=user.id)
            notify(
                user_id=str(dentist["id"]),
                type="case_status",
                message=f"Your transfer to {_name(fetch_profile(to_lab_id))} was approved.",
                actor_id=user.id,
            )
    _rows(
        get_supabase_admin().table("lab_requests")
        .update({"status": "approved" if accept else "rejected", "decided_by": user.id, "decided_at": pa.utc_now_iso()})
        .eq("id", request_id)
    )
    if kind == "join":
        lab_name = _name(fetch_profile(lab_id))
        notify(
            user_id=str(dentist["id"]),
            type="case_status",
            message=f"{lab_name} accepted you." if accept else f"{lab_name} declined your request. You can ask again.",
            actor_id=user.id,
        )
    elif not accept:
        notify(
            user_id=str(dentist["id"]),
            type="case_status",
            message="Your lab transfer request was declined.",
            actor_id=user.id,
        )
    return {"ok": True}


@router.post("/{lab_id}/requests/{request_id}/accept")
def accept_request(lab_id: str, request_id: str, user: AuthUser = Depends(get_current_user)):
    return _decide_request(lab_id, request_id, user, True)


@router.post("/{lab_id}/requests/{request_id}/reject")
def reject_request(lab_id: str, request_id: str, user: AuthUser = Depends(get_current_user)):
    return _decide_request(lab_id, request_id, user, False)


@router.post("/{lab_id}/removal-requests", status_code=status.HTTP_201_CREATED)
def request_removal(lab_id: str, body: RemovalIn, user: AuthUser = Depends(get_current_user)):
    """The lab asks to remove one of its dentists; the admin decides."""
    labs.caller_lab(user, lab_id)
    dentist = labs.require_active_dentist(body.dentist_id, lab_id)
    db = get_supabase_admin()
    if _rows(db.table("lab_requests").select("id").eq("dentist_id", body.dentist_id).eq("kind", "remove").eq("status", "pending")):
        raise HTTPException(status.HTTP_409_CONFLICT, "A removal request for this dentist is already pending")
    row = _rows(db.table("lab_requests").insert(
        {"kind": "remove", "lab_id": lab_id, "dentist_id": body.dentist_id, "reason": body.reason.strip()}
    ))[0]
    for admin_id in _admins():
        notify(user_id=admin_id, type="case_status", message=f"A lab asked to remove {_name(dentist)}.", actor_id=user.id)
    return {"id": str(row["id"]), "status": "pending"}


# ── patients: assign / move, transfers ───────────────────────────────────────


class AssignIn(BaseModel):
    dentist_id: str
    lab_id: str | None = None  # the admin names the lab; a lab acts for itself


class TransferIn(BaseModel):
    to_lab_id: str


class DecideIn(BaseModel):
    dentist_id: str | None = None
    reason: str | None = Field(default=None, max_length=1000)


@patients_router.post("/{patient_id}/assign", summary="Lab moves a patient to one of its dentists")
def assign_patient(patient_id: str, body: AssignIn, user: AuthUser = Depends(get_current_user)):
    lab_id = (body.lab_id or "").strip() if _is_admin(user) else user.id
    if not lab_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "lab_id is required")
    labs.caller_lab(user, lab_id)
    patient = pa.fetch_patient(patient_id)
    if patient is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Patient not found")
    if not labs.can_assign(user, patient, lab_id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Your lab hasn't been given this patient")
    dentist = labs.require_active_dentist(body.dentist_id, lab_id)
    if str(patient.get("created_by")) == str(dentist["id"]):
        raise HTTPException(status.HTTP_409_CONFLICT, "This dentist already owns the patient")
    labs.assign_owner(patient, dentist, lab_id=lab_id, actor_id=user.id)
    return {"ok": True}


@patients_router.post("/{patient_id}/transfers", status_code=status.HTTP_201_CREATED, summary="Share with another lab")
def start_transfer(patient_id: str, body: TransferIn, user: AuthUser = Depends(get_current_user)):
    """The patient's dentist asks their lab to share the patient with another lab;
    the admin sends it straight to the other lab."""
    patient = pa.require_patient_access(patient_id, user.id)
    labs.require_owner(user, patient)
    to_lab = labs.require_lab(body.to_lab_id)
    if _is_admin(user):
        from_lab, first = None, "awaiting_recipient"
    else:
        me = labs.require_active_dentist(user.id)
        from_lab, first = str(me.get("lab_id") or ""), "awaiting_sender"
        if not from_lab:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "You're not linked to a lab yet")
        if to_lab.get("hidden_from_labs") or str(to_lab["id"]) == from_lab:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Pick another lab")
    row = labs.open_transfer(patient, kind="share", from_lab=from_lab, to_lab=str(to_lab["id"]), actor_id=user.id, status_=first)
    return _transfer_out(row, {})


def _transfer_out(t: dict[str, Any], people: dict[str, dict[str, Any]], patients: dict[str, dict] | None = None) -> dict:
    p = (patients or {}).get(str(t["patient_id"]))
    return {
        "id": str(t["id"]),
        "kind": t.get("kind"),
        "status": t.get("status"),
        "patient_id": str(t["patient_id"]),
        "patient_name": pa.patient_display_name(p) if p else None,
        "from_lab": {"id": t.get("from_lab_id"), "name": _name(people.get(str(t.get("from_lab_id") or "")))},
        "to_lab": {"id": str(t["to_lab_id"]), "name": _name(people.get(str(t["to_lab_id"])))},
        "requested_by_name": _name(people.get(str(t.get("requested_by") or ""))),
        "dentist_name": _name(people.get(str(t.get("dentist_id") or ""))),
        "reason": t.get("reason"),
        "created_at": t.get("created_at"),
        "updated_at": t.get("updated_at"),
    }


@router.get("/{lab_id}/transfers", summary="Transfers sent by or to this lab (waiting_on_us first in the app)")
def lab_transfers(lab_id: str, user: AuthUser = Depends(get_current_user)):
    labs.caller_lab(user, lab_id)
    rows = _rows(
        get_supabase_admin().table("lab_transfers").select("*")
        .or_(f"from_lab_id.eq.{lab_id},to_lab_id.eq.{lab_id}").order("created_at", desc=True)
    )
    people = fetch_profiles_by_ids(
        {str(t.get(k) or "") for t in rows for k in ("from_lab_id", "to_lab_id", "requested_by", "dentist_id")} - {""}
    )
    pids = list({str(t["patient_id"]) for t in rows})
    patients = {
        str(p["id"]): p
        for p in (_rows(get_supabase_admin().table("patients").select("id,first_name,last_name").in_("id", pids)) if pids else [])
    }
    out = []
    for t in rows:
        item = _transfer_out(t, people, patients)
        st = t.get("status")
        item["waiting_on_us"] = (st == "awaiting_sender" and str(t.get("from_lab_id")) == lab_id) or (
            st == "awaiting_recipient" and str(t["to_lab_id"]) == lab_id
        )
        out.append(item)
    return out


def _decide(transfer_id: str, action: str, body: DecideIn | None, user: AuthUser) -> dict:
    t = labs.decide_transfer(
        labs.fetch_transfer(transfer_id), user, action=action,
        dentist_id=body.dentist_id if body else None, reason=body.reason if body else None,
    )
    return {"id": str(t["id"]), "status": t.get("status")}


@transfers_router.post("/{transfer_id}/forward", summary="Sending lab passes it on to the other lab")
def forward_transfer(transfer_id: str, user: AuthUser = Depends(get_current_user)):
    return _decide(transfer_id, "forward", None, user)


@transfers_router.post("/{transfer_id}/accept", summary="Receiving lab accepts and picks a dentist")
def accept_transfer(transfer_id: str, body: DecideIn, user: AuthUser = Depends(get_current_user)):
    if not body.dentist_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Choose a dentist")
    return _decide(transfer_id, "accept", body, user)


@transfers_router.post("/{transfer_id}/reject")
def reject_transfer(transfer_id: str, body: DecideIn, user: AuthUser = Depends(get_current_user)):
    return _decide(transfer_id, "reject", body, user)

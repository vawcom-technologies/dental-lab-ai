"""Lab membership: a dentist joining, leaving or moving between labs."""

from __future__ import annotations

from typing import Any

from fastapi import HTTPException, status

from app.core.security import AuthUser, canonicalize_role
from app.core.supabase_client import get_supabase_admin
from app.services import case_status
from app.services import patient_access as pa
from app.services.notify import notify
from app.services.profiles import fetch_profile


def _execute(query: Any) -> list[dict[str, Any]]:
    try:
        return list(getattr(query.execute(), "data", None) or [])
    except Exception as exc:
        raise pa.db_error(exc) from exc


def require_lab(lab_id: str) -> dict[str, Any]:
    rows = _execute(
        get_supabase_admin().table("profiles").select("*").eq("id", lab_id).limit(1)
    )
    lab = rows[0] if rows else None
    if (
        lab is None
        or lab.get("role") != "laboratory"
        or lab.get("anonymized_at")
        or lab.get("deleted")
        or lab.get("verified") is not True
    ):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Lab not found")
    return lab


def _leave_lab(dentist_id: str, lab_id: str, actor_id: str | None) -> None:
    """Old lab loses open cases (under review → in progress); completed stay view-only."""
    patients = _execute(
        get_supabase_admin()
        .table("patients")
        .select("id,status")
        .eq("created_by", dentist_id)
        .eq("deleted", False)
    )
    open_ids = []
    for p in patients:
        if p.get("status") == "completed":
            continue
        open_ids.append(str(p["id"]))
        if p.get("status") == "in_review":
            case_status.set_status(p, "in_progress", actor_id=actor_id, type="lab_left")
    if open_ids:
        _execute(
            get_supabase_admin()
            .table("patient_access")
            .delete()
            .eq("user_id", lab_id)
            .in_("patient_id", open_ids)
        )


def set_lab(
    dentist: dict[str, Any],
    lab_id: str | None,
    *,
    actor_id: str | None,
    reason: str = "removed",
) -> dict[str, Any]:
    """Move a dentist to `lab_id`, or out of their lab (None) with `reason`:
    no_lab | removed | lab_deleted."""
    old = dentist.get("lab_id")
    if old == lab_id:
        return dentist
    if old:
        _leave_lab(str(dentist["id"]), str(old), actor_id)
    now = pa.utc_now_iso()
    patch = {
        "lab_id": lab_id,
        "unassigned_reason": None if lab_id else reason,
        "unassigned_at": None if lab_id else now,
        "updated_at": now,
    }
    if lab_id:
        patch["lab_join_deferred_at"] = None
    rows = _execute(
        get_supabase_admin().table("profiles").update(patch).eq("id", str(dentist["id"]))
    )
    return rows[0] if rows else {**dentist, **patch}


# ── Phase 3: acting for a lab, sharing, owners, transfers ───────────────────

OPEN = ("awaiting_sender", "awaiting_recipient")


def _role(user: AuthUser) -> str:
    return canonicalize_role(user.role, default="")


def caller_lab(user: AuthUser, lab_id: str) -> dict[str, Any]:
    """A lab acts only for itself; the admin can act for any lab."""
    if _role(user) != "admin" and user.id != lab_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "You can only act for your own lab")
    return require_lab(lab_id)


def require_active_dentist(dentist_id: str, lab_id: str | None = None) -> dict[str, Any]:
    d = fetch_profile(dentist_id)
    if not d or d.get("role") != "dentist" or d.get("deleted") or d.get("verified") is not True:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Dentist not found")
    if lab_id and str(d.get("lab_id") or "") != lab_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "That dentist isn't in this lab")
    return d


def require_owner(user: AuthUser, patient: dict[str, Any]) -> None:
    """Only the owner (or the admin) passes a patient on. A dentist it was shared
    with can work on it but can't share it further, so it never spreads beyond
    what the owner and their lab agreed to."""
    if _role(user) != "admin" and not pa.is_owner(patient, user.id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only the patient's dentist can share this patient")


def share_rule(user: AuthUser, patient: dict[str, Any], target: dict[str, Any]) -> tuple[str, str | None]:
    """(status, ticket_lab_id) for the owner sharing a patient with `target`.
    Own lab → immediate; a dentist in your lab → ticket for your lab;
    anyone else → a transfer. The admin shares with anyone immediately."""
    require_owner(user, patient)
    if _role(user) == "admin":
        return "approved", None
    me = fetch_profile(user.id) or {}
    my_lab = str(me.get("lab_id") or "")
    if _role(user) != "dentist" or not my_lab:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Only dentists in a lab can share patients")
    if str(target["id"]) == my_lab:
        return "approved", None
    if target.get("role") == "dentist" and str(target.get("lab_id") or "") == my_lab:
        return "pending", my_lab
    raise HTTPException(
        status.HTTP_400_BAD_REQUEST,
        {"detail": "To share outside your lab, send a transfer to the other lab.", "code": "USE_TRANSFER"},
    )


def grant(patient_id: str, user_id: str, actor_id: str) -> None:
    _execute(
        get_supabase_admin().table("patient_access").upsert(
            {
                "patient_id": patient_id,
                "user_id": user_id,
                "granted_by": actor_id,
                "requested_by": actor_id,
                "approved_by": actor_id,
                "status": "approved",
                "ticket_lab_id": None,
                "created_at": pa.utc_now_iso(),
            },
            on_conflict="patient_id,user_id",
        )
    )


def share_owned_with_lab(dentist_id: str, lab_id: str, patient_ids: list[str], *, actor_id: str) -> None:
    """Auto-share the dentist's owned patients with `lab_id`."""
    if not patient_ids:
        return
    owned = _execute(
        get_supabase_admin().table("patients").select("id")
        .eq("created_by", dentist_id).eq("deleted", False).in_("id", patient_ids)
    )
    for row in owned:
        grant(str(row["id"]), lab_id, actor_id)


def apply_transfer(dentist: dict[str, Any], to_lab_id: str, patient_ids: list[str], *, actor_id: str) -> None:
    """Move a dentist to another lab and share the patients they bring."""
    require_lab(to_lab_id)
    set_lab(dentist, to_lab_id, actor_id=actor_id)
    share_owned_with_lab(str(dentist["id"]), to_lab_id, patient_ids, actor_id=actor_id)


def clear_pending_lab_moves(dentist_id: str) -> None:
    """Cancel open join/transfer requests (e.g. admin force-assign)."""
    _execute(
        get_supabase_admin()
        .table("lab_requests")
        .update({"status": "rejected", "decided_at": pa.utc_now_iso()})
        .eq("dentist_id", dentist_id)
        .in_("kind", ["join", "transfer"])
        .eq("status", "pending")
    )


def assign_owner(patient: dict[str, Any], dentist: dict[str, Any], *, lab_id: str, actor_id: str) -> None:
    """Make `dentist` (of `lab_id`) the owner. The lab keeps access; the previous
    owner loses it (a move, not a share); open handovers for the patient close."""
    pid, new = str(patient["id"]), str(dentist["id"])
    _execute(
        get_supabase_admin()
        .table("patients")
        .update({"created_by": new, "unassigned_at": None, "waiting_lab_id": None, "updated_at": pa.utc_now_iso()})
        .eq("id", pid)
    )
    _execute(get_supabase_admin().table("patient_access").delete().eq("patient_id", pid).eq("user_id", new))
    grant(pid, lab_id, actor_id)
    _execute(
        get_supabase_admin()
        .table("lab_transfers")
        .update({"status": "cancelled", "updated_at": pa.utc_now_iso()})
        .eq("patient_id", pid)
        .eq("kind", "handover")
        .in_("status", list(OPEN))
    )
    case_status.log_event(pid, actor_id=actor_id, type="reassigned", remarks=f"Assigned to {pa.profile_display_name(dentist)}")
    name = pa.patient_display_name(patient)
    notify(user_id=new, type="case_status", message=f"{name} was assigned to you.", patient_id=pid, actor_id=actor_id)
    old = str(patient.get("created_by") or "")
    if old and old != new:
        notify(user_id=old, type="case_status", message=f"{name} was moved to another dentist.", patient_id=pid, actor_id=actor_id)


def can_assign(user: AuthUser, patient: dict[str, Any], lab_id: str) -> bool:
    """A lab moves only patients it was given: shared with it, created by it, or waiting on it."""
    pid = str(patient["id"])
    return (
        _role(user) == "admin"
        or str(patient.get("created_by") or "") == lab_id
        or str(patient.get("waiting_lab_id") or "") == lab_id
        or pa.has_shared_access(pid, lab_id)
    )


def fetch_transfer(transfer_id: str) -> dict[str, Any]:
    rows = _execute(get_supabase_admin().table("lab_transfers").select("*").eq("id", transfer_id).limit(1))
    if not rows:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Transfer not found")
    return rows[0]


def open_transfer(
    patient: dict[str, Any], *, kind: str, from_lab: str | None, to_lab: str, actor_id: str, status_: str
) -> dict[str, Any]:
    pid = str(patient["id"])
    existing = _execute(
        get_supabase_admin().table("lab_transfers").select("id").eq("patient_id", pid).eq("to_lab_id", to_lab).in_("status", list(OPEN))
    )
    if existing:
        raise HTTPException(status.HTTP_409_CONFLICT, "There is already an open transfer to that lab")
    rows = _execute(
        get_supabase_admin().table("lab_transfers").insert(
            {"kind": kind, "patient_id": pid, "from_lab_id": from_lab, "to_lab_id": to_lab,
             "requested_by": actor_id, "status": status_}
        )
    )
    waiting_on = from_lab if status_ == "awaiting_sender" else to_lab
    notify(
        user_id=waiting_on,
        type="case_status",
        message=f"Transfer request for {pa.patient_display_name(patient)}.",
        patient_id=pid,
        actor_id=actor_id,
    )
    return rows[0]


def decide_transfer(
    transfer: dict[str, Any], user: AuthUser, *, action: str, dentist_id: str | None = None, reason: str | None = None
) -> dict[str, Any]:
    """forward (sender lab) → accept with a dentist / reject (whichever lab it waits on)."""
    st = transfer.get("status")
    waiting_on = str((transfer.get("from_lab_id") if st == "awaiting_sender" else transfer.get("to_lab_id")) or "")
    if st not in OPEN:
        raise HTTPException(status.HTTP_409_CONFLICT, "This transfer is already closed")
    if _role(user) != "admin" and user.id != waiting_on:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "This transfer isn't waiting on your lab")
    patient = pa.fetch_patient(str(transfer["patient_id"]))
    if patient is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Patient not found")
    pid, name = str(patient["id"]), pa.patient_display_name(patient)
    patch: dict[str, Any] = {"decided_by": user.id, "updated_at": pa.utc_now_iso()}

    if action == "forward":
        if st != "awaiting_sender":
            raise HTTPException(status.HTTP_409_CONFLICT, "Only the sending lab forwards a transfer")
        patch["status"] = "awaiting_recipient"
        notify(user_id=str(transfer["to_lab_id"]), type="case_status", message=f"Transfer request for {name}.", patient_id=pid, actor_id=user.id)
    elif action == "accept":
        if st != "awaiting_recipient":
            raise HTTPException(status.HTTP_409_CONFLICT, "The sending lab hasn't forwarded this transfer yet")
        to_lab = str(transfer["to_lab_id"])
        dentist = require_active_dentist(dentist_id or "", to_lab)
        if transfer.get("kind") == "handover":
            assign_owner(patient, dentist, lab_id=to_lab, actor_id=user.id)
        else:
            grant(pid, str(dentist["id"]), user.id)
            case_status.log_event(pid, actor_id=user.id, type="shared", remarks=f"Shared with {pa.profile_display_name(dentist)}")
            notify(user_id=str(dentist["id"]), type="case_status", message=f"{name} was shared with you.", patient_id=pid, actor_id=user.id)
        patch |= {"status": "accepted", "dentist_id": str(dentist["id"])}
    elif action == "reject":
        patch |= {"status": "rejected", "reason": (reason or "").strip() or None}
        if transfer.get("kind") == "handover":
            # Back to the sender, still unassigned, so it can pick a dentist or another lab.
            _execute(get_supabase_admin().table("patients").update({"waiting_lab_id": None}).eq("id", pid).eq("waiting_lab_id", str(transfer["to_lab_id"])))
    else:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Unknown action")

    rows = _execute(get_supabase_admin().table("lab_transfers").update(patch).eq("id", str(transfer["id"])))
    if action != "forward":
        for uid in {str(transfer.get("requested_by") or ""), str(transfer.get("from_lab_id") or "")} - {"", user.id}:
            notify(user_id=uid, type="case_status", message=f"Transfer of {name} was {patch['status']}.", patient_id=pid, actor_id=user.id)
    return rows[0] if rows else {**transfer, **patch}


# ── Phase 4: who may message whom ────────────────────────────────────────────


def _patients_of(user_id: str) -> set[str]:
    """Patients a user owns or was approved to see."""
    db = get_supabase_admin()
    owned = _execute(db.table("patients").select("id").eq("created_by", user_id).eq("deleted", False))
    shared = _execute(db.table("patient_access").select("patient_id").eq("user_id", user_id).eq("status", "approved"))
    return {str(r["id"]) for r in owned} | {str(r["patient_id"]) for r in shared}


def _people_on(patient_ids: set[str]) -> set[str]:
    """Everyone with access to any of these patients."""
    if not patient_ids:
        return set()
    db = get_supabase_admin()
    ids = list(patient_ids)
    owners = _execute(db.table("patients").select("created_by").in_("id", ids))
    shared = _execute(db.table("patient_access").select("user_id").in_("patient_id", ids).eq("status", "approved"))
    return {str(r["created_by"]) for r in owners} | {str(r["user_id"]) for r in shared}


def messaging_rule(viewer_id: str):
    """Predicate over profiles: may `viewer_id` message them? (docs/roadmap.md → Messaging)
    Same-lab dentists; a dentist and their own lab; lab ↔ lab; the admin ↔ anyone;
    and anyone sharing access to a patient. Built once per viewer so contact lists
    don't query per row."""
    me = fetch_profile(viewer_id) or {}
    my_role, my_lab = me.get("role"), str(me.get("lab_id") or "")
    if me.get("deleted"):
        return lambda other: False
    shared_people: set[str] | None = None

    def allowed(other: dict[str, Any] | None) -> bool:
        nonlocal shared_people
        if not other or other.get("deleted") or str(other.get("id")) == viewer_id:
            return False
        role, oid = other.get("role"), str(other["id"])
        lab = str(other.get("lab_id") or "")
        if "admin" in (my_role, role):
            return True
        if my_role == role == "laboratory":
            return True
        if my_role == "dentist" and role == "laboratory" and my_lab == oid:
            return True
        if my_role == "laboratory" and role == "dentist" and lab == viewer_id:
            return True
        if my_role == role == "dentist" and my_lab and my_lab == lab:
            return True
        if shared_people is None:
            shared_people = _people_on(_patients_of(viewer_id))
        return oid in shared_people

    return allowed


def can_message(sender_id: str, recipient_id: str) -> bool:
    return messaging_rule(sender_id)(fetch_profile(recipient_id))


def _pending(dentist_id: str, kind: str, lab_col: str, name_key: str) -> dict[str, Any] | None:
    rows = _execute(
        get_supabase_admin().table("lab_requests").select("*")
        .eq("dentist_id", dentist_id).eq("kind", kind).eq("status", "pending").limit(1)
    )
    if not rows:
        return None
    lab = fetch_profile(str(rows[0].get(lab_col) or ""))
    return {**rows[0], "id": str(rows[0]["id"]), name_key: pa.profile_display_name(lab, fallback="") or None}


def pending_join(dentist_id: str) -> dict[str, Any] | None:
    """The dentist's open request to join a lab."""
    return _pending(dentist_id, "join", "lab_id", "lab_name")


def pending_transfer(dentist_id: str) -> dict[str, Any] | None:
    """Open transfer request (current lab decides)."""
    return _pending(dentist_id, "transfer", "to_lab_id", "to_lab_name")

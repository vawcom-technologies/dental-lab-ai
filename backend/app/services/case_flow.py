"""Automatic case status (docs/roadmap.md → Status flow).

Every scan / shade / smile change, sharing with the lab, "Submit to lab" and the
lab's review go through here, so the rules live in one place.
"""

from __future__ import annotations

from typing import Any

from fastapi import HTTPException, status

from app.core.security import AuthUser, canonicalize_role
from app.core.supabase_client import get_supabase_admin
from app.services import case_status
from app.services import patient_access as pa
from app.services import patient_media as pm
from app.services.notify import notify
from app.services.profiles import fetch_profile

LOCKED = ("in_review", "completed")
_ITEMS = (  # (name, table, extra filter)
    ("scan", "patient_scans", None),
    ("shade", "shade_detections", "analysis"),  # only a shade with a saved analysis counts
    ("smile", "smile_previews", None),
)


def _role(user: AuthUser) -> str:
    return canonicalize_role(user.role, default="")


# ── guards ───────────────────────────────────────────────────────────────────


def require_can_change(user: AuthUser) -> None:
    """Labs review; they never upload, edit or delete scans, shades or smiles."""
    if _role(user) == "laboratory":
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "Labs can review cases but not change scans, shades or smile previews."
        )


def require_can_delete(user: AuthUser, table: str, row_id: str) -> None:
    require_can_change(user)
    row = pm.fetch_row(table, row_id)
    if row is not None:
        require_unlocked(str(row.get("patient_id") or ""))


def require_unlocked(patient_id: str) -> None:
    """Under review / completed: items can only be replaced, not deleted."""
    patient = pa.fetch_patient(patient_id)
    if patient and patient.get("status") in LOCKED:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            {"detail": "This case is with the lab. Replace the item instead of deleting it.", "code": "CASE_LOCKED"},
        )


# ── facts ────────────────────────────────────────────────────────────────────


def items(patient_id: str) -> dict[str, bool]:
    out = {}
    for name, table, needs in _ITEMS:
        q = get_supabase_admin().table(table).select("id").eq("patient_id", patient_id).limit(1)
        if needs:
            q = q.not_.is_(needs, "null")
        try:
            out[name] = bool(getattr(q.execute(), "data", None))
        except Exception as exc:
            raise pa.db_error(exc) from exc
    return out


def owner_lab(patient: dict[str, Any]) -> str | None:
    """The reviewing lab: the owner dentist's lab."""
    owner = fetch_profile(str(patient.get("created_by") or ""))
    if not owner or owner.get("role") != "dentist":
        return None
    return str(owner.get("lab_id") or "") or None


def _shared_lab(patient: dict[str, Any]) -> str | None:
    lab = owner_lab(patient)
    return lab if lab and pa.has_shared_access(str(patient["id"]), lab) else None


# ── transitions ──────────────────────────────────────────────────────────────


def _submit(patient: dict[str, Any], lab_id: str, actor_id: str, remarks: str | None) -> dict[str, Any]:
    patient = case_status.set_status(
        patient, "in_review", actor_id=actor_id, type="submitted", remarks=remarks, auto_submit=True
    )
    notify(
        user_id=lab_id,
        type="case_status",
        message=f"{pa.patient_display_name(patient)} was submitted for review.",
        patient_id=str(patient["id"]),
        actor_id=actor_id,
    )
    return patient


def maybe_auto_submit(patient: dict[str, Any], actor_id: str) -> dict[str, Any]:
    if patient.get("status") != "in_progress" or patient.get("auto_submit") is False:
        return patient
    lab = _shared_lab(patient)
    if lab is None or not all(items(str(patient["id"])).values()):
        return patient
    return _submit(patient, lab, actor_id, "Submitted automatically: scan, shade and smile preview saved")


def after_change(patient_id: str, actor_id: str, *, scan: bool = False) -> dict[str, Any] | None:
    """Call after a scan, shade or smile was added, replaced or edited."""
    patient = pa.fetch_patient(patient_id)
    if patient is None:
        return None
    st = patient.get("status") or "pending"
    if st == "pending":
        if not scan:
            return patient
        patient = case_status.set_status(patient, "in_progress", actor_id=actor_id, type="scan_added")
    elif st == "rejected":
        # Work resumes; automatic submission stays off until the dentist submits by hand.
        return case_status.set_status(patient, "in_progress", actor_id=actor_id, type="updated")
    elif st in LOCKED:
        lab = _shared_lab(patient)
        if st == "completed":
            patient = case_status.set_status(
                patient, "in_review" if lab else "in_progress", actor_id=actor_id, type="reopened"
            )
        else:
            case_status.log_event(patient_id, actor_id=actor_id, type="updated", to_status=st)
        if lab:
            verb = "reopened" if st == "completed" else "updated"
            notify(
                user_id=lab,
                type="case_status",
                message=f"{pa.patient_display_name(patient)} was {verb} by the dentist.",
                patient_id=patient_id,
                actor_id=actor_id,
            )
        return patient
    return maybe_auto_submit(patient, actor_id)


def after_share(patient_id: str, target_user_id: str, actor_id: str) -> None:
    """Sharing with the owner's lab can complete the automatic-submission conditions."""
    patient = pa.fetch_patient(patient_id)
    if patient and owner_lab(patient) == str(target_user_id):
        maybe_auto_submit(patient, actor_id)


def submit(patient: dict[str, Any], user: AuthUser, *, confirm_incomplete: bool) -> dict[str, Any]:
    """"Submit to lab": shares with the owner's lab and turns automatic submission back on."""
    require_can_change(user)
    if patient.get("status") in LOCKED:
        raise HTTPException(status.HTTP_409_CONFLICT, "This case is already with the lab")
    lab = owner_lab(patient)
    if lab is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "The patient's dentist isn't linked to a lab yet.")
    missing = [name for name, ok in items(str(patient["id"])).items() if not ok]
    if missing and not confirm_incomplete:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            {"detail": "Some items are missing.", "code": "INCOMPLETE", "missing": missing},
        )
    if not pa.has_shared_access(str(patient["id"]), lab):
        now = pa.utc_now_iso()
        try:
            get_supabase_admin().table("patient_access").upsert(
                {
                    "patient_id": str(patient["id"]),
                    "user_id": lab,
                    "granted_by": user.id,
                    "requested_by": user.id,
                    "approved_by": user.id,
                    "status": "approved",
                    "created_at": now,
                },
                on_conflict="patient_id,user_id",
            ).execute()
        except Exception as exc:
            raise pa.db_error(exc) from exc
    remarks = f"Submitted without: {', '.join(missing)}" if missing else None
    return _submit(patient, lab, user.id, remarks)


def review(patient: dict[str, Any], user: AuthUser, *, approve: bool, remarks: str | None) -> dict[str, Any]:
    """The owner's lab (or the admin) approves → completed, or rejects with remarks."""
    is_admin = _role(user) == "admin"
    if not is_admin and _shared_lab(patient) != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Only the patient's lab can review this case.")
    if patient.get("status") != "in_review":
        raise HTTPException(status.HTTP_409_CONFLICT, "This case isn't waiting for review")
    remarks = (remarks or "").strip() or None
    if not approve and not remarks:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Remarks are required when rejecting")
    patient = case_status.set_status(
        patient,
        "completed" if approve else "rejected",
        actor_id=user.id,
        type="approved" if approve else "rejected",
        remarks=remarks,
        auto_submit=None if approve else False,
    )
    name = pa.patient_display_name(patient)
    notify(
        user_id=str(patient.get("created_by") or ""),
        type="case_status",
        message=f"The lab approved {name}." if approve else f"The lab rejected {name}: {remarks}",
        patient_id=str(patient["id"]),
        actor_id=user.id,
    )
    return patient


def summary(patient: dict[str, Any], user: AuthUser) -> dict[str, Any]:
    """Everything the app needs to show the case state and its actions."""
    pid = str(patient["id"])
    have = items(pid)
    lab_id = owner_lab(patient)
    lab = fetch_profile(lab_id) if lab_id else None
    shared = bool(lab_id) and pa.has_shared_access(pid, lab_id)
    st = patient.get("status") or "pending"
    try:
        events = getattr(
            get_supabase_admin().table("case_events").select("*").eq("patient_id", pid).order("created_at").execute(),
            "data",
            None,
        ) or []
    except Exception as exc:
        raise pa.db_error(exc) from exc
    names: dict[str, str | None] = {}
    for actor in {str(e.get("actor_id") or "") for e in events} - {""}:
        names[actor] = pa.profile_display_name(fetch_profile(actor), fallback="") or None
    rejection = None
    for e in reversed(events):
        if e.get("to_status") == "rejected":
            rejection = e
            break
        if e.get("type") in ("submitted", "approved"):
            break  # dealt with: resubmitted or approved since
    role = _role(user)
    return {
        "status": st,
        "auto_submit": patient.get("auto_submit") is not False,
        "items": have,
        "missing": [k for k, ok in have.items() if not ok],
        "lab": {"id": lab_id, "name": pa.profile_display_name(lab, fallback="") or None} if lab_id else None,
        "shared_with_lab": shared,
        "can_submit": role != "laboratory" and bool(lab_id) and st not in LOCKED,
        "can_review": st == "in_review" and (role == "admin" or (shared and user.id == lab_id)),
        "last_rejection": {
            "remarks": rejection.get("remarks"),
            "by": names.get(str(rejection.get("actor_id") or "")),
            "at": rejection.get("created_at"),
        }
        if rejection
        else None,
        "events": [
            {
                "type": e.get("type"),
                "actor_name": names.get(str(e.get("actor_id") or "")),
                "remarks": e.get("remarks"),
                "from_status": e.get("from_status"),
                "to_status": e.get("to_status"),
                "created_at": e.get("created_at"),
            }
            for e in events
        ],
    }

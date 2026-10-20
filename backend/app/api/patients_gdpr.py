"""GDPR-compliant patient management API (ownership, sharing, encrypted notes, audit)."""

from __future__ import annotations

import logging
import re
from typing import Any, Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import JSONResponse, StreamingResponse
from starlette.background import BackgroundTask

from app.services.file_urls import client_file_url
from app.core.security import AuthUser, canonicalize_role, get_current_user
from app.core.supabase_client import get_supabase_admin
from app.schemas_patients import (
    AccessRequestDecision,
    AgentError,
    AgentResponse,
    EditNoteRequest,
    GrantAccessRequest,
    PatientAccessEntryOut,
    PatientCreateRequest,
    PatientNoteOut,
    PatientOut,
    PatientUpdateRequest,
    PendingAccessRequestOut,
    RenamePatientPhotoRequest,
    UploadNoteRequest,
)
from app.services import case_flow, case_status, labs
from app.services import patient_access as pa
from app.services.notify import actor_label, notify, notify_pair
from app.services.patient_crypto import decrypt_note, encrypt_note
from app.services.patient_export import build_patient_export
from app.services.profiles import (
    fetch_profile,
    fetch_profiles_by_ids,
    list_active_staff_profiles,
)
from app.services.r2 import delete_patient_photo_object, upload_patient_photo_bytes

router = APIRouter()
logger = logging.getLogger("app.api.patients_gdpr")

_PHOTO_ANGLES = frozenset({"frontal", "left", "right", "other"})
_MAX_PATIENT_PHOTOS = 12

_EDITABLE_FIELDS = frozenset(
    {
        "first_name",
        "last_name",
        "date_of_birth",
        "email",
        "address",
        "phone",
        "health_insurance",
    }
)

_PATIENT_STATUSES = frozenset(
    {"pending", "in_progress", "in_review", "completed", "rejected"}
)

_ILIKE_SPECIAL = re.compile(r"([%_\\])")
_MACHINE_CODE_PREFIX = re.compile(
    r"^\s*(?:ERROR|ERR|HTTP)[_-][A-Z0-9_]+\s*:\s*",
    re.IGNORECASE,
)
_PERMISSION_DENIED_PREFIX = re.compile(
    r"^\s*Permission denied[.:]\s*",
    re.IGNORECASE,
)


def _escape_ilike(value: str) -> str:
    return _ILIKE_SPECIAL.sub(r"\\\1", value)


def _user_message(message: str) -> str:
    """Never send ERROR_403_FORBIDDEN-style prefixes to the client UI."""
    text = str(message or "").strip()
    while True:
        cleaned = _MACHINE_CODE_PREFIX.sub("", text).strip()
        if cleaned == text:
            break
        text = cleaned
    text = _PERMISSION_DENIED_PREFIX.sub("", text).strip()
    return text or "Something went wrong. Please try again."


def _ok(
    *,
    action: str,
    user_id: str,
    http_code: int = 200,
    patient_id: str | None = None,
    payload: dict[str, Any] | None = None,
) -> JSONResponse:
    body = AgentResponse(
        status="SUCCESS",
        http_code=http_code,
        action=action,
        authenticated_user_id=user_id,
        target_patient_id=patient_id,
        payload=payload or {},
        error=None,
    )
    return JSONResponse(status_code=http_code, content=body.model_dump(mode="json"))


def _err(
    *,
    action: str,
    user_id: str,
    http_code: int,
    code: str,
    message: str,
    patient_id: str | None = None,
) -> JSONResponse:
    body = AgentResponse(
        status="ERROR",
        http_code=http_code,
        action=action,
        authenticated_user_id=user_id,
        target_patient_id=patient_id,
        payload={},
        error=AgentError(code=code, message=_user_message(message)),
    )
    return JSONResponse(status_code=http_code, content=body.model_dump(mode="json"))


def _from_http(
    *,
    action: str,
    user_id: str,
    exc: HTTPException,
    patient_id: str | None = None,
) -> JSONResponse:
    detail = exc.detail if isinstance(exc.detail, dict) else {}
    return _err(
        action=action,
        user_id=user_id,
        http_code=exc.status_code,
        code=str(detail.get("code") or f"HTTP_{exc.status_code}"),
        message=str(detail.get("detail") or exc.detail),
        patient_id=patient_id,
    )


def _normalize_patient_status(raw: Any) -> str:
    value = str(raw or "pending").strip().lower()
    if value == "awaiting_scan":
        return "pending"
    if value == "complete":
        return "completed"
    if value in _PATIENT_STATUSES:
        return value
    return "pending"


def _patient_public(row: dict[str, Any]) -> dict[str, Any]:
    return PatientOut(
        id=str(row["id"]),
        created_by=str(row["created_by"]),
        first_name=row.get("first_name") or "",
        last_name=row.get("last_name") or "",
        date_of_birth=row.get("date_of_birth"),
        email=str(row.get("email") or "").strip(),
        address=row.get("address") or "",
        phone=row.get("phone") or "",
        health_insurance=row.get("health_insurance") or "",
        status=_normalize_patient_status(row.get("status")),  # type: ignore[arg-type]
        deleted=bool(row.get("deleted") or False),
        deleted_at=row.get("deleted_at"),
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
        dentist_updated=bool((row.get("lab_review") or {}).get("dentist_updated")),
    ).model_dump(mode="json")


def _note_public(
    row: dict[str, Any],
    plaintext: str,
    *,
    author_name: str | None = None,
) -> dict[str, Any]:
    author_id = str(row["author_id"])
    resolved = (author_name or "").strip() or "Unknown Practitioner"
    return PatientNoteOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        author_id=author_id,
        author_name=resolved,
        note_content=plaintext,
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
    ).model_dump(mode="json")


def _note_author_display_name(
    profile: dict[str, Any] | None, author_id: str
) -> str:
    if not profile:
        return "Unknown Practitioner"
    name = (profile.get("name") or "").strip()
    if name:
        return name
    email = (profile.get("email") or "").strip()
    return email or "Unknown Practitioner"


def _profile_display_name(profile: dict[str, Any] | None, fallback_id: str) -> str:
    if not profile:
        return fallback_id
    name = (profile.get("name") or "").strip()
    if name:
        return name
    email = (profile.get("email") or "").strip()
    return email or fallback_id


def _patient_display_name(patient: dict[str, Any]) -> str:
    first = (patient.get("first_name") or "").strip()
    last = (patient.get("last_name") or "").strip()
    return f"{first} {last}".strip() or str(patient.get("id"))


# ── Reads ─────────────────────────────────────────────────────────────────────


@router.get("", summary="List accessible patients")
def list_patients(
    q: str | None = Query(
        default=None,
        description="Search first_name, last_name, phone, or email (ILIKE)",
    ),
    status: str | None = Query(
        default=None,
        description="Filter by workflow status (pending|in_progress|in_review|completed|rejected)",
    ),
    user: AuthUser = Depends(get_current_user),
):
    action = "list_patients"
    search = (q or "").strip()
    status_filter = (status or "").strip().lower()
    if status_filter in {"awaiting_scan", "all", ""}:
        status_filter = "" if status_filter in {"all", ""} else "pending"
    if status_filter == "complete":
        status_filter = "completed"
    if status_filter and status_filter not in _PATIENT_STATUSES:
        return _err(
            action=action,
            user_id=user.id,
            http_code=400,
            code="INVALID_STATUS",
            message=(
                "status must be one of: pending, in_progress, in_review, "
                "completed, rejected"
            ),
        )
    try:
        owned_q = (
            get_supabase_admin()
            .table("patients")
            .select("*")
            .eq("created_by", user.id)
            .eq("deleted", False)
            .order("updated_at", desc=True)
        )
        if status_filter:
            owned_q = owned_q.eq("status", status_filter)
        if search:
            pattern = f"%{_escape_ilike(search)}%"
            owned_q = owned_q.or_(
                f"first_name.ilike.{pattern},"
                f"last_name.ilike.{pattern},"
                f"phone.ilike.{pattern},"
                f"email.ilike.{pattern}"
            )
        try:
            owned = owned_q.execute()
        except Exception as owned_exc:
            if status_filter and "status" in str(owned_exc):
                # Column missing — fall back to unfiltered owned list.
                owned_q = (
                    get_supabase_admin()
                    .table("patients")
                    .select("*")
                    .eq("created_by", user.id)
                    .eq("deleted", False)
                    .order("updated_at", desc=True)
                )
                if search:
                    pattern = f"%{_escape_ilike(search)}%"
                    owned_q = owned_q.or_(
                        f"first_name.ilike.{pattern},"
                        f"last_name.ilike.{pattern},"
                        f"phone.ilike.{pattern},"
                        f"email.ilike.{pattern}"
                    )
                owned = owned_q.execute()
                status_filter = ""
            else:
                raise
        shared_ids_res = (
            get_supabase_admin()
            .table("patient_access")
            .select("patient_id")
            .eq("user_id", user.id)
            .eq("status", "approved")
            .execute()
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
        )

    rows = list(getattr(owned, "data", None) or [])
    shared_ids = [
        str(r["patient_id"]) for r in (getattr(shared_ids_res, "data", None) or [])
    ]
    if shared_ids:
        try:
            shared_q = (
                get_supabase_admin()
                .table("patients")
                .select("*")
                .in_("id", shared_ids)
                .eq("deleted", False)
            )
            if status_filter:
                shared_q = shared_q.eq("status", status_filter)
            if search:
                pattern = f"%{_escape_ilike(search)}%"
                shared_q = shared_q.or_(
                    f"first_name.ilike.{pattern},"
                    f"last_name.ilike.{pattern},"
                    f"phone.ilike.{pattern},"
                    f"email.ilike.{pattern}"
                )
            shared = shared_q.execute()
            for r in getattr(shared, "data", None) or []:
                if str(r.get("created_by")) != user.id:
                    rows.append(r)
        except Exception as exc:
            return _err(
                action=action,
                user_id=user.id,
                http_code=502,
                code="DB_ERROR",
                message=str(exc),
            )

    rows.sort(key=lambda r: r.get("updated_at") or "", reverse=True)
    return _ok(
        action=action,
        user_id=user.id,
        payload={"patients": [_patient_public(r) for r in rows]},
    )


# ── Access approval (static paths BEFORE /{patient_id}) ───────────────────────


@router.get(
    "/access/pending",
    summary="List pending sharing tickets this lab decides",
)
def list_pending_access_requests(user: AuthUser = Depends(get_current_user)):
    """Sharing tickets (a dentist sharing with a colleague in the same lab)
    waiting for this lab. Dentists never decide access requests."""
    action = "list_pending_access_requests"
    try:
        pending_res = (
            get_supabase_admin()
            .table("patient_access")
            .select("*")
            .eq("status", "pending")
            .eq("ticket_lab_id", user.id)
            .order("created_at", desc=True)
            .execute()
        )
        pending_rows = getattr(pending_res, "data", None) or []
        ids = list({str(r["patient_id"]) for r in pending_rows})
        patients_res = (
            get_supabase_admin()
            .table("patients")
            .select("id,first_name,last_name")
            .in_("id", ids)
            .eq("deleted", False)
            .execute()
            if ids
            else None
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
        )
    patients_by_id = {str(r["id"]): r for r in (getattr(patients_res, "data", None) or [])}
    pending_rows = [r for r in pending_rows if str(r["patient_id"]) in patients_by_id]
    profile_ids: set[str] = set()
    for row in pending_rows:
        profile_ids.add(str(row.get("user_id") or ""))
        profile_ids.add(str(row.get("requested_by") or row.get("granted_by") or ""))
    profile_ids.discard("")

    profiles_by_id: dict[str, dict[str, Any]] = {}
    for pid in profile_ids:
        profile = fetch_profile(pid)
        if profile:
            profiles_by_id[pid] = profile

    pending_requests: list[dict[str, Any]] = []
    for row in pending_rows:
        patient_id = str(row["patient_id"])
        patient = patients_by_id.get(patient_id) or {}
        target_id = str(row.get("user_id") or "")
        requester_id = str(row.get("requested_by") or row.get("granted_by") or "")
        pending_requests.append(
            {
                "request_id": str(row["id"]),
                "patient_id": patient_id,
                "patient_name": _patient_display_name(patient),
                "target_user_id": target_id,
                "target_user_name": _profile_display_name(
                    profiles_by_id.get(target_id), target_id
                ),
                "requested_by_user_id": requester_id,
                "requested_by_user_name": _profile_display_name(
                    profiles_by_id.get(requester_id), requester_id
                ),
                "status": row.get("status") or "pending",
                "created_at": row.get("created_at"),
            }
        )

    return _ok(
        action=action,
        user_id=user.id,
        payload={"pending_requests": pending_requests},
    )


@router.patch(
    "/access/requests/{request_id}",
    summary="Lab approves or rejects a pending sharing ticket",
)
def decide_access_request(
    request_id: str,
    payload: AccessRequestDecision,
    user: AuthUser = Depends(get_current_user),
):
    decision = payload.action
    action = (
        "approve_patient_access" if decision == "approve" else "reject_patient_access"
    )

    try:
        req_res = (
            get_supabase_admin()
            .table("patient_access")
            .select("*")
            .eq("id", request_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
        )

    rows = getattr(req_res, "data", None) or []
    if not rows:
        return _err(
            action=action,
            user_id=user.id,
            http_code=404,
            code="NOT_FOUND",
            message="Access request not found",
        )

    access_row = rows[0]
    patient_id = str(access_row["patient_id"])
    patient = pa.fetch_patient(patient_id, include_deleted=True)
    if patient is None:
        return _err(
            action=action,
            user_id=user.id,
            http_code=404,
            code="NOT_FOUND",
            message="Patient not found",
            patient_id=patient_id,
        )
    # Sharing tickets are the lab's call (dentists never decide access requests).
    decider = str(access_row.get("ticket_lab_id") or "")
    if user.id != decider and not pa.is_admin(user.id):
        return _err(
            action=action,
            user_id=user.id,
            http_code=403,
            code="ERROR_403_FORBIDDEN",
            message="Permission Denied: only the dentist's lab can approve or reject this request.",
            patient_id=patient_id,
        )
    if (access_row.get("status") or "") != "pending":
        return _err(
            action=action,
            user_id=user.id,
            http_code=400,
            code="INVALID_STATE",
            message=(
                "Access request is not pending "
                f"(current status: {access_row.get('status')})"
            ),
            patient_id=patient_id,
        )

    update: dict[str, Any] = {
        "status": "approved" if decision == "approve" else "rejected"
    }
    if decision == "approve":
        update["approved_by"] = user.id
    else:
        update["approved_by"] = None

    try:
        upd_res = (
            get_supabase_admin()
            .table("patient_access")
            .update(update)
            .eq("id", request_id)
            .execute()
        )
        updated_rows = getattr(upd_res, "data", None) or []
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={
                "request_id": request_id,
                "target_user_id": access_row.get("user_id"),
                "decision": decision,
            },
        )
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )

    updated = updated_rows[0] if updated_rows else {**access_row, **update}
    target_id = str(access_row.get("user_id") or "")
    name = _patient_display_name(patient)
    who = actor_label(target_id, fallback="a colleague")
    if decision == "approve":
        notify_pair(
            counterpart_id=target_id,
            actor_id=user.id,
            type="case_status",
            counterpart_message=(
                f"Access approved for {name}. You can open this patient record."
            ),
            actor_message=f"You approved {who}'s access to {name}.",
            patient_id=patient_id,
        )
    else:
        notify_pair(
            counterpart_id=target_id,
            actor_id=user.id,
            type="case_status",
            counterpart_message=f"Access to {name} was declined.",
            actor_message=f"You declined {who}'s request to access {name}.",
            patient_id=patient_id,
        )
    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={"request": updated},
    )


@router.get(
    "/{patient_id}/access",
    summary="List access grants and requests for a patient",
)
def list_patient_access(
    patient_id: str,
    user: AuthUser = Depends(get_current_user),
):
    action = "list_patient_access"
    try:
        patient = pa.require_patient_access(patient_id, user.id)
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )

    owner_id = str(patient.get("created_by") or "")
    is_owner = pa.is_owner(patient, user.id)
    owner_profile = fetch_profile(owner_id)
    owner_payload = {
        "user_id": owner_id,
        "full_name": _profile_display_name(owner_profile, owner_id),
        "role": (owner_profile or {}).get("role") or "dentist",
        "email": ((owner_profile or {}).get("email") or "").strip() or None,
        "clinic_name": ((owner_profile or {}).get("clinic_name") or "").strip()
        or None,
    }

    try:
        query = (
            get_supabase_admin()
            .table("patient_access")
            .select("*")
            .eq("patient_id", patient_id)
            .order("created_at", desc=True)
        )
        # Shared users may see the owner + their own row only (not other staff).
        if not is_owner:
            query = query.eq("user_id", user.id)
        result = query.execute()
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )

    rows = getattr(result, "data", None) or []
    profile_ids: set[str] = set()
    for row in rows:
        profile_ids.add(str(row.get("user_id") or ""))
        profile_ids.add(str(row.get("requested_by") or ""))
        profile_ids.add(str(row.get("granted_by") or ""))
    profile_ids.discard("")
    profiles_by_id = fetch_profiles_by_ids(profile_ids)

    access_list: list[dict[str, Any]] = []
    for row in rows:
        uid = str(row.get("user_id") or "")
        profile = profiles_by_id.get(uid)
        requester_id = str(row.get("requested_by") or row.get("granted_by") or "")
        access_list.append(
            {
                "access_id": str(row["id"]),
                "user_id": uid,
                "full_name": _profile_display_name(profile, uid),
                "role": (profile or {}).get("role"),
                "email": ((profile or {}).get("email") or "").strip() or None,
                "clinic_name": ((profile or {}).get("clinic_name") or "").strip()
                or None,
                "status": row.get("status") or "approved",
                "requested_by_name": _profile_display_name(
                    profiles_by_id.get(requester_id), requester_id
                )
                if requester_id
                else None,
                "created_at": row.get("created_at"),
            }
        )

    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={
            "is_owner": is_owner,
            "owner": owner_payload,
            "access_list": access_list,
        },
    )


@router.get(
    "/{patient_id}/eligible-users",
    summary="List staff eligible to invite for patient access",
)
def list_eligible_users(
    patient_id: str,
    user: AuthUser = Depends(get_current_user),
):
    action = "list_eligible_users"
    try:
        patient = pa.require_patient_access(patient_id, user.id)
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )

    owner_id = str(patient.get("created_by") or "")

    try:
        access_res = (
            get_supabase_admin()
            .table("patient_access")
            .select("user_id,status")
            .eq("patient_id", patient_id)
            .in_("status", ["approved", "pending"])
            .execute()
        )
        staff_rows = list_active_staff_profiles()
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )

    excluded: set[str] = {owner_id}
    for row in getattr(access_res, "data", None) or []:
        uid = str(row.get("user_id") or "")
        if uid:
            excluded.add(uid)

    # Owner only: their own lab and its dentists (other labs go through a transfer).
    if pa.is_admin(user.id):
        allowed = lambda r: True  # noqa: E731
    elif pa.is_owner(patient, user.id):
        my_lab = str((fetch_profile(user.id) or {}).get("lab_id") or "")
        allowed = lambda r: bool(my_lab) and (  # noqa: E731
            str(r.get("id")) == my_lab or (r.get("role") == "dentist" and str(r.get("lab_id") or "") == my_lab)
        )
    else:
        allowed = lambda r: False  # noqa: E731
    eligible_users: list[dict[str, Any]] = []
    for row in staff_rows:
        uid = str(row.get("id") or "")
        if not uid or uid in excluded or not allowed(row):
            continue
        eligible_users.append(
            {
                "user_id": uid,
                "full_name": _profile_display_name(row, uid),
                "email": row.get("email"),
                "role": row.get("role"),
                "clinic_name": row.get("clinic_name"),
                "avatar_url": row.get("avatar_url"),
            }
        )

    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={"eligible_users": eligible_users},
    )


@router.get("/{patient_id}", summary="Get patient (owner or shared)")
def get_patient(patient_id: str, user: AuthUser = Depends(get_current_user)):
    action = "get_patient"
    try:
        patient = pa.require_patient_access(patient_id, user.id)
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={"patient": _patient_public(patient)},
    )


@router.get(
    "/{patient_id}/export",
    summary="Export patient as one zip: patient.xml + files (owner only)",
)
def export_patient(patient_id: str, user: AuthUser = Depends(get_current_user)):
    action = "export_patient"
    try:
        patient = pa.fetch_patient(patient_id)
        if patient is None:
            raise HTTPException(status_code=404, detail="Patient not found")
        pa.require_owner(patient, user.id)
        out, filename, files = build_patient_export(patient)
        pa.write_audit_log(
            actor_id=user.id,
            action="patient.export",
            patient_id=patient_id,
            details={"files": files},
        )
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    return StreamingResponse(
        iter(lambda: out.read(1024 * 1024), b""),
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
        background=BackgroundTask(out.close),
    )


# ── 1. create_patient ─────────────────────────────────────────────────────────


@router.post("", summary="Create patient", status_code=201)
def create_patient(
    payload: PatientCreateRequest,
    user: AuthUser = Depends(get_current_user),
):
    action = "create_patient"
    logger.debug("create_patient user_id=%s", user.id)
    role = canonicalize_role(user.role, default="")
    owner_id, send_to = user.id, None
    # Dentists may create patients with or without a lab.
    if role in ("laboratory", "admin"):
        try:
            if payload.dentist_id:
                own_lab = user.id if role == "laboratory" else None
                owner_id = str(labs.require_active_dentist(payload.dentist_id, own_lab)["id"])
            elif payload.send_to_lab_id and payload.send_to_lab_id != user.id:
                send_to = str(labs.require_lab(payload.send_to_lab_id)["id"])
            else:
                raise HTTPException(
                    400,
                    "Choose one of your dentists, or a lab to send the patient to",
                )
        except HTTPException as exc:
            return _from_http(action=action, user_id=user.id, exc=exc)
    row = {
        "created_by": owner_id,
        "first_name": payload.first_name.strip(),
        "last_name": payload.last_name.strip(),
        "date_of_birth": payload.date_of_birth.isoformat(),
        "email": str(payload.email).strip().lower(),
        "address": payload.address.strip(),
        "phone": payload.phone.strip(),
        "health_insurance": payload.health_insurance.strip(),
        "status": "pending",  # set automatically from here on (services/case_flow.py)
        # Sent to another lab: unassigned until that lab picks a dentist.
        "unassigned_at": pa.utc_now_iso() if send_to else None,
        "waiting_lab_id": send_to,
        "deleted": False,
        "created_at": pa.utc_now_iso(),
        "updated_at": pa.utc_now_iso(),
    }
    try:
        try:
            result = get_supabase_admin().table("patients").insert(row).execute()
        except Exception as insert_exc:
            # Pre-migration DBs may not have patients.status yet.
            if "status" not in str(insert_exc):
                raise
            row.pop("status", None)
            result = get_supabase_admin().table("patients").insert(row).execute()
        created = (getattr(result, "data", None) or [None])[0]
        if not created:
            return _err(
                action=action,
                user_id=user.id,
                http_code=502,
                code="DB_ERROR",
                message="Insert returned no row",
            )
        patient_id = str(created["id"])
        try:
            case_status.log_event(patient_id, actor_id=user.id, type="created", to_status="pending")
            if send_to:
                labs.open_transfer(
                    created, kind="handover", from_lab=user.id if role == "laboratory" else None,
                    to_lab=send_to, actor_id=user.id, status_="awaiting_recipient",
                )
            elif owner_id != user.id and role == "laboratory":
                labs.grant(patient_id, user.id, user.id)  # the creating lab keeps access
        except Exception:
            # Don't leave a half-linked patient (e.g. "waiting for lab" with no transfer).
            get_supabase_admin().table("patients").delete().eq("id", patient_id).execute()
            raise
        if not send_to and owner_id != user.id:
            notify(
                user_id=owner_id, type="case_status", patient_id=patient_id, actor_id=user.id,
                message=f"{_patient_display_name(created)} was created and assigned to you.",
            )
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={
                "first_name": row["first_name"],
                "last_name": row["last_name"],
                "email": row["email"],
            },
        )
    except HTTPException as exc:
        return _from_http(action=action, user_id=user.id, exc=exc)
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
        )

    return _ok(
        action=action,
        user_id=user.id,
        http_code=201,
        patient_id=patient_id,
        payload={"patient": _patient_public(created)},
    )


# ── 2. edit_patient ───────────────────────────────────────────────────────────


@router.patch("/{patient_id}", summary="Edit patient (owner only)")
def edit_patient(
    patient_id: str,
    payload: PatientUpdateRequest,
    user: AuthUser = Depends(get_current_user),
):
    action = "edit_patient"
    patient = pa.fetch_patient(patient_id)
    if patient is None:
        return _err(
            action=action,
            user_id=user.id,
            http_code=404,
            code="NOT_FOUND",
            message="Patient not found",
            patient_id=patient_id,
        )
    if not pa.is_owner(patient, user.id):
        return _err(
            action=action,
            user_id=user.id,
            http_code=403,
            code="ERROR_403_FORBIDDEN",
            message=pa.OWNER_EDIT_DENIED,
            patient_id=patient_id,
        )

    updates: dict[str, Any] = {}
    for key, value in (payload.fields_to_update or {}).items():
        if key not in _EDITABLE_FIELDS:
            return _err(
                action=action,
                user_id=user.id,
                http_code=400,
                code="INVALID_FIELD",
                message=f"Field '{key}' cannot be updated",
                patient_id=patient_id,
            )
        if key == "email":
            if value is None or not str(value).strip():
                return _err(
                    action=action,
                    user_id=user.id,
                    http_code=400,
                    code="VALIDATION_ERROR",
                    message="email cannot be null or empty",
                    patient_id=patient_id,
                )
            value = str(value).strip().lower()
        if isinstance(value, str):
            value = value.strip()
        if hasattr(value, "isoformat"):
            value = value.isoformat()
        updates[key] = value

    if not updates:
        return _err(
            action=action,
            user_id=user.id,
            http_code=400,
            code="EMPTY_UPDATE",
            message="fields_to_update must not be empty",
            patient_id=patient_id,
        )

    updates["updated_at"] = pa.utc_now_iso()
    try:
        result = (
            get_supabase_admin()
            .table("patients")
            .update(updates)
            .eq("id", patient_id)
            .eq("created_by", user.id)
            .execute()
        )
        rows = getattr(result, "data", None) or []
        if not rows:
            return _err(
                action=action,
                user_id=user.id,
                http_code=404,
                code="NOT_FOUND",
                message="Patient not found",
                patient_id=patient_id,
            )
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={"updated_fields": sorted(k for k in updates if k != "updated_at")},
        )
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )

    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={"patient": _patient_public(rows[0])},
    )


# ── 3. delete_patient ─────────────────────────────────────────────────────────


@router.delete("/{patient_id}", summary="Soft or hard delete patient (owner only)")
def delete_patient(
    patient_id: str,
    delete_type: Literal["soft", "hard"] = Query(default="soft"),
    user: AuthUser = Depends(get_current_user),
):
    action = "delete_patient"
    patient = pa.fetch_patient(patient_id, include_deleted=True)
    if patient is None:
        return _err(
            action=action,
            user_id=user.id,
            http_code=404,
            code="NOT_FOUND",
            message="Patient not found",
            patient_id=patient_id,
        )
    if not pa.is_owner(patient, user.id):
        return _err(
            action=action,
            user_id=user.id,
            http_code=403,
            code="ERROR_403_FORBIDDEN",
            message=pa.OWNER_ONLY_DENIED,
            patient_id=patient_id,
        )

    try:
        if delete_type == "soft":
            result = (
                get_supabase_admin()
                .table("patients")
                .update(
                    {
                        "deleted": True,
                        "deleted_at": pa.utc_now_iso(),
                        "updated_at": pa.utc_now_iso(),
                    }
                )
                .eq("id", patient_id)
                .execute()
            )
            rows = getattr(result, "data", None) or []
            pa.write_audit_log(
                actor_id=user.id,
                action=action,
                patient_id=patient_id,
                details={"delete_type": "soft"},
            )
            return _ok(
                action=action,
                user_id=user.id,
                patient_id=patient_id,
                payload={
                    "delete_type": "soft",
                    "patient": _patient_public(rows[0]) if rows else None,
                },
            )

        # hard — cascade notes + access via FK (GDPR Art. 17)
        get_supabase_admin().table("patients").delete().eq("id", patient_id).execute()
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=None,
            details={
                "delete_type": "hard",
                "former_patient_id": patient_id,
                "former_name": f"{patient.get('first_name')} {patient.get('last_name')}",
            },
        )
        return _ok(
            action=action,
            user_id=user.id,
            patient_id=patient_id,
            payload={"delete_type": "hard", "deleted": True},
        )
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )


# ── 4. grant_patient_access ───────────────────────────────────────────────────


@router.post(
    "/{patient_id}/access",
    summary="Grant or request shared access (owner or approved share)",
    status_code=201,
)
def grant_patient_access(
    patient_id: str,
    payload: GrantAccessRequest,
    user: AuthUser = Depends(get_current_user),
):
    target = payload.target_user_id.strip()
    patient = pa.fetch_patient(patient_id)
    if patient is None:
        return _err(
            action="grant_patient_access",
            user_id=user.id,
            http_code=404,
            code="NOT_FOUND",
            message="Patient not found",
            patient_id=patient_id,
        )

    action = "share_patient"
    if target == user.id:
        return _err(
            action=action,
            user_id=user.id,
            http_code=400,
            code="INVALID_TARGET",
            message="Cannot grant access to yourself",
            patient_id=patient_id,
        )
    if target == str(patient.get("created_by")):
        return _err(
            action=action,
            user_id=user.id,
            http_code=400,
            code="INVALID_TARGET",
            message="Target user is already the patient owner",
            patient_id=patient_id,
        )
    target_profile = fetch_profile(target)
    if target_profile is None:
        return _err(
            action=action,
            user_id=user.id,
            http_code=404,
            code="TARGET_NOT_FOUND",
            message="Target user not found",
            patient_id=patient_id,
        )
    try:
        # Owner only: own lab → immediate, same-lab dentist → ticket for the lab.
        share_status, ticket_lab = labs.share_rule(user, patient, target_profile)
    except HTTPException as exc:
        return _from_http(action=action, user_id=user.id, exc=exc, patient_id=patient_id)
    approved = share_status == "approved"
    action = "grant_patient_access" if approved else "request_patient_access"

    existing = pa.fetch_access_row(patient_id, target)
    if existing and (existing.get("status") or "") in ("approved", "pending"):
        return _err(
            action=action,
            user_id=user.id,
            http_code=400,
            code="ALREADY_HAS_ACCESS",
            message="Target user already has access or a pending request",
            patient_id=patient_id,
        )

    access_row = {
        "patient_id": patient_id,
        "user_id": target,
        "granted_by": user.id,
        "requested_by": user.id,
        "approved_by": user.id if approved else None,
        "status": share_status,
        "ticket_lab_id": ticket_lab,
        "created_at": pa.utc_now_iso(),
    }

    try:
        result = (
            get_supabase_admin()
            .table("patient_access")
            .upsert(access_row, on_conflict="patient_id,user_id")
            .execute()
        )
        rows = getattr(result, "data", None) or []
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={
                "target_user_id": target,
                "status": access_row["status"],
                "ticket_lab_id": ticket_lab,
            },
        )
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )

    name = _patient_display_name(patient)
    who = actor_label(user.id)
    target_name = actor_label(target, fallback="a colleague")
    if approved:
        notify_pair(
            counterpart_id=target,
            actor_id=user.id,
            type="case_status",
            counterpart_message=f"{who} granted you access to {name}.",
            actor_message=f"You granted {target_name} access to {name}.",
            patient_id=patient_id,
        )
    else:
        notify_pair(
            counterpart_id=ticket_lab,
            actor_id=user.id,
            type="case_status",
            counterpart_message=f"{who} asked to share {name} with {target_name}.",
            actor_message=f"Your lab will review sharing {name} with {target_name}.",
            patient_id=patient_id,
        )

    return _ok(
        action=action,
        user_id=user.id,
        http_code=201,
        patient_id=patient_id,
        payload={
            "access": rows[0]
            if rows
            else access_row
        },
    )


# ── 5. revoke_patient_access ──────────────────────────────────────────────────


@router.delete(
    "/{patient_id}/access/{target_user_id}",
    summary="Revoke shared access (owner only)",
)
def revoke_patient_access(
    patient_id: str,
    target_user_id: str,
    user: AuthUser = Depends(get_current_user),
):
    action = "revoke_patient_access"
    patient = pa.fetch_patient(patient_id)
    if patient is None:
        return _err(
            action=action,
            user_id=user.id,
            http_code=404,
            code="NOT_FOUND",
            message="Patient not found",
            patient_id=patient_id,
        )
    if not pa.is_owner(patient, user.id):
        return _err(
            action=action,
            user_id=user.id,
            http_code=403,
            code="ERROR_403_FORBIDDEN",
            message=pa.OWNER_ONLY_DENIED,
            patient_id=patient_id,
        )

    try:
        get_supabase_admin().table("patient_access").delete().eq(
            "patient_id", patient_id
        ).eq("user_id", target_user_id).execute()
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={"target_user_id": target_user_id},
        )
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )

    name = _patient_display_name(patient)
    who = actor_label(target_user_id, fallback="a colleague")
    notify_pair(
        counterpart_id=target_user_id,
        actor_id=user.id,
        type="case_status",
        counterpart_message=f"Your access to {name} was revoked.",
        actor_message=f"You revoked {who}'s access to {name}.",
        patient_id=patient_id,
    )
    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={"revoked": True, "target_user_id": target_user_id},
    )


# ── 6. upload_patient_note ────────────────────────────────────────────────────


@router.post(
    "/{patient_id}/notes",
    summary="Upload encrypted clinical note (owner or shared)",
    status_code=201,
)
def upload_patient_note(
    patient_id: str,
    payload: UploadNoteRequest,
    user: AuthUser = Depends(get_current_user),
):
    action = "upload_patient_note"
    try:
        pa.require_patient_access(patient_id, user.id)
        ciphertext = encrypt_note(payload.note_content)
        result = (
            get_supabase_admin()
            .table("patient_notes")
            .insert(
                {
                    "patient_id": patient_id,
                    "author_id": user.id,
                    "note_ciphertext": ciphertext,
                    "created_at": pa.utc_now_iso(),
                    "updated_at": pa.utc_now_iso(),
                }
            )
            .execute()
        )
        rows = getattr(result, "data", None) or []
        if not rows:
            return _err(
                action=action,
                user_id=user.id,
                http_code=502,
                code="DB_ERROR",
                message="Note insert returned no row",
                patient_id=patient_id,
            )
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={"note_id": str(rows[0]["id"])},
        )
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )

    # Return decrypted content only to the authorized caller (never log it)
    author_profile = fetch_profile(user.id)
    return _ok(
        action=action,
        user_id=user.id,
        http_code=201,
        patient_id=patient_id,
        payload={
            "note": _note_public(
                rows[0],
                payload.note_content,
                author_name=_note_author_display_name(author_profile, user.id),
            )
        },
    )


@router.get(
    "/{patient_id}/notes",
    summary="List decrypted notes (owner or shared)",
)
def list_patient_notes(patient_id: str, user: AuthUser = Depends(get_current_user)):
    action = "list_patient_notes"
    try:
        pa.require_patient_access(patient_id, user.id)
        result = (
            get_supabase_admin()
            .table("patient_notes")
            .select("*")
            .eq("patient_id", patient_id)
            .order("created_at", desc=True)
            .execute()
        )
        rows = getattr(result, "data", None) or []
        author_ids = {str(r.get("author_id") or "") for r in rows}
        author_ids.discard("")
        profiles_by_id = fetch_profiles_by_ids(author_ids)
        notes = [
            _note_public(
                r,
                decrypt_note(r["note_ciphertext"]),
                author_name=_note_author_display_name(
                    profiles_by_id.get(str(r.get("author_id") or "")),
                    str(r.get("author_id") or ""),
                ),
            )
            for r in rows
        ]
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )
    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={"notes": notes},
    )


# ── 7. edit_patient_note ──────────────────────────────────────────────────────


@router.patch(
    "/notes/{note_id}",
    summary="Edit note (author or patient owner)",
)
def edit_patient_note(
    note_id: str,
    payload: EditNoteRequest,
    user: AuthUser = Depends(get_current_user),
):
    action = "edit_patient_note"
    try:
        note_res = (
            get_supabase_admin()
            .table("patient_notes")
            .select("*")
            .eq("id", note_id)
            .limit(1)
            .execute()
        )
        notes = getattr(note_res, "data", None) or []
        if not notes:
            return _err(
                action=action,
                user_id=user.id,
                http_code=404,
                code="NOT_FOUND",
                message="Note not found",
            )
        note = notes[0]
        patient_id = str(note["patient_id"])
        patient = pa.fetch_patient(patient_id)
        if patient is None:
            return _err(
                action=action,
                user_id=user.id,
                http_code=404,
                code="NOT_FOUND",
                message="Patient not found",
                patient_id=patient_id,
            )

        is_author = str(note.get("author_id")) == user.id
        is_owner = pa.is_owner(patient, user.id)
        if not (is_author or is_owner):
            return _err(
                action=action,
                user_id=user.id,
                http_code=403,
                code="ERROR_403_FORBIDDEN",
                message=pa.ACCESS_DENIED,
                patient_id=patient_id,
            )

        ciphertext = encrypt_note(payload.new_note_content)
        result = (
            get_supabase_admin()
            .table("patient_notes")
            .update(
                {
                    "note_ciphertext": ciphertext,
                    "updated_at": pa.utc_now_iso(),
                }
            )
            .eq("id", note_id)
            .execute()
        )
        rows = getattr(result, "data", None) or []
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={"note_id": note_id},
        )
    except HTTPException as exc:
        return _from_http(action=action, user_id=user.id, exc=exc)
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
        )

    updated_row = rows[0] if rows else note
    author_id = str(updated_row.get("author_id") or note.get("author_id") or "")
    author_profile = fetch_profile(author_id) if author_id else None

    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={
            "note": _note_public(
                updated_row,
                payload.new_note_content,
                author_name=_note_author_display_name(author_profile, author_id),
            )
        },
    )


# ── 8. delete_patient_note ────────────────────────────────────────────────────


@router.delete(
    "/notes/{note_id}",
    summary="Delete note (author or patient owner)",
)
def delete_patient_note(note_id: str, user: AuthUser = Depends(get_current_user)):
    action = "delete_patient_note"
    try:
        note_res = (
            get_supabase_admin()
            .table("patient_notes")
            .select("*")
            .eq("id", note_id)
            .limit(1)
            .execute()
        )
        notes = getattr(note_res, "data", None) or []
        if not notes:
            return _err(
                action=action,
                user_id=user.id,
                http_code=404,
                code="NOT_FOUND",
                message="Note not found",
            )
        note = notes[0]
        patient_id = str(note["patient_id"])
        patient = pa.fetch_patient(patient_id)
        if patient is None:
            return _err(
                action=action,
                user_id=user.id,
                http_code=404,
                code="NOT_FOUND",
                message="Patient not found",
                patient_id=patient_id,
            )

        is_author = str(note.get("author_id")) == user.id
        is_owner = pa.is_owner(patient, user.id)
        if not (is_author or is_owner):
            return _err(
                action=action,
                user_id=user.id,
                http_code=403,
                code="ERROR_403_FORBIDDEN",
                message=pa.ACCESS_DENIED,
                patient_id=patient_id,
            )

        get_supabase_admin().table("patient_notes").delete().eq("id", note_id).execute()
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={"note_id": note_id},
        )
    except HTTPException as exc:
        return _from_http(action=action, user_id=user.id, exc=exc)
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
        )

    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={"deleted": True, "note_id": note_id},
    )


# ── Patient clinical photos (camera tab — no case required) ───────────────────


def _photo_public(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": str(row.get("id") or ""),
        "patient_id": str(row.get("patient_id") or ""),
        "angle": row.get("angle") or "other",
        "filename": row.get("filename") or "photo.jpg",
        "file_url": client_file_url("photos", row),
        "byte_size": int(row.get("byte_size") or 0),
        "taken_at": row.get("created_at"),
    }


@router.get(
    "/{patient_id}/photos",
    summary="List clinical photos for a patient",
)
def list_patient_photos(patient_id: str, user: AuthUser = Depends(get_current_user)):
    action = "list_patient_photos"
    try:
        pa.require_patient_access(patient_id, user.id)
        result = (
            get_supabase_admin()
            .table("patient_photos")
            .select("*")
            .eq("patient_id", patient_id)
            .order("created_at", desc=True)
            .execute()
        )
        rows = getattr(result, "data", None) or []
        photos = [_photo_public(r) for r in rows]
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )

    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={"photos": photos, "max_photos": _MAX_PATIENT_PHOTOS},
    )


@router.post(
    "/{patient_id}/photos",
    summary="Upload a clinical photo for a patient (max 12)",
    status_code=201,
)
async def upload_patient_photo(
    patient_id: str,
    angle: str = Form(...),
    file: UploadFile = File(...),
    user: AuthUser = Depends(get_current_user),
):
    action = "upload_patient_photo"
    case_flow.require_can_change(user)  # labs review; they don't add photos
    angle_norm = (angle or "").strip().lower()
    if angle_norm not in _PHOTO_ANGLES:
        return _err(
            action=action,
            user_id=user.id,
            http_code=400,
            code="VALIDATION_ERROR",
            message=f"angle must be one of {sorted(_PHOTO_ANGLES)}",
            patient_id=patient_id,
        )
    try:
        pa.require_patient_access(patient_id, user.id)
        count_res = (
            get_supabase_admin()
            .table("patient_photos")
            .select("id", count="exact")
            .eq("patient_id", patient_id)
            .execute()
        )
        count = getattr(count_res, "count", None)
        if count is None:
            count = len(getattr(count_res, "data", None) or [])
        if int(count) >= _MAX_PATIENT_PHOTOS:
            return _err(
                action=action,
                user_id=user.id,
                http_code=400,
                code="LIMIT_REACHED",
                message=f"Max {_MAX_PATIENT_PHOTOS} photos per patient",
                patient_id=patient_id,
            )

        data = await file.read()
        if not data:
            return _err(
                action=action,
                user_id=user.id,
                http_code=400,
                code="VALIDATION_ERROR",
                message="Empty photo file",
                patient_id=patient_id,
            )
        filename = file.filename or f"photo_{angle_norm}.jpg"
        file_url = upload_patient_photo_bytes(
            patient_id=patient_id,
            filename=filename,
            data=data,
            content_type=file.content_type or "image/jpeg",
        )
        insert = (
            get_supabase_admin()
            .table("patient_photos")
            .insert(
                {
                    "patient_id": patient_id,
                    "uploaded_by": user.id,
                    "angle": angle_norm,
                    "filename": filename,
                    "file_url": file_url,
                    "byte_size": len(data),
                    "created_at": pa.utc_now_iso(),
                }
            )
            .execute()
        )
        rows = getattr(insert, "data", None) or []
        if not rows:
            return _err(
                action=action,
                user_id=user.id,
                http_code=502,
                code="DB_ERROR",
                message="Photo insert returned no row",
                patient_id=patient_id,
            )
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={"photo_id": str(rows[0]["id"]), "angle": angle_norm},
        )
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )

    return _ok(
        action=action,
        user_id=user.id,
        http_code=201,
        patient_id=patient_id,
        payload={"photo": _photo_public(rows[0])},
    )


@router.patch(
    "/{patient_id}/photos/{photo_id}",
    summary="Rename a clinical photo",
)
def rename_patient_photo(
    patient_id: str,
    photo_id: str,
    payload: RenamePatientPhotoRequest,
    user: AuthUser = Depends(get_current_user),
):
    case_flow.require_can_change(user)
    action = "rename_patient_photo"
    name = (payload.filename or "").strip()
    if not name:
        return _err(
            action=action,
            user_id=user.id,
            http_code=400,
            code="VALIDATION_ERROR",
            message="filename is required",
            patient_id=patient_id,
        )
    try:
        pa.require_patient_access(patient_id, user.id)
        existing = (
            get_supabase_admin()
            .table("patient_photos")
            .select("*")
            .eq("id", photo_id)
            .eq("patient_id", patient_id)
            .limit(1)
            .execute()
        )
        rows = getattr(existing, "data", None) or []
        if not rows:
            return _err(
                action=action,
                user_id=user.id,
                http_code=404,
                code="NOT_FOUND",
                message="Photo not found",
                patient_id=patient_id,
            )
        updated = (
            get_supabase_admin()
            .table("patient_photos")
            .update({"filename": name})
            .eq("id", photo_id)
            .eq("patient_id", patient_id)
            .execute()
        )
        out_rows = getattr(updated, "data", None) or []
        if not out_rows:
            out_rows = [{**rows[0], "filename": name}]
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={"photo_id": photo_id, "filename": name},
        )
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )

    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={"photo": _photo_public(out_rows[0])},
    )


@router.delete(
    "/{patient_id}/photos/{photo_id}",
    summary="Delete a clinical photo for a patient",
)
def delete_patient_photo(
    patient_id: str,
    photo_id: str,
    user: AuthUser = Depends(get_current_user),
):
    action = "delete_patient_photo"
    case_flow.require_can_change(user)
    try:
        pa.require_patient_access(patient_id, user.id)
        existing = (
            get_supabase_admin()
            .table("patient_photos")
            .select("id, file_url")
            .eq("id", photo_id)
            .eq("patient_id", patient_id)
            .limit(1)
            .execute()
        )
        rows = getattr(existing, "data", None) or []
        if not rows:
            return _err(
                action=action,
                user_id=user.id,
                http_code=404,
                code="NOT_FOUND",
                message="Photo not found",
                patient_id=patient_id,
            )
        file_url = str(rows[0].get("file_url") or "")
        delete_patient_photo_object(file_url)
        get_supabase_admin().table("patient_photos").delete().eq(
            "id", photo_id
        ).execute()
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={"photo_id": photo_id},
        )
    except HTTPException as exc:
        return _from_http(
            action=action, user_id=user.id, exc=exc, patient_id=patient_id
        )
    except Exception as exc:
        return _err(
            action=action,
            user_id=user.id,
            http_code=502,
            code="DB_ERROR",
            message=str(exc),
            patient_id=patient_id,
        )

    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={"deleted": True, "photo_id": photo_id},
    )

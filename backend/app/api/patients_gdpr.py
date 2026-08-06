"""GDPR-compliant patient management API (ownership, sharing, encrypted notes, audit)."""

from __future__ import annotations

import logging
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import JSONResponse

from app.core.security import AuthUser, get_current_user
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
    UploadNoteRequest,
)
from app.services import patient_access as pa
from app.services.patient_crypto import decrypt_note, encrypt_note
from app.services.profiles import (
    fetch_profile,
    fetch_profiles_by_ids,
    list_active_staff_profiles,
)

router = APIRouter()
logger = logging.getLogger("app.api.patients_gdpr")

_EDITABLE_FIELDS = frozenset(
    {
        "first_name",
        "last_name",
        "date_of_birth",
        "address",
        "phone",
        "health_insurance",
    }
)


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
        error=AgentError(code=code, message=message),
    )
    return JSONResponse(status_code=http_code, content=body.model_dump(mode="json"))


def _from_http(
    *,
    action: str,
    user_id: str,
    exc: HTTPException,
    patient_id: str | None = None,
) -> JSONResponse:
    return _err(
        action=action,
        user_id=user_id,
        http_code=exc.status_code,
        code=f"HTTP_{exc.status_code}",
        message=str(exc.detail),
        patient_id=patient_id,
    )


def _patient_public(row: dict[str, Any]) -> dict[str, Any]:
    return PatientOut(
        id=str(row["id"]),
        created_by=str(row["created_by"]),
        first_name=row.get("first_name") or "",
        last_name=row.get("last_name") or "",
        date_of_birth=row.get("date_of_birth"),
        address=row.get("address") or "",
        phone=row.get("phone") or "",
        health_insurance=row.get("health_insurance") or "",
        deleted=bool(row.get("deleted") or False),
        deleted_at=row.get("deleted_at"),
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
    ).model_dump(mode="json")


def _note_public(row: dict[str, Any], plaintext: str) -> dict[str, Any]:
    return PatientNoteOut(
        id=str(row["id"]),
        patient_id=str(row["patient_id"]),
        author_id=str(row["author_id"]),
        note_content=plaintext,
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
    ).model_dump(mode="json")


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
def list_patients(user: AuthUser = Depends(get_current_user)):
    action = "list_patients"
    try:
        owned = (
            get_supabase_admin()
            .table("patients")
            .select("*")
            .eq("created_by", user.id)
            .eq("deleted", False)
            .order("updated_at", desc=True)
            .execute()
        )
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
            shared = (
                get_supabase_admin()
                .table("patients")
                .select("*")
                .in_("id", shared_ids)
                .eq("deleted", False)
                .execute()
            )
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
    summary="List pending access requests for owned patients",
)
def list_pending_access_requests(user: AuthUser = Depends(get_current_user)):
    action = "list_pending_access_requests"
    try:
        owned = (
            get_supabase_admin()
            .table("patients")
            .select("id,first_name,last_name")
            .eq("created_by", user.id)
            .eq("deleted", False)
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

    owned_rows = getattr(owned, "data", None) or []
    if not owned_rows:
        return _ok(action=action, user_id=user.id, payload={"pending_requests": []})

    patients_by_id = {str(r["id"]): r for r in owned_rows}
    owned_ids = list(patients_by_id.keys())

    try:
        pending_res = (
            get_supabase_admin()
            .table("patient_access")
            .select("*")
            .eq("status", "pending")
            .in_("patient_id", owned_ids)
            .order("created_at", desc=True)
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

    pending_rows = getattr(pending_res, "data", None) or []
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
    summary="Approve or reject a pending access request (owner only)",
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
    if not pa.is_owner(patient, user.id):
        return _err(
            action=action,
            user_id=user.id,
            http_code=403,
            code="ERROR_403_FORBIDDEN",
            message=(
                "Permission Denied: Only the patient owner can approve or "
                "reject access requests."
            ),
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
        "role": "Owner",
    }

    # Shared users must not see other staff on this patient's access list.
    if not is_owner:
        return _ok(
            action=action,
            user_id=user.id,
            patient_id=patient_id,
            payload={
                "is_owner": False,
                "owner": owner_payload,
                "access_list": [],
            },
        )

    try:
        result = (
            get_supabase_admin()
            .table("patient_access")
            .select("*")
            .eq("patient_id", patient_id)
            .order("created_at", desc=True)
            .execute()
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
        requester_id = str(row.get("requested_by") or row.get("granted_by") or "")
        access_list.append(
            {
                "access_id": str(row["id"]),
                "user_id": uid,
                "full_name": _profile_display_name(profiles_by_id.get(uid), uid),
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
            "is_owner": True,
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

    eligible_users: list[dict[str, Any]] = []
    for row in staff_rows:
        uid = str(row.get("id") or "")
        if not uid or uid in excluded:
            continue
        eligible_users.append(
            {
                "user_id": uid,
                "full_name": _profile_display_name(row, uid),
                "email": row.get("email"),
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


# ── 1. create_patient ─────────────────────────────────────────────────────────


@router.post("", summary="Create patient", status_code=201)
def create_patient(
    payload: PatientCreateRequest,
    user: AuthUser = Depends(get_current_user),
):
    action = "create_patient"
    logger.debug("create_patient user_id=%s", user.id)
    row = {
        "created_by": user.id,
        "first_name": payload.first_name.strip(),
        "last_name": payload.last_name.strip(),
        "date_of_birth": payload.date_of_birth.isoformat(),
        "address": payload.address.strip(),
        "phone": payload.phone.strip(),
        "health_insurance": payload.health_insurance.strip(),
        "deleted": False,
        "created_at": pa.utc_now_iso(),
        "updated_at": pa.utc_now_iso(),
    }
    try:
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
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={"first_name": row["first_name"], "last_name": row["last_name"]},
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

    try:
        caller_role = pa.require_owner_or_approved_share(patient, patient_id, user.id)
    except HTTPException as exc:
        return _err(
            action="grant_patient_access",
            user_id=user.id,
            http_code=exc.status_code,
            code="ERROR_403_FORBIDDEN" if exc.status_code == 403 else f"HTTP_{exc.status_code}",
            message=str(exc.detail),
            patient_id=patient_id,
        )

    is_owner_grant = caller_role == "owner"
    action = "grant_patient_access" if is_owner_grant else "request_patient_access"

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
    if fetch_profile(target) is None:
        return _err(
            action=action,
            user_id=user.id,
            http_code=404,
            code="TARGET_NOT_FOUND",
            message="Target user not found",
            patient_id=patient_id,
        )

    existing = pa.fetch_access_row(patient_id, target)
    if (
        not is_owner_grant
        and existing
        and (existing.get("status") or "") == "approved"
    ):
        return _err(
            action=action,
            user_id=user.id,
            http_code=400,
            code="ALREADY_HAS_ACCESS",
            message="Target user already has approved access",
            patient_id=patient_id,
        )

    now = pa.utc_now_iso()
    if is_owner_grant:
        access_row = {
            "patient_id": patient_id,
            "user_id": target,
            "granted_by": user.id,
            "requested_by": user.id,
            "approved_by": user.id,
            "status": "approved",
            "created_at": now,
        }
    else:
        access_row = {
            "patient_id": patient_id,
            "user_id": target,
            "granted_by": user.id,
            "requested_by": user.id,
            "approved_by": None,
            "status": "pending",
            "created_at": now,
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
                "caller_role": caller_role,
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
    return _ok(
        action=action,
        user_id=user.id,
        http_code=201,
        patient_id=patient_id,
        payload={"note": _note_public(rows[0], payload.note_content)},
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
        notes = [_note_public(r, decrypt_note(r["note_ciphertext"])) for r in rows]
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

    return _ok(
        action=action,
        user_id=user.id,
        patient_id=patient_id,
        payload={
            "note": _note_public(
                rows[0] if rows else note, payload.new_note_content
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

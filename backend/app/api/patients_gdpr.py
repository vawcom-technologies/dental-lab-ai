"""GDPR-compliant patient management API (ownership, sharing, encrypted notes, audit)."""

from __future__ import annotations

import logging
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import JSONResponse

from app.core.security import AuthUser, get_current_user
from app.core.supabase_client import get_supabase_admin
from app.schemas_patients import (
    AgentError,
    AgentResponse,
    EditNoteRequest,
    GrantAccessRequest,
    PatientCreateRequest,
    PatientNoteOut,
    PatientOut,
    PatientUpdateRequest,
    UploadNoteRequest,
)
from app.services import patient_access as pa
from app.services.patient_crypto import decrypt_note, encrypt_note
from app.services.profiles import fetch_profile

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
    summary="Grant shared access (owner only)",
    status_code=201,
)
def grant_patient_access(
    patient_id: str,
    payload: GrantAccessRequest,
    user: AuthUser = Depends(get_current_user),
):
    action = "grant_patient_access"
    target = payload.target_user_id.strip()
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
    if target == user.id:
        return _err(
            action=action,
            user_id=user.id,
            http_code=400,
            code="INVALID_TARGET",
            message="Cannot grant access to yourself",
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

    try:
        result = (
            get_supabase_admin()
            .table("patient_access")
            .upsert(
                {
                    "patient_id": patient_id,
                    "user_id": target,
                    "granted_by": user.id,
                    "created_at": pa.utc_now_iso(),
                },
                on_conflict="patient_id,user_id",
            )
            .execute()
        )
        rows = getattr(result, "data", None) or []
        pa.write_audit_log(
            actor_id=user.id,
            action=action,
            patient_id=patient_id,
            details={"target_user_id": target},
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
        payload={"access": rows[0] if rows else {"patient_id": patient_id, "user_id": target}},
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

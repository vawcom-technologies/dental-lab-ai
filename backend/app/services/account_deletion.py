"""Permanent account / profile purge (RESTRICT-safe + R2 best-effort)."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import HTTPException, status

from app.core.supabase_client import get_supabase_admin
from app.services.r2 import (
    PatientAssetKind,
    delete_chat_media_object,
    delete_patient_asset,
    delete_patient_photo_object,
    is_patient_images_url,
)

logger = logging.getLogger("app.account_deletion")

_MEDIA_TABLES: tuple[tuple[str, PatientAssetKind | None], ...] = (
    ("patient_photos", None),
    ("patient_scans", "scans"),
    ("shade_detections", "shades"),
    ("smile_previews", "smiles"),
)


def _db_error(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail=f"Database operation failed: {str(exc).strip() or 'unknown error'}",
    )


def _select(table: str, **filters: Any) -> list[dict[str, Any]]:
    try:
        query = get_supabase_admin().table(table).select("*")
        for key, value in filters.items():
            query = query.eq(key, value)
        result = query.execute()
    except Exception as exc:
        raise _db_error(exc) from exc
    return list(getattr(result, "data", None) or [])


def _delete_eq(table: str, column: str, value: str) -> None:
    try:
        get_supabase_admin().table(table).delete().eq(column, value).execute()
    except Exception as exc:
        raise _db_error(exc) from exc


def _delete_in(table: str, column: str, values: list[str]) -> None:
    if not values:
        return
    try:
        get_supabase_admin().table(table).delete().in_(column, values).execute()
    except Exception as exc:
        raise _db_error(exc) from exc


def _purge_media_row(table: str, row: dict[str, Any], kind: PatientAssetKind | None) -> None:
    url = str(row.get("file_url") or "").strip()
    key = str(row.get("file_key") or "").strip()
    if not url and not key:
        return
    try:
        if table == "patient_photos" or kind is None:
            if url:
                delete_patient_photo_object(url)
            return
        if url and is_patient_images_url(url):
            # Shared camera CDN object — owned by patient_photos lifecycle.
            return
        if key:
            delete_patient_asset(kind=kind, file_key=key)
    except HTTPException as exc:
        logger.warning(
            "R2 purge skipped table=%s id=%s detail=%s",
            table,
            row.get("id"),
            getattr(exc, "detail", exc),
        )
    except Exception as exc:
        logger.warning(
            "R2 purge error table=%s id=%s detail=%s",
            table,
            row.get("id"),
            exc,
        )


def _purge_chat_for_user(user_id: str) -> None:
    try:
        result = (
            get_supabase_admin()
            .table("conversations")
            .select("id")
            .or_(f"user_a.eq.{user_id},user_b.eq.{user_id}")
            .execute()
        )
    except Exception as exc:
        raise _db_error(exc) from exc

    conversation_ids = [
        str(row["id"])
        for row in (getattr(result, "data", None) or [])
        if row.get("id")
    ]
    if not conversation_ids:
        return

    for cid in conversation_ids:
        try:
            msgs = (
                get_supabase_admin()
                .table("messages")
                .select("id,media_url,media_type")
                .eq("conversation_id", cid)
                .execute()
            )
        except Exception as exc:
            raise _db_error(exc) from exc
        for msg in getattr(msgs, "data", None) or []:
            url = str(msg.get("media_url") or "").strip()
            if not url:
                continue
            media_type = str(msg.get("media_type") or "document")
            delete_chat_media_object(media_type=media_type, file_url=url)

    _delete_in("conversations", "id", conversation_ids)


def _purge_owned_patients(user_id: str) -> None:
    patients = _select("patients", created_by=user_id)
    patient_ids = [str(p["id"]) for p in patients if p.get("id")]
    for pid in patient_ids:
        for table, kind in _MEDIA_TABLES:
            rows = _select(table, patient_id=pid)
            for row in rows:
                _purge_media_row(table, row, kind)
    if patient_ids:
        _delete_in("patients", "id", patient_ids)


def _purge_leftover_user_refs(user_id: str) -> None:
    # Notes authored on others' patients
    _delete_eq("patient_notes", "author_id", user_id)

    # Media uploaded onto patients this user does not own
    for table, kind in _MEDIA_TABLES:
        rows = _select(table, uploaded_by=user_id)
        for row in rows:
            _purge_media_row(table, row, kind)
        _delete_eq(table, "uploaded_by", user_id)

    _delete_eq("appointments", "created_by", user_id)
    _delete_eq("notifications", "user_id", user_id)

    # Access rows that would RESTRICT profile delete
    _delete_eq("patient_access", "user_id", user_id)
    _delete_eq("patient_access", "granted_by", user_id)

    try:
        get_supabase_admin().table("patient_access").update(
            {"requested_by": None}
        ).eq("requested_by", user_id).execute()
        get_supabase_admin().table("patient_access").update(
            {"approved_by": None}
        ).eq("approved_by", user_id).execute()
    except Exception as exc:
        raise _db_error(exc) from exc

    _delete_eq("patient_audit_logs", "actor_id", user_id)


def purge_user_account(user_id: str) -> None:
    """
    Permanently remove a user's clinical data, chat, Auth identity, and profile.

    Order respects ON DELETE RESTRICT FKs. R2 cleanup is best-effort.
    """
    uid = (user_id or "").strip()
    if not uid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="user_id is required",
        )

    logger.info("account purge start user_id=%s", uid)

    _purge_chat_for_user(uid)
    _purge_owned_patients(uid)
    _purge_leftover_user_refs(uid)

    auth_deleted = False
    try:
        get_supabase_admin().auth.admin.delete_user(uid)
        auth_deleted = True
        logger.info("account purge auth deleted user_id=%s", uid)
    except Exception as exc:
        msg = str(exc).strip().lower()
        if "not found" in msg or "user not found" in msg:
            logger.info("account purge auth already missing user_id=%s", uid)
        else:
            logger.error("account purge auth failed user_id=%s detail=%s", uid, exc)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Auth delete failed: {str(exc).strip() or 'unknown error'}",
            ) from exc

    try:
        get_supabase_admin().table("profiles").delete().eq("id", uid).execute()
    except Exception as exc:
        logger.error("account purge profile failed user_id=%s detail=%s", uid, exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=(
                "Profile delete failed after data purge"
                + ("; auth user was removed" if auth_deleted else "")
                + f": {str(exc).strip() or 'unknown error'}"
            ),
        ) from exc

    logger.info("account purge ok user_id=%s", uid)

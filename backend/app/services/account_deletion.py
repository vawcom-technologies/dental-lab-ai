"""Permanent account / profile purge (RESTRICT-safe + R2 best-effort)."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import HTTPException, status

from app.core.supabase_client import get_supabase_admin
from app.services import patient_media as pm
from app.services.r2 import (
    PatientAssetKind,
    bucket_for,
    delete_chat_media_object,
    delete_patient_photo_object,
    get_r2_client,
    is_local_patient_photo_url,
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
    """Best-effort: delete a media row's files (R2 or local), then the row."""
    try:
        if kind is None:
            delete_patient_photo_object(str(row.get("file_url") or ""))
        else:
            for key in (row.get("file_key"), row.get("base_file_key")):
                pm.delete_file_if_unused(
                    table=table,
                    kind=kind,
                    patient_id=str(row.get("patient_id") or ""),
                    file_key=str(key or ""),
                    ignore_row_id=str(row.get("id")),
                )
    except Exception as exc:
        logger.warning("R2 purge skipped table=%s id=%s detail=%s", table, row.get("id"), exc)
    # Gone now, so the next row's "still used?" check doesn't count it.
    _delete_eq(table, "id", str(row["id"]))


def _purge_patient_folders(patient_id: str) -> None:
    """GDPR: every R2 file under the patient's folder, in every patient bucket."""
    client = get_r2_client()
    for kind in ("photos", "scans", "shades", "smiles"):
        try:
            bucket, _ = bucket_for(kind)
            pages = client.get_paginator("list_objects_v2").paginate(
                Bucket=bucket, Prefix=f"patients/{patient_id}/"
            )
            keys = [{"Key": o["Key"]} for page in pages for o in page.get("Contents", [])]
            for i in range(0, len(keys), 1000):
                client.delete_objects(Bucket=bucket, Delete={"Objects": keys[i : i + 1000]})
        except Exception as exc:
            logger.warning("R2 folder purge skipped kind=%s patient=%s detail=%s", kind, patient_id, exc)


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


def _purge_inbox_for_user(user_id: str) -> None:
    """Unassigned scans waiting in the user's inbox (rows go with the profile)."""
    try:
        bucket, _ = bucket_for("scans")
        client = get_r2_client()
        pages = client.get_paginator("list_objects_v2").paginate(
            Bucket=bucket, Prefix=f"inbox/{user_id}/"
        )
        keys = [{"Key": o["Key"]} for page in pages for o in page.get("Contents", [])]
        for i in range(0, len(keys), 1000):
            client.delete_objects(Bucket=bucket, Delete={"Objects": keys[i : i + 1000]})
    except Exception as exc:
        logger.warning("R2 inbox purge skipped user=%s detail=%s", user_id, exc)


def _purge_owned_patients(user_id: str) -> None:
    patients = _select("patients", created_by=user_id)
    patient_ids = [str(p["id"]) for p in patients if p.get("id")]
    for pid in patient_ids:
        # Local-disk camera photos (dev) aren't in R2.
        for row in _select("patient_photos", patient_id=pid):
            url = str(row.get("file_url") or "")
            if is_local_patient_photo_url(url):
                delete_patient_photo_object(url)
        _purge_patient_folders(pid)
        for table, _ in _MEDIA_TABLES:
            _delete_eq(table, "patient_id", pid)
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
    _purge_inbox_for_user(uid)
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

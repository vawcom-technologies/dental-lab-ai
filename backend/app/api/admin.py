"""Admin user management against public.profiles + Supabase Auth."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.security import AuthUser, require_admin
from app.core.supabase_client import get_supabase_admin
from app.schemas import ProfileActionOut, ProfileListOut, ProfileOut
from app.services.account_deletion import purge_user_account

router = APIRouter()
logger = logging.getLogger("app.api.admin")


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _db_error(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail=f"Database operation failed: {str(exc).strip() or 'unknown error'}",
    )


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


def _fetch_profile(user_id: str) -> dict[str, Any] | None:
    logger.debug("fetch_profile user_id=%s", user_id)
    try:
        result = (
            get_supabase_admin()
            .table("profiles")
            .select("*")
            .eq("id", user_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.debug("fetch_profile error user_id=%s detail=%s", user_id, exc)
        raise _db_error(exc) from exc

    data = getattr(result, "data", None) or []
    if not data:
        logger.debug("fetch_profile not found user_id=%s", user_id)
        return None
    return data[0]


def _is_deleted(row: dict[str, Any]) -> bool:
    return bool(row.get("deleted") is True)


@router.get("/users", response_model=ProfileListOut)
def list_active_users(
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=200),
    _: AuthUser = Depends(require_admin),
):
    """Return non-deleted, non-admin profiles, newest `updated_at` first."""
    logger.debug("list_active_users skip=%s limit=%s", skip, limit)
    try:
        result = (
            get_supabase_admin()
            .table("profiles")
            .select("*")
            .or_("deleted.eq.false,deleted.is.null")
            .neq("role", "admin")  # <--- Excludes profiles with role='admin'
            .order("updated_at", desc=True)
            .range(skip, skip + limit - 1)
            .execute()
        )
    except Exception as exc:
        logger.debug("list_active_users error detail=%s", exc)
        raise _db_error(exc) from exc

    rows = getattr(result, "data", None) or []
    items = [_row_to_profile(row) for row in rows]
    logger.debug("list_active_users ok count=%s", len(items))
    return ProfileListOut(items=items, skip=skip, limit=limit, count=len(items))

@router.patch("/users/{user_id}/verify", response_model=ProfileActionOut)
def verify_user(user_id: str, _: AuthUser = Depends(require_admin)):
    """Set `verified=true` for an active (non-deleted) profile."""
    logger.debug("verify_user start user_id=%s", user_id)
    existing = _fetch_profile(user_id)
    if existing is None or _is_deleted(existing):
        logger.debug("verify_user not found/deleted user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    try:
        result = (
            get_supabase_admin()
            .table("profiles")
            .update({"verified": True, "updated_at": _utc_now_iso()})
            .eq("id", user_id)
            .or_("deleted.eq.false,deleted.is.null")
            .execute()
        )
    except Exception as exc:
        logger.debug("verify_user error user_id=%s detail=%s", user_id, exc)
        raise _db_error(exc) from exc

    rows = getattr(result, "data", None) or []
    if not rows:
        logger.debug("verify_user update returned empty user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    profile = _row_to_profile(rows[0])
    logger.debug("verify_user ok user_id=%s", user_id)
    return ProfileActionOut(message="User marked as verified", user=profile)


@router.delete("/users/{user_id}/soft-delete", response_model=ProfileActionOut)
def soft_delete_user(user_id: str, _: AuthUser = Depends(require_admin)):
    """Soft-delete a profile (`deleted=true`)."""
    logger.debug("soft_delete_user start user_id=%s", user_id)
    existing = _fetch_profile(user_id)
    if existing is None:
        logger.debug("soft_delete_user not found user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    if _is_deleted(existing):
        logger.debug("soft_delete_user already deleted user_id=%s", user_id)
        return ProfileActionOut(
            message="User was already soft-deleted",
            user=_row_to_profile(existing),
        )

    try:
        result = (
            get_supabase_admin()
            .table("profiles")
            .update({"deleted": True, "updated_at": _utc_now_iso()})
            .eq("id", user_id)
            .execute()
        )
    except Exception as exc:
        logger.debug("soft_delete_user error user_id=%s detail=%s", user_id, exc)
        raise _db_error(exc) from exc

    rows = getattr(result, "data", None) or []
    if not rows:
        logger.debug("soft_delete_user update empty user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    logger.debug("soft_delete_user ok user_id=%s", user_id)
    return ProfileActionOut(
        message="User soft-deleted successfully",
        user=_row_to_profile(rows[0]),
    )


@router.delete("/users/{user_id}/hard-delete", response_model=ProfileActionOut)
def hard_delete_user(user_id: str, _: AuthUser = Depends(require_admin)):
    """Permanently remove the user, Auth identity, and all owned clinical data."""
    logger.debug("hard_delete_user start user_id=%s", user_id)
    purge_user_account(user_id)
    logger.debug("hard_delete_user ok user_id=%s", user_id)
    return ProfileActionOut(
        message="User permanently removed from Auth, profiles, and related data",
        user=None,
    )

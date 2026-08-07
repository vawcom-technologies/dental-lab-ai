"""Helpers for reading public.profiles."""

from __future__ import annotations

import logging
from typing import Any

from app.core.supabase_client import get_supabase_admin

logger = logging.getLogger("app.profiles")


def fetch_profile(user_id: str) -> dict[str, Any] | None:
    """Load a profiles row by auth user id. Returns None on miss or query failure."""
    if not user_id:
        return None
    try:
        result = (
            get_supabase_admin()
            .table("profiles")
            .select("id,name,email,phone,role,clinic_name,verified,deleted,updated_at")
            .eq("id", user_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.warning("profiles lookup failed user_id=%s detail=%s", user_id, exc)
        return None

    rows = getattr(result, "data", None) or []
    if not rows:
        logger.debug("profiles row missing user_id=%s", user_id)
        return None
    return rows[0]


def fetch_profiles_by_ids(user_ids: list[str] | set[str]) -> dict[str, dict[str, Any]]:
    """Batch-load profiles keyed by id. Soft-deleted rows are omitted."""
    ids = [str(uid) for uid in user_ids if uid]
    if not ids:
        return {}
    try:
        result = (
            get_supabase_admin()
            .table("profiles")
            .select("id,name,email,phone,role,clinic_name,verified,deleted,updated_at")
            .in_("id", ids)
            .or_("deleted.eq.false,deleted.is.null")
            .execute()
        )
    except Exception as exc:
        logger.warning("profiles batch lookup failed count=%s detail=%s", len(ids), exc)
        return {}
    out: dict[str, dict[str, Any]] = {}
    for row in getattr(result, "data", None) or []:
        out[str(row["id"])] = row
    return out


def list_active_staff_profiles() -> list[dict[str, Any]]:
    """All non-deleted system staff profiles (for invite pickers)."""
    try:
        result = (
            get_supabase_admin()
            .table("profiles")
            .select("id,name,email,phone,role,clinic_name,verified,deleted")
            .or_("deleted.eq.false,deleted.is.null")
            .order("name", desc=False)
            .execute()
        )
    except Exception as exc:
        logger.warning("list_active_staff_profiles failed detail=%s", exc)
        raise
    return list(getattr(result, "data", None) or [])

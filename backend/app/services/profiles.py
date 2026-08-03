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

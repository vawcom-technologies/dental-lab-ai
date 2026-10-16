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
            .select("id,name,email,phone,role,clinic_name,verified,deleted,updated_at,avatar_url,lab_id")
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
            .select("id,name,email,phone,role,clinic_name,verified,deleted,updated_at,avatar_url,lab_id")
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


def persist_signup_profile(
    *,
    user_id: str,
    email: str,
    name: str,
    role: str,
    clinic_name: str | None,
    phone: str | None,
    avatar_url: str | None = None,
) -> None:
    """Write dentist | laboratory onto public.profiles after Auth signup."""
    if not user_id:
        return
    row = {
        "id": user_id,
        "email": email,
        "name": name,
        "role": role,
        "clinic_name": clinic_name,
        "phone": phone,
        "avatar_url": avatar_url,
    }
    try:
        existing = fetch_profile(user_id)
        admin = get_supabase_admin()
        if existing:
            admin.table("profiles").update(
                {
                    "email": email,
                    "name": name,
                    "role": role,
                    "clinic_name": clinic_name,
                    "phone": phone,
                    "avatar_url": avatar_url,
                }
            ).eq("id", user_id).execute()
        else:
            admin.table("profiles").insert(row).execute()
    except Exception as exc:
        logger.warning(
            "persist_signup_profile failed user_id=%s detail=%s", user_id, exc
        )


def is_rejected_email(email: str) -> bool:
    """True when the admin rejected a signup with this email (public.rejected_signups)."""
    result = (
        get_supabase_admin()
        .table("rejected_signups")
        .select("id")
        .eq("email", (email or "").strip().lower())
        .limit(1)
        .execute()
    )
    return bool(getattr(result, "data", None))


def lab_name(profile: dict[str, Any], labs: dict[str, dict[str, Any]] | None = None) -> str | None:
    """Name of a dentist's lab (None for labs/admin or a dentist without one).
    Pass `labs` (from fetch_profiles_by_ids) to avoid a lookup per row."""
    lab_id = str(profile.get("lab_id") or "")
    if profile.get("role") != "dentist" or not lab_id:
        return None
    lab = (labs or {}).get(lab_id) if labs is not None else fetch_profile(lab_id)
    return (str((lab or {}).get("name") or "").strip()) or None

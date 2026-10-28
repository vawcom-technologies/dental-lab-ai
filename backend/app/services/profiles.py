"""Helpers for reading public.profiles."""

from __future__ import annotations

import logging
from typing import Any

from app.core.supabase_client import get_supabase_admin

logger = logging.getLogger("app.profiles")

_PROFILE_COLS = (
    "id,name,email,phone,role,clinic_name,verified,deleted,updated_at,"
    "avatar_url,lab_id,public_number"
)
_ROLE_ALIASES = {"lab": "laboratory", "clinic": "laboratory"}


def _staff_family(role: str | None) -> str | None:
    """dentist | laboratory | None (admin / unknown)."""
    raw = (role or "").strip().lower()
    mapped = _ROLE_ALIASES.get(raw, raw)
    if mapped in ("dentist", "laboratory"):
        return mapped
    return None


def public_id_prefix(role: str | None) -> str | None:
    """D for dentists, L for labs; None for admin / unknown."""
    family = _staff_family(role)
    if family == "dentist":
        return "D"
    if family == "laboratory":
        return "L"
    return None


def format_public_id(role: str | None, number: Any) -> str | None:
    """Human-facing ID like D-01 / L-02."""
    prefix = public_id_prefix(role)
    if prefix is None:
        return None
    try:
        n = int(number)
    except (TypeError, ValueError):
        return None
    if n < 1:
        return None
    return f"{prefix}-{n:02d}"


def public_id_from_profile(profile: dict[str, Any] | None) -> str | None:
    if not profile:
        return None
    return format_public_id(profile.get("role"), profile.get("public_number"))


def _role_filter_for_number(role: str) -> list[str]:
    family = _staff_family(role)
    if family == "dentist":
        return ["dentist"]
    if family == "laboratory":
        return ["laboratory", "lab", "clinic"]
    return []


def next_public_number(role: str) -> int | None:
    """Next free public_number for dentists or labs."""
    roles = _role_filter_for_number(role)
    if not roles:
        return None
    try:
        result = (
            get_supabase_admin()
            .table("profiles")
            .select("public_number")
            .in_("role", roles)
            .not_.is_("public_number", "null")
            .order("public_number", desc=True)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.warning("next_public_number failed role=%s detail=%s", role, exc)
        return 1
    rows = getattr(result, "data", None) or []
    if not rows:
        return 1
    try:
        return int(rows[0].get("public_number") or 0) + 1
    except (TypeError, ValueError):
        return 1


def ensure_public_number(user_id: str, role: str | None = None) -> int | None:
    """Assign a public_number if this dentist/lab does not have one yet."""
    if not user_id:
        return None
    profile = fetch_profile(user_id)
    if not profile:
        return None
    existing = profile.get("public_number")
    if existing is not None:
        try:
            return int(existing)
        except (TypeError, ValueError):
            pass
    role_value = role or profile.get("role")
    number = next_public_number(str(role_value or ""))
    if number is None:
        return None
    try:
        get_supabase_admin().table("profiles").update(
            {"public_number": number}
        ).eq("id", user_id).is_("public_number", "null").execute()
    except Exception as exc:
        logger.warning(
            "ensure_public_number failed user_id=%s detail=%s", user_id, exc
        )
        refreshed = fetch_profile(user_id)
        raw = (refreshed or {}).get("public_number")
        try:
            return int(raw) if raw is not None else None
        except (TypeError, ValueError):
            return None
    refreshed = fetch_profile(user_id)
    raw = (refreshed or {}).get("public_number")
    try:
        return int(raw) if raw is not None else number
    except (TypeError, ValueError):
        return number


def fetch_profile(user_id: str) -> dict[str, Any] | None:
    """Load a profiles row by auth user id. Returns None on miss or query failure."""
    if not user_id:
        return None
    try:
        result = (
            get_supabase_admin()
            .table("profiles")
            .select(_PROFILE_COLS)
            .eq("id", user_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        # Older DBs may lack public_number until migration 027 runs.
        logger.warning("profiles lookup failed user_id=%s detail=%s", user_id, exc)
        try:
            result = (
                get_supabase_admin()
                .table("profiles")
                .select(
                    "id,name,email,phone,role,clinic_name,verified,deleted,"
                    "updated_at,avatar_url,lab_id"
                )
                .eq("id", user_id)
                .limit(1)
                .execute()
            )
        except Exception as exc2:
            logger.warning(
                "profiles fallback lookup failed user_id=%s detail=%s", user_id, exc2
            )
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
            .select(_PROFILE_COLS)
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
            .select(
                "id,name,email,phone,role,clinic_name,verified,deleted,"
                "lab_id,avatar_url,public_number"
            )
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
    public_number = next_public_number(role)
    row = {
        "id": user_id,
        "email": email,
        "name": name,
        "role": role,
        "clinic_name": clinic_name,
        "phone": phone,
        "avatar_url": avatar_url,
    }
    if public_number is not None:
        row["public_number"] = public_number
    try:
        existing = fetch_profile(user_id)
        admin = get_supabase_admin()
        if existing:
            patch = {
                "email": email,
                "name": name,
                "role": role,
                "clinic_name": clinic_name,
                "phone": phone,
                "avatar_url": avatar_url,
            }
            if existing.get("public_number") is None and public_number is not None:
                patch["public_number"] = public_number
            admin.table("profiles").update(patch).eq("id", user_id).execute()
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


def is_approved_email(email: str) -> bool:
    """True when an active profile with this email was approved by the admin."""
    result = (
        get_supabase_admin()
        .table("profiles")
        .select("id")
        .eq("email", (email or "").strip().lower())
        .eq("verified", True)
        .eq("deleted", False)
        .limit(1)
        .execute()
    )
    return bool(getattr(result, "data", None))

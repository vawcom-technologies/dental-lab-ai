"""User / contact discovery for starting new conversations."""

from __future__ import annotations

import logging
import re

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.security import AuthUser, get_current_user
from app.core.supabase_client import get_supabase_admin
from app.schemas import UserProfileResponse

router = APIRouter()
logger = logging.getLogger("app.api.users")

# Strip PostgREST filter metacharacters from free-text search
_ILLEGAL_FILTER = re.compile(r"[,.()]")


def _sanitize_search(value: str) -> str:
    cleaned = _ILLEGAL_FILTER.sub(" ", value).strip()
    # Collapse whitespace; wrap for ilike
    return " ".join(cleaned.split())


@router.get(
    "/users",
    response_model=list[UserProfileResponse],
    summary="List Available Contacts",
    tags=["Users & Contacts"],
)
def list_available_contacts(
    search: str | None = Query(
        default=None,
        description="Case-insensitive filter on name or clinic_name",
    ),
    role: str | None = Query(
        default=None,
        description="Optional role filter (e.g. clinic, dentist, lab, admin)",
    ),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user: AuthUser = Depends(get_current_user),
):
    """
    Search `public.profiles` for other users to message.

    Always excludes the authenticated caller. Soft-deleted and unverified
    profiles are omitted so contacts are actionable for conversations.
    """
    logger.debug(
        "list_contacts user_id=%s search=%r role=%r limit=%s offset=%s",
        user.id,
        search,
        role,
        limit,
        offset,
    )

    try:
        query = (
            get_supabase_admin()
            .table("profiles")
            .select("id,name,email,role,clinic_name,phone")
            .neq("id", user.id)
            .or_("deleted.eq.false,deleted.is.null")
            .eq("verified", True)
            .order("name", desc=False)
            .range(offset, offset + limit - 1)
        )

        if role and role.strip():
            query = query.eq("role", role.strip())

        if search and search.strip():
            term = _sanitize_search(search)
            if term:
                # PostgREST or_(name.ilike.*term*,clinic_name.ilike.*term*)
                pattern = f"%{term}%"
                query = query.or_(
                    f"name.ilike.{pattern},clinic_name.ilike.{pattern}"
                )

        result = query.execute()
    except Exception as exc:
        logger.warning("list_contacts failed user_id=%s detail=%s", user.id, exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Database operation failed: {str(exc).strip() or 'unknown error'}",
        ) from exc

    rows = getattr(result, "data", None) or []
    return [
        UserProfileResponse(
            id=str(row.get("id")),
            name=row.get("name"),
            email=row.get("email"),
            role=row.get("role"),
            clinic_name=row.get("clinic_name"),
            phone=row.get("phone"),
        )
        for row in rows
    ]

"""User / contact discovery for starting conversations."""

from __future__ import annotations

import logging
import re

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, EmailStr

from app.core.security import AuthUser, get_current_user
from app.core.supabase_client import get_supabase_admin

router = APIRouter()
logger = logging.getLogger("app.api.users")

_ILIKE_SPECIAL = re.compile(r"([%_\\])")


class UserProfileResponse(BaseModel):
    id: str
    name: str | None = None
    email: EmailStr | str | None = None
    role: str | None = None
    clinic_name: str | None = None
    phone: str | None = None


def _escape_ilike(value: str) -> str:
    """Escape %, _, and \\ so user input is treated literally in ilike patterns."""
    return _ILIKE_SPECIAL.sub(r"\\\1", value)


def _db_error(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail=f"Database operation failed: {str(exc).strip() or 'unknown error'}",
    )


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
    Discover other profiles to start a 1-to-1 conversation with.

    Excludes the authenticated user. Soft-deleted profiles are omitted.
    """
    logger.debug(
        "list_users viewer=%s search=%r role=%r limit=%s offset=%s",
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
            .order("name", desc=False)
            .range(offset, offset + limit - 1)
        )

        if role and role.strip():
            query = query.eq("role", role.strip())

        if search and search.strip():
            term = _escape_ilike(search.strip())
            pattern = f"%{term}%"
            # PostgREST or-filter: name ilike OR clinic_name ilike
            query = query.or_(
                f"name.ilike.{pattern},clinic_name.ilike.{pattern}"
            )

        result = query.execute()
    except Exception as exc:
        logger.warning("list_users failed viewer=%s detail=%s", user.id, exc)
        raise _db_error(exc) from exc

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

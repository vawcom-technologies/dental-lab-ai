from dataclasses import dataclass
from typing import Any
import logging

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.supabase_client import get_supabase
from app.services.profiles import fetch_profile

bearer_scheme = HTTPBearer(auto_error=True)
logger = logging.getLogger("app.api.security")

# Flutter registration roles + admin. Legacy clinic/lab map to laboratory.
STAFF_ROLES = frozenset({"dentist", "laboratory", "admin"})
_ROLE_ALIASES = {"lab": "laboratory", "clinic": "laboratory"}


def canonicalize_role(role: str | None, *, default: str = "dentist") -> str:
    """Normalize stored / metadata roles to dentist | laboratory | admin."""
    raw = (role or "").strip().lower()
    mapped = _ROLE_ALIASES.get(raw, raw)
    if mapped in STAFF_ROLES:
        return mapped
    return default


@dataclass
class AuthUser:
    id: str
    email: str
    name: str
    role: str
    clinic_name: str | None = None
    phone: str | None = None
    raw: Any | None = None


def _meta(user: Any) -> dict:
    return dict(getattr(user, "user_metadata", None) or {})


def user_from_supabase(user: Any) -> AuthUser:
    """Build AuthUser from Auth metadata, then overlay public.profiles when available."""
    meta = _meta(user)
    email = (getattr(user, "email", None) or meta.get("email") or "").strip().lower()
    auth_user = AuthUser(
        id=str(user.id),
        email=email,
        name=str(meta.get("name") or email.split("@")[0] or "User"),
        role=canonicalize_role(meta.get("role")),
        clinic_name=meta.get("clinic_name") or None,
        phone=meta.get("phone") or None,
        raw=user,
    )

    profile = fetch_profile(auth_user.id)
    if not profile:
        return auth_user

    role = canonicalize_role(profile.get("role"), default="")
    if role:
        auth_user.role = role
    name = (profile.get("name") or "").strip()
    if name:
        auth_user.name = name
    profile_email = (profile.get("email") or "").strip().lower()
    if profile_email:
        auth_user.email = profile_email
    if profile.get("clinic_name") is not None:
        clinic = str(profile.get("clinic_name") or "").strip()
        auth_user.clinic_name = clinic or None
    if profile.get("phone") is not None:
        phone = str(profile.get("phone") or "").strip()
        auth_user.phone = phone or None
    return auth_user


def get_user_from_token(token: str) -> AuthUser:
    """Validate a JWT string (HTTP Bearer or WebSocket subprotocol). Raises HTTPException."""
    if not token or not token.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Your session expired. Please sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        response = get_supabase().auth.get_user(token.strip())
    except Exception as exc:
        logger.debug("get_user_from_token invalid detail=%s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Your session expired. Please sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    user = getattr(response, "user", None)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Your session expired. Please sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user_from_supabase(user)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> AuthUser:
    token = credentials.credentials
    logger.debug("get_current_user validating bearer token")
    auth_user = get_user_from_token(token)
    return auth_user


def require_dentist(user: AuthUser = Depends(get_current_user)) -> AuthUser:
    """Any staff role: dentist, laboratory (incl. legacy clinic/lab), or admin."""
    role = canonicalize_role(user.role, default="")
    if role not in STAFF_ROLES:
        raise HTTPException(
            status_code=403,
            detail="You need a dentist or laboratory account to continue.",
        )
    return user


def require_dentist_only(user: AuthUser = Depends(get_current_user)) -> AuthUser:
    """Dentist / admin only — laboratory accounts cannot call these routes."""
    role = canonicalize_role(user.role, default="")
    if role not in ("dentist", "admin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This action is only available to dentists.",
        )
    return user


def require_admin(user: AuthUser = Depends(get_current_user)) -> AuthUser:
    if canonicalize_role(user.role, default="") != "admin":
        logger.debug(
            "require_admin denied user_id=%s role=%s email=%s",
            user.id,
            user.role,
            user.email,
        )
        raise HTTPException(
            status_code=403,
            detail="Only an administrator can do this.",
        )
    logger.debug("require_admin ok user_id=%s email=%s", user.id, user.email)
    return user

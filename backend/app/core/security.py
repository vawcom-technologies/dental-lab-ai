from dataclasses import dataclass
from typing import Any
import logging

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.supabase_client import get_supabase
from app.services.profiles import fetch_profile

bearer_scheme = HTTPBearer(auto_error=True)
logger = logging.getLogger("app.api.security")


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
        role=str(meta.get("role") or "clinic"),
        clinic_name=meta.get("clinic_name") or None,
        phone=meta.get("phone") or None,
        raw=user,
    )

    profile = fetch_profile(auth_user.id)
    if not profile:
        return auth_user

    role = (profile.get("role") or "").strip()
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
    """Validate a JWT string (HTTP Bearer or WebSocket ?token=). Raises HTTPException."""
    if not token or not token.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        response = get_supabase().auth.get_user(token.strip())
    except Exception as exc:
        logger.debug("get_user_from_token invalid detail=%s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    user = getattr(response, "user", None)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user_from_supabase(user)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> AuthUser:
    token = credentials.credentials
    logger.debug("get_current_user validating bearer token")
    auth_user = get_user_from_token(token)
    logger.debug(
        "get_current_user ok user_id=%s role=%s",
        auth_user.id,
        auth_user.role,
    )
    return auth_user


def require_dentist(user: AuthUser = Depends(get_current_user)) -> AuthUser:
    if user.role not in ("clinic", "dentist", "lab"):
        raise HTTPException(status_code=403, detail="Clinic, dentist, or lab access required")
    return user


def require_admin(user: AuthUser = Depends(get_current_user)) -> AuthUser:
    if user.role != "admin":
        logger.debug(
            "require_admin denied user_id=%s role=%s email=%s",
            user.id,
            user.role,
            user.email,
        )
        raise HTTPException(status_code=403, detail="Admin access required")
    logger.debug("require_admin ok user_id=%s email=%s", user.id, user.email)
    return user

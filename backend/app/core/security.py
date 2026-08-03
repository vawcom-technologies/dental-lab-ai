from dataclasses import dataclass
from typing import Any

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.supabase_client import get_supabase

bearer_scheme = HTTPBearer(auto_error=True)


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
    meta = _meta(user)
    email = (getattr(user, "email", None) or meta.get("email") or "").strip().lower()
    return AuthUser(
        id=str(user.id),
        email=email,
        name=str(meta.get("name") or email.split("@")[0] or "User"),
        role=str(meta.get("role") or "clinic"),
        clinic_name=meta.get("clinic_name") or None,
        phone=meta.get("phone") or None,
        raw=user,
    )


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> AuthUser:
    token = credentials.credentials
    try:
        response = get_supabase().auth.get_user(token)
    except Exception as exc:
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


def require_dentist(user: AuthUser = Depends(get_current_user)) -> AuthUser:
    if user.role not in ("clinic", "dentist", "lab"):
        raise HTTPException(status_code=403, detail="Clinic, dentist, or lab access required")
    return user

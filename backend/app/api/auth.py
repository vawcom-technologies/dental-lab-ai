from typing import Any
import logging

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status

from app.core.config import settings
from app.core.security import AuthUser, get_current_user, user_from_supabase
from app.core.supabase_client import get_supabase, get_supabase_admin
from app.schemas import (
    AuthMessageOut,
    ForgotPasswordRequest,
    PasswordChange,
    SignInRequest,
    SignUpRequest,
    TokenOut,
    UserOut,
)
from app.services.email import send_welcome_email
from app.services.profiles import fetch_profile

router = APIRouter()
logger = logging.getLogger("app.api.auth")


def _supabase_error_detail(exc: Exception) -> str:
    return str(exc).strip() or "Authentication request failed"


def _clean_optional(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    return cleaned or None


def _is_duplicate_signup(user: Any) -> bool:
    """Supabase returns a user with empty identities on duplicate email signup."""
    return hasattr(user, "identities") and user.identities == []


PENDING_VERIFICATION_SIGNIN = (
    "Your account is pending admin verification. "
    "Please wait for an administrator to approve your account."
)
ACCOUNT_DEACTIVATED = (
    "Your account has been deactivated. Please contact support."
)
SIGNUP_PENDING_VERIFICATION = (
    "Account created successfully. An administrator must verify your account "
    "before you can sign in."
)


def _enforce_signin_access(profile: dict[str, Any] | None, *, user_id: str) -> None:
    """Block soft-deleted / unverified users. Admins bypass the verified check."""
    if profile is None:
        logger.debug("signin blocked: no profile user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=PENDING_VERIFICATION_SIGNIN,
        )

    if profile.get("deleted") is True:
        logger.debug("signin blocked: deleted user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=ACCOUNT_DEACTIVATED,
        )

    role = (profile.get("role") or "").strip()
    if role == "admin":
        logger.debug("signin access allowed: admin bypass user_id=%s", user_id)
        return

    if profile.get("verified") is not True:
        logger.debug(
            "signin blocked: unverified user_id=%s verified=%s",
            user_id,
            profile.get("verified"),
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=PENDING_VERIFICATION_SIGNIN,
        )


def _profile_fields(user: Any) -> dict[str, Any]:
    """Prefer public.profiles; fall back to Auth user_metadata / defaults."""
    auth_user = user_from_supabase(user)
    profile = fetch_profile(auth_user.id)

    if not profile:
        logger.debug(
            "profile missing — using metadata fallback user_id=%s role=%s",
            auth_user.id,
            auth_user.role,
        )
        return {
            "user_id": auth_user.id,
            "email": auth_user.email,
            "name": auth_user.name,
            "role": auth_user.role or "clinic",
            "clinic_name": auth_user.clinic_name,
            "phone": auth_user.phone,
        }

    role = (profile.get("role") or "").strip() or auth_user.role or "clinic"
    name = (profile.get("name") or "").strip() or auth_user.name
    email = (
        (profile.get("email") or "").strip().lower()
        or auth_user.email
    )
    clinic_name = _clean_optional(profile.get("clinic_name")) or auth_user.clinic_name
    phone = _clean_optional(profile.get("phone")) or auth_user.phone

    logger.debug(
        "profile loaded user_id=%s role=%s verified=%s",
        auth_user.id,
        role,
        profile.get("verified"),
    )
    return {
        "user_id": auth_user.id,
        "email": email,
        "name": name,
        "role": role,
        "clinic_name": clinic_name,
        "phone": phone,
    }


def _token_out(
    session: Any | None,
    user: Any,
    *,
    email_confirmation_required: bool = False,
    message: str | None = None,
    include_tokens: bool = True,
) -> TokenOut:
    fields = _profile_fields(user)
    if message is None and email_confirmation_required:
        message = "Account created. Confirm your email before signing in."

    use_session = session if include_tokens else None
    return TokenOut(
        access_token=getattr(use_session, "access_token", None) if use_session else None,
        refresh_token=getattr(use_session, "refresh_token", None) if use_session else None,
        expires_in=getattr(use_session, "expires_in", None) if use_session else None,
        token_type=(getattr(use_session, "token_type", None) if use_session else None)
        or "bearer",
        email_confirmation_required=email_confirmation_required,
        message=message,
        user_id=fields["user_id"],
        role=fields["role"],
        name=fields["name"],
        email=fields["email"],
        clinic_name=fields["clinic_name"],
        phone=fields["phone"],
    )


@router.post("/signup", response_model=TokenOut, status_code=status.HTTP_201_CREATED)
def signup(payload: SignUpRequest, background_tasks: BackgroundTasks):
    email = str(payload.email).lower().strip()
    name = (payload.name or "").strip()
    logger.debug("signup start email=%s name=%s", email, name)
    if not name:
        logger.debug("signup rejected: empty name email=%s", email)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Name is required",
        )

    clinic_name = _clean_optional(payload.clinic_name)
    # Validated + normalized to +49XXXXXXXXXXX (11 digits) by SignUpRequest
    phone = payload.phone
    metadata = {
        "name": name,
        "role": "clinic",
        "clinic_name": clinic_name,
        "phone": phone,
    }

    try:
        result = get_supabase().auth.sign_up(
            {
                "email": email,
                "password": payload.password,
                "options": {"data": metadata},
            }
        )
    except Exception as exc:
        logger.debug("signup supabase error email=%s detail=%s", email, exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=_supabase_error_detail(exc),
        ) from exc

    user = getattr(result, "user", None)
    session = getattr(result, "session", None)

    if user is None:
        logger.debug("signup failed: no user returned email=%s", email)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Signup failed",
        )

    if _is_duplicate_signup(user):
        logger.debug("signup duplicate email=%s", email)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="An account with this email address already exists.",
        )

    # Notify only after a real, non-duplicate signup succeeded
    background_tasks.add_task(
        send_welcome_email,
        name,
        email,
        "clinic",
        clinic_name,
        phone,
    )
    logger.debug(
        "signup ok user_id=%s session=%s email_queued=true",
        getattr(user, "id", None),
        session is not None,
    )

    # Account is created, but access requires admin verification (no tokens yet)
    return _token_out(
        session,
        user,
        email_confirmation_required=session is None,
        message=SIGNUP_PENDING_VERIFICATION,
        include_tokens=False,
    )


@router.post("/signin", response_model=TokenOut)
def signin(payload: SignInRequest):
    email = str(payload.email).lower().strip()
    logger.debug("signin start email=%s", email)
    try:
        result = get_supabase().auth.sign_in_with_password(
            {"email": email, "password": payload.password}
        )
    except Exception as exc:
        logger.debug("signin failed email=%s detail=%s", email, exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        ) from exc

    user = getattr(result, "user", None)
    session = getattr(result, "session", None)
    if user is None or session is None:
        logger.debug("signin failed: missing user/session email=%s", email)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        )

    user_id = str(user.id)
    profile = fetch_profile(user_id)
    _enforce_signin_access(profile, user_id=user_id)

    token = _token_out(session, user)
    logger.debug("signin ok user_id=%s role=%s", token.user_id, token.role)
    return token


@router.post("/forgot-password", response_model=AuthMessageOut)
def forgot_password(payload: ForgotPasswordRequest):
    email = str(payload.email).lower().strip()
    redirect = _clean_optional(settings.password_reset_redirect_url)
    logger.debug("forgot-password start email=%s redirect=%s", email, bool(redirect))

    try:
        if redirect:
            get_supabase().auth.reset_password_email(
                email, {"redirect_to": redirect}
            )
        else:
            get_supabase().auth.reset_password_email(email)
    except Exception as exc:
        logger.debug("forgot-password error email=%s detail=%s", email, exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=_supabase_error_detail(exc),
        ) from exc

    logger.debug("forgot-password ok email=%s", email)
    return AuthMessageOut(
        message="If an account exists for that email, a password reset link has been sent."
    )


@router.get("/me", response_model=UserOut)
def me(user: AuthUser = Depends(get_current_user)):
    logger.debug("me user_id=%s email=%s role=%s", user.id, user.email, user.role)
    return UserOut(
        id=user.id,
        email=user.email,
        name=user.name,
        role=user.role,
        clinic_name=user.clinic_name,
        phone=user.phone,
    )


@router.post("/me/password", response_model=AuthMessageOut)
def change_password(
    payload: PasswordChange,
    user: AuthUser = Depends(get_current_user),
):
    """Change password for the authenticated user (requires current password)."""
    logger.debug("change_password start user_id=%s email=%s", user.id, user.email)

    if payload.current_password == payload.new_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must be different from the current password",
        )

    # Verify current password against Supabase Auth
    try:
        verified = get_supabase().auth.sign_in_with_password(
            {"email": user.email, "password": payload.current_password}
        )
    except Exception as exc:
        logger.debug(
            "change_password current password invalid user_id=%s detail=%s",
            user.id,
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current password is incorrect",
        ) from exc

    if getattr(verified, "user", None) is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current password is incorrect",
        )

    try:
        get_supabase_admin().auth.admin.update_user_by_id(
            user.id,
            {"password": payload.new_password},
        )
    except Exception as exc:
        logger.debug(
            "change_password update failed user_id=%s detail=%s",
            user.id,
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=_supabase_error_detail(exc),
        ) from exc

    logger.debug("change_password ok user_id=%s", user.id)
    return AuthMessageOut(message="Password updated")

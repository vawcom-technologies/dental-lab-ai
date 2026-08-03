from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.config import settings
from app.core.security import AuthUser, get_current_user, user_from_supabase
from app.core.supabase_client import get_supabase
from app.schemas import (
    AuthMessageOut,
    ForgotPasswordRequest,
    SignInRequest,
    SignUpRequest,
    TokenOut,
    UserOut,
)

router = APIRouter()


def _supabase_error_detail(exc: Exception) -> str:
    return str(exc).strip() or "Authentication request failed"


def _token_out(session: Any, user: Any) -> TokenOut:
    auth_user = user_from_supabase(user)
    return TokenOut(
        access_token=session.access_token,
        refresh_token=getattr(session, "refresh_token", None),
        expires_in=getattr(session, "expires_in", None),
        token_type=getattr(session, "token_type", None) or "bearer",
        user_id=auth_user.id,
        role=auth_user.role,
        name=auth_user.name,
        email=auth_user.email,
        clinic_name=auth_user.clinic_name,
        phone=auth_user.phone,
    )


@router.post("/signup", response_model=TokenOut, status_code=status.HTTP_201_CREATED)
def signup(payload: SignUpRequest):
    email = payload.email.lower().strip()
    metadata = {
        "name": payload.name.strip(),
        "role": "clinic",
        "clinic_name": (payload.clinic_name or "").strip() or None,
        "phone": (payload.phone or "").strip() or None,
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
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=_supabase_error_detail(exc),
        ) from exc

    user = result.user
    session = result.session
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Signup failed",
        )

    if session is None:
        # Email confirmation enabled in the Supabase project — no session yet
        auth_user = user_from_supabase(user)
        return TokenOut(
            access_token=None,
            refresh_token=None,
            expires_in=None,
            email_confirmation_required=True,
            message="Account created. Confirm your email before signing in.",
            user_id=auth_user.id,
            role=auth_user.role,
            name=auth_user.name,
            email=auth_user.email,
            clinic_name=auth_user.clinic_name,
            phone=auth_user.phone,
        )

    return _token_out(session, user)


@router.post("/signin", response_model=TokenOut)
def signin(payload: SignInRequest):
    email = payload.email.lower().strip()
    try:
        result = get_supabase().auth.sign_in_with_password(
            {"email": email, "password": payload.password}
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        ) from exc

    if result.user is None or result.session is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        )
    return _token_out(result.session, result.user)


@router.post("/forgot-password", response_model=AuthMessageOut)
def forgot_password(payload: ForgotPasswordRequest):
    email = payload.email.lower().strip()
    redirect = (settings.password_reset_redirect_url or "").strip() or None

    try:
        if redirect:
            get_supabase().auth.reset_password_email(
                email, {"redirect_to": redirect}
            )
        else:
            get_supabase().auth.reset_password_email(email)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=_supabase_error_detail(exc),
        ) from exc

    return AuthMessageOut(
        message="If an account exists for that email, a password reset link has been sent."
    )


@router.get("/me", response_model=UserOut)
def me(user: AuthUser = Depends(get_current_user)):
    return UserOut(
        id=user.id,
        email=user.email,
        name=user.name,
        role=user.role,
        clinic_name=user.clinic_name,
        phone=user.phone,
    )

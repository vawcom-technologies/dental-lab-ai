"""Shared Pydantic schemas — split further per domain as APIs grow."""

from datetime import date, datetime
from typing import Optional
import re

from pydantic import BaseModel, EmailStr, Field, field_validator


# ── Auth (Supabase) ───────────────────────────────────────────────────────────

_PHONE_DIGITS_RE = re.compile(r"\D+")
_PASSWORD_UPPER_RE = re.compile(r"[A-Z]")
_PASSWORD_DIGIT_RE = re.compile(r"[0-9]")


def validate_password_complexity(value: str) -> str:
    """Enforce min length, uppercase letter, and digit for new passwords."""
    errors: list[str] = []
    if len(value) < 8:
        errors.append("at least 8 characters long")
    if not _PASSWORD_UPPER_RE.search(value):
        errors.append("at least one uppercase letter (A-Z)")
    if not _PASSWORD_DIGIT_RE.search(value):
        errors.append("at least one numeric digit (0-9)")
    if errors:
        raise ValueError(f"Password must contain {', '.join(errors)}.")
    return value


def normalize_german_phone(value: str) -> str:
    """Require DE numbers as +49 followed by exactly 11 digits."""
    raw = (value or "").strip()
    if not raw:
        raise ValueError("Phone number is required")

    digits = _PHONE_DIGITS_RE.sub("", raw)

    # Strip leading international / trunk prefixes down to national digits
    if digits.startswith("0049"):
        digits = digits[4:]
    elif digits.startswith("49") and len(digits) > 11:
        digits = digits[2:]
    elif digits.startswith("0") and len(digits) == 12:
        # national format 0XXXXXXXXXXX → drop leading 0
        digits = digits[1:]

    if len(digits) != 11 or not digits.isdigit():
        raise ValueError(
            "Phone must be a German number: +49 followed by exactly 11 digits "
            "(e.g. +4917012345678 or 17012345678)"
        )

    return f"+49{digits}"


class SignUpRequest(BaseModel):
    email: EmailStr
    name: str = Field(min_length=1, max_length=255)
    password: str = Field(min_length=8, max_length=128)
    clinic_name: str | None = Field(default=None, max_length=255)
    phone: str = Field(min_length=1, max_length=64)

    @field_validator("phone")
    @classmethod
    def _phone_de(cls, v: str) -> str:
        return normalize_german_phone(v)

    @field_validator("password")
    @classmethod
    def _password_complexity(cls, v: str) -> str:
        return validate_password_complexity(v)


class SignInRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class PasswordChange(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def _password_complexity(cls, v: str) -> str:
        return validate_password_complexity(v)


class AuthMessageOut(BaseModel):
    message: str


class TokenOut(BaseModel):
    access_token: str | None = None
    refresh_token: str | None = None
    expires_in: int | None = None
    token_type: str = "bearer"
    email_confirmation_required: bool = False
    message: str | None = None
    user_id: str
    role: str
    name: str
    email: str
    clinic_name: str | None = None
    phone: str | None = None


class UserOut(BaseModel):
    id: str
    email: EmailStr
    name: str
    role: str
    clinic_name: str | None = None
    phone: str | None = None


# ── Admin / profiles ───────────────────────────────────────────────────────────

class ProfileOut(BaseModel):
    id: str
    name: str | None = None
    email: str | None = None
    phone: str | None = None
    role: str | None = None
    clinic_name: str | None = None
    verified: bool = False
    deleted: bool = False
    updated_at: datetime | None = None


class ProfileListOut(BaseModel):
    items: list[ProfileOut]
    skip: int
    limit: int
    count: int


class ProfileActionOut(BaseModel):
    message: str
    user: ProfileOut | None = None


# ── Patients ──────────────────────────────────────────────────────────────────

class PatientCreate(BaseModel):
    first_name: str = Field(min_length=1, max_length=120)
    last_name: str = Field(min_length=1, max_length=120)
    dob: Optional[date] = None
    address: Optional[str] = None
    phone: Optional[str] = None
    health_insurance: Optional[str] = None
    notes: Optional[str] = None


class PatientUpdate(BaseModel):
    first_name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    last_name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    dob: Optional[date] = None
    address: Optional[str] = None
    phone: Optional[str] = None
    health_insurance: Optional[str] = None
    notes: Optional[str] = None


class PatientOut(BaseModel):
    id: int
    dentist_id: int
    first_name: str
    last_name: str
    dob: Optional[date] = None
    address: Optional[str] = None
    phone: Optional[str] = None
    health_insurance: Optional[str] = None
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ── Cases ─────────────────────────────────────────────────────────────────────

class CaseCreate(BaseModel):
    patient_id: int
    status: str = "pending"

    @field_validator("status")
    @classmethod
    def _status_ok(cls, v: str) -> str:
        allowed = {"pending", "in_progress", "in_review", "rejected", "completed"}
        if v not in allowed:
            raise ValueError(f"status must be one of {sorted(allowed)}")
        return v


class CaseUpdate(BaseModel):
    status: Optional[str] = None

    @field_validator("status")
    @classmethod
    def _status_ok(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        allowed = {"pending", "in_progress", "in_review", "rejected", "completed"}
        if v not in allowed:
            raise ValueError(f"status must be one of {sorted(allowed)}")
        return v


class CaseOut(BaseModel):
    id: int
    patient_id: int
    status: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ── AI POC ────────────────────────────────────────────────────────────────────

class ShadeAnalyzeOut(BaseModel):
    """Per-tooth / per-zone shade analysis."""

    teeth: list[dict]
    tooth_count: int
    accepted_count: int
    note: str
    image_width: int | None = None
    image_height: int | None = None


class ScanValidateOut(BaseModel):
    result: str
    reasons: list[str]
    note: str
    issues: list[dict] = []
    prompt_rescan: bool = False

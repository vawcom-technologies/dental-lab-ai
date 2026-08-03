"""Shared Pydantic schemas — split further per domain as APIs grow."""

from datetime import date, datetime
from typing import Optional
import re

from pydantic import BaseModel, EmailStr, Field, field_validator


# ── Auth (Supabase) ───────────────────────────────────────────────────────────

_PHONE_DIGITS_RE = re.compile(r"\D+")


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
    password: str = Field(min_length=6, max_length=128)
    clinic_name: str | None = Field(default=None, max_length=255)
    phone: str = Field(min_length=1, max_length=64)

    @field_validator("phone")
    @classmethod
    def _phone_de(cls, v: str) -> str:
        return normalize_german_phone(v)


class SignInRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


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

class ShadeSuggestOut(BaseModel):
    suggested_shade: str
    confidence: float
    top_matches: list[dict]
    note: str


class ScanValidateOut(BaseModel):
    result: str
    quality_score: float
    reasons: list[str]
    note: str
    issues: list[dict] = []
    prompt_rescan: bool = False

"""Shared Pydantic schemas — split further per domain as APIs grow."""

from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field, field_validator


# ── Auth (Supabase) ───────────────────────────────────────────────────────────

class SignUpRequest(BaseModel):
    email: EmailStr
    name: str = Field(min_length=1, max_length=255)
    password: str = Field(min_length=6, max_length=128)
    clinic_name: str | None = Field(default=None, max_length=255)
    phone: str | None = Field(default=None, max_length=64)


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
    quality_score: float
    reasons: list[str]
    note: str
    issues: list[dict] = []
    prompt_rescan: bool = False

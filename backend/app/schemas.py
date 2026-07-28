"""Shared Pydantic schemas — split further per domain as APIs grow."""

from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field


# ── Auth ──────────────────────────────────────────────────────────────────────

class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    role: str
    name: str
    email: str


class UserOut(BaseModel):
    id: int
    email: EmailStr
    name: str
    role: str

    class Config:
        from_attributes = True


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


class CaseUpdate(BaseModel):
    status: Optional[str] = None


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

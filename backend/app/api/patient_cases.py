"""Case status endpoints: state, "Submit to lab", and the lab's review."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.core.security import AuthUser, get_current_user
from app.services import case_flow
from app.services import patient_access as pa

router = APIRouter()


class SubmitIn(BaseModel):
    confirm_incomplete: bool = False


class ReviewIn(BaseModel):
    decision: Literal["approve", "reject"]
    remarks: str | None = Field(default=None, max_length=4000)


def _patient(patient_id: str, user: AuthUser) -> dict:
    return pa.require_patient_access(patient_id, user.id)  # 404 / 403


@router.get("/{patient_id}/case", summary="Case status, what's missing, allowed actions, history")
def get_case(patient_id: str, user: AuthUser = Depends(get_current_user)):
    return case_flow.summary(_patient(patient_id, user), user)


@router.post("/{patient_id}/submit", summary="Submit to lab (409 INCOMPLETE lists missing items)")
def submit_case(patient_id: str, body: SubmitIn, user: AuthUser = Depends(get_current_user)):
    patient = case_flow.submit(_patient(patient_id, user), user, confirm_incomplete=body.confirm_incomplete)
    return case_flow.summary(patient, user)


@router.post("/{patient_id}/review", summary="Lab approves, or rejects with remarks")
def review_case(patient_id: str, body: ReviewIn, user: AuthUser = Depends(get_current_user)):
    patient = case_flow.review(
        _patient(patient_id, user), user, approve=body.decision == "approve", remarks=body.remarks
    )
    return case_flow.summary(patient, user)

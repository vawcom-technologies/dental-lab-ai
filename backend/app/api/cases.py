"""Cases API — list/create/update clinical cases."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_dentist
from app.models import User, Patient, Case, ActivityLog
from app.schemas import CaseCreate, CaseUpdate, CaseOut

router = APIRouter()


def _dentist_patient_ids(db: Session, user: User) -> set[int] | None:
    """None = lab sees all; otherwise set of allowed patient ids."""
    if user.role == "lab":
        return None
    rows = db.query(Patient.id).filter(Patient.dentist_id == user.id).all()
    return {r[0] for r in rows}


@router.get("", response_model=list[CaseOut])
def list_cases(
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    q = db.query(Case)
    allowed = _dentist_patient_ids(db, user)
    if allowed is not None:
        q = q.filter(Case.patient_id.in_(allowed or {-1}))
    return q.order_by(Case.updated_at.desc()).all()


@router.post("", response_model=CaseOut, status_code=status.HTTP_201_CREATED)
def create_case(
    payload: CaseCreate,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    patient = db.query(Patient).filter(Patient.id == payload.patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    if user.role == "dentist" and patient.dentist_id != user.id:
        raise HTTPException(status_code=403, detail="Not your patient")

    case = Case(patient_id=payload.patient_id, status=payload.status)
    db.add(case)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="case.create",
            target_type="case",
            target_id=case.id,
        )
    )
    db.commit()
    db.refresh(case)
    return case


@router.get("/{case_id}", response_model=CaseOut)
def get_case(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    case = db.query(Case).filter(Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    allowed = _dentist_patient_ids(db, user)
    if allowed is not None and case.patient_id not in allowed:
        raise HTTPException(status_code=403, detail="Forbidden")
    return case


@router.patch("/{case_id}", response_model=CaseOut)
def update_case(
    case_id: int,
    payload: CaseUpdate,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    case = db.query(Case).filter(Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    allowed = _dentist_patient_ids(db, user)
    if allowed is not None and case.patient_id not in allowed:
        raise HTTPException(status_code=403, detail="Forbidden")
    if payload.status is not None:
        case.status = payload.status
    db.add(
        ActivityLog(
            user_id=user.id,
            action="case.update",
            target_type="case",
            target_id=case.id,
        )
    )
    db.commit()
    db.refresh(case)
    return case

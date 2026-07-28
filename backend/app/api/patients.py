from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_dentist
from app.models import User, Patient, ActivityLog
from app.schemas import PatientCreate, PatientUpdate, PatientOut

router = APIRouter()


def _scoped_query(db: Session, user: User):
    q = db.query(Patient)
    if user.role == "dentist":
        q = q.filter(Patient.dentist_id == user.id)
    return q


@router.get("", response_model=list[PatientOut])
def list_patients(
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    return _scoped_query(db, user).order_by(Patient.updated_at.desc()).all()


@router.post("", response_model=PatientOut, status_code=status.HTTP_201_CREATED)
def create_patient(
    payload: PatientCreate,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    dentist_id = user.id if user.role == "dentist" else user.id
    patient = Patient(dentist_id=dentist_id, **payload.model_dump())
    db.add(patient)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="patient.create",
            target_type="patient",
            target_id=patient.id,
        )
    )
    db.commit()
    db.refresh(patient)
    return patient


@router.get("/{patient_id}", response_model=PatientOut)
def get_patient(
    patient_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    patient = _scoped_query(db, user).filter(Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    return patient


@router.patch("/{patient_id}", response_model=PatientOut)
def update_patient(
    patient_id: int,
    payload: PatientUpdate,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    patient = _scoped_query(db, user).filter(Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(patient, key, value)
    db.add(
        ActivityLog(
            user_id=user.id,
            action="patient.update",
            target_type="patient",
            target_id=patient.id,
        )
    )
    db.commit()
    db.refresh(patient)
    return patient


@router.delete("/{patient_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_patient(
    patient_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    patient = _scoped_query(db, user).filter(Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    db.add(
        ActivityLog(
            user_id=user.id,
            action="patient.delete",
            target_type="patient",
            target_id=patient.id,
        )
    )
    db.delete(patient)
    db.commit()
    return None

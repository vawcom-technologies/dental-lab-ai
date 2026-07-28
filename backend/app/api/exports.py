from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_dentist
from app.models import User, Patient, ActivityLog
from app.services.datev_export import build_patient_datev_xml

router = APIRouter()


@router.get("/{patient_id}/datev.xml")
def export_patient_datev(
    patient_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    """Export one patient as DATEV-like XML (skeleton from client sample)."""
    q = db.query(Patient).filter(Patient.id == patient_id)
    if user.role == "dentist":
        q = q.filter(Patient.dentist_id == user.id)
    patient = q.first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    payload = {
        "id": patient.id,
        "dentist_id": patient.dentist_id,
        "first_name": patient.first_name,
        "last_name": patient.last_name,
        "dob": patient.dob,
        "address": patient.address,
        "phone": patient.phone,
        "health_insurance": patient.health_insurance,
        "notes": patient.notes,
    }
    xml_bytes = build_patient_datev_xml(payload)

    db.add(
        ActivityLog(
            user_id=user.id,
            action="patient.export_datev",
            target_type="patient",
            target_id=patient.id,
        )
    )
    db.commit()

    filename = f"datev_patient_{patient.id}.xml"
    return Response(
        content=xml_bytes,
        media_type="application/xml",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )

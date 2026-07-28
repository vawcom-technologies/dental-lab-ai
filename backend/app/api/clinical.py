"""Shade / shape / scan-body selection persistence (Week 3)."""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_dentist
from app.models import (
    User,
    Case,
    ShadeSelection,
    ShapeSelection,
    ScanBodySelection,
    ActivityLog,
)

router = APIRouter()


class ShadeSave(BaseModel):
    ai_suggested_shade: str | None = None
    confidence_score: float | None = None
    final_shade: str
    overridden_by_dentist: bool = False


class ShapeSave(BaseModel):
    shape_id: str
    position_x: float = 0.0
    position_y: float = 0.0
    rotation: float = 0.0
    scale: float = 1.0


class ScanBodySave(BaseModel):
    detected_diameter: float | None = None
    table_diameter_mm: float | None = None
    matched_tooth_position: str | None = None
    matched_manufacturer: str | None = None
    matched_platform: str | None = None
    confidence_score: float | None = None
    overridden_by_dentist: bool = False
    detection_method: str | None = None


@router.post("/{case_id}/shade")
def save_shade(
    case_id: int,
    payload: ShadeSave,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    if not db.query(Case).filter(Case.id == case_id).first():
        raise HTTPException(status_code=404, detail="Case not found")
    row = ShadeSelection(case_id=case_id, **payload.model_dump())
    db.add(row)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="shade.save",
            target_type="shade_selection",
            target_id=row.id,
        )
    )
    db.commit()
    return {"id": row.id, "final_shade": row.final_shade}


@router.get("/{case_id}/shade")
def latest_shade(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    row = (
        db.query(ShadeSelection)
        .filter(ShadeSelection.case_id == case_id)
        .order_by(ShadeSelection.id.desc())
        .first()
    )
    if not row:
        return None
    return {
        "id": row.id,
        "ai_suggested_shade": row.ai_suggested_shade,
        "confidence_score": row.confidence_score,
        "final_shade": row.final_shade,
        "overridden_by_dentist": row.overridden_by_dentist,
        "created_at": row.created_at,
    }


@router.post("/{case_id}/shape")
def save_shape(
    case_id: int,
    payload: ShapeSave,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    if not db.query(Case).filter(Case.id == case_id).first():
        raise HTTPException(status_code=404, detail="Case not found")
    row = ShapeSelection(case_id=case_id, **payload.model_dump())
    db.add(row)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="shape.save",
            target_type="shape_selection",
            target_id=row.id,
        )
    )
    db.commit()
    return {"id": row.id, "shape_id": row.shape_id}


@router.get("/{case_id}/shape")
def latest_shape(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    row = (
        db.query(ShapeSelection)
        .filter(ShapeSelection.case_id == case_id)
        .order_by(ShapeSelection.id.desc())
        .first()
    )
    if not row:
        return None
    return {
        "id": row.id,
        "shape_id": row.shape_id,
        "position_x": row.position_x,
        "position_y": row.position_y,
        "rotation": row.rotation,
        "scale": row.scale,
        "created_at": row.created_at,
    }


@router.post("/{case_id}/scan-body")
def save_scan_body(
    case_id: int,
    payload: ScanBodySave,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    if not db.query(Case).filter(Case.id == case_id).first():
        raise HTTPException(status_code=404, detail="Case not found")
    row = ScanBodySelection(case_id=case_id, **payload.model_dump())
    db.add(row)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="scan_body.save",
            target_type="scan_body_selection",
            target_id=row.id,
        )
    )
    db.commit()
    return {
        "id": row.id,
        "detected_diameter": row.detected_diameter,
        "matched_manufacturer": row.matched_manufacturer,
        "matched_tooth_position": row.matched_tooth_position,
    }


@router.get("/{case_id}/scan-body")
def latest_scan_body(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    row = (
        db.query(ScanBodySelection)
        .filter(ScanBodySelection.case_id == case_id)
        .order_by(ScanBodySelection.id.desc())
        .first()
    )
    if not row:
        return None
    return {
        "id": row.id,
        "detected_diameter": row.detected_diameter,
        "table_diameter_mm": row.table_diameter_mm,
        "matched_tooth_position": row.matched_tooth_position,
        "matched_manufacturer": row.matched_manufacturer,
        "matched_platform": row.matched_platform,
        "confidence_score": row.confidence_score,
        "overridden_by_dentist": row.overridden_by_dentist,
        "detection_method": row.detection_method,
        "created_at": row.created_at,
    }

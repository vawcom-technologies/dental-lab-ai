"""Shade / shape selection persistence (Week 3)."""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_dentist
from app.models import User, Case, ShadeSelection, ShapeSelection, ActivityLog

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

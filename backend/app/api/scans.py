"""Scans API — upload PLY + run quality validation (Week 2+)."""

from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.ai.scan_quality import validate_ply_bytes
from app.core.database import get_db
from app.core.security import require_dentist
from app.models import User, Case, Scan, ActivityLog
from app.storage.local import save_case_file

router = APIRouter()


@router.post("/{case_id}/scans")
async def upload_scan(
    case_id: int,
    file: UploadFile = File(...),
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    case = db.query(Case).filter(Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")

    data = await file.read()
    validation = validate_ply_bytes(data, filename=file.filename or "scan.ply")
    path = save_case_file(case_id, "scans", file.filename or "scan.ply", data)

    scan = Scan(
        case_id=case_id,
        file_path=str(path),
        format="PLY",
        scan_quality_score=validation["quality_score"],
        validation_result=validation["result"],
    )
    db.add(scan)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="scan.upload",
            target_type="scan",
            target_id=scan.id,
        )
    )
    db.commit()
    db.refresh(scan)
    return {
        "id": scan.id,
        "case_id": case_id,
        "validation_result": scan.validation_result,
        "quality_score": scan.scan_quality_score,
        "reasons": validation["reasons"],
        "issues": validation.get("issues", []),
        "note": validation["note"],
        "prompt_rescan": validation.get("prompt_rescan", False),
    }


@router.get("/{case_id}/scans")
def list_scans(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    scans = db.query(Scan).filter(Scan.case_id == case_id).all()
    return [
        {
            "id": s.id,
            "case_id": s.case_id,
            "validation_result": s.validation_result,
            "quality_score": s.scan_quality_score,
            "uploaded_at": s.uploaded_at,
            "file_path": s.file_path,
        }
        for s in scans
    ]

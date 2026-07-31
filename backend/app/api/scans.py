"""Scans API — upload PLY/STL/OBJ + quality validation + preview/delete."""

from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session, joinedload

from app.ai.scan_quality import (
    detect_mesh_format,
    preview_mesh_bytes,
    validate_scan_bytes,
)
from app.core.database import get_db
from app.core.security import require_dentist
from app.models import User, Case, Scan, ActivityLog
from app.services.notify import notify, notify_lab_users, patient_display_name
from app.storage.local import read_case_file, save_case_file

router = APIRouter()


def _get_case(db: Session, case_id: int) -> Case:
    case = (
        db.query(Case)
        .options(joinedload(Case.patient))
        .filter(Case.id == case_id)
        .first()
    )
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")
    return case


def _get_scan(db: Session, case_id: int, scan_id: int) -> Scan:
    scan = (
        db.query(Scan)
        .filter(Scan.id == scan_id, Scan.case_id == case_id)
        .first()
    )
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")
    return scan


def _serialize_scan(scan: Scan, case: Case | None = None) -> dict:
    patient = case.patient if case is not None else None
    if patient is None and case is not None:
        patient = None
    raw_name = Path(scan.file_path).name.removesuffix(".enc")
    return {
        "id": scan.id,
        "case_id": scan.case_id,
        "patient_id": case.patient_id if case else None,
        "patient_name": patient_display_name(patient) if patient else None,
        "filename": raw_name,
        "format": scan.format,
        "validation_result": scan.validation_result,
        "quality_score": scan.scan_quality_score,
        "uploaded_at": scan.uploaded_at.isoformat() if scan.uploaded_at else None,
    }


@router.post("/{case_id}/scans")
async def upload_scan(
    case_id: int,
    file: UploadFile = File(...),
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    case = _get_case(db, case_id)
    if user.role == "dentist" and case.patient and case.patient.dentist_id != user.id:
        raise HTTPException(status_code=403, detail="Not your patient")

    filename = file.filename or "scan.ply"
    data = await file.read()
    mesh_kind = detect_mesh_format(data, filename)
    validation = validate_scan_bytes(data, filename=filename)
    path = save_case_file(case_id, "scans", filename, data)

    scan = Scan(
        case_id=case_id,
        file_path=str(path),
        format=(mesh_kind or "ply").upper(),
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

    name = patient_display_name(case.patient)
    prompt_rescan = bool(validation.get("prompt_rescan", False))
    reasons = validation.get("reasons") or []
    reason_txt = "; ".join(str(r) for r in reasons[:2]) if reasons else ""

    if prompt_rescan or validation.get("result") in ("fail", "failed", "reject", "rejected"):
        detail = f" {reason_txt}." if reason_txt else " Rescan before sending to the lab."
        notify(
            db,
            user_id=case.patient.dentist_id if case.patient else user.id,
            type="scan_quality",
            message=f"Scan quality issue for {name}.{detail}",
            case_id=case_id,
        )
    else:
        notify_lab_users(
            db,
            type="case_status",
            message=f"New scan uploaded for {name}.",
            case_id=case_id,
            exclude_user_id=user.id,
        )

    db.commit()
    db.refresh(scan)
    out = _serialize_scan(scan, case)
    out.update(
        {
            "reasons": validation["reasons"],
            "issues": validation.get("issues", []),
            "note": validation["note"],
            "prompt_rescan": prompt_rescan,
        }
    )
    return out


@router.get("/{case_id}/scans")
def list_scans(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    case = _get_case(db, case_id)
    if user.role == "dentist" and case.patient and case.patient.dentist_id != user.id:
        raise HTTPException(status_code=403, detail="Not your patient")
    scans = (
        db.query(Scan)
        .filter(Scan.case_id == case_id)
        .order_by(Scan.uploaded_at.desc(), Scan.id.desc())
        .all()
    )
    return [_serialize_scan(s, case) for s in scans]


@router.delete("/{case_id}/scans/{scan_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_scan(
    case_id: int,
    scan_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    case = _get_case(db, case_id)
    if user.role == "dentist" and case.patient and case.patient.dentist_id != user.id:
        raise HTTPException(status_code=403, detail="Not your patient")
    scan = _get_scan(db, case_id, scan_id)
    path = Path(scan.file_path)
    db.add(
        ActivityLog(
            user_id=user.id,
            action="scan.delete",
            target_type="scan",
            target_id=scan.id,
        )
    )
    db.delete(scan)
    db.commit()
    if path.is_file():
        try:
            path.unlink()
        except OSError:
            pass
    return None


@router.get("/{case_id}/scans/{scan_id}/preview")
def scan_preview(
    case_id: int,
    scan_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    """Downsampled XYZ point cloud for the interactive chairside viewer."""
    case = _get_case(db, case_id)
    if user.role == "dentist" and case.patient and case.patient.dentist_id != user.id:
        raise HTTPException(status_code=403, detail="Not your patient")
    scan = _get_scan(db, case_id, scan_id)
    path = Path(scan.file_path)
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Scan file missing on server")
    # Files are stored encrypted at rest — decrypt before mesh parsing.
    raw_name = path.name.removesuffix(".enc")
    try:
        data = read_case_file(path)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Could not decrypt scan: {exc}") from exc
    preview = preview_mesh_bytes(data, filename=raw_name)
    meta = _serialize_scan(scan, case)
    preview.update(meta)
    return preview


@router.get("/{case_id}/scans/{scan_id}/file")
def download_scan_file(
    case_id: int,
    scan_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    from fastapi.responses import Response

    case = _get_case(db, case_id)
    if user.role == "dentist" and case.patient and case.patient.dentist_id != user.id:
        raise HTTPException(status_code=403, detail="Not your patient")
    scan = _get_scan(db, case_id, scan_id)
    path = Path(scan.file_path)
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Scan file missing on server")
    raw_name = path.name.removesuffix(".enc")
    try:
        data = read_case_file(path)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Could not decrypt scan: {exc}") from exc
    return Response(
        content=data,
        media_type="application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{raw_name}"'},
    )

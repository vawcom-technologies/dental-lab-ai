"""Photos API — frontal/left/right, max 10 per case (Week 2)."""

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_dentist
from app.models import User, Case, Photo, ActivityLog
from app.storage.local import save_case_file

router = APIRouter()

ALLOWED_ANGLES = {"frontal", "left", "right", "other"}
MAX_PHOTOS = 10


@router.post("/{case_id}/photos")
async def upload_photo(
    case_id: int,
    angle: str = Form(...),
    file: UploadFile = File(...),
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    if angle not in ALLOWED_ANGLES:
        raise HTTPException(status_code=400, detail=f"angle must be one of {sorted(ALLOWED_ANGLES)}")
    case = db.query(Case).filter(Case.id == case_id).first()
    if not case:
        raise HTTPException(status_code=404, detail="Case not found")

    count = db.query(Photo).filter(Photo.case_id == case_id).count()
    if count >= MAX_PHOTOS:
        raise HTTPException(status_code=400, detail=f"Max {MAX_PHOTOS} photos per case")

    data = await file.read()
    path = save_case_file(case_id, "photos", file.filename or "photo.jpg", data)
    photo = Photo(
        case_id=case_id,
        file_path=str(path),
        angle=angle,
        resolution=None,  # fill from EXIF/client metadata in Week 2
    )
    db.add(photo)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="photo.upload",
            target_type="photo",
            target_id=photo.id,
        )
    )
    db.commit()
    db.refresh(photo)
    return {
        "id": photo.id,
        "case_id": case_id,
        "angle": photo.angle,
        "file_path": photo.file_path,
        "taken_at": photo.taken_at,
    }


@router.get("/{case_id}/photos")
def list_photos(
    case_id: int,
    user: User = Depends(require_dentist),
    db: Session = Depends(get_db),
):
    photos = db.query(Photo).filter(Photo.case_id == case_id).all()
    return [
        {
            "id": p.id,
            "angle": p.angle,
            "file_path": p.file_path,
            "taken_at": p.taken_at,
        }
        for p in photos
    ]

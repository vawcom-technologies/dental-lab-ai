from fastapi import APIRouter, File, Form, HTTPException, UploadFile
import json

from app.ai.scan_body import detect_diameter_from_image, list_reference_table, match_scan_body
from app.ai.scan_quality import validate_ply_bytes
from app.ai.shade_analyze import analyze_shade_from_bytes, analyze_tooth_from_outline_bytes
from app.schemas import ScanValidateOut, ShadeAnalyzeOut

router = APIRouter()


@router.post("/shade/suggest", response_model=ShadeAnalyzeOut)
async def shade_suggest(file: UploadFile = File(...)):
    data = await file.read()
    result = analyze_shade_from_bytes(data)
    return ShadeAnalyzeOut(
        teeth=result["teeth"],
        tooth_count=result["tooth_count"],
        accepted_count=result["accepted_count"],
        note=result["note"],
        image_width=result.get("image_width"),
        image_height=result.get("image_height"),
    )


@router.post("/shade/resample-outline")
async def shade_resample_outline(
    file: UploadFile = File(...),
    outline_json: str = Form(...),
    tooth_index: int = Form(0),
):
    """Re-match zones after the dentist edits a tooth outline polygon."""
    try:
        outline = json.loads(outline_json)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="outline_json must be JSON") from exc
    if not isinstance(outline, list) or len(outline) < 3:
        raise HTTPException(status_code=400, detail="outline needs at least 3 points")
    data = await file.read()
    try:
        return analyze_tooth_from_outline_bytes(
            data, outline, tooth_index=int(tooth_index)
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/scan/validate", response_model=ScanValidateOut)
async def scan_validate(file: UploadFile = File(...)):
    data = await file.read()
    result = validate_ply_bytes(data, filename=file.filename or "scan.ply")
    return ScanValidateOut(
        result=result["result"],
        quality_score=result["quality_score"],
        reasons=result["reasons"],
        note=result["note"],
        issues=result.get("issues", []),
        prompt_rescan=result.get("prompt_rescan", False),
    )


@router.get("/scan-body/table")
def scan_body_table():
    return {
        "rows": list_reference_table(),
        "note": "Provisional table — replace with client ground truth.",
    }


@router.post("/scan-body/match")
def scan_body_match(diameter_mm: float = Form(...)):
    return match_scan_body(diameter_mm)


@router.post("/scan-body/detect")
async def scan_body_detect(
    file: UploadFile = File(...),
    pixels_per_mm: float | None = Form(None),
    known_diameter_mm: float | None = Form(None),
):
    data = await file.read()
    return detect_diameter_from_image(
        data,
        pixels_per_mm=pixels_per_mm,
        known_diameter_mm=known_diameter_mm,
    )

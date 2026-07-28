from fastapi import APIRouter, File, Form, UploadFile

from app.ai.scan_body import detect_diameter_from_image, list_reference_table, match_scan_body
from app.ai.scan_quality import validate_ply_bytes
from app.ai.shade import suggest_shade_from_bytes
from app.schemas import ScanValidateOut, ShadeSuggestOut

router = APIRouter()


@router.post("/shade/suggest", response_model=ShadeSuggestOut)
async def shade_suggest(file: UploadFile = File(...)):
    data = await file.read()
    result = suggest_shade_from_bytes(data)
    return ShadeSuggestOut(
        suggested_shade=result["suggested_shade"],
        confidence=result["confidence"],
        top_matches=result["top_matches"],
        note=result["note"],
    )


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

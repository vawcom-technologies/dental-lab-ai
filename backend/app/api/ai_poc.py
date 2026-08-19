from __future__ import annotations

import asyncio
import json
import logging
import time

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field

from app.ai.scan_quality import validate_ply_bytes
from app.ai.shade_analyze import analyze_shade_from_bytes, analyze_tooth_from_outline_bytes
from app.core.security import AuthUser, get_current_user
from app.schemas import ScanValidateOut, ShadeAnalyzeOut
from app.services import patient_media as pm
from app.services.shade_media import load_shade_detection_bytes

router = APIRouter()
logger = logging.getLogger("app.api.ai")


class ShadeSuggestFromDetectionIn(BaseModel):
    shade_detection_id: str = Field(min_length=1)


class ShadeResampleFromDetectionIn(BaseModel):
    shade_detection_id: str = Field(min_length=1)
    outline: list[list[float]]
    tooth_index: int = 0


def _shade_out(result: dict) -> ShadeAnalyzeOut:
    return ShadeAnalyzeOut(
        teeth=result["teeth"],
        tooth_count=result["tooth_count"],
        accepted_count=result["accepted_count"],
        note=result["note"],
        image_width=result.get("image_width"),
        image_height=result.get("image_height"),
    )


async def _analyze_bytes(data: bytes) -> dict:
    started = time.perf_counter()
    result = await asyncio.to_thread(analyze_shade_from_bytes, data)
    logger.info(
        "shade analyze done bytes=%s ms=%.0f teeth=%s",
        len(data),
        (time.perf_counter() - started) * 1000,
        result.get("tooth_count"),
    )
    return result


def _load_detection_for_user(shade_detection_id: str, user: AuthUser) -> dict:
    row = pm.fetch_row("shade_detections", shade_detection_id.strip())
    if row is None:
        raise HTTPException(status_code=404, detail="Shade detection not found")
    pm.require_patient_access(str(row.get("patient_id") or ""), user.id)
    return row


@router.post("/shade/suggest", response_model=ShadeAnalyzeOut)
async def shade_suggest(file: UploadFile = File(...)):
    data = await file.read()
    result = await _analyze_bytes(data)
    return _shade_out(result)


@router.post("/shade/suggest-from-detection", response_model=ShadeAnalyzeOut)
async def shade_suggest_from_detection(
    payload: ShadeSuggestFromDetectionIn,
    user: AuthUser = Depends(get_current_user),
):
    """Analyze a photo already stored on the server — no client re-upload."""
    row = _load_detection_for_user(payload.shade_detection_id, user)
    data = await asyncio.to_thread(load_shade_detection_bytes, row)
    result = await _analyze_bytes(data)
    return _shade_out(result)


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
        return await asyncio.to_thread(
            analyze_tooth_from_outline_bytes,
            data,
            outline,
            tooth_index=int(tooth_index),
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/shade/resample-outline-from-detection")
async def shade_resample_outline_from_detection(
    payload: ShadeResampleFromDetectionIn,
    user: AuthUser = Depends(get_current_user),
):
    if not isinstance(payload.outline, list) or len(payload.outline) < 3:
        raise HTTPException(status_code=400, detail="outline needs at least 3 points")
    row = _load_detection_for_user(payload.shade_detection_id, user)
    data = await asyncio.to_thread(load_shade_detection_bytes, row)
    try:
        return await asyncio.to_thread(
            analyze_tooth_from_outline_bytes,
            data,
            payload.outline,
            tooth_index=int(payload.tooth_index),
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/scan/validate", response_model=ScanValidateOut)
async def scan_validate(file: UploadFile = File(...)):
    data = await file.read()
    result = await asyncio.to_thread(
        validate_ply_bytes, data, filename=file.filename or "scan.ply"
    )
    return ScanValidateOut(
        result=result["result"],
        reasons=result["reasons"],
        note=result["note"],
        issues=result.get("issues", []),
        prompt_rescan=result.get("prompt_rescan", False),
    )

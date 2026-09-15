"""Chairside interpreter HTTP API. Turns are not stored."""

from __future__ import annotations

import asyncio
import logging

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field

from app.ai.interpreter import (
    InterpreterError,
    configured_providers,
    language_catalog,
    run_turn,
)
from app.core.security import AuthUser, require_dentist

router = APIRouter()
logger = logging.getLogger("app.api.interpreter")


class InterpreterTurnIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    source_lang: str = Field(min_length=2, max_length=8)
    target_lang: str = Field(min_length=2, max_length=8)


def _http(exc: InterpreterError) -> HTTPException:
    return HTTPException(status_code=exc.status_code, detail=str(exc))


@router.get("/languages")
async def list_languages(_: AuthUser = Depends(require_dentist)):
    return {
        "languages": language_catalog(),
        "providers": configured_providers(),
    }


@router.post("/turn")
async def interpreter_turn(
    payload: InterpreterTurnIn,
    _: AuthUser = Depends(require_dentist),
):
    try:
        result = await asyncio.to_thread(
            run_turn,
            text=payload.text,
            source_lang=payload.source_lang,
            target_lang=payload.target_lang,
        )
    except InterpreterError as exc:
        raise _http(exc) from exc
    logger.info(
        "interpreter turn provider=%s src=%s dst=%s chars=%s stt=%s",
        result.get("provider"),
        result.get("source_lang"),
        result.get("target_lang"),
        len(result.get("original") or ""),
        result.get("stt"),
    )
    return result


@router.post("/turn-audio")
async def interpreter_turn_audio(
    source_lang: str = Form(...),
    target_lang: str = Form(...),
    file: UploadFile = File(...),
    _: AuthUser = Depends(require_dentist),
):
    data = await file.read()
    try:
        result = await asyncio.to_thread(
            run_turn,
            audio=data,
            filename=file.filename or "speech.m4a",
            source_lang=source_lang,
            target_lang=target_lang,
        )
    except InterpreterError as exc:
        raise _http(exc) from exc
    logger.info(
        "interpreter audio provider=%s src=%s dst=%s chars=%s",
        result.get("provider"),
        result.get("source_lang"),
        result.get("target_lang"),
        len(result.get("original") or ""),
    )
    return result

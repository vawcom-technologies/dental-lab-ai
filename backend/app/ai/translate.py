"""Message / chairside translation. Interpreter is the real implementation."""

from __future__ import annotations

from app.ai.interpreter import translate_text as interpreter_translate


def translate_text(text: str, target_lang: str = "en", source_lang: str = "de") -> dict:
    return interpreter_translate(
        text,
        source_lang=source_lang,
        target_lang=target_lang,
    )

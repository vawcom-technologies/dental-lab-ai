"""Message translation (LLM). Scope: chat-only vs full UI — confirm with client."""

from __future__ import annotations


def translate_text(text: str, target_lang: str = "en") -> dict:
    return {
        "original": text,
        "translated": text,
        "target_lang": target_lang,
        "note": "Stub — wire Claude/GPT when translation scope is confirmed.",
    }

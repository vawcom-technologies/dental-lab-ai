"""Chairside interpreter language catalog (no network)."""

from __future__ import annotations

from app.ai.interpreter import (
    LANGUAGES,
    detect_formality,
    language_or_raise,
    translate_text,
)


def test_language_codes_are_unique():
    codes = [row["code"] for row in LANGUAGES]
    assert len(codes) == len(set(codes))
    assert len(codes) >= 70


def test_clinic_first_includes_iraqi_and_german():
    clinic = [row["code"] for row in LANGUAGES if row["clinic"]]
    for code in ("ar", "ku", "ckb", "tr", "fa", "de", "en"):
        assert code in clinic
    assert clinic[0] == "ar"


def test_rtl_flags():
    rtl = {row["code"] for row in LANGUAGES if row["rtl"]}
    assert {"ar", "fa", "ur", "he", "ckb", "ku", "ps"} <= rtl
    assert "de" not in rtl


def test_detect_formality_defaults_to_sie():
    assert detect_formality("Bitte den Mund öffnen.", "de", "ar") == "formal"
    assert detect_formality("Please open your mouth.", "en", "de") == "formal"


def test_detect_formality_keeps_du_and_sie():
    assert detect_formality("Kannst du den Mund öffnen?", "de", "en") == "informal"
    assert detect_formality("Können Sie den Mund öffnen?", "de", "en") == "formal"


def test_same_language_is_identity():
    out = translate_text("Bitte den Mund öffnen.", source_lang="de", target_lang="de")
    assert out["translated"] == "Bitte den Mund öffnen."
    assert out["provider"] == "identity"


def test_unknown_language_raises():
    try:
        language_or_raise("xx")
        raise AssertionError("expected InterpreterError")
    except Exception as exc:
        assert "Unsupported" in str(exc)


def test_live_gtx_german_to_arabic():
    """Network smoke — skip if the public translator is unreachable."""
    try:
        out = translate_text(
            "Bitte den Mund öffnen.",
            source_lang="de",
            target_lang="ar",
        )
    except Exception as exc:  # pragma: no cover
        import pytest

        pytest.skip(f"translator unavailable: {exc}")
    assert out["provider"] in {"deepl", "google", "openai", "gtx"}
    assert out["translated"]
    assert out["translated"] != "Bitte den Mund öffnen."
    assert any("\u0600" <= ch <= "\u06FF" for ch in out["translated"])

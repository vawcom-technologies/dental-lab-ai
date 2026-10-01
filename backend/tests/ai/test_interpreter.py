"""Chairside interpreter language catalog (no network)."""

from __future__ import annotations

import pytest

from app.ai import interpreter
from app.ai.interpreter import (
    LANGUAGES,
    InterpreterError,
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


class _Resp:
    status_code = 200

    def __init__(self, content):
        self._content = content

    def json(self):
        return {"choices": [{"message": {"content": self._content}}]}


def _fake_llm(monkeypatch, content='"Können Sie bitte den Mund öffnen?"'):
    seen = {}

    class _Client:
        def post(self, url, headers=None, json=None):
            seen["url"], seen["body"] = url, json
            return _Resp(content)

    monkeypatch.setattr(interpreter, "_client", _Client())
    monkeypatch.setattr(interpreter.settings, "interpreter_llm_api_key", "k")
    return seen


def test_llm_turn_is_formal_by_default_and_unquoted(monkeypatch):
    seen = _fake_llm(monkeypatch)
    out = translate_text("Open wide please.", source_lang="en", target_lang="de")
    assert out["provider"] == "llm"
    assert out["formality"] == "formal"
    assert out["translated"] == "Können Sie bitte den Mund öffnen?"
    system = seen["body"]["messages"][0]["content"]
    assert "formal" in system and "never mix registers" in system
    assert seen["body"]["messages"][1]["content"] == "Open wide please."


def test_explicit_informal_changes_the_prompt(monkeypatch):
    seen = _fake_llm(monkeypatch)
    translate_text("Hi", source_lang="en", target_lang="de", formality="informal")
    assert "informal" in seen["body"]["messages"][0]["content"]


def test_missing_key_is_a_clear_503(monkeypatch):
    monkeypatch.setattr(interpreter.settings, "interpreter_llm_api_key", "")
    monkeypatch.setattr(interpreter.settings, "openai_api_key", "")
    with pytest.raises(InterpreterError) as err:
        translate_text("Hi", source_lang="en", target_lang="de")
    assert err.value.status_code == 503

"""Chairside doctor ↔ patient interpreter.

Translates one turn at a time. Does not persist audio or text.
Prefer DeepL (EU) → Google Cloud → OpenAI → public Google gtx fallback.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

import httpx

from app.core.config import settings

logger = logging.getLogger("app.ai.interpreter")

_MAX_TEXT = 2000
_MAX_AUDIO = 4 * 1024 * 1024
_HTTP_TIMEOUT = 45.0

# Clinic-first, then the rest of a high-coverage spoken-language set.
# `speech` is a BCP-47 hint for on-device STT; empty means type-only.
LANGUAGES: tuple[dict[str, Any], ...] = (
    # ── Clinic-first (Iraqi / EU dental chair) ────────────────────────────
    {"code": "ar", "name": "Arabic", "native": "العربية", "rtl": True, "clinic": True, "speech": "ar_SA"},
    {"code": "ku", "name": "Kurdish (Kurmanji)", "native": "Kurdî", "rtl": True, "clinic": True, "speech": ""},
    {"code": "ckb", "name": "Kurdish (Sorani)", "native": "کوردی", "rtl": True, "clinic": True, "speech": ""},
    {"code": "tr", "name": "Turkish", "native": "Türkçe", "rtl": False, "clinic": True, "speech": "tr_TR"},
    {"code": "fa", "name": "Persian", "native": "فارسی", "rtl": True, "clinic": True, "speech": "fa_IR"},
    {"code": "en", "name": "English", "native": "English", "rtl": False, "clinic": True, "speech": "en_US"},
    {"code": "de", "name": "German", "native": "Deutsch", "rtl": False, "clinic": True, "speech": "de_DE"},
    {"code": "ru", "name": "Russian", "native": "Русский", "rtl": False, "clinic": True, "speech": "ru_RU"},
    {"code": "uk", "name": "Ukrainian", "native": "Українська", "rtl": False, "clinic": True, "speech": "uk_UA"},
    {"code": "pl", "name": "Polish", "native": "Polski", "rtl": False, "clinic": True, "speech": "pl_PL"},
    {"code": "ro", "name": "Romanian", "native": "Română", "rtl": False, "clinic": True, "speech": "ro_RO"},
    {"code": "bg", "name": "Bulgarian", "native": "Български", "rtl": False, "clinic": True, "speech": "bg_BG"},
    {"code": "sq", "name": "Albanian", "native": "Shqip", "rtl": False, "clinic": True, "speech": "sq_AL"},
    {"code": "sr", "name": "Serbian", "native": "Српски", "rtl": False, "clinic": True, "speech": "sr_RS"},
    {"code": "hr", "name": "Croatian", "native": "Hrvatski", "rtl": False, "clinic": True, "speech": "hr_HR"},
    {"code": "bs", "name": "Bosnian", "native": "Bosanski", "rtl": False, "clinic": True, "speech": "bs_BA"},
    {"code": "it", "name": "Italian", "native": "Italiano", "rtl": False, "clinic": True, "speech": "it_IT"},
    {"code": "fr", "name": "French", "native": "Français", "rtl": False, "clinic": True, "speech": "fr_FR"},
    {"code": "es", "name": "Spanish", "native": "Español", "rtl": False, "clinic": True, "speech": "es_ES"},
    {"code": "pt", "name": "Portuguese", "native": "Português", "rtl": False, "clinic": True, "speech": "pt_PT"},
    {"code": "vi", "name": "Vietnamese", "native": "Tiếng Việt", "rtl": False, "clinic": True, "speech": "vi_VN"},
    {"code": "zh", "name": "Chinese", "native": "中文", "rtl": False, "clinic": True, "speech": "zh_CN"},
    {"code": "hi", "name": "Hindi", "native": "हिन्दी", "rtl": False, "clinic": True, "speech": "hi_IN"},
    {"code": "ur", "name": "Urdu", "native": "اردو", "rtl": True, "clinic": True, "speech": "ur_PK"},
    {"code": "so", "name": "Somali", "native": "Soomaali", "rtl": False, "clinic": True, "speech": ""},
    {"code": "ps", "name": "Pashto", "native": "پښتو", "rtl": True, "clinic": True, "speech": ""},
    {"code": "am", "name": "Amharic", "native": "አማርኛ", "rtl": False, "clinic": True, "speech": ""},
    {"code": "ti", "name": "Tigrinya", "native": "ትግርኛ", "rtl": False, "clinic": True, "speech": ""},
    # ── Broader coverage ──────────────────────────────────────────────────
    {"code": "af", "name": "Afrikaans", "native": "Afrikaans", "rtl": False, "clinic": False, "speech": "af_ZA"},
    {"code": "az", "name": "Azerbaijani", "native": "Azərbaycan", "rtl": False, "clinic": False, "speech": ""},
    {"code": "be", "name": "Belarusian", "native": "Беларуская", "rtl": False, "clinic": False, "speech": ""},
    {"code": "bn", "name": "Bengali", "native": "বাংলা", "rtl": False, "clinic": False, "speech": "bn_BD"},
    {"code": "ca", "name": "Catalan", "native": "Català", "rtl": False, "clinic": False, "speech": "ca_ES"},
    {"code": "cs", "name": "Czech", "native": "Čeština", "rtl": False, "clinic": False, "speech": "cs_CZ"},
    {"code": "cy", "name": "Welsh", "native": "Cymraeg", "rtl": False, "clinic": False, "speech": "cy_GB"},
    {"code": "da", "name": "Danish", "native": "Dansk", "rtl": False, "clinic": False, "speech": "da_DK"},
    {"code": "el", "name": "Greek", "native": "Ελληνικά", "rtl": False, "clinic": False, "speech": "el_GR"},
    {"code": "et", "name": "Estonian", "native": "Eesti", "rtl": False, "clinic": False, "speech": "et_EE"},
    {"code": "eu", "name": "Basque", "native": "Euskara", "rtl": False, "clinic": False, "speech": ""},
    {"code": "fi", "name": "Finnish", "native": "Suomi", "rtl": False, "clinic": False, "speech": "fi_FI"},
    {"code": "ga", "name": "Irish", "native": "Gaeilge", "rtl": False, "clinic": False, "speech": "ga_IE"},
    {"code": "gl", "name": "Galician", "native": "Galego", "rtl": False, "clinic": False, "speech": ""},
    {"code": "gu", "name": "Gujarati", "native": "ગુજરાતી", "rtl": False, "clinic": False, "speech": "gu_IN"},
    {"code": "ha", "name": "Hausa", "native": "Hausa", "rtl": False, "clinic": False, "speech": ""},
    {"code": "he", "name": "Hebrew", "native": "עברית", "rtl": True, "clinic": False, "speech": "he_IL"},
    {"code": "hu", "name": "Hungarian", "native": "Magyar", "rtl": False, "clinic": False, "speech": "hu_HU"},
    {"code": "hy", "name": "Armenian", "native": "Հայերեն", "rtl": False, "clinic": False, "speech": ""},
    {"code": "id", "name": "Indonesian", "native": "Bahasa Indonesia", "rtl": False, "clinic": False, "speech": "id_ID"},
    {"code": "ig", "name": "Igbo", "native": "Igbo", "rtl": False, "clinic": False, "speech": ""},
    {"code": "is", "name": "Icelandic", "native": "Íslenska", "rtl": False, "clinic": False, "speech": "is_IS"},
    {"code": "ja", "name": "Japanese", "native": "日本語", "rtl": False, "clinic": False, "speech": "ja_JP"},
    {"code": "ka", "name": "Georgian", "native": "ქართული", "rtl": False, "clinic": False, "speech": ""},
    {"code": "kk", "name": "Kazakh", "native": "Қазақ", "rtl": False, "clinic": False, "speech": ""},
    {"code": "km", "name": "Khmer", "native": "ខ្មែរ", "rtl": False, "clinic": False, "speech": ""},
    {"code": "kn", "name": "Kannada", "native": "ಕನ್ನಡ", "rtl": False, "clinic": False, "speech": "kn_IN"},
    {"code": "ko", "name": "Korean", "native": "한국어", "rtl": False, "clinic": False, "speech": "ko_KR"},
    {"code": "lo", "name": "Lao", "native": "ລາວ", "rtl": False, "clinic": False, "speech": ""},
    {"code": "lt", "name": "Lithuanian", "native": "Lietuvių", "rtl": False, "clinic": False, "speech": "lt_LT"},
    {"code": "lv", "name": "Latvian", "native": "Latviešu", "rtl": False, "clinic": False, "speech": "lv_LV"},
    {"code": "mk", "name": "Macedonian", "native": "Македонски", "rtl": False, "clinic": False, "speech": "mk_MK"},
    {"code": "ml", "name": "Malayalam", "native": "മലയാളം", "rtl": False, "clinic": False, "speech": "ml_IN"},
    {"code": "mn", "name": "Mongolian", "native": "Монгол", "rtl": False, "clinic": False, "speech": ""},
    {"code": "mr", "name": "Marathi", "native": "मराठी", "rtl": False, "clinic": False, "speech": "mr_IN"},
    {"code": "ms", "name": "Malay", "native": "Bahasa Melayu", "rtl": False, "clinic": False, "speech": "ms_MY"},
    {"code": "mt", "name": "Maltese", "native": "Malti", "rtl": False, "clinic": False, "speech": "mt_MT"},
    {"code": "my", "name": "Burmese", "native": "မြန်မာ", "rtl": False, "clinic": False, "speech": ""},
    {"code": "nb", "name": "Norwegian", "native": "Norsk", "rtl": False, "clinic": False, "speech": "nb_NO"},
    {"code": "ne", "name": "Nepali", "native": "नेपाली", "rtl": False, "clinic": False, "speech": ""},
    {"code": "nl", "name": "Dutch", "native": "Nederlands", "rtl": False, "clinic": False, "speech": "nl_NL"},
    {"code": "pa", "name": "Punjabi", "native": "ਪੰਜਾਬੀ", "rtl": False, "clinic": False, "speech": "pa_IN"},
    {"code": "sk", "name": "Slovak", "native": "Slovenčina", "rtl": False, "clinic": False, "speech": "sk_SK"},
    {"code": "sl", "name": "Slovenian", "native": "Slovenščina", "rtl": False, "clinic": False, "speech": "sl_SI"},
    {"code": "sv", "name": "Swedish", "native": "Svenska", "rtl": False, "clinic": False, "speech": "sv_SE"},
    {"code": "sw", "name": "Swahili", "native": "Kiswahili", "rtl": False, "clinic": False, "speech": "sw_KE"},
    {"code": "ta", "name": "Tamil", "native": "தமிழ்", "rtl": False, "clinic": False, "speech": "ta_IN"},
    {"code": "te", "name": "Telugu", "native": "తెలుగు", "rtl": False, "clinic": False, "speech": "te_IN"},
    {"code": "th", "name": "Thai", "native": "ไทย", "rtl": False, "clinic": False, "speech": "th_TH"},
    {"code": "tl", "name": "Filipino", "native": "Filipino", "rtl": False, "clinic": False, "speech": "fil_PH"},
    {"code": "uz", "name": "Uzbek", "native": "Oʻzbek", "rtl": False, "clinic": False, "speech": ""},
    {"code": "yo", "name": "Yoruba", "native": "Yorùbá", "rtl": False, "clinic": False, "speech": ""},
    {"code": "zu", "name": "Zulu", "native": "isiZulu", "rtl": False, "clinic": False, "speech": "zu_ZA"},
)

_BY_CODE = {str(row["code"]): row for row in LANGUAGES}

# DeepL uses uppercase codes; a few of ours need a remap.
_DEEPL = {
    "ar": "AR",
    "bg": "BG",
    "cs": "CS",
    "da": "DA",
    "de": "DE",
    "el": "EL",
    "en": "EN",
    "es": "ES",
    "et": "ET",
    "fi": "FI",
    "fr": "FR",
    "he": "HE",
    "hu": "HU",
    "id": "ID",
    "it": "IT",
    "ja": "JA",
    "ko": "KO",
    "lt": "LT",
    "lv": "LV",
    "nb": "NB",
    "nl": "NL",
    "pl": "PL",
    "pt": "PT",
    "ro": "RO",
    "ru": "RU",
    "sk": "SK",
    "sl": "SL",
    "sv": "SV",
    "th": "TH",
    "tr": "TR",
    "uk": "UK",
    "vi": "VI",
    "zh": "ZH",
}


class InterpreterError(Exception):
    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.status_code = status_code


def language_catalog() -> list[dict[str, Any]]:
    return [dict(row) for row in LANGUAGES]


def language_or_raise(code: str) -> dict[str, Any]:
    key = (code or "").strip().lower()
    if key == "no":
        key = "nb"
    row = _BY_CODE.get(key)
    if row is None:
        raise InterpreterError(f"Unsupported language: {code}")
    return row


def configured_providers() -> dict[str, str]:
    translate = "none"
    if (settings.deepl_api_key or "").strip():
        translate = "deepl"
    elif (settings.google_translate_api_key or "").strip():
        translate = "google"
    elif (settings.openai_api_key or "").strip():
        translate = "openai"
    elif settings.interpreter_allow_gtx_fallback:
        translate = "gtx"
    stt = "whisper" if (settings.openai_api_key or "").strip() else "none"
    return {"translate": translate, "stt": stt}


_INFORMAL_DE = re.compile(
    r"\b(du|dir|dich|dein|deine|deinen|deinem|deiner|euch|euer|eure)\b",
    re.IGNORECASE,
)
_FORMAL_DE = re.compile(r"\b(Sie|Ihnen|Ihre|Ihren|Ihrem|Ihrer)\b")


def detect_formality(text: str, source_lang: str, target_lang: str) -> str:
    """'formal' or 'informal'. Clinic German defaults to Sie unless they said du."""
    src = (source_lang or "").lower()
    dst = (target_lang or "").lower()
    if src != "de" and dst != "de":
        return "formal"
    if _INFORMAL_DE.search(text or ""):
        return "informal"
    if _FORMAL_DE.search(text or ""):
        return "formal"
    return "formal"


def _output_misses_formality(text: str, target_lang: str, formality: str) -> bool:
    if (target_lang or "").lower() != "de":
        return False
    informal = bool(_INFORMAL_DE.search(text or ""))
    formal = bool(_FORMAL_DE.search(text or ""))
    if formality == "formal" and informal:
        return True
    if formality == "informal" and formal and not informal:
        return True
    return False


def translate_text(
    text: str,
    *,
    source_lang: str,
    target_lang: str,
    formality: str | None = None,
) -> dict[str, Any]:
    original = (text or "").strip()
    if not original:
        raise InterpreterError("Type or speak something first.")
    if len(original) > _MAX_TEXT:
        raise InterpreterError(f"Text is too long (max {_MAX_TEXT} characters).")

    src = language_or_raise(source_lang)
    dst = language_or_raise(target_lang)
    if src["code"] == dst["code"]:
        return {
            "original": original,
            "translated": original,
            "source_lang": src["code"],
            "target_lang": dst["code"],
            "provider": "identity",
            "stt": False,
            "formality": (formality or detect_formality(original, source_lang, target_lang)),
        }

    wanted = (formality or detect_formality(original, source_lang, target_lang)).strip().lower()
    if wanted not in {"formal", "informal"}:
        wanted = "formal"

    errors: list[str] = []
    fallback: dict[str, Any] | None = None
    for name, fn in (
        ("deepl", _deepl_translate),
        ("google", _google_translate),
        ("openai", _openai_translate),
        ("gtx", _gtx_translate),
    ):
        try:
            translated = fn(original, src["code"], dst["code"], wanted)
            if translated:
                payload = {
                    "original": original,
                    "translated": translated,
                    "source_lang": src["code"],
                    "target_lang": dst["code"],
                    "provider": name,
                    "stt": False,
                    "formality": wanted,
                }
                if not _output_misses_formality(translated, dst["code"], wanted):
                    return payload
                if fallback is None:
                    fallback = payload
        except InterpreterError as exc:
            errors.append(f"{name}: {exc}")
        except Exception as exc:  # pragma: no cover - network
            logger.info("interpreter provider %s failed: %s", name, type(exc).__name__)
            errors.append(f"{name}: unavailable")

    if fallback is not None:
        return fallback

    raise InterpreterError(
        "Translation is not available right now. "
        "Add DEEPL_API_KEY (or GOOGLE_TRANSLATE_API_KEY / OPENAI_API_KEY) "
        "to backend/.env and restart the API. "
        + ("; ".join(errors) if errors else ""),
        status_code=503,
    )


def transcribe_audio(
    data: bytes,
    *,
    filename: str,
    language: str,
) -> str:
    key = (settings.openai_api_key or "").strip()
    if not key:
        raise InterpreterError(
            "Voice transcription needs OPENAI_API_KEY. Type the sentence instead.",
            status_code=503,
        )
    if not data:
        raise InterpreterError("Empty audio.")
    if len(data) > _MAX_AUDIO:
        raise InterpreterError("Recording is too long. Speak a shorter sentence.")

    lang = language_or_raise(language)["code"]
    name = (filename or "speech.m4a").split("/")[-1] or "speech.m4a"
    files = {"file": (name, data, "application/octet-stream")}
    form = {"model": "whisper-1", "language": lang}
    try:
        with httpx.Client(timeout=_HTTP_TIMEOUT) as client:
            res = client.post(
                "https://api.openai.com/v1/audio/transcriptions",
                headers={"Authorization": f"Bearer {key}"},
                data=form,
                files=files,
            )
    except httpx.HTTPError as exc:
        raise InterpreterError("Could not reach the speech service.", 503) from exc
    if res.status_code >= 400:
        raise InterpreterError("Could not transcribe speech. Try typing instead.", 502)
    payload = res.json()
    text = str(payload.get("text") or "").strip()
    if not text:
        raise InterpreterError("Nothing was heard. Hold the button and speak clearly.")
    return text


def run_turn(
    *,
    text: str | None = None,
    audio: bytes | None = None,
    filename: str = "speech.m4a",
    source_lang: str,
    target_lang: str,
    formality: str | None = None,
) -> dict[str, Any]:
    spoken = False
    if audio:
        text = transcribe_audio(audio, filename=filename, language=source_lang)
        spoken = True
    result = translate_text(
        text or "",
        source_lang=source_lang,
        target_lang=target_lang,
        formality=formality,
    )
    result["stt"] = spoken
    return result


_DEEPL_FORMALITY_TARGETS = {
    "DE",
    "FR",
    "IT",
    "ES",
    "NL",
    "PL",
    "PT",
    "JA",
    "RU",
}


def _deepl_translate(
    text: str, source: str, target: str, formality: str = "formal"
) -> str | None:
    key = (settings.deepl_api_key or "").strip()
    if not key:
        return None
    src = _DEEPL.get(source)
    dst = _DEEPL.get(target)
    if not dst:
        return None
    base = (
        "https://api.deepl.com/v2/translate"
        if not key.endswith(":fx")
        else "https://api-free.deepl.com/v2/translate"
    )
    data: dict[str, Any] = {"text": [text], "target_lang": dst}
    if src:
        data["source_lang"] = src
    if dst in _DEEPL_FORMALITY_TARGETS:
        data["formality"] = "prefer_more" if formality == "formal" else "prefer_less"
    with httpx.Client(timeout=_HTTP_TIMEOUT) as client:
        res = client.post(
            base,
            headers={"Authorization": f"DeepL-Auth-Key {key}"},
            json=data,
        )
    if res.status_code >= 400:
        raise InterpreterError("DeepL rejected the request.")
    translations = res.json().get("translations") or []
    if not translations:
        raise InterpreterError("DeepL returned an empty translation.")
    return str(translations[0].get("text") or "").strip()


def _google_translate(
    text: str, source: str, target: str, _formality: str = "formal"
) -> str | None:
    key = (settings.google_translate_api_key or "").strip()
    if not key:
        return None
    with httpx.Client(timeout=_HTTP_TIMEOUT) as client:
        res = client.post(
            "https://translation.googleapis.com/language/translate/v2",
            params={"key": key},
            json={
                "q": text,
                "source": source,
                "target": target,
                "format": "text",
            },
        )
    if res.status_code >= 400:
        raise InterpreterError("Google Translate rejected the request.")
    translations = (
        (res.json().get("data") or {}).get("translations") or []
    )
    if not translations:
        raise InterpreterError("Google Translate returned an empty translation.")
    return str(translations[0].get("translatedText") or "").strip()


def _openai_translate(
    text: str, source: str, target: str, formality: str = "formal"
) -> str | None:
    key = (settings.openai_api_key or "").strip()
    if not key:
        return None
    src = language_or_raise(source)
    dst = language_or_raise(target)
    prompt = (
        f"Translate from {src['name']} to {dst['name']}. "
        "Return only the translation, no quotes or notes. "
        "Keep medical/dental terms accurate."
    )
    if dst["code"] == "de":
        prompt += (
            " Address the listener with informal German du/dir/dich, never Sie."
            if formality == "informal"
            else " Address the listener with formal German Sie/Ihnen/Ihr, never du/dir/dich."
        )
    elif src["code"] == "de":
        prompt += " Preserve the source formality (Sie vs du) in the translation."
    with httpx.Client(timeout=_HTTP_TIMEOUT) as client:
        res = client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {key}"},
            json={
                "model": "gpt-4o-mini",
                "temperature": 0.1,
                "messages": [
                    {"role": "system", "content": prompt},
                    {"role": "user", "content": text},
                ],
            },
        )
    if res.status_code >= 400:
        raise InterpreterError("OpenAI rejected the request.")
    choices = res.json().get("choices") or []
    if not choices:
        raise InterpreterError("OpenAI returned an empty translation.")
    content = ((choices[0].get("message") or {}).get("content") or "").strip()
    return content.strip().strip('"')


def _gtx_translate(
    text: str, source: str, target: str, _formality: str = "formal"
) -> str | None:
    if not settings.interpreter_allow_gtx_fallback:
        return None
    params = {
        "client": "gtx",
        "sl": source,
        "tl": target,
        "dt": "t",
        "q": text,
    }
    with httpx.Client(timeout=_HTTP_TIMEOUT) as client:
        res = client.get(
            "https://translate.googleapis.com/translate_a/single",
            params=params,
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/120.0.0.0 Safari/537.36"
                ),
                "Accept": "*/*",
            },
        )
    if res.status_code >= 400:
        logger.info("interpreter gtx status=%s", res.status_code)
        raise InterpreterError("Fallback translator is unavailable.")
    try:
        payload = res.json()
    except json.JSONDecodeError as exc:
        raise InterpreterError("Fallback translator returned invalid data.") from exc
    chunks = payload[0] if isinstance(payload, list) and payload else None
    if not isinstance(chunks, list):
        raise InterpreterError("Fallback translator returned an empty translation.")
    parts: list[str] = []
    for chunk in chunks:
        if isinstance(chunk, list) and chunk and isinstance(chunk[0], str):
            parts.append(chunk[0])
    translated = "".join(parts).strip()
    if not translated:
        raise InterpreterError("Fallback translator returned an empty translation.")
    return translated

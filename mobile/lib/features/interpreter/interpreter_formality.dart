/// Clinic interpreter: keep formal vs informal address (Sie/du, حضرتك/أنت, …).
enum InterpreterFormality { formal, informal }

class _FormalityPair {
  const _FormalityPair(this.informal, this.formal);
  final RegExp informal;
  final RegExp formal;
}

final _markers = <String, _FormalityPair>{
  'de': _FormalityPair(
    RegExp(
      r'\b(du|dir|dich|dein|deine|deinen|deinem|deiner|euch|euer|eure)\b',
      caseSensitive: false,
    ),
    RegExp(r'\b(Sie|Ihnen|Ihre|Ihren|Ihrem|Ihrer)\b'),
  ),
  'ar': _FormalityPair(
    RegExp(r'(أنت|انت|إليك|اليك|عندك|لكَ|لكِ)'),
    RegExp(r'(حضرتك|سيادتك|جنابك|سعادتك)'),
  ),
  'fr': _FormalityPair(
    RegExp(r"\b(tu|toi|te|ton|ta|tes|t['’])\b", caseSensitive: false),
    RegExp(r'\b(vous|votre|vos)\b', caseSensitive: false),
  ),
  'es': _FormalityPair(
    RegExp(r'\b(tú|te|ti|contigo)\b', caseSensitive: false),
    RegExp(r'\b(usted|ustedes)\b', caseSensitive: false),
  ),
  'it': _FormalityPair(
    RegExp(r'\b(tu|ti|te|tuo|tua|tuoi|tue)\b', caseSensitive: false),
    RegExp(r'\b(Lei|Loro|Sua|Sue|Suoi)\b'),
  ),
  'nl': _FormalityPair(
    RegExp(r'\b(jij|je|jou|jouw|jullie)\b', caseSensitive: false),
    RegExp(r'\b(u|uw|U)\b'),
  ),
  'pt': _FormalityPair(
    RegExp(r'\b(tu|te|ti|teu|tua|teus|tuas)\b', caseSensitive: false),
    RegExp(
      r'\b(você|vocês|o senhor|a senhora|os senhores|as senhoras)\b',
      caseSensitive: false,
    ),
  ),
  'tr': _FormalityPair(
    RegExp(r'\b(sen|sana|seni|senin)\b', caseSensitive: false),
    RegExp(r'\b(siz|size|sizi|sizin)\b', caseSensitive: false),
  ),
  'pl': _FormalityPair(
    RegExp(r'\b(ty|cię|ciebie|ci|twój|twoja|twoje)\b', caseSensitive: false),
    RegExp(r'\b(pan|pani|państwo|pana|panią)\b', caseSensitive: false),
  ),
  'ru': _FormalityPair(
    RegExp(
      r'\b(ты|тебя|тебе|тобой|твой|твоя|твоё|твои)\b',
      caseSensitive: false,
    ),
    RegExp(r'\b(вы|вас|вам|вами|ваш|ваша|ваше|ваши)\b', caseSensitive: false),
  ),
};

(bool, bool) _formalityHits(String text, String lang) {
  final pair = _markers[lang.toLowerCase()];
  if (pair == null) return (false, false);
  return (pair.informal.hasMatch(text), pair.formal.hasMatch(text));
}

InterpreterFormality detectInterpreterFormality(
  String text, {
  required String sourceLang,
  required String targetLang,
}) {
  final src = sourceLang.toLowerCase();
  final (informal, formal) = _formalityHits(text, src);
  if (informal && !formal) return InterpreterFormality.informal;
  if (formal && !informal) return InterpreterFormality.formal;
  if (informal && formal) return InterpreterFormality.formal;
  // Chairside default: formal you unless they spoke informal.
  return InterpreterFormality.formal;
}

bool translationMissesFormality(
  String translated, {
  required String targetLang,
  required InterpreterFormality wanted,
}) {
  final (informal, formal) = _formalityHits(translated, targetLang);
  if (wanted == InterpreterFormality.formal && informal && !formal) {
    return true;
  }
  if (wanted == InterpreterFormality.informal && formal && !informal) {
    return true;
  }
  return false;
}

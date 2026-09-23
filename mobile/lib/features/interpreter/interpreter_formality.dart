/// Clinic interpreter: keep Sie vs du (and similar formal/informal address).
enum InterpreterFormality { formal, informal }

final _informalDe = RegExp(
  r'\b(du|dir|dich|dein|deine|deinen|deinem|deiner|euch|euer|eure)\b',
  caseSensitive: false,
);

final _formalDe = RegExp(
  r'\b(Sie|Ihnen|Ihre|Ihren|Ihrem|Ihrer)\b',
);

final _informalOutDe = RegExp(
  r'\b(du|dir|dich|dein|deine)\b',
  caseSensitive: false,
);

InterpreterFormality detectInterpreterFormality(
  String text, {
  required String sourceLang,
  required String targetLang,
}) {
  final src = sourceLang.toLowerCase();
  final dst = targetLang.toLowerCase();
  final involved = src == 'de' || dst == 'de';
  if (!involved) return InterpreterFormality.formal;
  if (_informalDe.hasMatch(text)) return InterpreterFormality.informal;
  if (_formalDe.hasMatch(text)) return InterpreterFormality.formal;
  // Chairside default: doctor ↔ patient uses Sie unless they spoke du.
  return InterpreterFormality.formal;
}

bool translationMissesFormality(
  String translated, {
  required String targetLang,
  required InterpreterFormality wanted,
}) {
  if (targetLang.toLowerCase() != 'de') return false;
  final informal = _informalOutDe.hasMatch(translated);
  if (wanted == InterpreterFormality.formal && informal) return true;
  if (wanted == InterpreterFormality.informal &&
      _formalDe.hasMatch(translated) &&
      !informal) {
    return true;
  }
  return false;
}

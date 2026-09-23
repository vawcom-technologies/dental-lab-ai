import 'package:dental_lab_ai/features/interpreter/interpreter_formality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clinic German defaults to formal Sie', () {
    expect(
      detectInterpreterFormality(
        'Bitte den Mund öffnen.',
        sourceLang: 'de',
        targetLang: 'ar',
      ),
      InterpreterFormality.formal,
    );
    expect(
      detectInterpreterFormality(
        'Please open your mouth.',
        sourceLang: 'en',
        targetLang: 'de',
      ),
      InterpreterFormality.formal,
    );
  });

  test('spoken du stays informal and Sie stays formal', () {
    expect(
      detectInterpreterFormality(
        'Kannst du den Mund öffnen?',
        sourceLang: 'de',
        targetLang: 'en',
      ),
      InterpreterFormality.informal,
    );
    expect(
      detectInterpreterFormality(
        'Können Sie den Mund öffnen?',
        sourceLang: 'de',
        targetLang: 'en',
      ),
      InterpreterFormality.formal,
    );
  });

  test('Apple-style informal German is retried', () {
    expect(
      translationMissesFormality(
        'Kannst du bitte den Mund öffnen?',
        targetLang: 'de',
        wanted: InterpreterFormality.formal,
      ),
      isTrue,
    );
    expect(
      translationMissesFormality(
        'Können Sie bitte den Mund öffnen?',
        targetLang: 'de',
        wanted: InterpreterFormality.formal,
      ),
      isFalse,
    );
  });
}

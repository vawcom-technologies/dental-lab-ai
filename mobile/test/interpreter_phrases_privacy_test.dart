import 'package:dental_lab_ai/features/interpreter/interpreter_phrases.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phrases with personal details are never remembered', () {
    expect(looksPersonal('Bitte weit öffnen'), isFalse);
    expect(looksPersonal('Ihr Termin ist am 12.11.'), isTrue);
    expect(looksPersonal('Rufen Sie 0170 1234567 an'), isTrue);
    expect(looksPersonal('Schreiben Sie an anna@praxis.de'), isTrue);
    expect(looksPersonal('a' * 121), isTrue);
  });
}

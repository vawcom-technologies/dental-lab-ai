import 'package:dental_lab_ai/features/interpreter/interpreter_languages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interpreter catalog has unique codes and clinic-first Arabic', () {
    final codes = kInterpreterLanguages.map((e) => e.code).toList();
    expect(codes.toSet().length, codes.length);
    expect(codes.length, greaterThanOrEqualTo(70));
    expect(codes.first, 'ar');
    expect(
      kInterpreterLanguages.where((e) => e.clinic).map((e) => e.code),
      containsAll(['ar', 'ku', 'ckb', 'tr', 'fa', 'de', 'en']),
    );
    expect(InterpreterLanguage.byCode(kInterpreterLanguages, 'ar')?.rtl, isTrue);
    expect(InterpreterLanguage.byCode(kInterpreterLanguages, 'de')?.rtl, isFalse);
  });
}

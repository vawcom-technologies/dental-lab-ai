import 'package:dental_lab_ai/features/interpreter/interpreter_phrases.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only repeated phrases become pills; STT variants merge', () {
    final p = PhraseCounts()
      ..add('Open wide.')
      ..add('Rinse, please')
      ..add('open wide');
    expect(p.repeated(), ['open wide']);
    p.remove('Open wide');
    expect(p.repeated(), isEmpty);
  });

  test('survives JSON round trip and clear', () {
    final p = PhraseCounts()
      ..add('Bite down')
      ..add('Bite down');
    final back = PhraseCounts.fromJson(p.toJson());
    expect(back.repeated(), ['Bite down']);
    back.clear();
    expect(back.isEmpty, isTrue);
    expect(PhraseCounts.fromJson('garbage').isEmpty, isTrue);
  });
}

import 'package:dental_lab_ai/features/interpreter/apple_translate.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleTranslate.channel, null);
  });

  test('apple translate returns native text', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleTranslate.channel, (call) async {
      expect(call.method, 'translate');
      expect(call.arguments['source'], 'de');
      expect(call.arguments['target'], 'ar');
      return 'من فضلك افتح فمك';
    });

    expect(
      await AppleTranslate.translate(
        text: 'Bitte den Mund öffnen',
        sourceLang: 'de',
        targetLang: 'ar',
      ),
      'من فضلك افتح فمك',
    );
  });

  test('same language skips the channel', () async {
    expect(
      await AppleTranslate.translate(
        text: 'hello',
        sourceLang: 'en',
        targetLang: 'en',
      ),
      'hello',
    );
  });

  test('warmSpeech is a no-op when the plugin is missing', () async {
    await AppleTranslate.warmSpeech('fa_IR');
  });

  test('warmSpeech asks iOS to fetch speech assets', () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleTranslate.channel, (call) async {
      expect(call.method, 'speechWarm');
      expect(call.arguments['locale'], 'fa_IR');
      called = true;
      return null;
    });
    await AppleTranslate.warmSpeech('fa_IR');
    expect(called, isTrue);
  });

  test('unsupported pair throws AppleTranslateUnsupported', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleTranslate.channel, (call) async {
      throw PlatformException(code: 'unsupported');
    });

    expect(
      () => AppleTranslate.translate(
        text: 'Bitte warten',
        sourceLang: 'de',
        targetLang: 'ku',
      ),
      throwsA(isA<AppleTranslateUnsupported>()),
    );
  });
}

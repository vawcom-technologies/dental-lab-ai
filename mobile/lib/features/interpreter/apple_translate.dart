import 'dart:async';

import 'package:flutter/services.dart';

class AppleTranslateUnsupported implements Exception {
  const AppleTranslateUnsupported();
}

/// Apple Translate on demand (iPadOS 18+).
class AppleTranslate {
  static const channel = MethodChannel('elite_dent/apple_translate');

  /// Ask iOS to start fetching speech assets. Does not wait or block listen.
  static Future<void> warmSpeech(String locale) async {
    final id = locale.trim();
    if (id.isEmpty) return;
    try {
      await channel.invokeMethod<void>('speechWarm', {'locale': id});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<String?> translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final spoken = text.trim();
    if (spoken.isEmpty) return null;
    final source = sourceLang.trim().toLowerCase();
    final target = targetLang.trim().toLowerCase();
    if (source == target) return spoken;
    try {
      final out = await channel
          .invokeMethod<String>('translate', {
            'text': spoken,
            'source': source,
            'target': target,
          })
          .timeout(const Duration(seconds: 90));
      final translated = out?.trim() ?? '';
      return translated.isEmpty ? null : translated;
    } on MissingPluginException {
      throw const AppleTranslateUnsupported();
    } on PlatformException catch (e) {
      if (e.code == 'unsupported') throw const AppleTranslateUnsupported();
      rethrow;
    }
  }
}

import 'dart:async';

import 'package:flutter/services.dart';

class AppleTranslateUnsupported implements Exception {
  const AppleTranslateUnsupported();
}

/// The pair is supported but its language pack has not been downloaded yet.
class AppleTranslateNotInstalled implements Exception {
  const AppleTranslateNotInstalled();
}

enum AppleLanguageStatus { installed, supported, unsupported }

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

  /// Cheap local check; never starts a translation or a download.
  static Future<AppleLanguageStatus> status({
    required String sourceLang,
    required String targetLang,
  }) async {
    try {
      final raw = await channel.invokeMethod<String>('status', {
        'source': sourceLang.trim().toLowerCase(),
        'target': targetLang.trim().toLowerCase(),
      });
      return switch (raw) {
        'installed' => AppleLanguageStatus.installed,
        'supported' => AppleLanguageStatus.supported,
        _ => AppleLanguageStatus.unsupported,
      };
    } on MissingPluginException {
      return AppleLanguageStatus.unsupported;
    } on PlatformException {
      return AppleLanguageStatus.unsupported;
    }
  }

  /// Shows Apple's download sheet for the pair. True once the packs are in.
  static Future<bool> prepare({
    required String sourceLang,
    required String targetLang,
  }) async {
    try {
      final ok = await channel
          .invokeMethod<String>('prepare', {
            'source': sourceLang.trim().toLowerCase(),
            'target': targetLang.trim().toLowerCase(),
          })
          .timeout(const Duration(minutes: 5));
      return ok == 'ok';
    } on MissingPluginException {
      return false;
    } on TimeoutException {
      return false;
    } on PlatformException {
      return false;
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
    } on TimeoutException {
      throw const AppleTranslateUnsupported();
    } on PlatformException catch (e) {
      // Simulator / missing packs / unsupported pair → let the app use backend.
      // Do not treat bad args as unsupported (caller bug).
      if (e.code == 'args') rethrow;
      if (e.code == 'notInstalled') throw const AppleTranslateNotInstalled();
      throw const AppleTranslateUnsupported();
    }
  }
}

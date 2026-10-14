import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Native: write into a temp file the recorder can close and we can re-read.
Future<String> resolveVoiceRecordPath({String extension = 'wav'}) async {
  final dir = await getTemporaryDirectory();
  final ext = extension.startsWith('.') ? extension.substring(1) : extension;
  return '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
}

Future<void> deleteVoiceRecord(String path) async {
  try {
    await File(path).delete();
  } catch (_) {}
}

/// Interpreter OpenAI voice cache. Library/Caches survives visits (so a
/// repeated phrase is never billed twice) and iOS purges it under pressure.
Future<String> ttsCachePath(String name) async {
  final base = await getApplicationCacheDirectory();
  final dir = Directory('${base.path}/interpreter_tts');
  await dir.create(recursive: true);
  return '${dir.path}/$name.mp3';
}

Future<bool> audioFileExists(String path) => File(path).exists();

Future<void> writeAudioFile(String path, List<int> bytes) =>
    File(path).writeAsBytes(bytes, flush: true);

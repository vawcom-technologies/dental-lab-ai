/// Stub / web: empty path streams into browser memory (blob).
Future<String> resolveVoiceRecordPath({String extension = 'wav'}) async => '';

Future<void> deleteVoiceRecord(String path) async {}

Future<String> ttsCachePath(String name) async => '';

Future<bool> audioFileExists(String path) async => false;

Future<void> writeAudioFile(String path, List<int> bytes) async {}

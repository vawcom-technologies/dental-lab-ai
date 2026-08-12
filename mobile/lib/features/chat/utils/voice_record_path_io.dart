import 'package:path_provider/path_provider.dart';

/// Native: write into a temp file the recorder can close and we can re-read.
Future<String> resolveVoiceRecordPath({String extension = 'wav'}) async {
  final dir = await getTemporaryDirectory();
  final ext = extension.startsWith('.') ? extension.substring(1) : extension;
  return '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
}

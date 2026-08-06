import 'package:path_provider/path_provider.dart';

/// Native: write into a temp file the recorder can close and we can re-read.
Future<String> resolveVoiceRecordPath() async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
}

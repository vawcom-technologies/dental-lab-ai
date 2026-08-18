import 'dart:io';

import 'package:video_player/video_player.dart';

/// Reads duration from the original local file without playing it.
Future<double?> probeLocalVideoDuration(String path) async {
  final filePath = path.trim();
  if (filePath.isEmpty) return null;
  final file = File(filePath);
  if (!file.existsSync()) return null;
  final controller = VideoPlayerController.file(file);
  try {
    await controller.initialize();
    final ms = controller.value.duration.inMilliseconds;
    if (ms <= 0) return null;
    return ms / 1000.0;
  } catch (_) {
    return null;
  } finally {
    await controller.dispose();
  }
}

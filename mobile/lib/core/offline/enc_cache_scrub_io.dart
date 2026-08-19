import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<void> scrubEncFilesOnDisk({String prefix = 'enc_file_'}) async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    await _scrubDir(Directory(docs.path), prefix);
  } catch (_) {}
  try {
    final temp = await getTemporaryDirectory();
    await _scrubDir(Directory(temp.path), prefix);
  } catch (_) {}
}

Future<void> _scrubDir(Directory dir, String prefix) async {
  if (!await dir.exists()) return;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.isEmpty
        ? ''
        : entity.uri.pathSegments.last;
    if (name.startsWith(prefix) || name.contains(prefix)) {
      try {
        await entity.delete();
      } catch (_) {}
    }
  }
}

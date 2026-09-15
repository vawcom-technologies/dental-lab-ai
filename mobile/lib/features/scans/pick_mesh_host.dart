import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class HostMeshCandidate {
  const HostMeshCandidate({
    required this.path,
    required this.name,
    required this.folder,
  });
  final String path;
  final String name;
  final String folder;
}

bool get isIosSimulator => false;

bool get useIosFilesPicker => false;

bool isMeshFilename(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.ply') ||
      lower.endsWith('.stl') ||
      lower.endsWith('.obj');
}

Future<Uint8List?> readMeshBytes(PlatformFile file) async {
  if (file.bytes != null && file.bytes!.isNotEmpty) {
    return Uint8List.fromList(file.bytes!);
  }
  try {
    final raw = await file.xFile.readAsBytes();
    if (raw.isNotEmpty) return raw;
  } catch (_) {}
  return null;
}

Future<Uint8List?> readPathBytes(String path) async => null;

Future<void> seedHostMeshFiles() async {}

Future<List<String>> hostMeshSearchDirs() async => const [];

Future<List<HostMeshCandidate>> listHostMeshFiles(List<String> dirs) async =>
    const [];

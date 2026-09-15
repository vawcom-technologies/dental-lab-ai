import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

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

bool get isIosSimulator {
  if (!Platform.isIOS) return false;
  if (Platform.environment['SIMULATOR_DEVICE_NAME']?.isNotEmpty == true) {
    return true;
  }
  if (Platform.environment['SIMULATOR_UDID']?.isNotEmpty == true) {
    return true;
  }
  try {
    return Platform.resolvedExecutable.contains('CoreSimulator');
  } catch (_) {
    return false;
  }
}

/// Real iPad: system Files sheet. Simulator uses the Mac folder list instead.
bool get useIosFilesPicker => Platform.isIOS && !isIosSimulator;

const _meshExt = {'.ply', '.stl', '.obj'};

bool isMeshFilename(String name) {
  final lower = name.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0) return false;
  return _meshExt.contains(lower.substring(dot));
}

Future<Uint8List?> readMeshBytes(PlatformFile file) async {
  if (file.bytes != null && file.bytes!.isNotEmpty) {
    return Uint8List.fromList(file.bytes!);
  }
  final path = file.path;
  if (path != null && path.isNotEmpty) {
    final fromPath = await readPathBytes(path);
    if (fromPath != null && fromPath.isNotEmpty) return fromPath;
  }
  try {
    final raw = await file.xFile.readAsBytes();
    if (raw.isNotEmpty) return raw;
  } catch (_) {}
  return null;
}

Future<Uint8List?> readPathBytes(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) return await file.readAsBytes();
  } catch (_) {}
  return null;
}

const _projectMeshDirs = [
  '/Users/app/Projects/dental-lab-ai/mobile/debug_scans',
  '/Users/app/Projects/dental-lab-ai/references/scans',
];

String _basename(String path) {
  final sep = path.lastIndexOf(Platform.pathSeparator);
  return sep < 0 ? path : path.substring(sep + 1);
}

Future<List<String>> hostMeshSearchDirs() async {
  final home = Platform.environment['SIMULATOR_HOST_HOME'] ??
      Platform.environment['HOME'] ??
      '';
  final dirs = <String>[
    ..._projectMeshDirs,
    if (home.isNotEmpty) ...[
      '$home/Projects/dental-lab-ai/mobile/debug_scans',
      '$home/Projects/dental-lab-ai/references/scans',
    ],
  ];
  try {
    dirs.insert(0, (await getApplicationDocumentsDirectory()).path);
  } catch (_) {}
  return [
    for (final path in dirs)
      if (path.isNotEmpty) path,
  ];
}

Future<void> seedHostMeshFiles() async {
  if (!isIosSimulator) return;
  Directory? docs;
  try {
    docs = await getApplicationDocumentsDirectory();
  } catch (_) {
    return;
  }
  for (final srcPath in _projectMeshDirs) {
    try {
      final src = Directory(srcPath);
      if (!await src.exists()) continue;
      await for (final entity in src.list(followLinks: false)) {
        final name = _basename(entity.path);
        if (name.startsWith('.') || !isMeshFilename(name)) continue;
        if (!await FileSystemEntity.isFile(entity.path)) continue;
        final dest = File('${docs.path}/$name');
        if (await dest.exists()) continue;
        await File(entity.path).copy(dest.path);
      }
    } catch (_) {}
  }
}

Future<List<HostMeshCandidate>> listHostMeshFiles(List<String> dirs) async {
  final out = <HostMeshCandidate>[];
  final seen = <String>{};
  for (final dirPath in dirs) {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(followLinks: false)) {
        try {
          final name = _basename(entity.path);
          if (name.startsWith('.') || !isMeshFilename(name)) continue;
          if (!await FileSystemEntity.isFile(entity.path)) continue;
          if (!seen.add(name.toLowerCase())) continue;
          out.add(
            HostMeshCandidate(
              path: entity.path,
              name: name,
              folder: dirPath,
            ),
          );
        } catch (_) {}
      }
    } catch (_) {}
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_snackbar.dart';
import 'pick_mesh_host.dart' if (dart.library.io) 'pick_mesh_host_io.dart' as host;

class PickedMeshFile {
  const PickedMeshFile({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}

/// Pick a PLY / STL / OBJ.
///
/// Real iPad uses the system Files sheet (iCloud, USB, On My iPad).
/// The iOS Simulator cannot open Mac Downloads, so it lists `debug_scans`.
Future<PickedMeshFile?> pickMeshFile(BuildContext context) async {
  if (host.isIosSimulator) {
    try {
      await host.seedHostMeshFiles();
    } catch (_) {}
    return _pickFromListed(
      context,
      await host.listHostMeshFiles(await host.hostMeshSearchDirs()),
    );
  }

  try {
    final result = await FilePicker.pickFiles(
      type: host.useIosFilesPicker ? FileType.any : FileType.custom,
      allowedExtensions:
          host.useIosFilesPicker ? null : const ['ply', 'stl', 'obj'],
      withData: false,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final name = file.name.trim().isNotEmpty ? file.name : 'scan.ply';
    if (!host.isMeshFilename(name)) {
      if (context.mounted) {
        AppSnackBars.error(
          context,
          AppLocalizations.of(context).scansNeedMeshFile,
        );
      }
      return null;
    }
    final bytes = await host.readMeshBytes(file);
    if (bytes == null || bytes.isEmpty) {
      if (context.mounted) {
        AppSnackBars.error(
          context,
          AppLocalizations.of(context).scansCouldNotReadFile,
        );
      }
      return null;
    }
    return PickedMeshFile(bytes: bytes, name: name);
  } catch (_) {
    if (host.isIosSimulator && context.mounted) {
      return _pickFromListed(
        context,
        await host.listHostMeshFiles(await host.hostMeshSearchDirs()),
      );
    }
    rethrow;
  }
}

Future<PickedMeshFile?> _pickFromListed(
  BuildContext context,
  List<host.HostMeshCandidate> files,
) async {
  if (!context.mounted) return null;
  final loc = AppLocalizations.of(context);
  final selected = await showModalBottomSheet<host.HostMeshCandidate>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.scansSimulatorPickTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      loc.scansSimulatorPickHint,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: files.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            loc.scansSimulatorPickEmpty,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: files.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final item = files[i];
                          return ListTile(
                            leading: const Icon(Icons.view_in_ar_outlined),
                            title: Text(item.name),
                            subtitle: Text(
                              item.folder,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(ctx, item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (selected == null) return null;
  final bytes = await host.readPathBytes(selected.path);
  if (bytes == null || bytes.isEmpty) return null;
  return PickedMeshFile(bytes: bytes, name: selected.name);
}

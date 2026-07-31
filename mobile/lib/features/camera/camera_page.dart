import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/offline/sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'live_camera_capture.dart';

/// Week 2 camera capture — frontal / left / right, max 10 photos per case.
class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    required this.api,
    required this.dentistName,
  });

  final ApiClient api;
  final String dentistName;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late final SyncService _sync = SyncService(api: widget.api);
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _case;
  List<Map<String, dynamic>> _photos = [];
  String _angle = 'frontal';
  bool _loading = true;
  bool _busy = false;
  String? _status;
  String? _error;

  static const angles = ['frontal', 'left', 'right'];
  static const maxPhotos = 10;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await widget.api.listPatients();
      setState(() => _patients = patients);
      if (patients.isNotEmpty) {
        await _selectPatient(patients.first);
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectPatient(Map<String, dynamic> patient) async {
    setState(() {
      _patient = patient;
      _case = null;
      _photos = [];
      _status = null;
    });
    final cases = await widget.api.listCases();
    final mine = cases.where((c) => c['patient_id'] == patient['id']).toList();
    Map<String, dynamic> caseRow;
    if (mine.isEmpty) {
      caseRow = await widget.api.createCase(patient['id'] as int);
    } else {
      caseRow = mine.first;
    }
    final photos = await widget.api.listPhotos(caseRow['id'] as int);
    setState(() {
      _case = caseRow;
      _photos = photos;
    });
  }

  Future<void> _capture({required bool fromCamera}) async {
    if (_case == null) return;
    if (_photos.length >= maxPhotos) {
      AppHaptics.warn();
      setState(() => _error = 'Max $maxPhotos photos per case');
      return;
    }

    Uint8List? bytes;
    String filename = 'photo_$_angle.jpg';

    if (fromCamera) {
      // Live camera preview (not the photo library / file picker).
      bytes = await captureWithLiveCamera(
        context,
        hint: 'Capture $_angle photo for this case',
      );
      if (bytes == null) return;
    } else {
      AppHaptics.medium();
      final xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (xfile == null) return;
      bytes = Uint8List.fromList(await xfile.readAsBytes());
      if (xfile.name.isNotEmpty) filename = xfile.name;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final result = await _sync.capturePhoto(
        caseId: _case!['id'] as int,
        angle: _angle,
        bytes: bytes,
        filename: filename,
      );
      AppHaptics.success();
      if (result['queued'] == true) {
        setState(() => _status = result['note'] as String? ?? 'Queued offline');
      } else {
        setState(
          () => _status = 'Uploaded $_angle photo (${bytes!.length} bytes)',
        );
        final photos = await widget.api.listPhotos(_case!['id'] as int);
        setState(() => _photos = photos);
      }
      await _sync.flush();
      if (_case != null && result['queued'] != true) {
        final photos = await widget.api.listPhotos(_case!['id'] as int);
        setState(() => _photos = photos);
      }
    } catch (e) {
      AppHaptics.warn();
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).cameraTitle,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.navy),
          ),
          const Text(
            'Frontal / left / right · up to 10 photos · full resolution · encrypted local cache',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_patients.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Add a patient first, then capture photos.',
                    style: TextStyle(color: AppColors.muted)),
              ),
            )
          else
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 280,
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Patient', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                            initialValue: _patient?['id'] as int?,
                            items: _patients
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p['id'] as int,
                                    child: Text('${p['first_name']} ${p['last_name']}'),
                                  ),
                                )
                                .toList(),
                            onChanged: (id) {
                              final p = _patients.firstWhere((e) => e['id'] == id);
                              _selectPatient(p);
                            },
                          ),
                          const SizedBox(height: 16),
                          const Text('Angle', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: angles.map((a) {
                              final selected = _angle == a;
                              return ChoiceChip(
                                label: Text(a),
                                selected: selected,
                                onSelected: (_) => setState(() => _angle = a),
                                selectedColor: AppColors.sidebarActive,
                                labelStyle: TextStyle(
                                  color: selected ? AppColors.navy : AppColors.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _capture(fromCamera: true),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Take photo'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _capture(fromCamera: false),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('From gallery'),
                          ),
                          if (_busy) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                          ],
                          if (_status != null) ...[
                            const SizedBox(height: 12),
                            Text(_status!, style: const TextStyle(color: AppColors.success, fontSize: 12)),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Case ${_case?['id'] ?? '—'} · ${_photos.length}/$maxPhotos photos',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _photos.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No photos yet. Capture frontal, left, and right.',
                                      style: TextStyle(color: AppColors.muted),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _photos.length,
                                    separatorBuilder: (_, _) => const Divider(height: 1),
                                    itemBuilder: (context, i) {
                                      final p = _photos[i];
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: AppColors.sidebarActive,
                                          child: Text(
                                            '${i + 1}',
                                            style: const TextStyle(
                                              color: AppColors.navy,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          (p['angle'] as String? ?? 'photo').toUpperCase(),
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        subtitle: Text(
                                          '${p['taken_at'] ?? ''}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                        trailing: const Icon(Icons.lock_outline,
                                            size: 16, color: AppColors.muted),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

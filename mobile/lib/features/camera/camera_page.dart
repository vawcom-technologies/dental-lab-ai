import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/images/orient_image.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/patient_picker.dart';
import '../../core/widgets/ui_kit.dart';
import 'live_camera_capture.dart';

/// Chairside camera — frontal / left / right, max 12 photos per patient.
class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    required this.api,
    required this.patientSession,
    this.active = true,
  });

  final ApiClient api;
  final PatientSession patientSession;
  final bool active;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _patient;
  List<Map<String, dynamic>> _photos = [];
  String _angle = 'frontal';
  bool _loading = true;
  bool _busy = false;
  String _busyLabel = 'Saving photo…';
  String? _status;
  String? _error;

  static const angles = ['frontal', 'left', 'right'];
  static const maxPhotos = 12;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant CameraPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _onPageActivated();
    }
  }

  String _pid(Map<String, dynamic> row) => '${row['id'] ?? ''}';

  String get _patientLabel {
    final p = _patient;
    if (p == null) return '';
    return '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  String _joinMeta(Iterable<String> parts) =>
      parts.where((p) => p.isNotEmpty).join(' · ');

  String _photoName(Map<String, dynamic> photo) {
    final raw = '${photo['filename'] ?? ''}'.trim();
    if (raw.isEmpty) {
      final angle = '${photo['angle'] ?? 'photo'}';
      return angle.isEmpty ? 'Photo' : _titleCase(angle);
    }
    final lower = raw.toLowerCase();
    for (final ext in ['.jpg', '.jpeg', '.png', '.heic', '.webp']) {
      if (lower.endsWith(ext)) return raw.substring(0, raw.length - ext.length);
    }
    return raw;
  }

  String _formatTakenAt(dynamic raw) {
    if (raw == null) return '';
    final s = '$raw'.trim();
    if (s.isEmpty) return '';
    try {
      return DateFormat('MMM d, h:mm a').format(DateTime.parse(s).toLocal());
    } catch (_) {
      return s;
    }
  }

  String _photoAngle(Map<String, dynamic> photo) =>
      '${photo['angle'] ?? ''}'.toUpperCase();

  String _photoSubtitle(Map<String, dynamic> photo) => _joinMeta([
        _formatTakenAt(photo['taken_at']),
        _photoAngle(photo),
      ]);

  String _photoHeader(Map<String, dynamic> photo) => _joinMeta([
        _photoName(photo),
        _photoAngle(photo),
        _formatTakenAt(photo['taken_at']),
      ]);

  Future<void> _reloadPhotos(String pid) async {
    final photos = await widget.api.listPatientPhotos(pid);
    if (!mounted) return;
    setState(() => _photos = photos);
  }

  Future<void> _runBusy(String label, Future<String> Function() work) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
      _error = null;
      _status = null;
    });
    try {
      final status = await work();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (e) {
      AppHaptics.warn();
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.patientSession.ensureLoaded();
      if (!mounted) return;
      setState(() {
        _patients = List<Map<String, dynamic>>.from(
          widget.patientSession.patients,
        );
        _error = null;
      });
      final sel = widget.patientSession.selected;
      if (sel != null) {
        await _selectPatient(sel, publish: false);
      } else if (_patients.isNotEmpty) {
        await _selectPatient(_patients.first);
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onPageActivated() async {
    if (!widget.patientSession.isLoaded) return;
    final list = List<Map<String, dynamic>>.from(
      widget.patientSession.patients,
    );
    final sel = widget.patientSession.selected;
    if (!mounted) return;
    setState(() => _patients = list);
    if (sel == null) {
      if (_patient != null) {
        setState(() {
          _patient = null;
          _photos = [];
        });
      }
      return;
    }
    if (_patient == null || _pid(_patient!) != _pid(sel)) {
      await _selectPatient(sel, publish: false);
    }
  }

  Future<void> _reloadPatients({bool selectFirst = false}) async {
    await widget.patientSession.refresh(keepSelection: !selectFirst);
    if (!mounted) return;
    setState(() {
      _patients = List<Map<String, dynamic>>.from(
        widget.patientSession.patients,
      );
      _error = null;
    });
    if (_patients.isEmpty) {
      setState(() {
        _patient = null;
        _photos = [];
      });
      widget.patientSession.clearSelection();
      return;
    }
    if (selectFirst) {
      await _selectPatient(_patients.first);
      return;
    }
    final sel = widget.patientSession.selected ?? _patients.first;
    await _selectPatient(sel, publish: false);
  }

  void _openNewPatientPage() {
    widget.patientSession.requestNavigateToNewPatient();
  }

  Future<void> _selectPatient(
    Map<String, dynamic> patient, {
    bool publish = true,
  }) async {
    if (publish) widget.patientSession.select(patient);
    setState(() {
      _patient = patient;
      _photos = [];
      _status = null;
      _error = null;
    });
    final pid = _pid(patient);
    if (pid.isEmpty) return;
    try {
      await _reloadPhotos(pid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _capture({required bool fromCamera}) async {
    final patient = _patient;
    final pid = patient == null ? '' : _pid(patient);
    if (pid.isEmpty) return;
    if (_photos.length >= maxPhotos) {
      AppHaptics.warn();
      setState(() => _error = 'Max $maxPhotos photos per patient');
      return;
    }

    Uint8List? bytes;
    String filename = _titleCase(_angle);

    if (fromCamera) {
      bytes = await captureWithLiveCamera(
        context,
        hint: 'Align $_angle guide for $_patientLabel — hold preview for upper/lower',
        angle: _angle,
      );
      if (bytes == null) return;
    } else {
      AppHaptics.medium();
      final xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (xfile == null) return;
      bytes = bakeExifOrientation(Uint8List.fromList(await xfile.readAsBytes()));
      if (xfile.name.isNotEmpty) filename = xfile.name;
    }

    await _runBusy('Saving photo…', () async {
      await widget.api.uploadPatientPhoto(
        patientId: pid,
        angle: _angle,
        bytes: bytes!,
        filename: filename,
      );
      AppHaptics.success();
      await _reloadPhotos(pid);
      return 'Saved $_angle photo for $_patientLabel';
    });
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    final patient = _patient;
    final pid = patient == null ? '' : _pid(patient);
    final photoId = '${photo['id'] ?? ''}';
    if (pid.isEmpty || photoId.isEmpty) return;

    final angle = '${photo['angle'] ?? 'photo'}'.toUpperCase();
    final confirmed = await AppDialogs.confirm(
      context,
      title: 'Delete photo?',
      message: 'Remove this $angle photo from $_patientLabel\'s record.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;

    await _runBusy('Deleting photo…', () async {
      await widget.api.deletePatientPhoto(patientId: pid, photoId: photoId);
      await _reloadPhotos(pid);
      return 'Deleted $angle photo';
    });
  }

  Future<void> _renamePhoto(Map<String, dynamic> photo) async {
    final patient = _patient;
    final pid = patient == null ? '' : _pid(patient);
    final photoId = '${photo['id'] ?? ''}';
    if (pid.isEmpty || photoId.isEmpty) return;

    final name = await AppDialogs.prompt(
      context,
      title: 'Rename photo',
      initial: _photoName(photo),
      placeholder: 'e.g. Upper smile',
      confirmLabel: 'Save',
    );
    if (!mounted) return;
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == _photoName(photo)) return;

    await _runBusy('Renaming photo…', () async {
      await widget.api.renamePatientPhoto(
        patientId: pid,
        photoId: photoId,
        filename: trimmed,
      );
      AppHaptics.success();
      await _reloadPhotos(pid);
      return 'Renamed to $trimmed';
    });
  }

  Future<void> _copyPhotoToShade(Map<String, dynamic> photo) async {
    final photoId = '${photo['id'] ?? ''}';
    if (photoId.isEmpty) return;
    final label = _photoName(photo);
    await _runBusy('Copying to Shade Detection…', () async {
      final row = await widget.api.copyToShadeDetection(photoId);
      final shadeId = '${row['id'] ?? ''}'.trim();
      if (shadeId.isNotEmpty) {
        widget.patientSession.requestShadeHandoff(shadeId);
      }
      return 'Copied “$label” to Shade Detection — mapping teeth…';
    });
  }

  Future<void> _copyPhotoToSmile(Map<String, dynamic> photo) async {
    final photoId = '${photo['id'] ?? ''}';
    if (photoId.isEmpty) return;
    final label = _photoName(photo);
    await _runBusy('Copying to Smile Preview…', () async {
      await widget.api.copyToSmilePreview(photoId);
      return 'Copied “$label” to Smile Preview';
    });
  }

  void _onPhotoMenuSelected(_PhotoMenuAction action, Map<String, dynamic> photo) {
    switch (action) {
      case _PhotoMenuAction.rename:
        _renamePhoto(photo);
      case _PhotoMenuAction.copyToShade:
        _copyPhotoToShade(photo);
      case _PhotoMenuAction.copyToSmile:
        _copyPhotoToSmile(photo);
      case _PhotoMenuAction.delete:
        _deletePhoto(photo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCapture = !_busy && _patient != null && _photos.length < maxPhotos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            icon: Icons.photo_camera_outlined,
            title: AppLocalizations.of(context).cameraTitle,
            subtitle:
                'Frontal / left / right · up to 12 photos per patient · saved to patient record',
            actions: [
              PatientPickerButton(
                patients: _patients,
                selected: _patient,
                enabled: !_busy,
                onSelect: _selectPatient,
                onAdd: _openNewPatientPage,
                onRefresh: () async {
                  setState(() => _busy = true);
                  try {
                    await _reloadPatients();
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
                emptyHint: 'No patients yet — add one to capture photos.',
              ),
              FilledButton.icon(
                onPressed:
                    canCapture ? () => _capture(fromCamera: true) : null,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Take photo'),
              ),
              OutlinedButton.icon(
                onPressed:
                    canCapture ? () => _capture(fromCamera: false) : null,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Gallery'),
              ),
            ],
          ),
          if (_status != null || _error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error ?? _status!,
              style: TextStyle(
                color: _error != null ? AppColors.danger : AppColors.success,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_loading)
            const Expanded(
              child: ToothPageLoader(message: 'Preparing camera…'),
            )
          else if (_patients.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Add a patient from the header to start capturing photos.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            )
          else ...[
            SectionCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Angle',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: angles.map((a) {
                            final selected = _angle == a;
                            return ChoiceChip(
                              label: Text(_titleCase(a)),
                              selected: selected,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onSelected: (_) => setState(() => _angle = a),
                              selectedColor: AppColors.sidebarActive,
                              labelStyle: TextStyle(
                                color: selected
                                    ? AppColors.navy
                                    : AppColors.muted,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: ToothLoadingIndicator(
                        size: 24,
                        loadingText: _busyLabel,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SectionCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _patient == null
                          ? 'Photos'
                          : '$_patientLabel · ${_photos.length}/$maxPhotos photos',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
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
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final p = _photos[i];
                                final url = '${p['file_url'] ?? ''}';
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  onTap: url.isEmpty
                                      ? null
                                      : () => _viewPhoto(p),
                                  leading: _PhotoThumb(url: url, index: i),
                                  title: Text(
                                    _photoName(p),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _photoSubtitle(p),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  trailing: PopupMenuButton<_PhotoMenuAction>(
                                    tooltip: 'Photo options',
                                    enabled: !_busy,
                                    icon: const Icon(
                                      Icons.more_vert,
                                      color: AppColors.muted,
                                    ),
                                    onSelected: (action) =>
                                        _onPhotoMenuSelected(action, p),
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: _PhotoMenuAction.rename,
                                        child: ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.edit_outlined),
                                          title: Text('Rename'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: _PhotoMenuAction.copyToShade,
                                        child: ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(
                                            Icons.palette_outlined,
                                          ),
                                          title: Text('Copy to Shade Detection'),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: _PhotoMenuAction.copyToSmile,
                                        child: ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(
                                            Icons.sentiment_satisfied_alt_outlined,
                                          ),
                                          title: Text('Copy to Smile Preview'),
                                        ),
                                      ),
                                      PopupMenuDivider(),
                                      PopupMenuItem(
                                        value: _PhotoMenuAction.delete,
                                        child: ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(
                                            Icons.delete_outline,
                                            color: AppColors.danger,
                                          ),
                                          title: Text(
                                            'Delete',
                                            style: TextStyle(
                                              color: AppColors.danger,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _viewPhoto(Map<String, dynamic> photo) {
    final url = '${photo['file_url'] ?? ''}';
    if (url.isEmpty) return;
    final header = _photoHeader(photo);
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: Colors.black,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          header,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Rename photo',
                        onPressed: _busy
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                // Wait for the viewer route to finish disposing
                                // before opening the rename dialog.
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  _renamePhoto(photo);
                                });
                              },
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Colors.white70,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete photo',
                        onPressed: _busy
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  _deletePhoto(photo);
                                });
                              },
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.white70,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Could not load photo',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _PhotoMenuAction {
  rename,
  copyToShade,
  copyToSmile,
  delete,
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.url, required this.index});

  final String url;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return CircleAvatar(
        backgroundColor: AppColors.sidebarActive,
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => ColoredBox(
            color: AppColors.sidebarActive,
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
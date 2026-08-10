import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'live_camera_capture.dart';

/// Chairside camera — frontal / left / right, max 12 photos per patient.
class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    required this.api,
  });

  final ApiClient api;

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
      bytes = Uint8List.fromList(await xfile.readAsBytes());
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete photo?'),
        content: Text('Remove this $angle photo from $_patientLabel\'s record.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

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

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenamePhotoDialog(initialName: _photoName(photo)),
    );
    if (!mounted) return;
    if (name == null || name.isEmpty || name == _photoName(photo)) return;

    await _runBusy('Renaming photo…', () async {
      await widget.api.renamePatientPhoto(
        patientId: pid,
        photoId: photoId,
        filename: name,
      );
      AppHaptics.success();
      await _reloadPhotos(pid);
      return 'Renamed to $name';
    });
  }

  @override
  Widget build(BuildContext context) {
    final canCapture = !_busy && _patient != null && _photos.length < maxPhotos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppLocalizations.of(context).cameraTitle,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Frontal / left / right · up to 12 photos per patient · saved to patient record',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Expanded(
              child: ToothPageLoader(message: 'Preparing camera…'),
            )
          else if (_patients.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Add a patient first, then capture photos.',
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
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Patient',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue:
                                  _patient == null ? null : _pid(_patient!),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              items: _patients
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: _pid(p),
                                      child: Text(
                                        '${p['first_name']} ${p['last_name']}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (id) {
                                if (id == null) return;
                                final p = _patients
                                    .firstWhere((e) => _pid(e) == id);
                                _selectPatient(p);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Angle',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
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
                                  onSelected: (_) =>
                                      setState(() => _angle = a),
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: canCapture
                                    ? () => _capture(fromCamera: true)
                                    : null,
                                icon: const Icon(
                                  Icons.photo_camera_outlined,
                                  size: 18,
                                ),
                                label: const Text('Take photo'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: canCapture
                                    ? () => _capture(fromCamera: false)
                                    : null,
                                icon: const Icon(
                                  Icons.photo_library_outlined,
                                  size: 18,
                                ),
                                label: const Text('Gallery'),
                              ),
                            ),
                          ],
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
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _status!,
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
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
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Rename photo',
                                        onPressed: _busy
                                            ? null
                                            : () => _renamePhoto(p),
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete photo',
                                        onPressed: _busy
                                            ? null
                                            : () => _deletePhoto(p),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                          color: AppColors.danger,
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
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
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
    );
  }
}

class _RenamePhotoDialog extends StatefulWidget {
  const _RenamePhotoDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenamePhotoDialog> createState() => _RenamePhotoDialogState();
}

class _RenamePhotoDialogState extends State<_RenamePhotoDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename photo'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. Upper smile',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
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
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/images/orient_image.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/patient_picker.dart';
import '../../core/widgets/touchable.dart';
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
  String? _selectedPhotoId;
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

  String _clinicalAngleLabel(String angle) {
    switch (angle.trim().toLowerCase()) {
      case 'frontal':
        return 'Frontal smile';
      case 'left':
        return 'Left profile';
      case 'right':
        return 'Right profile';
      case 'other':
        return 'Clinical photo';
      default:
        return angle.isEmpty ? 'Clinical photo' : _titleCase(angle);
    }
  }

  String _clinicalPhotoName({required String angle, String extension = '.jpg'}) {
    final patient = _patientLabel.trim();
    final view = _clinicalAngleLabel(angle);
    final base = patient.isEmpty ? view : '$patient · $view';
    final ext = extension.toLowerCase();
    final safeExt = ['.jpg', '.jpeg', '.png', '.heic', '.webp'].contains(ext)
        ? ext
        : '.jpg';
    return '$base$safeExt';
  }

  bool _isMachineFilename(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return true;
    final lower = name.toLowerCase();
    if (lower.startsWith('image_picker')) return true;
    if (lower.startsWith('img_') || lower.startsWith('dsc_')) return true;
    if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-', caseSensitive: false)
        .hasMatch(name)) {
      return true;
    }
    if (RegExp(r'^[a-f0-9]{16,}', caseSensitive: false).hasMatch(name)) {
      return true;
    }
    return false;
  }

  String _photoName(Map<String, dynamic> photo) {
    final raw = '${photo['filename'] ?? ''}'.trim();
    final angle = '${photo['angle'] ?? 'photo'}';
    if (raw.isEmpty || _isMachineFilename(raw)) {
      return _clinicalAngleLabel(angle);
    }
    var display = raw;
    final lower = display.toLowerCase();
    for (final ext in ['.jpg', '.jpeg', '.png', '.heic', '.webp']) {
      if (lower.endsWith(ext)) {
        display = display.substring(0, display.length - ext.length);
        break;
      }
    }
    return display;
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

  String _photoSubtitle(Map<String, dynamic> photo) =>
      _formatTakenAt(photo['taken_at']);

  String _photoAngleKey(Map<String, dynamic> photo) =>
      '${photo['angle'] ?? ''}'.trim().toLowerCase();

  List<Map<String, dynamic>> get _visiblePhotos => _photos
      .where((photo) => _photoAngleKey(photo) == _angle)
      .toList();

  int _countForAngle(String angle) =>
      _photos.where((photo) => _photoAngleKey(photo) == angle).length;

  Map<String, dynamic>? get _selectedPhoto {
    final id = _selectedPhotoId;
    if (id == null) return null;
    for (final photo in _visiblePhotos) {
      if ('${photo['id'] ?? ''}' == id) return photo;
    }
    return null;
  }

  void _syncPhotoSelection() {
    final visible = _visiblePhotos;
    if (visible.isEmpty) {
      _selectedPhotoId = null;
      return;
    }
    if (_selectedPhotoId != null &&
        visible.any((p) => '${p['id'] ?? ''}' == _selectedPhotoId)) {
      return;
    }
    _selectedPhotoId = '${visible.first['id'] ?? ''}';
  }

  void _setAngle(String angle) {
    if (angle == _angle) return;
    AppHaptics.selection();
    setState(() {
      _angle = angle;
      _syncPhotoSelection();
    });
  }

  void _selectPhoto(Map<String, dynamic> photo) {
    final id = '${photo['id'] ?? ''}';
    if (id.isEmpty || id == _selectedPhotoId) return;
    AppHaptics.selection();
    setState(() => _selectedPhotoId = id);
  }

  Future<void> _reloadPhotos(String pid, {bool selectNewest = false}) async {
    final photos = await widget.api.listPatientPhotos(pid);
    if (!mounted) return;
    setState(() {
      _photos = photos;
      if (selectNewest) _selectedPhotoId = null;
      _syncPhotoSelection();
    });
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
          _selectedPhotoId = null;
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
        _selectedPhotoId = null;
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
      _selectedPhotoId = null;
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
    var filename = _clinicalPhotoName(angle: _angle);

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
      final ext = xfile.name.contains('.')
          ? '.${xfile.name.split('.').last}'
          : '.jpg';
      filename = _clinicalPhotoName(angle: _angle, extension: ext);
    }

    await _runBusy('Saving photo…', () async {
      await widget.api.uploadPatientPhoto(
        patientId: pid,
        angle: _angle,
        bytes: bytes!,
        filename: filename,
      );
      AppHaptics.success();
      await _reloadPhotos(pid, selectNewest: true);
      return 'Saved $_angle photo for $_patientLabel';
    });
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    final patient = _patient;
    final pid = patient == null ? '' : _pid(patient);
    final photoId = '${photo['id'] ?? ''}';
    if (pid.isEmpty || photoId.isEmpty) return;

    final angle = _clinicalAngleLabel('${photo['angle'] ?? ''}');
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

  Future<void> _openPhotoWithShade(Map<String, dynamic> photo) async {
    final photoId = '${photo['id'] ?? ''}';
    if (photoId.isEmpty) return;
    final label = _photoName(photo);
    await _runBusy('Opening with Shade Detection…', () async {
      final row = await widget.api.copyToShadeDetection(photoId);
      final shadeId = '${row['id'] ?? ''}'.trim();
      if (shadeId.isNotEmpty) {
        widget.patientSession.requestShadeHandoff(shadeId);
      }
      return 'Opening “$label” with Shade Detection…';
    });
  }

  Future<void> _openPhotoWithSmile(Map<String, dynamic> photo) async {
    final photoId = '${photo['id'] ?? ''}';
    if (photoId.isEmpty) return;
    final label = _photoName(photo);
    await _runBusy('Opening with Smile Preview…', () async {
      final row = await widget.api.copyToSmilePreview(photoId);
      final smileId = '${row['id'] ?? ''}'.trim();
      if (smileId.isNotEmpty) {
        widget.patientSession.requestSmileHandoff(smileId);
      }
      return 'Opening “$label” with Smile Preview…';
    });
  }

  void _onPhotoMenuSelected(_PhotoMenuAction action, Map<String, dynamic> photo) {
    switch (action) {
      case _PhotoMenuAction.rename:
        _renamePhoto(photo);
      case _PhotoMenuAction.openWithShade:
        _openPhotoWithShade(photo);
      case _PhotoMenuAction.openWithSmile:
        _openPhotoWithSmile(photo);
      case _PhotoMenuAction.delete:
        _deletePhoto(photo);
    }
  }


  void _afterViewer(BuildContext dialogContext, VoidCallback action) {
    Navigator.of(dialogContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      action();
    });
  }

  void _viewPhoto(Map<String, dynamic> photo) {
    final url = widget.api.resolveMediaUrl('${photo['file_url'] ?? ''}');
    if (url.isEmpty) return;
    final name = _photoName(photo);
    final taken = _photoSubtitle(photo);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close photo',
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, _) {
        return Material(
          color: Colors.black,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (taken.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                taken,
                                style: AppFonts.style(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      AppButtons.glassIcon(
                        tooltip: 'Rename',
                        onPressed: _busy
                            ? null
                            : () => _afterViewer(ctx, () => _renamePhoto(photo)),
                        icon: Icons.edit_outlined,
                      ),
                      const SizedBox(width: 8),
                      AppButtons.glassIcon(
                        tooltip: 'Delete',
                        onPressed: _busy
                            ? null
                            : () => _afterViewer(ctx, () => _deletePhoto(photo)),
                        icon: Icons.delete_outline,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      AppButtons.glassIcon(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icons.close,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _FilledNetworkPhoto(
                      url: url,
                      headers: widget.api.mediaHeaders,
                      interactive: true,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      AppButtons.glass(
                        onPressed: _busy
                            ? null
                            : () => _afterViewer(
                                  ctx,
                                  () => _openPhotoWithShade(photo),
                                ),
                        label: 'Open with Shade Detection',
                        icon: Icons.palette_outlined,
                      ),
                      AppButtons.glass(
                        onPressed: _busy
                            ? null
                            : () => _afterViewer(
                                  ctx,
                                  () => _openPhotoWithSmile(photo),
                                ),
                        label: 'Open with Smile Preview',
                        icon: Icons.sentiment_satisfied_alt_outlined,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _angleBar() {
    return GlassSurface(
      borderRadius: BorderRadius.circular(16),
      blur: 16,
      tint: Colors.white.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Angle',
              style: AppFonts.style(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.navy,
              ),
            ),
          ),
          Expanded(
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: _angle,
              backgroundColor: AppColors.inset,
              thumbColor: Colors.white,
              children: {
                for (final a in angles)
                  a: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Text(
                      '${_titleCase(a)} (${_countForAngle(a)})',
                      textAlign: TextAlign.center,
                      style: AppFonts.style(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
              },
              onValueChanged: (value) {
                if (value == null) return;
                _setAngle(value);
              },
            ),
          ),
          if (_busy) ...[
            const SizedBox(width: 10),
            const ToothLoadingIndicator(size: 22, compact: true),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _busyLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.style(
                  fontSize: 13,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _photosWorkspace() {
    if (_patient == null) {
      return _CameraEmpty(
        icon: Icons.person_add_alt_1_outlined,
        title: 'Choose a patient',
        message: 'Select a patient in the header to capture chairside photos.',
      );
    }
    if (_photos.isEmpty) {
      return _CameraEmpty(
        icon: Icons.photo_camera_outlined,
        title: 'No photos yet',
        message:
            'Take a frontal, left, or right photo — it is saved to this patient record.',
        action: AppButtons.primary(
          onPressed: _busy ? null : () => _capture(fromCamera: true),
          label: 'Take photo',
          icon: Icons.photo_camera_outlined,
        ),
      );
    }
    return AdaptiveSplit(
      panelOnRight: true,
      panelFraction: 0.28,
      minPanelWidth: 280,
      maxPanelWidth: 320,
      gap: 16,
      narrowPanelHeight: 360,
      content: _photoGrid(),
      panel: AppSwitcher(
        child: KeyedSubtree(
          key: ValueKey(_selectedPhotoId ?? 'none'),
          child: _photoInspector(),
        ),
      ),
    );
  }

  Widget _photoGrid() {
    final visible = _visiblePhotos;
    final angleLabel = _clinicalAngleLabel(_angle);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$_patientLabel · $angleLabel · ${visible.length} of ${_photos.length}/$maxPhotos',
            style: AppFonts.style(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: visible.isEmpty
                ? _CameraEmpty(
                    icon: Icons.photo_outlined,
                    title: 'No $angleLabel photos',
                    message:
                        'Switch angle or take a ${_titleCase(_angle).toLowerCase()} photo for this patient.',
                    action: AppButtons.primary(
                      onPressed:
                          _busy ? null : () => _capture(fromCamera: true),
                      label: 'Take photo',
                      icon: Icons.photo_camera_outlined,
                    ),
                  )
                : ScrollConfiguration(
                    behavior: const EliteScrollBehavior(),
                    child: GridView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.86,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final photo = visible[i];
                        final id = '${photo['id'] ?? ''}';
                        final url = widget.api.resolveMediaUrl(
                          '${photo['file_url'] ?? ''}',
                        );
                        return _PhotoGridTile(
                          name: _photoName(photo),
                          subtitle: _photoSubtitle(photo),
                          url: url,
                          headers: widget.api.mediaHeaders,
                          selected: id == _selectedPhotoId,
                          enabled: !_busy,
                          onTap: () {
                            if (id == _selectedPhotoId) {
                              _viewPhoto(photo);
                              return;
                            }
                            _selectPhoto(photo);
                          },
                          onMenu: (action) =>
                              _onPhotoMenuSelected(action, photo),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _photoInspector() {
    final photo = _selectedPhoto;
    if (photo == null) {
      return SectionCard(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _clinicalAngleLabel(_angle),
              style: AppFonts.style(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: const ColoredBox(
                color: Color(0xFF111827),
                child: SizedBox(
                  height: 168,
                  child: Center(
                    child: Text(
                      'Nothing selected',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Take a ${_titleCase(_angle).toLowerCase()} photo or pick one from the grid.',
              style: AppFonts.style(
                fontSize: 13,
                height: 1.35,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      );
    }
    final url = widget.api.resolveMediaUrl('${photo['file_url'] ?? ''}');
    final name = _photoName(photo);
    final taken = _photoSubtitle(photo);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: -0.2,
                        color: AppColors.navy,
                      ),
                    ),
                    if (taken.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        taken,
                        style: AppFonts.style(
                          fontSize: 14,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AppButtons.icon(
                tooltip: 'View full screen',
                onPressed: url.isEmpty ? null : () => _viewPhoto(photo),
                icon: Icons.open_in_full_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Touchable(
            onTap: url.isEmpty ? null : () => _viewPhoto(photo),
            scale: 0.99,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: const Color(0xFF111827),
                child: SizedBox(
                  height: 168,
                  child: url.isEmpty
                      ? const Center(
                          child: Text(
                            'Photo unavailable',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : _FilledNetworkPhoto(
                          url: url,
                          headers: widget.api.mediaHeaders,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppButtons.primary(
            onPressed: _busy ? null : () => _openPhotoWithSmile(photo),
            label: 'Smile Preview',
            icon: Icons.sentiment_satisfied_alt_outlined,
          ),
          const SizedBox(height: 8),
          AppButtons.secondary(
            onPressed: _busy ? null : () => _openPhotoWithShade(photo),
            label: 'Shade Detection',
            icon: Icons.palette_outlined,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              AppButtons.ghost(
                onPressed: _busy ? null : () => _renamePhoto(photo),
                label: 'Rename',
                icon: Icons.edit_outlined,
                compact: true,
              ),
              const Spacer(),
              AppButtons.danger(
                onPressed: _busy ? null : () => _deletePhoto(photo),
                label: 'Delete',
                icon: Icons.delete_outline,
                compact: true,
                soft: true,
              ),
            ],
          ),
        ],
      ),
    );
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
                'Frontal, left, and right photos · up to 12 per patient',
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
              AppButtons.primary(
                onPressed: canCapture ? () => _capture(fromCamera: true) : null,
                label: 'Take photo',
                icon: Icons.photo_camera_outlined,
              ),
              AppButtons.secondary(
                onPressed:
                    canCapture ? () => _capture(fromCamera: false) : null,
                label: 'Gallery',
                icon: Icons.photo_library_outlined,
              ),
            ],
          ),
          if (_status != null || _error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error ?? _status!,
              style: AppFonts.style(
                color: _error != null ? AppColors.danger : AppColors.success,
                fontSize: 14,
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
              child: _CameraEmpty(
                icon: Icons.person_add_alt_1_outlined,
                title: 'Add a patient',
                message:
                    'Add a patient from the header to start capturing photos.',
              ),
            )
          else ...[
            _angleBar(),
            const SizedBox(height: 14),
            Expanded(
              child: AppSwitcher(
                child: KeyedSubtree(
                  key: ValueKey(_angle),
                  child: _photosWorkspace(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _PhotoMenuAction {
  rename,
  openWithShade,
  openWithSmile,
  delete,
}

class _CameraEmpty extends StatelessWidget {
  const _CameraEmpty({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(24),
          blur: 18,
          tint: Colors.white.withValues(alpha: 0.55),
          padding: const EdgeInsets.fromLTRB(36, 40, 36, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NeoIconBadge(
                icon: icon,
                size: 64,
                iconSize: 30,
                color: AppColors.dentalBlue,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppFonts.style(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppFonts.style(
                  color: AppColors.muted,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 22),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilledNetworkPhoto extends StatelessWidget {
  const _FilledNetworkPhoto({
    required this.url,
    required this.headers,
    this.interactive = false,
  });

  final String url;
  final Map<String, String> headers;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final image = Image.network(
          url,
          headers: headers,
          fit: BoxFit.contain,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          alignment: Alignment.center,
          errorBuilder: (_, _, _) => const Center(
            child: Text(
              'Could not load photo',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        );
        if (!interactive) return image;
        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: image,
          ),
        );
      },
    );
  }
}

class _PhotoGridTile extends StatelessWidget {
  const _PhotoGridTile({
    required this.name,
    required this.subtitle,
    required this.url,
    required this.headers,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onMenu,
  });

  final String name;
  final String subtitle;
  final String url;
  final Map<String, String> headers;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<_PhotoMenuAction> onMenu;

  @override
  Widget build(BuildContext context) {
    return Touchable(
      enabled: enabled,
      selectionHaptic: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.dentalBlue : Colors.transparent,
            width: 3,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.dentalBlue.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: ColoredBox(
            color: AppColors.sidebarActive,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url.isEmpty)
                  const Center(
                    child: Icon(
                      Icons.photo_outlined,
                      color: AppColors.muted,
                      size: 28,
                    ),
                  )
                else
                  Image.network(
                    url,
                    headers: headers,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0),
                          Colors.black.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 18, 4, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          PopupMenuButton<_PhotoMenuAction>(
                            tooltip: 'Photo options',
                            enabled: enabled,
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.more_horiz,
                              color: Colors.white,
                              size: 20,
                            ),
                            onSelected: onMenu,
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: _PhotoMenuAction.rename,
                                child: Text('Rename'),
                              ),
                              PopupMenuItem(
                                value: _PhotoMenuAction.openWithShade,
                                child: Text('Open with Shade Detection'),
                              ),
                              PopupMenuItem(
                                value: _PhotoMenuAction.openWithSmile,
                                child: Text('Open with Smile Preview'),
                              ),
                              PopupMenuDivider(),
                              PopupMenuItem(
                                value: _PhotoMenuAction.delete,
                                child: Text(
                                  'Delete',
                                  style: TextStyle(color: AppColors.danger),
                                ),
                              ),
                            ],
                          ),
                        ],
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

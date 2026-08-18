import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/patient_picker.dart';
import '../../core/widgets/ui_kit.dart';

/// Single entry in the smile-shape library.
class ShapeLibraryItem {
  const ShapeLibraryItem({
    required this.id,
    required this.shapeId,
    required this.label,
    required this.asset,
  });

  final int id;
  final String shapeId;
  final String label;
  final String asset;
}

/// Tooth-shape library (individual images). Legacy client grid is archived.
class ShapeLibrary {
  ShapeLibrary._();

  /// Original Elite Dent 5×4 photo grid — archived; restore via [legacyGridAsset].
  static const legacyGridAsset =
      'assets/clinical/archive/tooth-preview-grid.legacy.png';
  static const legacyCols = 5;
  static const legacyRows = 4;

  static const items = <ShapeLibraryItem>[
    ShapeLibraryItem(
      id: 1,
      shapeId: 'shape_1',
      label: 'Soft oval',
      asset: 'assets/clinical/shapes/shape_01_soft_oval.png',
    ),
    ShapeLibraryItem(
      id: 2,
      shapeId: 'shape_2',
      label: 'Classic oval',
      asset: 'assets/clinical/shapes/shape_02_classic_oval.png',
    ),
    ShapeLibraryItem(
      id: 3,
      shapeId: 'shape_3',
      label: 'Rounded',
      asset: 'assets/clinical/shapes/shape_03_rounded.png',
    ),
    ShapeLibraryItem(
      id: 4,
      shapeId: 'shape_4',
      label: 'Natural oval',
      asset: 'assets/clinical/shapes/shape_04_natural_oval.png',
    ),
    ShapeLibraryItem(
      id: 5,
      shapeId: 'shape_5',
      label: 'Youthful',
      asset: 'assets/clinical/shapes/shape_05_youthful.png',
    ),
    ShapeLibraryItem(
      id: 6,
      shapeId: 'shape_6',
      label: 'Soft square',
      asset: 'assets/clinical/shapes/shape_06_soft_square.png',
    ),
    ShapeLibraryItem(
      id: 7,
      shapeId: 'shape_7',
      label: 'Balanced',
      asset: 'assets/clinical/shapes/shape_07_balanced.png',
    ),
    ShapeLibraryItem(
      id: 8,
      shapeId: 'shape_8',
      label: 'Soft rect',
      asset: 'assets/clinical/shapes/shape_08_soft_rect.png',
    ),
    ShapeLibraryItem(
      id: 9,
      shapeId: 'shape_9',
      label: 'Hollywood',
      asset: 'assets/clinical/shapes/shape_09_hollywood.png',
    ),
    ShapeLibraryItem(
      id: 10,
      shapeId: 'shape_10',
      label: 'Strong square',
      asset: 'assets/clinical/shapes/shape_10_strong_square.png',
    ),
    ShapeLibraryItem(
      id: 11,
      shapeId: 'shape_11',
      label: 'Tapered',
      asset: 'assets/clinical/shapes/shape_11_tapered.png',
    ),
    ShapeLibraryItem(
      id: 12,
      shapeId: 'shape_12',
      label: 'Canine lift',
      asset: 'assets/clinical/shapes/shape_12_canine_lift.png',
    ),
  ];

  static int get total => items.length;

  static ShapeLibraryItem at(int index) =>
      items[index.clamp(0, items.length - 1)];

  static int indexOfShapeId(String? shapeId) {
    if (shapeId == null || shapeId.isEmpty) return 0;
    final match = RegExp(r'shape_(\d+)').firstMatch(shapeId);
    if (match == null) return 0;
    final id = int.tryParse(match.group(1)!) ?? 1;
    final idx = items.indexWhere((e) => e.id == id);
    return idx < 0 ? 0 : idx;
  }
}

/// Tooth-shape try-on: overlay a library smile on the patient photo and save.
class ShapeOverlayPage extends StatefulWidget {
  const ShapeOverlayPage({
    super.key,
    required this.api,
    required this.patientSession,
    this.active = true,
  });

  final ApiClient api;
  final PatientSession patientSession;
  final bool active;

  static const cellW = 260.0;
  static const cellH = 174.0;

  @override
  State<ShapeOverlayPage> createState() => _ShapeOverlayPageState();
}

class _ShapeOverlayPageState extends State<ShapeOverlayPage> {
  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _case;
  Uint8List? _photoBytes;

  int _shapeIndex = 0;
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _width = 1.0; // ponytail: session-only; persist when API gets scale_x/y
  double _height = 1.0;
  double _rotation = 0;
  double _opacity = 0.88;
  bool _showOverlay = true;
  bool _comparing = false;
  bool _showGuides = true;
  bool _fullscreen = false;
  bool _placementOpen = true;

  double _baseScale = 1.0;
  double _baseRotation = 0;
  bool _centeredOnce = false;
  Size? _lastCanvas;
  Size? _imageSize; // photo px — remap placement when stage size changes

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _status;
  String? _error;
  List<Map<String, dynamic>> _smileItems = [];

  ShapeLibraryItem get _selected => ShapeLibrary.at(_shapeIndex);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant ShapeOverlayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _onPageActivated();
    }
  }

  Future<void> _bootstrap() async {
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
      await _consumeSmileHandoff();
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
          _case = null;
          _smileItems = [];
        });
      }
      return;
    }
    if (_patient == null || _pid(_patient!) != _pid(sel)) {
      await _selectPatient(sel, publish: false);
    }
    await _consumeSmileHandoff();
  }

  String _pid(Map<String, dynamic> row) => '${row['id'] ?? ''}';

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
        _case = null;
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

  Future<void> _selectPatient(
    Map<String, dynamic> patient, {
    bool publish = true,
  }) async {
    if (publish) widget.patientSession.select(patient);
    setState(() {
      _patient = patient;
      _status = null;
      _error = null;
      _dirty = false;
      _smileItems = [];
    });
    try {
      final patientId = _pid(patient);
      final cases = await widget.api.listCases();
      final mine = cases
          .where((c) => '${c['patient_id']}' == patientId)
          .toList();
      Map<String, dynamic>? caseRow = mine.isEmpty ? null : mine.first;
      if (caseRow == null) {
        final asInt = int.tryParse(patientId);
        if (asInt != null) {
          caseRow = await widget.api.createCase(asInt);
        }
      }
      if (!mounted) return;
      setState(() => _case = caseRow);
      final caseId = caseRow?['id'];
      if (caseId is num) {
        await _restoreSaved(caseId.toInt());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _case = null);
    }
    await _loadSmilePreviews();
  }

  Future<void> _loadSmilePreviews() async {
    final patient = _patient;
    if (patient == null) {
      if (mounted) setState(() => _smileItems = []);
      return;
    }
    final pid = _pid(patient);
    if (pid.isEmpty) return;
    try {
      final rows = await widget.api.listSmilePreviews(pid);
      if (!mounted) return;
      setState(() => _smileItems = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Camera handoff: load the photo onto the overlay canvas.
  Future<void> _consumeSmileHandoff() async {
    final id = widget.patientSession.takePendingSmilePreviewId();
    if (id == null || id.isEmpty || _patient == null) return;

    await _loadSmilePreviews();
    if (!mounted) return;

    Map<String, dynamic>? item;
    for (final row in _smileItems) {
      if ('${row['id'] ?? ''}' == id) {
        item = row;
        break;
      }
    }
    if (item == null) {
      setState(
        () => _error =
            'Photo is not in Smile Preview yet. Open Smile Preview again.',
      );
      return;
    }

    final url = '${item['file_url'] ?? ''}'.trim();
    if (url.isEmpty) {
      setState(() => _error = 'This photo has no file to open.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes = await widget.api.downloadMediaBytes(url);
      if (!mounted) return;
      await _applyPhotoBytes(
        bytes,
        status: 'Opened from Camera — select a shape from the library.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyPhotoBytes(
    Uint8List data, {
    String? status,
  }) async {
    setState(() {
      _photoBytes = data;
      _imageSize = null;
      _scale = 1.05;
      _width = 1.0;
      _height = 1.0;
      _rotation = 0;
      _opacity = 0.88;
      _showOverlay = true;
      _centeredOnce = false;
      _dirty = true;
      _status = status ?? 'Photo loaded — select a shape from the library.';
    });
    await _readImageSize(data);
  }

  void _openNewPatientPage() {
    widget.patientSession.requestNavigateToNewPatient();
  }

  Future<void> _restoreSaved(int caseId) async {
    try {
      final saved = await widget.api.latestShape(caseId);
      if (saved == null || !mounted) return;
      final idx = ShapeLibrary.indexOfShapeId(saved['shape_id']?.toString());
      setState(() {
        _shapeIndex = idx;
        _offset = Offset(
          (saved['position_x'] as num?)?.toDouble() ?? _offset.dx,
          (saved['position_y'] as num?)?.toDouble() ?? _offset.dy,
        );
        _rotation = (saved['rotation'] as num?)?.toDouble() ?? 0;
        _scale = (saved['scale'] as num?)?.toDouble() ?? 1.0;
        _status = 'Restored ${_selected.label}';
        _centeredOnce = true;
        _dirty = false;
      });
    } catch (_) {}
  }

  Future<void> _readImageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      if (!mounted) return;
      setState(() {
        _imageSize = Size(img.width.toDouble(), img.height.toDouble());
      });
      img.dispose();
    } catch (_) {
      if (mounted) setState(() => _imageSize = null);
    }
  }

  /// BoxFit.contain destination for the patient photo in [canvas].
  Rect _photoRect(Size canvas) {
    final img = _imageSize;
    if (img == null || img.width <= 0 || img.height <= 0) {
      return Offset.zero & canvas;
    }
    final s = math.min(canvas.width / img.width, canvas.height / img.height);
    final w = img.width * s;
    final h = img.height * s;
    return Rect.fromLTWH(
      (canvas.width - w) / 2,
      (canvas.height - h) / 2,
      w,
      h,
    );
  }

  void _remapPlacement(Size from, Size to) {
    final a = _photoRect(from);
    final b = _photoRect(to);
    if (a.width < 1 || a.height < 1) return;
    final sx = b.width / a.width;
    _offset = Offset(
      b.left + (_offset.dx - a.left) * sx,
      b.top + (_offset.dy - a.top) * sx,
    );
    _scale = (_scale * sx).clamp(0.15, 8.0);
  }

  Future<void> _pickPhoto() async {
    if (_patient == null) {
      setState(() => _error = 'Select a patient first.');
      return;
    }
    setState(() => _error = null);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.first.bytes;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _error = 'Could not read image bytes.');
        return;
      }

      if (!mounted) return;
      final confirmed = await confirmPatientMediaUpload(context);
      if (!confirmed || !mounted) return;

      final data = Uint8List.fromList(bytes);
      final name = picked.files.first.name.isNotEmpty
          ? picked.files.first.name
          : 'smile.jpg';
      final pid = _pid(_patient!);

      setState(() => _saving = true);
      final uploaded = await runWithToothLoadingDialog(
        context,
        message: 'Uploading…',
        action: () => widget.api.uploadSmilePreview(
          patientId: pid,
          bytes: data,
          filename: name,
        ),
      );
      if (!mounted) return;

      setState(() {
        _smileItems = [uploaded, ..._smileItems];
        _saving = false;
      });
      await _applyPhotoBytes(
        data,
        status: 'Smile preview saved — select a shape from the library.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  void _selectShape(int i) {
    if (i < 0 || i >= ShapeLibrary.total) return;
    setState(() {
      _shapeIndex = i;
      _status = 'Selected ${ShapeLibrary.at(i).label}';
      _dirty = true;
      _showOverlay = true;
    });
  }

  void _centerIn(Size canvas) {
    setState(() {
      final w = ShapeOverlayPage.cellW * _scale * _width;
      final h = ShapeOverlayPage.cellH * _scale * _height;
      final photo = _photoRect(canvas);
      _offset = Offset(
        photo.left + (photo.width - w) / 2,
        photo.top + (photo.height - h) / 2,
      );
      _centeredOnce = true;
    });
  }

  void _resetTransform(Size canvas) {
    setState(() {
      _scale = 1.05;
      _width = 1.0;
      _height = 1.0;
      _rotation = 0;
      _opacity = 0.88;
      final w = ShapeOverlayPage.cellW * _scale * _width;
      final h = ShapeOverlayPage.cellH * _scale * _height;
      final photo = _photoRect(canvas);
      _offset = Offset(
        photo.left + (photo.width - w) / 2,
        photo.top + (photo.height - h) / 2,
      );
      _dirty = true;
    });
  }

  void _nudge(double dx, double dy) {
    setState(() {
      _offset += Offset(dx, dy);
      _dirty = true;
    });
  }

  Offset _localDragDelta(Offset screenDelta) {
    final rad = _rotation * math.pi / 180;
    final c = math.cos(rad);
    final s = math.sin(rad);
    return Offset(
      screenDelta.dx * c + screenDelta.dy * s,
      -screenDelta.dx * s + screenDelta.dy * c,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_case == null) {
      setState(() => _error = 'Select a patient first');
      return;
    }
    if (_photoBytes == null) {
      setState(() => _error = 'Load a patient smile photo first');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.saveShape(
        caseId: _case!['id'] as int,
        shapeId: _selected.shapeId,
        x: _offset.dx,
        y: _offset.dy,
        rotation: _rotation,
        scale: _scale,
      );
      await widget.api.markCaseInProgressIfPending(
        _case!['id'] as int,
        _case!['status']?.toString(),
      );
      _case = {..._case!, 'status': 'in_progress'};
      setState(() {
        _dirty = false;
      });
      if (mounted) {
        AppSnackBars.success(
          context,
          'Saved “${_selected.label}” to case #${_case!['id']}',
        );
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
      if (mounted) AppSnackBars.error(context, msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _patientName {
    final p = _patient;
    if (p == null) return '—';
    return '${p['first_name']} ${p['last_name']}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ToothPageLoader(message: 'Loading smile preview…');
    }

    if (_fullscreen) {
      return ColoredBox(
        color: const Color(0xFF0F1724),
        child: _photoBytes == null ? _emptyStage() : _photoStage(),
      );
    }

    final portrait = AppBreakpoints.isPortrait(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        portrait ? 16 : 28,
        portrait ? 16 : 24,
        portrait ? 16 : 28,
        portrait ? 16 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_status != null || _error != null) ...[
            const SizedBox(height: 10),
            if (_status != null)
              Text(
                _status!,
                style: const TextStyle(color: AppColors.success, fontSize: 13),
              ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: AdaptiveSplit(
              panelOnRight: true,
              panelFraction: 0.3,
              minPanelWidth: portrait ? 260 : 300,
              maxPanelWidth: 360,
              gap: 16,
              narrowPanelHeight: portrait ? 260 : 480,
              narrowContentMinHeight: 220,
              narrowContentFirst: true,
              narrowContentMaxHeight: portrait ? 360 : null,
              panel: _buildRail(),
              content: _buildStage(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return PageHeader(
      icon: Icons.sentiment_satisfied_alt_outlined,
      title: AppLocalizations.of(context).smileTitle,
      subtitle:
          'Pick a tooth shape · place it on the patient photo · save to case',
      actions: [
        PatientPickerButton(
          patients: _patients,
          selected: _patient,
          caseId: _case?['id'],
          onSelect: _selectPatient,
          onAdd: _openNewPatientPage,
          onRefresh: _reloadPatients,
          enabled: !_saving,
          emptyHint: 'No patients yet — add one to save the try-on.',
        ),
        OutlinedButton.icon(
          onPressed: _saving || _patient == null ? null : _pickPhoto,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text(_photoBytes == null ? 'Load photo' : 'Change photo'),
        ),
        FilledButton.icon(
          onPressed: _saving || _photoBytes == null ? null : _save,
          icon: _saving
              ? const ToothLoadingIndicator(
                  size: 16,
                  compact: true,
                  color: Colors.white,
                )
              : Icon(_dirty ? Icons.save : Icons.save_outlined, size: 18),
          label: Text(
            _saving ? 'Saving…' : (_dirty ? 'Save changes' : 'Save to case'),
          ),
        ),
      ],
    );
  }

  Widget _buildStage() {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadii.border,
        child: _photoBytes == null ? _emptyStage() : _photoStage(),
      ),
    );
  }

  Widget _emptyStage() {
    return Stack(
      children: [
        Container(
          color: const Color(0xFF0F1724),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.dentalBlue.withValues(alpha: 0.15),
                      border: Border.all(
                        color: AppColors.dentalBlue.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.sentiment_satisfied_alt_outlined,
                      size: 34,
                      color: AppColors.dentalBlue,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Load a patient smile photo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppBreakpoints.isPortrait(context)
                        ? 'Then tap a shape in the library below and place it over the teeth.'
                        : 'Then tap a shape in the library on the right and place it over the teeth.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      height: 1.4,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Load patient photo'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: _StageIconBtn(
            icon: _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            tip: _fullscreen ? 'Exit fullscreen' : 'Fullscreen',
            onTap: () => setState(() => _fullscreen = !_fullscreen),
          ),
        ),
      ],
    );
  }

  Widget _photoStage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = Size(constraints.maxWidth, constraints.maxHeight);
        final prev = _lastCanvas;
        if (prev != null &&
            _centeredOnce &&
            (prev.width != canvas.width || prev.height != canvas.height)) {
          _remapPlacement(prev, canvas);
        }
        _lastCanvas = canvas;
        if (!_centeredOnce) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_centeredOnce) _centerIn(canvas);
          });
        }

        final overlayVisible = _showOverlay && !_comparing;

        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: const Color(0xFF0F1724),
              child: Image.memory(
                _photoBytes!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            if (overlayVisible)
              Positioned(
                left: _offset.dx,
                top: _offset.dy,
                child: Transform.rotate(
                  angle: _rotation * math.pi / 180,
                  child: SizedBox(
                    width: ShapeOverlayPage.cellW * _scale * _width,
                    height: ShapeOverlayPage.cellH * _scale * _height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            onScaleStart: (_) {
                              _baseScale = _scale;
                              _baseRotation = _rotation;
                            },
                            onScaleUpdate: (d) {
                              setState(() {
                                _offset += d.focalPointDelta;
                                _scale =
                                    (_baseScale * d.scale).clamp(0.15, 8.0);
                                _rotation = (_baseRotation +
                                        d.rotation * 180 / math.pi)
                                    .clamp(-35.0, 35.0);
                                _dirty = true;
                              });
                            },
                            child: _OverlayTooth(
                              item: _selected,
                              opacity: _opacity,
                              showChrome: _showGuides,
                            ),
                          ),
                        ),
                        if (_showGuides) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: _AxisResizeHandle(
                              horizontal: true,
                              onDragUpdate: (delta) {
                                final local = _localDragDelta(delta);
                                setState(() {
                                  _width = (_width +
                                          local.dx /
                                              (ShapeOverlayPage.cellW *
                                                  _scale))
                                      .clamp(0.4, 2.4);
                                  _dirty = true;
                                });
                              },
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: _AxisResizeHandle(
                              horizontal: false,
                              onDragUpdate: (delta) {
                                final local = _localDragDelta(delta);
                                setState(() {
                                  _height = (_height +
                                          local.dy /
                                              (ShapeOverlayPage.cellH *
                                                  _scale))
                                      .clamp(0.4, 2.4);
                                  _dirty = true;
                                });
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              top: 12,
              child: _StageChip(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 44,
                        height: 30,
                        child: ShapeToothImage(item: _selected, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_selected.id} · ${_selected.label}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Row(
                children: [
                  _StageIconBtn(
                    icon: _comparing ? Icons.visibility_off : Icons.visibility,
                    tip: 'Hold to compare original',
                    onTapDown: () => setState(() => _comparing = true),
                    onTapUp: () => setState(() => _comparing = false),
                    onTapCancel: () => setState(() => _comparing = false),
                  ),
                  const SizedBox(width: 6),
                  _StageIconBtn(
                    icon: _showOverlay
                        ? Icons.layers_outlined
                        : Icons.layers_clear_outlined,
                    tip: _showOverlay ? 'Hide overlay' : 'Show overlay',
                    onTap: () => setState(() => _showOverlay = !_showOverlay),
                  ),
                  const SizedBox(width: 6),
                  _StageIconBtn(
                    icon: Icons.center_focus_strong,
                    tip: 'Center shape',
                    onTap: () => _centerIn(canvas),
                  ),
                  const SizedBox(width: 6),
                  _StageIconBtn(
                    icon: Icons.refresh,
                    tip: 'Reset placement',
                    onTap: () => _resetTransform(canvas),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              right: 56,
              bottom: 12,
              child: _StageChip(
                child: Text(
                  _comparing
                      ? 'Original photo'
                      : 'Select a library shape → drag / pinch / rotate into place',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: _StageIconBtn(
                icon: _fullscreen
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen,
                tip: _fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                onTap: () => setState(() => _fullscreen = !_fullscreen),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _libraryHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Shape library',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.navy,
            ),
          ),
        ),
        Text(
          '${_shapeIndex + 1}/${ShapeLibrary.total}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }

  Widget _shapeTile(int i, {bool compact = false}) {
    final item = ShapeLibrary.at(i);
    final selected = i == _shapeIndex;
    return Material(
      color: selected
          ? AppColors.dentalBlue.withValues(alpha: 0.12)
          : const Color(0xFF0F1724),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectShape(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.dentalBlue : Colors.white12,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, compact ? 16 : 18),
                child: ShapeToothImage(item: item, fit: BoxFit.contain),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: selected
                      ? AppColors.dentalBlue.withValues(alpha: 0.9)
                      : Colors.black54,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
              ),
              if (selected)
                const Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(
                    Icons.check_circle,
                    size: 16,
                    color: AppColors.dentalBlue,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactRail() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _libraryHeader(),
          const SizedBox(height: 2),
          Text(
            _selected.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.dentalBlue,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ShapeLibrary.total,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => SizedBox(
                width: 88,
                child: _shapeTile(i, compact: true),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 8),
          const Text(
            'Placement',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          _SliderRow(
            label: 'Size',
            value: _scale,
            min: 0.15,
            max: 8.0,
            display: '×${_scale.toStringAsFixed(2)}',
            onChanged: (v) => setState(() {
              _scale = v;
              _dirty = true;
            }),
          ),
          _SliderRow(
            label: 'Width',
            value: _width,
            min: 0.4,
            max: 2.4,
            display: '×${_width.toStringAsFixed(2)}',
            onChanged: (v) => setState(() {
              _width = v;
              _dirty = true;
            }),
          ),
          _SliderRow(
            label: 'Height',
            value: _height,
            min: 0.4,
            max: 2.4,
            display: '×${_height.toStringAsFixed(2)}',
            onChanged: (v) => setState(() {
              _height = v;
              _dirty = true;
            }),
          ),
          _SliderRow(
            label: 'Rotate',
            value: _rotation,
            min: -35,
            max: 35,
            display: '${_rotation.toStringAsFixed(0)}°',
            onChanged: (v) => setState(() {
              _rotation = v;
              _dirty = true;
            }),
          ),
          _SliderRow(
            label: 'Blend',
            value: _opacity,
            min: 0.25,
            max: 1.0,
            display: '${(_opacity * 100).round()}%',
            onChanged: (v) => setState(() {
              _opacity = v;
              _dirty = true;
            }),
          ),
          Row(
            children: [
              const Text(
                'Nudge',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const Spacer(),
              _NudgeBtn(
                icon: Icons.keyboard_arrow_left,
                onTap: () => _nudge(-4, 0),
              ),
              _NudgeBtn(
                icon: Icons.keyboard_arrow_up,
                onTap: () => _nudge(0, -4),
              ),
              _NudgeBtn(
                icon: Icons.keyboard_arrow_down,
                onTap: () => _nudge(0, 4),
              ),
              _NudgeBtn(
                icon: Icons.keyboard_arrow_right,
                onTap: () => _nudge(4, 0),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FilterChip(
                  label: const Text('Guides', style: TextStyle(fontSize: 12)),
                  selected: _showGuides,
                  onSelected: (v) => setState(() => _showGuides = v),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: _lastCanvas == null
                      ? null
                      : () => _resetTransform(_lastCanvas!),
                  child: const Text('Reset', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRail() {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = AppBreakpoints.isPortrait(context) ||
              (constraints.hasBoundedHeight && constraints.maxHeight < 420);
          if (compact) return _compactRail();

          final short =
              constraints.hasBoundedHeight && constraints.maxHeight < 560;
          final previewH = short ? 72.0 : 100.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Shape library',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  Text(
                    '${_shapeIndex + 1}/${ShapeLibrary.total}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _selected.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.dentalBlue,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: previewH,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1724),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.dentalBlue.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ShapeToothImage(item: _selected, fit: BoxFit.contain),
              ),
              const SizedBox(height: 12),
              Expanded(
                flex: _placementOpen ? 3 : 5,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (_placementOpen &&
                        n is ScrollUpdateNotification &&
                        (n.scrollDelta ?? 0).abs() > 0) {
                      setState(() => _placementOpen = false);
                    }
                    return false;
                  },
                  child: GridView.builder(
                    itemCount: ShapeLibrary.total,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.05,
                    ),
                    itemBuilder: (context, i) {
                      final item = ShapeLibrary.at(i);
                      final selected = i == _shapeIndex;
                      return Material(
                        color: selected
                            ? AppColors.dentalBlue.withValues(alpha: 0.12)
                            : const Color(0xFF0F1724),
                        borderRadius: BorderRadius.circular(10),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _selectShape(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AppColors.dentalBlue
                                    : Colors.white12,
                                width: selected ? 2.5 : 1,
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(4, 4, 4, 18),
                                  child: ShapeToothImage(
                                    item: item,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    color: selected
                                        ? AppColors.dentalBlue
                                            .withValues(alpha: 0.9)
                                        : Colors.black54,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      item.label,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? Colors.white
                                            : Colors.white70,
                                      ),
                                    ),
                                  ),
                                ),
                                if (selected)
                                  const Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Icon(
                                      Icons.check_circle,
                                      size: 16,
                                      color: AppColors.dentalBlue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              InkWell(
                onTap: () => setState(() => _placementOpen = !_placementOpen),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Placement',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Icon(
                        _placementOpen
                            ? Icons.expand_more
                            : Icons.expand_less,
                        size: 20,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
              // Placement sliders scroll inside remaining space — no bottom overflow.
              if (_placementOpen)
                Flexible(
                  flex: 2,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SliderRow(
                          label: 'Size',
                          value: _scale,
                          min: 0.15,
                          max: 8.0,
                          display: '×${_scale.toStringAsFixed(2)}',
                          onChanged: (v) => setState(() {
                            _scale = v;
                            _dirty = true;
                          }),
                        ),
                        _SliderRow(
                          label: 'Width',
                          value: _width,
                          min: 0.4,
                          max: 2.4,
                          display: '×${_width.toStringAsFixed(2)}',
                          onChanged: (v) => setState(() {
                            _width = v;
                            _dirty = true;
                          }),
                        ),
                        _SliderRow(
                          label: 'Height',
                          value: _height,
                          min: 0.4,
                          max: 2.4,
                          display: '×${_height.toStringAsFixed(2)}',
                          onChanged: (v) => setState(() {
                            _height = v;
                            _dirty = true;
                          }),
                        ),
                        _SliderRow(
                          label: 'Rotate',
                          value: _rotation,
                          min: -35,
                          max: 35,
                          display: '${_rotation.toStringAsFixed(0)}°',
                          onChanged: (v) => setState(() {
                            _rotation = v;
                            _dirty = true;
                          }),
                        ),
                        _SliderRow(
                          label: 'Blend',
                          value: _opacity,
                          min: 0.25,
                          max: 1.0,
                          display: '${(_opacity * 100).round()}%',
                          onChanged: (v) => setState(() {
                            _opacity = v;
                            _dirty = true;
                          }),
                        ),
                        Row(
                          children: [
                            const Text(
                              'Nudge',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                            const Spacer(),
                            _NudgeBtn(
                              icon: Icons.keyboard_arrow_left,
                              onTap: () => _nudge(-4, 0),
                            ),
                            _NudgeBtn(
                              icon: Icons.keyboard_arrow_up,
                              onTap: () => _nudge(0, -4),
                            ),
                            _NudgeBtn(
                              icon: Icons.keyboard_arrow_down,
                              onTap: () => _nudge(0, 4),
                            ),
                            _NudgeBtn(
                              icon: Icons.keyboard_arrow_right,
                              onTap: () => _nudge(4, 0),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: FilterChip(
                                label: const Text(
                                  'Guides',
                                  style: TextStyle(fontSize: 12),
                                ),
                                selected: _showGuides,
                                onSelected: (v) =>
                                    setState(() => _showGuides = v),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _lastCanvas == null
                                    ? null
                                    : () => _resetTransform(_lastCanvas!),
                                child: const Text(
                                  'Reset',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _patientName,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ShapeToothImage extends StatelessWidget {
  const ShapeToothImage({super.key, required this.item, this.fit = BoxFit.contain});

  final ShapeLibraryItem item;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      item.asset,
      fit: fit,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white38),
      ),
    );
  }
}

class _OverlayTooth extends StatelessWidget {
  const _OverlayTooth({
    required this.item,
    required this.opacity,
    required this.showChrome,
  });

  final ShapeLibraryItem item;
  final double opacity;
  final bool showChrome;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: opacity,
            child: ColorFiltered(
              // Soften near-black backdrop so teeth blend onto the patient photo
              colorFilter: const ColorFilter.matrix(<double>[
                1, 0, 0, 0, 0,
                0, 1, 0, 0, 0,
                0, 0, 1, 0, 0,
                0.45, 0.45, 0.45, 0, -12,
              ]),
              child: ShapeToothImage(item: item, fit: BoxFit.fill),
            ),
          ),
        ),
        if (showChrome)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.dentalBlue.withValues(alpha: 0.55),
                    width: 1.25,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AxisResizeHandle extends StatelessWidget {
  const _AxisResizeHandle({
    required this.horizontal,
    required this.onDragUpdate,
  });

  final bool horizontal;
  final ValueChanged<Offset> onDragUpdate;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerMove: (e) {
          if (e.down) onDragUpdate(e.delta);
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: horizontal ? 14 : 8,
              height: horizontal ? 8 : 14,
              decoration: BoxDecoration(
                color: AppColors.dentalBlue,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(9),
      ),
      child: child,
    );
  }
}

class _StageIconBtn extends StatelessWidget {
  const _StageIconBtn({
    required this.icon,
    required this.tip,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
  });

  final IconData icon;
  final String tip;
  final VoidCallback? onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapUp;
  final VoidCallback? onTapCancel;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          onTapDown: onTapDown == null ? null : (_) => onTapDown!(),
          onTapUp: onTapUp == null ? null : (_) => onTapUp!(),
          onTapCancel: onTapCancel,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

class _NudgeBtn extends StatelessWidget {
  const _NudgeBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

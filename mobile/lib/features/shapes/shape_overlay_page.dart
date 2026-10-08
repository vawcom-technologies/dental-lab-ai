import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as imglib;

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/patient_picker.dart';
import '../../core/widgets/ui_kit.dart';
import '../../core/errors/user_facing_error.dart';

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

  /// Lower-arch Batem models (gingiva at the bottom after 180° correction).
  static const lowerArchItems = <ShapeLibraryItem>[
    ShapeLibraryItem(
      id: 13,
      shapeId: 'shape_13',
      label: 'Implant natural',
      asset: 'assets/clinical/shapes/shape_13_implant_natural.png',
    ),
    ShapeLibraryItem(
      id: 15,
      shapeId: 'shape_15',
      label: 'Implant classic',
      asset: 'assets/clinical/shapes/shape_15_implant_classic.png',
    ),
  ];

  static List<ShapeLibraryItem> get catalog => [
        ...items,
        ...lowerArchItems,
      ];

  static int get total => catalog.length;

  static bool isLower(int index) => index >= items.length;

  static ShapeLibraryItem at(int index) {
    final all = catalog;
    return all[index.clamp(0, all.length - 1)];
  }

  static int indexOfShapeId(String? shapeId) {
    if (shapeId == null || shapeId.isEmpty) return 0;
    final match = RegExp(r'shape_(\d+)').firstMatch(shapeId);
    if (match == null) return 0;
    final id = int.tryParse(match.group(1)!) ?? 1;
    final idx = catalog.indexWhere((e) => e.id == id);
    return idx < 0 ? 0 : idx;
  }
}

/// Accordion of Batem smile models — jaw sections and rows open independently.
class BatemModelAccordion extends StatefulWidget {
  const BatemModelAccordion({
    super.key,
    required this.selectedIndexes,
    required this.openIds,
    required this.onToggle,
    required this.onSelect,
    this.shrinkWrap = false,
  });

  final Set<int> selectedIndexes;
  final Set<int> openIds;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onSelect;
  final bool shrinkWrap;

  @override
  State<BatemModelAccordion> createState() => _BatemModelAccordionState();
}

class _BatemModelAccordionState extends State<BatemModelAccordion> {
  final _openArch = <String>{'upper', 'lower'};

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final children = <Widget>[
      _archHeader('upper', loc.smileUpperJaw),
      if (_openArch.contains('upper'))
        ..._rowsFor(ShapeLibrary.items, startIndex: 0),
      _archHeader('lower', loc.smileLowerJaw),
      if (_openArch.contains('lower'))
        ..._rowsFor(
          ShapeLibrary.lowerArchItems,
          startIndex: ShapeLibrary.items.length,
        ),
    ];
    return ListView(
      primary: false,
      padding: const EdgeInsets.only(bottom: 8),
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: children,
    );
  }

  Widget _archHeader(String id, String label) {
    final open = _openArch.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.neo,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            setState(() {
              if (open) {
                _openArch.remove(id);
              } else {
                _openArch.add(id);
              }
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                Icon(
                  open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.navy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _rowsFor(List<ShapeLibraryItem> items, {required int startIndex}) {
    final loc = AppLocalizations.of(context);
    return [
      for (var i = 0; i < items.length; i++)
        _modelRow(
          loc: loc,
          item: items[i],
          catalogIndex: startIndex + i,
        ),
    ];
  }

  Widget _modelRow({
    required AppLocalizations loc,
    required ShapeLibraryItem item,
    required int catalogIndex,
  }) {
    final selected = widget.selectedIndexes.contains(catalogIndex);
    final open = widget.openIds.contains(item.id);
    return Padding(
      key: ValueKey('batem-${item.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? AppColors.dentalBlue.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.dentalBlue : AppColors.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => widget.onToggle(item.id),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: ColoredBox(
                        color: const Color(0xFF0F1724),
                        child: SizedBox(
                          width: 48,
                          height: 36,
                          child: ShapeToothImage(
                            item: item,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        shapeLabel(context, item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: selected
                              ? AppColors.dentalBlue
                              : AppColors.navy,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: open
                            ? AppColors.dentalBlue.withValues(alpha: 0.12)
                            : AppColors.neo,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        open ? loc.smileModelOpen : loc.smileModelClosed,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: open
                              ? AppColors.dentalBlue
                              : AppColors.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.navy,
                    ),
                  ],
                ),
              ),
            ),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: open
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Material(
                              color: const Color(0xFF0F1724),
                              borderRadius: BorderRadius.circular(10),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => widget.onSelect(catalogIndex),
                                child: SizedBox(
                                  height: 120,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: ShapeToothImage(
                                          item: item,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      if (selected)
                                        const Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Icon(
                                            Icons.check_circle,
                                            color: AppColors.dentalBlue,
                                            size: 22,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: () => widget.onSelect(catalogIndex),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.navy,
                                minimumSize: const Size.fromHeight(36),
                              ),
                              child: Text(loc.smileUseThisModel),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// JPEG-encode raw RGBA off the UI thread (for [compute]).
Uint8List _encodeJpeg((Uint8List, int, int) rgba) {
  final (bytes, w, h) = rgba;
  final image = imglib.Image.fromBytes(
    width: w,
    height: h,
    bytes: bytes.buffer,
    numChannels: 4,
  );
  return imglib.encodeJpg(image, quality: 92);
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

/// Position / size / opacity of one jaw's overlay.
class _Placement {
  Offset offset = Offset.zero;
  double scale = 1.0;
  double width = 1.0; // ponytail: session-only; persist when API gets scale_x/y
  double height = 1.0;
  double rotation = 0;
  double opacity = 0.88;

  void reset() {
    scale = 1.05;
    width = 1.0;
    height = 1.0;
    rotation = 0;
    opacity = 0.88;
  }
}

class _ShapeOverlayPageState extends State<ShapeOverlayPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _case;
  Uint8List? _photoBytes;

  // One model per jaw (catalog indexes); the placement controls edit the
  // active jaw via the getters/setters below.
  int? _upperIndex = 0;
  int? _lowerIndex;
  final _upperP = _Placement();
  final _lowerP = _Placement();
  bool _lowerActive = false;
  _Placement get _p => _lowerActive ? _lowerP : _upperP;
  Offset get _offset => _p.offset;
  set _offset(Offset v) => _p.offset = v;
  double get _scale => _p.scale;
  set _scale(double v) => _p.scale = v;
  double get _width => _p.width;
  set _width(double v) => _p.width = v;
  double get _height => _p.height;
  set _height(double v) => _p.height = v;
  double get _rotation => _p.rotation;
  set _rotation(double v) => _p.rotation = v;
  double get _opacity => _p.opacity;
  set _opacity(double v) => _p.opacity = v;
  bool _showOverlay = true;
  bool _comparing = false;
  bool _showGuides = true;
  bool _placementOpen = true;
  final Set<int> _openBatemIds = {ShapeLibrary.items.first.id};

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
  /// This patient's saved smiles (newest first) — the "Saved smiles" strip.
  List<Map<String, dynamic>> _smileItems = [];
  /// Saved smile being edited; null until the first Save.
  String? _smileId;
  /// Camera photo on the canvas (unsaved) — Save copies it server-side.
  String? _basePhotoId;
  String _baseFilename = 'smile.jpg';
  /// Placements of a reopened smile, applied once the canvas is laid out.
  Map<String, dynamic>? _pendingOverlay;
  bool _savedSmilesOpen = true;
  /// True for the frame Save captures: overlays on, edit handles off.
  bool _capturing = false;
  final _captureKey = GlobalKey();
  late final AnimationController _fsController;
  late final Animation<double> _fsExpand;

  int? get _activeIndex => _lowerActive ? _lowerIndex : _upperIndex;
  ShapeLibraryItem? get _selected {
    final i = _activeIndex;
    return i == null ? null : ShapeLibrary.at(i);
  }

  /// Selected models, upper first.
  List<(_Placement, ShapeLibraryItem)> get _chosen => [
        if (_upperIndex != null) (_upperP, ShapeLibrary.at(_upperIndex!)),
        if (_lowerIndex != null) (_lowerP, ShapeLibrary.at(_lowerIndex!)),
      ];

  @override
  void initState() {
    super.initState();
    _fsController = AnimationController(
      vsync: this,
      duration: AppMotion.page,
      reverseDuration: AppMotion.normal,
    );
    _fsExpand = CurvedAnimation(
      parent: _fsController,
      curve: AppMotion.spring,
      reverseCurve: AppMotion.easeOut,
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _fsController.dispose();
    super.dispose();
  }

  void _toggleFullscreen() {
    if (_fsController.value > 0.5) {
      _fsController.reverse();
    } else {
      _fsController.forward();
    }
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
      setState(() => _error = friendlyError(e));
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
    final switching = _patient == null || _pid(_patient!) != _pid(patient);
    setState(() {
      _patient = patient;
      _status = null;
      _error = null;
      _smileItems = [];
      if (switching) {
        // A photo or smile from the previous patient must never save here.
        _dirty = false;
        _photoBytes = null;
        _smileId = null;
        _basePhotoId = null;
        _pendingOverlay = null;
      }
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
    // Fresh: updating a saved smile (PATCH) doesn't evict this cached list.
    await _loadSmilePreviews(forceRefresh: true);
  }

  Future<void> _loadSmilePreviews({bool forceRefresh = false}) async {
    final patient = _patient;
    if (patient == null) {
      if (mounted) setState(() => _smileItems = []);
      return;
    }
    final pid = _pid(patient);
    if (pid.isEmpty) return;
    try {
      final rows = await widget.api.listSmilePreviews(
        pid,
        forceRefresh: forceRefresh,
      );
      if (!mounted || _patient == null || _pid(_patient!) != pid) return;
      setState(() => _smileItems = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
      });
    }
  }

  /// Camera handoff: put the camera photo on the canvas. Nothing is stored
  /// until Save.
  Future<void> _consumeSmileHandoff() async {
    final photoId = widget.patientSession.takePendingSmilePhotoId();
    if (photoId == null || photoId.isEmpty || _patient == null) return;
    Map<String, dynamic>? photo;
    try {
      final photos = await widget.api.listPatientPhotos(
        _pid(_patient!),
        forceRefresh: true,
      );
      for (final row in photos) {
        if ('${row['id'] ?? ''}' == photoId) {
          photo = row;
          break;
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
      return;
    }
    if (!mounted) return;
    if (photo == null) {
      setState(() => _error = AppLocalizations.of(context).tr('sh.photoNF'));
      return;
    }
    await _openOnCanvas(
      '${photo['file_url'] ?? ''}',
      basePhotoId: photoId,
      filename: '${photo['filename'] ?? 'smile.jpg'}',
      status: AppLocalizations.of(context).tr('sp.fromCam'),
    );
  }

  /// Reopen a saved smile: photo without overlays + shapes where they were.
  Future<void> _openSaved(Map<String, dynamic> item) async {
    final id = '${item['id'] ?? ''}';
    if (id.isEmpty || id == _smileId) return;
    final base = '${item['base_file_url'] ?? ''}';
    final overlay = item['overlay'];
    if (base.isEmpty || overlay is! Map) {
      // Earlier photo with no shapes yet: Save turns this record into a
      // saved smile (the photo becomes its base) instead of adding another.
      await _openOnCanvas(
        '${item['file_url'] ?? ''}',
        smileId: id,
        filename: '${item['file_name'] ?? 'smile.jpg'}',
      );
      return;
    }
    await _openOnCanvas(
      base,
      smileId: id,
      overlay: Map<String, dynamic>.from(overlay),
      status: AppLocalizations.of(context).tr('sp.reopened'),
    );
  }

  Future<void> _openOnCanvas(
    String url, {
    String? smileId,
    String? basePhotoId,
    String filename = 'smile.jpg',
    Map<String, dynamic>? overlay,
    String? status,
  }) async {
    if (url.trim().isEmpty) {
      setState(() => _error = AppLocalizations.of(context).tr('sp.noFile'));
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
        smileId: smileId,
        basePhotoId: basePhotoId,
        filename: filename,
        overlay: overlay,
        status: status,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyPhotoBytes(
    Uint8List data, {
    String? smileId,
    String? basePhotoId,
    String filename = 'smile.jpg',
    Map<String, dynamic>? overlay,
    String? status,
  }) async {
    setState(() {
      _photoBytes = data;
      _smileId = smileId;
      _basePhotoId = basePhotoId;
      _baseFilename = filename;
      _pendingOverlay = overlay;
      _imageSize = null;
      _upperP.reset();
      _lowerP.reset();
      _showOverlay = true;
      _centeredOnce = false;
      _dirty = overlay == null;
      _status = status;
    });
    await _readImageSize(data);
  }

  /// Shape placements relative to the photo (not the screen), so they restore
  /// exactly on any iPad size or orientation. x/y/scale are in photo widths.
  Map<String, dynamic> _overlayJson(Size canvas) {
    final r = _photoRect(canvas);
    Map<String, dynamic> one(_Placement p, int index) => {
          'shape_id': ShapeLibrary.at(index).shapeId,
          'label': ShapeLibrary.at(index).label,
          'jaw': ShapeLibrary.isLower(index) ? 'lower' : 'upper',
          'x': (p.offset.dx - r.left) / r.width,
          'y': (p.offset.dy - r.top) / r.width,
          'scale': p.scale / r.width,
          'width': p.width,
          'height': p.height,
          'rotation': p.rotation,
          'opacity': p.opacity,
        };
    return {
      'version': 1,
      'shapes': [
        if (_upperIndex != null) one(_upperP, _upperIndex!),
        if (_lowerIndex != null) one(_lowerP, _lowerIndex!),
      ],
      'active_jaw': _lowerActive ? 'lower' : 'upper',
    };
  }

  void _applyOverlay(Map<String, dynamic> overlay, Size canvas) {
    final r = _photoRect(canvas);
    double num0(Map s, String k, double fallback) =>
        (s[k] as num?)?.toDouble() ?? fallback;
    _upperIndex = null;
    _lowerIndex = null;
    for (final s in (overlay['shapes'] as List? ?? const [])) {
      if (s is! Map) continue;
      final idx = ShapeLibrary.indexOfShapeId(s['shape_id']?.toString());
      final lower = ShapeLibrary.isLower(idx);
      final p = lower ? _lowerP : _upperP;
      if (lower) {
        _lowerIndex = idx;
      } else {
        _upperIndex = idx;
      }
      p.offset = Offset(
        r.left + num0(s, 'x', 0) * r.width,
        r.top + num0(s, 'y', 0) * r.width,
      );
      p.scale = (num0(s, 'scale', 1 / r.width) * r.width).clamp(0.15, 8.0);
      p.width = num0(s, 'width', 1);
      p.height = num0(s, 'height', 1);
      p.rotation = num0(s, 'rotation', 0);
      p.opacity = num0(s, 'opacity', 0.88);
    }
    _lowerActive = _upperIndex == null ||
        (overlay['active_jaw'] == 'lower' && _lowerIndex != null);
    _openBatemIds
      ..clear()
      ..addAll([for (final (_, it) in _chosen) it.id]);
    _centeredOnce = true;
    _dirty = false;
  }

  /// The photo with overlays at photo resolution (max 2400 px wide), cropped
  /// to the photo — no letterbox, no edit handles, no stage buttons.
  Future<Uint8List> _renderComposite(Size canvas) async {
    setState(() => _capturing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _captureKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final r = _photoRect(canvas);
      final photoW = _imageSize?.width ?? r.width * 2;
      final ratio = math.min(photoW, 2400.0) / r.width;
      final full = await boundary.toImage(pixelRatio: ratio);
      final src = Rect.fromLTWH(
        r.left * ratio,
        r.top * ratio,
        r.width * ratio,
        r.height * ratio,
      );
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        full,
        src,
        Offset.zero & src.size,
        Paint()..filterQuality = FilterQuality.high,
      );
      final out = await recorder
          .endRecording()
          .toImage(src.width.round(), src.height.round());
      final rgba = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = out.width;
      final h = out.height;
      full.dispose();
      out.dispose();
      return compute(_encodeJpeg, (rgba!.buffer.asUint8List(), w, h));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _openNewPatientPage() {
    widget.patientSession.requestNavigateToNewPatient();
  }

  Future<void> _restoreSaved(int caseId) async {
    try {
      final rows = await widget.api.latestShapes(caseId);
      if (rows.isEmpty || !mounted) return;
      setState(() {
        _upperIndex = null;
        _lowerIndex = null;
        for (final r in rows) {
          final idx = ShapeLibrary.indexOfShapeId(r['shape_id']?.toString());
          final lower = ShapeLibrary.isLower(idx);
          final p = lower ? _lowerP : _upperP;
          if (lower) {
            _lowerIndex = idx;
          } else {
            _upperIndex = idx;
          }
          p.offset = Offset(
            (r['position_x'] as num?)?.toDouble() ?? p.offset.dx,
            (r['position_y'] as num?)?.toDouble() ?? p.offset.dy,
          );
          p.rotation = (r['rotation'] as num?)?.toDouble() ?? 0;
          p.scale = (r['scale'] as num?)?.toDouble() ?? 1.0;
        }
        _lowerActive = _upperIndex == null;
        _openBatemIds
          ..clear()
          ..addAll([for (final (_, it) in _chosen) it.id]);
        _status = AppLocalizations.of(context).trp('sh.restoredShape', {'n': _chosen.map((c) => shapeLabel(context, c.$2)).join(' + ')});
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
    for (final p in [_upperP, _lowerP]) {
      p.offset = Offset(
        b.left + (p.offset.dx - a.left) * sx,
        b.top + (p.offset.dy - a.top) * sx,
      );
      p.scale = (p.scale * sx).clamp(0.15, 8.0);
    }
  }

  Future<void> _pickPhoto() async {
    if (_patient == null) {
      setState(() => _error = AppLocalizations.of(context).tr('sh.selPat'));
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
        setState(() => _error = AppLocalizations.of(context).tr('sp.bytes'));
        return;
      }

      if (!mounted) return;
      final confirmed = await confirmPatientMediaUpload(context);
      if (!confirmed || !mounted) return;

      final name = picked.files.first.name.isNotEmpty
          ? picked.files.first.name
          : 'smile.jpg';
      // Nothing is uploaded until Save.
      await _applyPhotoBytes(
        Uint8List.fromList(bytes),
        filename: name,
        status: AppLocalizations.of(context).tr('sp.loaded'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  /// One model per jaw: picking replaces that jaw's model, picking the
  /// current one again removes it.
  void _selectShape(int i) {
    if (i < 0 || i >= ShapeLibrary.total) return;
    final lower = ShapeLibrary.isLower(i);
    final item = ShapeLibrary.at(i);
    setState(() {
      final remove = (lower ? _lowerIndex : _upperIndex) == i;
      if (lower) {
        _lowerIndex = remove ? null : i;
      } else {
        _upperIndex = remove ? null : i;
      }
      if (remove) {
        _lowerActive = !lower && _lowerIndex != null;
        _status = AppLocalizations.of(context).trp('sh.rm', {'n': shapeLabel(context, item)});
      } else {
        _lowerActive = lower;
        _openBatemIds.add(item.id);
        _status = AppLocalizations.of(context).trp('sh.sel', {'n': shapeLabel(context, item)});
        _showOverlay = true;
      }
      _dirty = true;
    });
  }

  void _toggleBatem(int id) {
    setState(() {
      if (!_openBatemIds.remove(id)) _openBatemIds.add(id);
    });
  }

  void _centerP(_Placement p, Size canvas, {double dyFrac = 0}) {
    final w = ShapeOverlayPage.cellW * p.scale * p.width;
    final h = ShapeOverlayPage.cellH * p.scale * p.height;
    final photo = _photoRect(canvas);
    p.offset = Offset(
      photo.left + (photo.width - w) / 2,
      photo.top + (photo.height - h) / 2 + h * dyFrac,
    );
  }

  /// [both]: first placement — lower sits below the upper (ponytail: fixed
  /// 0.5-cell drop; the user drags it onto the lower teeth).
  void _centerIn(Size canvas, {bool both = false}) {
    setState(() {
      if (both) {
        _centerP(_upperP, canvas);
        _centerP(_lowerP, canvas, dyFrac: 0.5);
      } else {
        _centerP(_p, canvas);
      }
      _centeredOnce = true;
    });
  }

  void _resetTransform(Size canvas) {
    setState(() {
      _p.reset();
      _centerP(_p, canvas, dyFrac: _lowerActive ? 0.5 : 0);
      _dirty = true;
    });
  }

  void _nudge(double dx, double dy) {
    setState(() {
      _offset += Offset(dx, dy);
      _dirty = true;
    });
  }

  Widget _nudgeControls() {
    // Four 36px buttons + gaps (~168) plus the label overflow a narrow rail
    // (~133). Scale the pad down when space is tight; full size when wide.
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context).smileNudge,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
            ),
          ),
        ],
      ),
    );
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
    final patient = _patient;
    if (patient == null) {
      setState(() => _error = AppLocalizations.of(context).tr('c.selPatFirst'));
      return;
    }
    if (_photoBytes == null) {
      setState(() =>
          _error = AppLocalizations.of(context).smileLoadSmilePhoto);
      return;
    }
    if (_chosen.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).tr('sp.selModel'));
      return;
    }
    final canvas = _lastCanvas;
    if (canvas == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.saveSmilePreview(
        patientId: _pid(patient),
        smileId: _smileId,
        composite: await _renderComposite(canvas),
        baseBytes: _basePhotoId == null ? _photoBytes : null,
        baseFilename: _baseFilename,
        basePhotoId: _basePhotoId,
        overlay: _overlayJson(canvas),
      );
      // Legacy numeric-id patients also keep their case shape rows.
      final caseId = _case?['id'];
      if (caseId is int) {
        await widget.api.saveShapes(
          caseId: caseId,
          shapes: [
            for (final (p, it) in _chosen)
              {
                'shape_id': it.shapeId,
                'position_x': p.offset.dx,
                'position_y': p.offset.dy,
                'rotation': p.rotation,
                'scale': p.scale,
              },
          ],
        );
        await widget.api.markCaseInProgressIfPending(
          caseId,
          _case!['status']?.toString(),
        );
        _case = {..._case!, 'status': 'in_progress'};
      }
      if (!mounted) return;
      final id = '${saved['id'] ?? ''}';
      setState(() {
        _smileId = id;
        _basePhotoId = null;
        _dirty = false;
        _smileItems = [
          saved,
          for (final row in _smileItems)
            if ('${row['id']}' != id) row,
        ];
      });
      final shapes = _chosen.map((c) => '“${shapeLabel(context, c.$2)}”').join(' + ');
      AppSnackBars.success(
        context,
        caseId is int
            ? AppLocalizations.of(context).trp('sp.savedCase', {'s': shapes, 'c': caseId})
            : AppLocalizations.of(context).trp('sp.saved', {'s': shapes}),
      );
    } catch (e) {
      final msg = friendlyError(e);
      setState(() => _error = msg);
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
    _error = AppSnackBars.drain(context, _error);
    if (_loading) {
      return ToothPageLoader(message: AppLocalizations.of(context).smileLoading);
    }

    final portrait = AppBreakpoints.isPortrait(context);

    return AnimatedBuilder(
      animation: _fsExpand,
      builder: (context, _) {
        final t = _fsExpand.value.clamp(0.0, 1.0);
        final chrome = (1.0 - t).clamp(0.0, 1.0);
        final pad = EdgeInsets.lerp(
          AppBreakpoints.pagePadding(
            context,
            portrait: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          ),
          EdgeInsets.zero,
          t,
        )!;
        return ColoredBox(
          color: Color.lerp(
                Theme.of(context).scaffoldBackgroundColor,
                const Color(0xFF0F1724),
                t,
              ) ??
              const Color(0xFF0F1724),
          child: Padding(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: chrome,
                    child: Opacity(
                      opacity: chrome,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(),
                          if (_status != null)
                            Text(
                              _status!,
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 13,
                              ),
                            ),
                          if (_smileItems.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _savedSmilesStrip(),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: AdaptiveSplit(
                    panelOnRight: true,
                    panelFraction: 0.3 * chrome.clamp(0.001, 1.0),
                    minPanelWidth: (portrait ? 260.0 : 300.0) * chrome,
                    maxPanelWidth: 360 * chrome,
                    gap: 16 * chrome,
                    narrowPanelHeight: (portrait ? 260.0 : 480.0) * chrome,
                    narrowContentMinHeight: 220,
                    narrowContentFirst: true,
                    narrowContentMaxHeight: portrait ? 360 : null,
                    panel: IgnorePointer(
                      ignoring: t > 0.2,
                      child: Opacity(
                        opacity: chrome,
                        child: _buildRail(),
                      ),
                    ),
                    content: _buildStage(chrome: chrome, expand: t),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteSaved(Map<String, dynamic> item) async {
    final id = '${item['id'] ?? ''}';
    if (id.isEmpty) return;
    final ok = await AppDialogs.confirm(
      context,
      title: AppLocalizations.of(context).tr('sp.delQ'),
      message: AppLocalizations.of(context).tr('sp.delMsg'),
      confirmLabel: AppLocalizations.of(context).commonDelete,
      isDestructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.deleteSmilePreview(id);
      if (!mounted) return;
      setState(() {
        _smileItems = [
          for (final row in _smileItems)
            if ('${row['id']}' != id) row,
        ];
        if (_smileId == id) {
          // Open smile deleted: clear it so Save can't bring it back.
          _photoBytes = null;
          _smileId = null;
          _basePhotoId = null;
          _pendingOverlay = null;
          _dirty = false;
        }
        _status = AppLocalizations.of(context).tr('sp.deleted');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// This patient's saved smiles; tap one to reopen it on the canvas.
  Widget _savedSmilesStrip() {
    return SizedBox(
      height: _savedSmilesOpen ? 64 : 32,
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _savedSmilesOpen = !_savedSmilesOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _savedSmilesOpen ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    AppLocalizations.of(context).trp('sp.savedN', {'n': _smileItems.length}),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (_savedSmilesOpen)
            Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _smileItems.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final item = _smileItems[i];
                final current = '${item['id']}' == _smileId;
                return GestureDetector(
                  onTap: _saving ? null : () => _openSaved(item),
                  child: Container(
                    width: 88,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1724),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: current
                            ? AppColors.dentalBlue
                            : AppColors.muted.withValues(alpha: 0.3),
                        width: current ? 2.5 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          widget.api
                              .resolveMediaUrl('${item['file_url'] ?? ''}'),
                          headers: widget.api.mediaHeaders,
                          fit: BoxFit.cover,
                          cacheWidth: 200,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            tooltip: AppLocalizations.of(context).tr('sp.delTip'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            onPressed:
                                _saving ? null : () => _deleteSaved(item),
                            icon: const CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
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
      subtitle: AppLocalizations.of(context).smilePageSubtitle,
      actions: [
        PatientPickerButton(
          patients: _patients,
          selected: _patient,
          caseId: _case?['id'],
          onSelect: _selectPatient,
          onAdd: _openNewPatientPage,
          onRefresh: _reloadPatients,
          enabled: !_saving,
          emptyHint: AppLocalizations.of(context).tr('sp.noPat'),
        ),
        OutlinedButton.icon(
          onPressed: _saving || _patient == null ? null : _pickPhoto,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text(_photoBytes == null ? AppLocalizations.of(context).smileLoadPhoto : AppLocalizations.of(context).smileChangePhoto),
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
            _saving
                ? AppLocalizations.of(context).tr('sp.saving')
                : _dirty
                    ? AppLocalizations.of(context).tr('sp.saveChanges')
                    : (_case?['id'] is int ? AppLocalizations.of(context).tr('sp.saveToCase') : AppLocalizations.of(context).save),
          ),
        ),
      ],
    );
  }

  Widget _buildStage({double chrome = 1, double expand = 0}) {
    return SectionCard(
      depth: chrome <= 0 ? 0 : chrome,
      color: Color.lerp(AppColors.card, const Color(0xFF0F1724), expand),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.lerp(
          BorderRadius.zero,
          AppRadii.border,
          chrome,
        )!,
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
                  Text(
                    AppLocalizations.of(context).smileLoadSmilePhoto,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppBreakpoints.isPortrait(context)
                        ? AppLocalizations.of(context).smileLoadSmileHintPortrait
                        : AppLocalizations.of(context).smileLoadSmileHint,
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
                    label: Text(AppLocalizations.of(context).smileLoadPatientPhoto),
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
            icon: _fsController.value > 0.5
                ? Icons.fullscreen_exit
                : Icons.fullscreen,
            tip: _fsController.value > 0.5
                ? AppLocalizations.of(context).tr('sp.exitFs')
                : AppLocalizations.of(context).tr('sp.fs'),
            onTap: _toggleFullscreen,
          ),
        ),
      ],
    );
  }

  Widget _overlay(bool lower) {
    final p = lower ? _lowerP : _upperP;
    final item = ShapeLibrary.at((lower ? _lowerIndex : _upperIndex)!);
    final active = lower == _lowerActive;
    final guides = _showGuides && active && !_capturing;
    return Positioned(
      left: p.offset.dx,
      top: p.offset.dy,
      child: Transform.rotate(
        angle: p.rotation * math.pi / 180,
        child: SizedBox(
          width: ShapeOverlayPage.cellW * p.scale * p.width,
          height: ShapeOverlayPage.cellH * p.scale * p.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  // Tap the other jaw's overlay to switch to editing it.
                  onTap: active ? null : () => setState(() => _lowerActive = lower),
                  onScaleStart: !active
                      ? null
                      : (_) {
                          _baseScale = _scale;
                          _baseRotation = _rotation;
                        },
                  onScaleUpdate: !active
                      ? null
                      : (d) {
                          setState(() {
                            _offset += d.focalPointDelta;
                            _scale = (_baseScale * d.scale).clamp(0.15, 8.0);
                            _rotation =
                                (_baseRotation + d.rotation * 180 / math.pi)
                                    .clamp(-35.0, 35.0);
                            _dirty = true;
                          });
                        },
                  child: _OverlayTooth(
                    item: item,
                    opacity: p.opacity,
                    showChrome: guides,
                  ),
                ),
              ),
              if (guides) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: _AxisResizeHandle(
                    horizontal: true,
                    onDragUpdate: (delta) {
                      final local = _localDragDelta(delta);
                      setState(() {
                        _width = (_width +
                                local.dx / (ShapeOverlayPage.cellW * _scale))
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
                                local.dy / (ShapeOverlayPage.cellH * _scale))
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
        final pending = _pendingOverlay;
        if (pending != null && _imageSize != null) {
          // Reopened smile: placements are photo-relative, so wait for the
          // photo size, then map them onto this canvas.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !identical(_pendingOverlay, pending)) return;
            setState(() {
              _applyOverlay(pending, canvas);
              _pendingOverlay = null;
            });
          });
        } else if (!_centeredOnce && pending == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_centeredOnce) _centerIn(canvas, both: true);
          });
        }

        final overlayVisible = (_showOverlay && !_comparing) || _capturing;

        return Stack(
          fit: StackFit.expand,
          children: [
            // What Save captures: photo + overlays only.
            RepaintBoundary(
              key: _captureKey,
              child: Stack(
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
                  if (overlayVisible) ...[
                    // Active jaw last so it sits on top and takes the gestures.
                    for (final lower
                        in _lowerActive ? [false, true] : [true, false])
                      if ((lower ? _lowerIndex : _upperIndex) != null)
                        _overlay(lower),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (_, item) in _chosen)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _StageChip(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(
                                width: 44,
                                height: 30,
                                child: ShapeToothImage(
                                    item: item, fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${item.id} · ${shapeLabel(context, item)}',
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
                ],
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Row(
                children: [
                  _StageIconBtn(
                    icon: _comparing ? Icons.visibility_off : Icons.visibility,
                    tip: AppLocalizations.of(context).tr('sp.compare'),
                    onTapDown: () => setState(() => _comparing = true),
                    onTapUp: () => setState(() => _comparing = false),
                    onTapCancel: () => setState(() => _comparing = false),
                  ),
                  const SizedBox(width: 6),
                  _StageIconBtn(
                    icon: _showOverlay
                        ? Icons.layers_outlined
                        : Icons.layers_clear_outlined,
                    tip: _showOverlay ? AppLocalizations.of(context).tr('sp.hideOv') : AppLocalizations.of(context).tr('sp.showOv'),
                    onTap: () => setState(() => _showOverlay = !_showOverlay),
                  ),
                  const SizedBox(width: 6),
                  _StageIconBtn(
                    icon: Icons.center_focus_strong,
                    tip: AppLocalizations.of(context).smileCenterShape,
                    onTap: () => _centerIn(canvas),
                  ),
                  const SizedBox(width: 6),
                  _StageIconBtn(
                    icon: Icons.refresh,
                    tip: AppLocalizations.of(context).smileResetPlacement,
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
                      ? AppLocalizations.of(context).smileOriginalPhoto
                      : AppLocalizations.of(context).smileSelectShapeHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: _StageIconBtn(
                icon: _fsController.value > 0.5
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen,
                tip: _fsController.value > 0.5
                    ? AppLocalizations.of(context).tr('sp.exitFs')
                    : AppLocalizations.of(context).tr('sp.fs'),
                onTap: _toggleFullscreen,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Which jaw the placement controls edit.
  String get _activeLabel {
    final loc = AppLocalizations.of(context);
    final sel = _selected;
    if (sel == null) return '—';
    return '${_lowerActive ? loc.smileLowerJaw : loc.smileUpperJaw} · ${shapeLabel(context, sel)}';
  }

  Widget _libraryHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            AppLocalizations.of(context).smileBatemModels,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.navy,
            ),
          ),
        ),
        Text(
          '${_chosen.length}/2',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }

  Widget _batemList({required bool shrinkWrap}) {
    return BatemModelAccordion(
      selectedIndexes: {?_upperIndex, ?_lowerIndex},
      openIds: _openBatemIds,
      onToggle: _toggleBatem,
      onSelect: _selectShape,
      shrinkWrap: shrinkWrap,
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
            _activeLabel,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.dentalBlue,
            ),
          ),
          const SizedBox(height: 10),
          _batemList(shrinkWrap: true),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).smilePlacement,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          _SliderRow(
            label: AppLocalizations.of(context).smileSize,
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
            label: AppLocalizations.of(context).smileWidth,
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
            label: AppLocalizations.of(context).smileHeight,
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
            label: AppLocalizations.of(context).smileRotate,
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
            label: AppLocalizations.of(context).smileBlend,
            value: _opacity,
            min: 0.25,
            max: 1.0,
            display: '${(_opacity * 100).round()}%',
            onChanged: (v) => setState(() {
              _opacity = v;
              _dirty = true;
            }),
          ),
          _nudgeControls(),
          Row(
            children: [
              Expanded(
                child: FilterChip(
                  label: Text(AppLocalizations.of(context).smileGuides, style: const TextStyle(fontSize: 12)),
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
                  child: Text(AppLocalizations.of(context).shadeReset, style: const TextStyle(fontSize: 12)),
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
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).smileBatemModels,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  Text(
                    '${_chosen.length}/2',
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
                _activeLabel,
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
                child: _selected == null
                    ? null
                    : ShapeToothImage(item: _selected!, fit: BoxFit.contain),
              ),
              const SizedBox(height: 12),
              Expanded(
                flex: _placementOpen ? 2 : 5,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (_placementOpen &&
                        n is ScrollUpdateNotification &&
                        (n.scrollDelta ?? 0).abs() > 0) {
                      setState(() => _placementOpen = false);
                    }
                    return false;
                  },
                  child: _batemList(shrinkWrap: false),
                ),
              ),
              const SizedBox(height: 4),
              const Divider(height: 1),
              InkWell(
                onTap: () => setState(() => _placementOpen = !_placementOpen),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context).smilePlacement,
                          style: const TextStyle(
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
                  flex: 3,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SliderRow(
                          label: AppLocalizations.of(context).smileSize,
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
                          label: AppLocalizations.of(context).smileWidth,
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
                          label: AppLocalizations.of(context).smileHeight,
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
                          label: AppLocalizations.of(context).smileRotate,
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
                          label: AppLocalizations.of(context).smileBlend,
                          value: _opacity,
                          min: 0.25,
                          max: 1.0,
                          display: '${(_opacity * 100).round()}%',
                          onChanged: (v) => setState(() {
                            _opacity = v;
                            _dirty = true;
                          }),
                        ),
                        _nudgeControls(),
                        Row(
                          children: [
                            Expanded(
                              child: FilterChip(
                                label: Text(
                                  AppLocalizations.of(context).smileGuides,
                                  style: const TextStyle(fontSize: 12),
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
                                child: Text(
                                  AppLocalizations.of(context).shadeReset,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _patientName,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
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
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: AppColors.inset,
        borderRadius: AppRadii.borderSm,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.borderSm,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 22, color: AppColors.navy),
          ),
        ),
      ),
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
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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

/// Localized display name of a library shape (keyed by its English label).
String shapeLabel(BuildContext context, ShapeLibraryItem it) =>
    AppLocalizations.of(context).tr('shape.${it.label}');

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
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
import '../cases/case_panel.dart';
import '../cases/case_store.dart';
import '../cases/submit_prompt.dart';
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
/// Batem models as a grid of big thumbnails per jaw. One tap picks a model
/// (a tap on a picked one removes it); a check marks the picked ones.
class BatemModelGrid extends StatelessWidget {
  const BatemModelGrid({
    super.key,
    required this.selectedIndexes,
    required this.onSelect,
  });

  final Set<int> selectedIndexes;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    Widget section(String label, List<ShapeLibraryItem> items, int start) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(2, 6, 2, 10), child: SectionLabel(label)),
            LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 300 ? 2 : 1;
                final w = (box.maxWidth - (cols - 1) * 10) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      SizedBox(
                        width: w,
                        child: _ModelTile(
                          key: ValueKey('batem-${items[i].id}'),
                          item: items[i],
                          selected: selectedIndexes.contains(start + i),
                          onTap: () => onSelect(start + i),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
    return ListView(
      primary: false,
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        section(loc.smileUpperJaw, ShapeLibrary.items, 0),
        const SizedBox(height: 14),
        section(loc.smileLowerJaw, ShapeLibrary.lowerArchItems, ShapeLibrary.items.length),
      ],
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({super.key, required this.item, required this.selected, required this.onTap});

  final ShapeLibraryItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      builder: (_, _) => AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected ? AppColors.dentalBlue.withValues(alpha: 0.10) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.dentalBlue : AppColors.border.withValues(alpha: 0.6),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ColoredBox(
                color: const Color(0xFF0F1724),
                child: SizedBox(
                  height: 84,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(padding: const EdgeInsets.all(8), child: ShapeToothImage(item: item, fit: BoxFit.contain)),
                      if (selected)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(Icons.check_circle, color: AppColors.dentalBlue, size: 22),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              shapeLabel(context, item),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppFonts.style(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.dentalBlue : AppColors.navy,
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
  /// Right panel: 0 = Models, 1 = Adjust.
  int _railTab = 0;

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
    widget.patientSession.cases.addListener(_onCase);
    _bootstrap();
  }

  @override
  void dispose() {
    widget.patientSession.cases.removeListener(_onCase);
    _fsController.dispose();
    super.dispose();
  }

  void _onCase() {
    if (mounted) setState(() {});
  }

  /// Server case for the selected patient (locked → replace, not delete).
  CaseInfo? get _caseInfo =>
      widget.patientSession.cases.of(_patient == null ? null : _pid(_patient!));

  /// Labs review only: no photo / save / delete (server returns 403).
  /// Labs view; while reviewing they edit too, which saves as a suggestion.
  bool get _readOnly => widget.api.isLaboratory && !(_caseInfo?.canSuggest ?? false);

  /// Saved smile the next new save stands in for (locked case).
  String? _replacingId;

  void _refreshCase() {
    final p = _patient;
    if (p != null) widget.patientSession.cases.refresh(_pid(p));
  }

  /// Locked case: start a new smile on a new photo; saving it replaces [item].
  Future<void> _replaceSaved(Map<String, dynamic> item) async {
    setState(() {
      _replacingId = '${item['id']}';
      _smileId = null;
      _photoBytes = null;
      _basePhotoId = null;
      _pendingOverlay = null;
      _dirty = false;
      _status = AppLocalizations.of(context).tr('case.replacingSmile');
    });
    await _pickPhoto();
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
    _replacingId = null;
    _refreshCase();
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
    if (_readOnly) return;
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
        _status = AppLocalizations.of(context).trp('sh.sel', {'n': shapeLabel(context, item)});
        _showOverlay = true;
      }
      _dirty = true;
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
    if (_saving || _readOnly) return;
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
    // Completed case: saving reopens it; ask first.
    if (!await confirmCaseChange(context, _caseInfo) || !mounted) return;
    final replacing = _smileId == null ? _replacingId : null;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.saveSmilePreview(
        replaces: replacing,
        patientId: _pid(patient),
        smileId: _smileId,
        composite: await _renderComposite(canvas),
        baseBytes: _basePhotoId == null ? _photoBytes : null,
        baseFilename: _baseFilename,
        basePhotoId: _basePhotoId,
        overlay: _overlayJson(canvas),
      );
      _refreshCase();
      if (!mounted) return;
      final id = '${saved['id'] ?? ''}';
      setState(() {
        if (replacing != null) {
          // The server removed the replaced smile.
          _smileItems = [for (final r in _smileItems) if ('${r['id']}' != replacing) r];
          _replacingId = null;
        }
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
        AppLocalizations.of(context).trp('sp.saved', {'s': shapes}),
      );
      await maybePromptSubmitToLab(
        context,
        cases: widget.patientSession.cases,
        patientId: _pid(patient),
      );
    } catch (e) {
      final msg = friendlyError(e);
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                          CaseRejectionBanner(
                            info: _caseInfo,
                            margin: const EdgeInsets.only(top: 12),
                            store: widget.patientSession.cases,
                            patientId: _patient == null ? null : _pid(_patient!),
                            api: widget.api,
                          ),
                          if (_patient != null)
                            CaseFeedbackBar(
                            key: ValueKey('fb-smile-${_pid(_patient!)}'),
                            store: widget.patientSession.cases,
                            patientId: _pid(_patient!),
                            item: 'smile',
                            margin: const EdgeInsets.only(top: 12),
                          ),
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
                        // Fullscreen shrinks this column to 0: keep the
                        // rail at its own width and clip it instead of
                        // squeezing (and overflowing) its rows / segments.
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final minW = portrait ? 260.0 : 300.0;
                            final w = box.maxWidth < minW ? minW : box.maxWidth;
                            return ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.topLeft,
                                minWidth: w,
                                maxWidth: w,
                                child: _buildRail(),
                              ),
                            );
                          },
                        ),
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
      _refreshCase();
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
                        if (!widget.api.isLaboratory) // labs never delete
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            tooltip: _caseInfo?.locked == true
                                ? AppLocalizations.of(context).tr('case.replace')
                                : AppLocalizations.of(context).tr('sp.delTip'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            onPressed: _saving
                                ? null
                                : () => _caseInfo?.locked == true ? _replaceSaved(item) : _deleteSaved(item),
                            icon: CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                _caseInfo?.locked == true ? Icons.swap_horiz_rounded : Icons.close,
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
      subtitleAsInfo: true,
      actions: [
        PatientPickerButton(
          patients: _patients,
          selected: _patient,
          onSelect: _selectPatient,
          onAdd: _openNewPatientPage,
          onRefresh: _reloadPatients,
          enabled: !_saving,
          emptyHint: AppLocalizations.of(context).tr('sp.noPat'),
        ),
        if (!_readOnly)
        OutlinedButton.icon(
          onPressed: _saving || _patient == null ? null : _pickPhoto,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text(_photoBytes == null ? AppLocalizations.of(context).smileLoadPhoto : AppLocalizations.of(context).smileChangePhoto),
        ),
        if (!_readOnly)
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
                    : AppLocalizations.of(context).save,
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
                  if (!_readOnly)
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
        if (_fsController.value > 0.5)
          Positioned(
            left: 12,
            top: 12,
            child: _StageIconBtn(
              icon: Icons.close_rounded,
              tip: AppLocalizations.of(context).tr('sp.exitFs'),
              onTap: _toggleFullscreen,
            ),
          )
        else
          Positioned(
            right: 12,
            bottom: 12,
            child: _StageIconBtn(
              icon: Icons.fullscreen,
              tip: AppLocalizations.of(context).tr('sp.fs'),
              onTap: _toggleFullscreen,
            ),
          ),
      ],
    );
  }

  /// Compare / layers / center / reset — plus close when fullscreen.
  Widget _stageToolbar(Size canvas, {required bool fullscreen}) {
    final loc = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fullscreen) ...[
          _StageIconBtn(
            icon: Icons.close_rounded,
            tip: loc.tr('sp.exitFs'),
            onTap: _toggleFullscreen,
          ),
          const SizedBox(width: 6),
        ],
        _StageIconBtn(
          icon: _comparing ? Icons.visibility_off : Icons.visibility,
          tip: loc.tr('sp.compare'),
          onTapDown: () => setState(() => _comparing = true),
          onTapUp: () => setState(() => _comparing = false),
          onTapCancel: () => setState(() => _comparing = false),
        ),
        const SizedBox(width: 6),
        _StageIconBtn(
          icon: _showOverlay ? Icons.layers_outlined : Icons.layers_clear_outlined,
          tip: _showOverlay ? loc.tr('sp.hideOv') : loc.tr('sp.showOv'),
          onTap: () => setState(() => _showOverlay = !_showOverlay),
        ),
        const SizedBox(width: 6),
        _StageIconBtn(
          icon: Icons.center_focus_strong,
          tip: loc.smileCenterShape,
          onTap: () => _centerIn(canvas),
        ),
        const SizedBox(width: 6),
        _StageIconBtn(
          icon: Icons.refresh,
          tip: loc.smileResetPlacement,
          onTap: () => _resetTransform(canvas),
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
                  if (_fsController.value > 0.5) ...[
                    _stageToolbar(canvas, fullscreen: true),
                    const SizedBox(height: 8),
                  ],
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
            if (_fsController.value <= 0.5)
              Positioned(
                right: 12,
                top: 12,
                child: _stageToolbar(canvas, fullscreen: false),
              ),
            Positioned(
              left: 12,
              right: _fsController.value > 0.5 ? 12 : 56,
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
            if (_fsController.value <= 0.5)
              Positioned(
                right: 12,
                bottom: 12,
                child: _StageIconBtn(
                  icon: Icons.fullscreen,
                  tip: AppLocalizations.of(context).tr('sp.fs'),
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

  Widget _buildRail() {
    final loc = AppLocalizations.of(context);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Two clear modes, each with the whole panel.
          SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _railTab,
              backgroundColor: AppColors.inset.withValues(alpha: 0.7),
              thumbColor: Colors.white,
              children: {
                0: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${loc.smileBatemModels} (${_chosen.length}/2)',
                        maxLines: 1,
                        style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  ),
                ),
                1: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(loc.smilePlacement,
                        maxLines: 1,
                        style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  ),
                ),
              },
              onValueChanged: (v) => setState(() => _railTab = v ?? 0),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AppSwitcher(
              child: KeyedSubtree(
                key: ValueKey(_railTab),
                child: _railTab == 0
                    ? BatemModelGrid(selectedIndexes: {?_upperIndex, ?_lowerIndex}, onSelect: _selectShape)
                    : _adjustTab(loc),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Placement of the active jaw's model: big sliders with − / + steps,
  /// a move pad, guides and reset.
  Widget _adjustTab(AppLocalizations loc) {
    if (_chosen.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sentiment_satisfied_alt_outlined, size: 40, color: AppColors.muted),
              const SizedBox(height: 10),
              Text(loc.tr('smile.pickFirst'),
                  textAlign: TextAlign.center, style: AppFonts.style(fontSize: 14, color: AppColors.muted, height: 1.4)),
              const SizedBox(height: 12),
              AppButtons.secondary(onPressed: () => setState(() => _railTab = 0), label: loc.smileBatemModels, compact: true),
            ],
          ),
        ),
      );
    }
    final enabled = _photoBytes != null;
    void set(void Function() f) => setState(() {
          f();
          _dirty = true;
        });
    return ListView(
      primary: false,
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        if (_upperIndex != null && _lowerIndex != null) ...[
          SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<bool>(
              groupValue: _lowerActive,
              children: {
                false: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(loc.smileUpperJaw, maxLines: 1)),
                ),
                true: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(loc.smileLowerJaw, maxLines: 1)),
                ),
              },
              onValueChanged: (v) => setState(() => _lowerActive = v ?? false),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            if (_selected != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ColoredBox(
                  color: const Color(0xFF0F1724),
                  child: SizedBox(width: 52, height: 40, child: ShapeToothImage(item: _selected!, fit: BoxFit.contain)),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_activeLabel,
                  style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dentalBlue)),
            ),
          ],
        ),
        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(loc.tr('smile.photoFirst'), style: AppFonts.style(fontSize: 12.5, color: AppColors.muted)),
          ),
        const SizedBox(height: 8),
        _AdjustRow(
          label: loc.smileSize,
          display: '×${_scale.toStringAsFixed(2)}',
          value: _scale, min: 0.15, max: 8.0, step: 0.05, enabled: enabled,
          onChanged: (v) => set(() => _scale = v),
        ),
        _AdjustRow(
          label: loc.smileWidth,
          display: '×${_width.toStringAsFixed(2)}',
          value: _width, min: 0.4, max: 2.4, step: 0.05, enabled: enabled,
          onChanged: (v) => set(() => _width = v),
        ),
        _AdjustRow(
          label: loc.smileHeight,
          display: '×${_height.toStringAsFixed(2)}',
          value: _height, min: 0.4, max: 2.4, step: 0.05, enabled: enabled,
          onChanged: (v) => set(() => _height = v),
        ),
        _AdjustRow(
          label: loc.smileRotate,
          display: '${_rotation.toStringAsFixed(0)}°',
          value: _rotation, min: -35, max: 35, step: 1, enabled: enabled,
          onChanged: (v) => set(() => _rotation = v),
        ),
        _AdjustRow(
          label: loc.smileBlend,
          display: '${(_opacity * 100).round()}%',
          value: _opacity, min: 0.25, max: 1.0, step: 0.05, enabled: enabled,
          onChanged: (v) => set(() => _opacity = v),
        ),
        const SizedBox(height: 6),
        Text(loc.smileNudge, style: AppFonts.style(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.navy)),
        const SizedBox(height: 8),
        // Cross-shaped pad with big targets.
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NudgeBtn(icon: Icons.keyboard_arrow_up, onTap: enabled ? () => _nudge(0, -4) : null),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NudgeBtn(icon: Icons.keyboard_arrow_left, onTap: enabled ? () => _nudge(-4, 0) : null),
                    const SizedBox(width: 52),
                    _NudgeBtn(icon: Icons.keyboard_arrow_right, onTap: enabled ? () => _nudge(4, 0) : null),
                  ],
                ),
                _NudgeBtn(icon: Icons.keyboard_arrow_down, onTap: enabled ? () => _nudge(0, 4) : null),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(loc.smileGuides, style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy)),
            ),
            CupertinoSwitch(value: _showGuides, onChanged: (v) => setState(() => _showGuides = v)),
          ],
        ),
        const SizedBox(height: 10),
        AppButtons.secondary(
          onPressed: _lastCanvas == null || !enabled ? null : () => _resetTransform(_lastCanvas!),
          icon: Icons.restart_alt_rounded,
          label: loc.shadeReset,
        ),
      ],
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: AppColors.inset,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, size: 28, color: onTap == null ? AppColors.muted : AppColors.navy),
          ),
        ),
      ),
    );
  }
}

/// One placement control: label + value, then − [big slider] +.
class _AdjustRow extends StatelessWidget {
  const _AdjustRow({
    required this.label,
    required this.display,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String display;
  final double value;
  final double min;
  final double max;
  final double step;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max);
    void bump(double d) => onChanged((v + d).clamp(min, max).toDouble());
    Widget stepBtn(IconData icon, double d) => Material(
          color: AppColors.inset,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: enabled ? () => bump(d) : null,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 22, color: enabled ? AppColors.navy : AppColors.muted),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: AppFonts.style(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.navy)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(999)),
                child: Text(display, style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              stepBtn(Icons.remove_rounded, -step),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                  ),
                  child: Slider(value: v, min: min, max: max, onChanged: enabled ? onChanged : null),
                ),
              ),
              stepBtn(Icons.add_rounded, step),
            ],
          ),
        ],
      ),
    );
  }
}

/// Localized display name of a library shape (keyed by its English label).
String shapeLabel(BuildContext context, ShapeLibraryItem it) =>
    AppLocalizations.of(context).tr('shape.${it.label}');

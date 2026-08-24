import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/images/orient_image.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/patient_picker.dart';
import '../../core/widgets/ui_kit.dart';
import 'shade_action_bar.dart';
import 'shade_override_pane.dart';
import 'shade_photo_pane.dart';
import 'shade_result_pane.dart';
import 'shade_session_pane.dart';
import 'shade_shared.dart';
import 'tooth_overlay.dart';

class ShadePage extends StatefulWidget {
  const ShadePage({
    super.key,
    required this.api,
    required this.patientSession,
    this.active = true,
  });

  final ApiClient api;
  final PatientSession patientSession;
  final bool active;

  @override
  State<ShadePage> createState() => _ShadePageState();
}

class _ShadePageState extends State<ShadePage> {
  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _case;

  String _selected = '—';
  String _detected = '—';
  double _confidence = 0.0;
  String? _finalShade;
  bool _busy = false;
  bool _saving = false;
  bool _loading = true;
  bool _sessionCollapsed = false;
  /// Keep session open in portrait after the user explicitly expands it.
  bool _sessionPinnedOpen = false;
  String? _saveStatus;
  String? _error;
  Uint8List? _previewBytes;
  String _previewFilename = 'tooth.jpg';
  Size _previewImageSize = Size.zero;
  List<Map<String, dynamic>> _topMatches = [];
  /// Aggregated across all teeth/zones for the Result card (not zone-similar).
  List<Map<String, dynamic>> _overallTopMatches = [];
  List<Map<String, dynamic>> _history = [];
  /// All saved shade-detection images for the selected patient (full history).
  List<Map<String, dynamic>> _allShadeItems = [];
  String? _shadeDetectionId;

  // Per-tooth / per-zone analysis (added onto existing UI)
  List<Map<String, dynamic>> _teeth = [];
  /// Full AI detection set — kept across isolate so other teeth stay tappable.
  List<Map<String, dynamic>> _teethMemory = [];
  /// Snapshots taken just before a tooth delete — overlay Undo restores them.
  final List<
      ({
        List<Map<String, dynamic>> teeth,
        int? selected,
        int? isolated,
      })> _teethUndo = [];
  /// Triple-tap focus: Result pane shows this tooth; overlay keeps all.
  int? _isolatedToothIndex;
  int? _selectedToothIndex;
  String _focusZone = 'middle';
  Size _analysisImageSize = Size.zero;
  /// Shade picked in Manual Override but not yet committed via zone Override.
  String? _pendingShade;
  /// Result-card overall Top match pick — Save override without zone Override.
  bool _overallShadePick = false;

  // Manual outline nudge (dentist adjusts auto edges slightly)
  bool _editOutlineMode = false;
  /// Session collapse to restore when outline edit ends.
  bool? _sessionCollapsedBeforeEdit;
  List<List<double>>? _editOutline;
  List<List<double>>? _editOutlineBackup;
  List<double>? _editBulges;
  List<double>? _editBulgesBackup;
  int? _activeHandleIndex;
  int? _activeEdgeIndex;
  bool _movingOutline = false;
  Offset? _bodyDragLast;
  /// Loupe follows this without setState — Image.memory stays mounted.
  final _magnifierFocal = ValueNotifier<Offset?>(null);
  Size? _magnifierViewSize;
  final _outlineHistory = OutlineEditHistory();
  OutlineSnap? _outlineBeforeDrag;
  /// Ticks on every handle move so only the overlay and loupe repaint —
  /// a page-level setState per pointer move rebuilds the whole shade screen.
  final _dragTick = ValueNotifier<int>(0);
  final _photoTransformController = TransformationController();

  Map<String, dynamic>? get _selectedTooth {
    if (_selectedToothIndex == null) return null;
    for (final t in _teeth) {
      if ((t['tooth_index'] as num?)?.toInt() == _selectedToothIndex) return t;
    }
    return null;
  }

  List<Map<String, dynamic>> _cloneTeeth(List<Map<String, dynamic>> src) =>
      src.map((t) => Map<String, dynamic>.from(t)).toList();

  void _rememberTeeth() {
    _teethMemory = _cloneTeeth(_teeth);
  }

  /// Result list: all teeth after detect; only the focused one after triple-tap.
  List<Map<String, dynamic>> get _teethForResultPane {
    final iso = _isolatedToothIndex;
    if (iso == null) return _teeth;
    return _teeth
        .where((t) => (t['tooth_index'] as num?)?.toInt() == iso)
        .toList();
  }

  bool _hasToothIndex(int index) =>
      _teeth.any((t) => (t['tooth_index'] as num?)?.toInt() == index);

  /// Bring back the full detection set from memory (e.g. after isolate).
  void _ensureTeethFromMemory({int? preferIndex}) {
    if (_teethMemory.isEmpty) return;
    final needRestore = preferIndex != null
        ? !_hasToothIndex(preferIndex)
        : _teeth.length < _teethMemory.length;
    if (!needRestore) return;
    _teeth = _cloneTeeth(_teethMemory);
  }

  Map<String, dynamic>? _zoneOf(Map<String, dynamic> tooth, String name) {
    final zones = tooth['zones'];
    if (zones is! Map) return null;
    final z = zones[name];
    if (z is Map<String, dynamic>) return z;
    if (z is Map) return z.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  String? _zoneEffective(Map<String, dynamic>? zone) {
    if (zone == null) return null;
    return (zone['override_shade'] as String?) ?? (zone['detected_shade'] as String?);
  }

  bool _zoneOverridden(Map<String, dynamic>? zone) =>
      zone != null && zone['override_shade'] != null;

  int? _currentCaseId() {
    final id = _case?['id'];
    return id is num ? id.toInt() : null;
  }

  String? _sessionKey() {
    final caseId = _currentCaseId();
    if (caseId != null) return 'case-$caseId';
    final shadeId = _shadeDetectionId?.trim() ?? '';
    if (shadeId.isNotEmpty) return 'shade-$shadeId';
    final pid = _patient == null ? '' : _pid(_patient!);
    if (pid.isEmpty) return null;
    return 'patient-$pid';
  }

  int _historyIndexForKey(String key) {
    return _history.indexWhere((h) => '${h['session_key'] ?? ''}' == key);
  }

  int _historyIndexForCase(int caseId) {
    final byKey = _historyIndexForKey('case-$caseId');
    if (byKey >= 0) return byKey;
    return _history.indexWhere(
      (h) => (h['case_id'] as num?)?.toInt() == caseId,
    );
  }

  bool _teethHaveAnyOverride() {
    for (final t in _teeth) {
      for (final z in kShadeZones) {
        if (_zoneOverridden(_zoneOf(t, z))) return true;
      }
    }
    return false;
  }

  Map<String, dynamic> _workspaceSnapshot() {
    return {
      'preview_bytes': _previewBytes == null
          ? null
          : Uint8List.fromList(_previewBytes!),
      'preview_filename': _previewFilename,
      'preview_image_width': _previewImageSize.width,
      'preview_image_height': _previewImageSize.height,
      'teeth': cloneShadeMaps(_teeth),
      'teeth_memory': cloneShadeMaps(
        _teethMemory.isEmpty ? _teeth : _teethMemory,
      ),
      'isolated_tooth_index': _isolatedToothIndex,
      'selected_tooth_index': _selectedToothIndex,
      'focus_zone': _focusZone,
      'analysis_image_width': _analysisImageSize.width,
      'analysis_image_height': _analysisImageSize.height,
      'detected': _detected,
      'selected': _selected,
      'confidence': _confidence,
      'top_matches': cloneShadeMaps(_topMatches),
      'overall_top_matches': cloneShadeMaps(_overallTopMatches),
      'final_shade': _finalShade,
      'pending_shade': _pendingShade,
      'overall_shade_pick': _overallShadePick,
    };
  }

  Map<String, dynamic> _sessionEntryFromCurrent({
    Object? savedId,
    String? summaryShade,
    bool? hasOverride,
  }) {
    final caseId = _currentCaseId();
    final teethSnapshots = _teeth.map((t) {
      final zones = <String, String?>{};
      for (final z in kShadeZones) {
        zones[z] = _zoneEffective(_zoneOf(t, z));
      }
      return {
        'tooth_index': t['tooth_index'],
        'label': t['label'] ??
            'Tooth ${((t['tooth_index'] as num?)?.toInt() ?? 0) + 1}',
        'zones': zones,
        'rejected': t['rejected'] == true,
      };
    }).toList();

    String? shade = summaryShade;
    if (shade == null || shade.isEmpty) {
      final tooth =
          _selectedTooth ?? (_teeth.isNotEmpty ? _teeth.first : null);
      if (tooth != null) {
        shade = _zoneEffective(_zoneOf(tooth, 'middle')) ??
            _zoneEffective(_zoneOf(tooth, _focusZone));
      }
      shade ??= _selected == '—' ? null : _selected;
    }

    return {
      'id': savedId,
      'session_key': _sessionKey(),
      'case_id': caseId,
      'patient_id': _patient == null ? null : _pid(_patient!),
      'name':
          '${_patient?['first_name'] ?? ''} ${_patient?['last_name'] ?? ''}'
              .trim(),
      'shade': shade ?? '—',
      'conf': _confidence,
      'override': hasOverride ?? _teethHaveAnyOverride(),
      'is_analysis': _teeth.isNotEmpty,
      'tooth_count': _teeth.length,
      'teeth': teethSnapshots,
      'patient': _patient == null ? null : Map<String, dynamic>.from(_patient!),
      'case': _case == null ? null : Map<String, dynamic>.from(_case!),
      'workspace': _workspaceSnapshot(),
    };
  }

  void _restoreWorkspace(Map<String, dynamic> ws) {
    final bytes = ws['preview_bytes'];
    _previewBytes = bytes is Uint8List
        ? Uint8List.fromList(bytes)
        : (bytes is List ? Uint8List.fromList(bytes.cast<int>()) : null);
    _previewFilename = ws['preview_filename'] as String? ?? 'tooth.jpg';
    final pw = (ws['preview_image_width'] as num?)?.toDouble() ?? 0;
    final ph = (ws['preview_image_height'] as num?)?.toDouble() ?? 0;
    _previewImageSize = (pw > 0 && ph > 0)
        ? Size(pw, ph)
        : Size.zero;
    final teethRaw = ws['teeth'];
    _teeth = teethRaw is List
        ? _parseTeeth(teethRaw)
        : <Map<String, dynamic>>[];
    final memRaw = ws['teeth_memory'];
    _teethMemory = memRaw is List
        ? _parseTeeth(memRaw)
        : _cloneTeeth(_teeth);
    _isolatedToothIndex = (ws['isolated_tooth_index'] as num?)?.toInt();
    _selectedToothIndex = (ws['selected_tooth_index'] as num?)?.toInt();
    _focusZone = ws['focus_zone'] as String? ?? 'middle';
    final iw = (ws['analysis_image_width'] as num?)?.toDouble() ?? 0;
    final ih = (ws['analysis_image_height'] as num?)?.toDouble() ?? 0;
    _analysisImageSize = (iw > 0 && ih > 0) ? Size(iw, ih) : Size.zero;
    _detected = ws['detected'] as String? ?? '—';
    _selected = ws['selected'] as String? ?? '—';
    _confidence = (ws['confidence'] as num?)?.toDouble() ?? 0;
    final tops = ws['top_matches'];
    _topMatches = tops is List
        ? tops
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];
    final overall = ws['overall_top_matches'];
    _overallTopMatches = overall is List
        ? overall
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];
    _finalShade = ws['final_shade'] as String?;
    _pendingShade = ws['pending_shade'] as String?;
    _overallShadePick = ws['overall_shade_pick'] == true;
    _exitOutlineEdit(clearStatus: false);
    _photoTransformController.value = Matrix4.identity();
  }

  void _openHistoryAt(int index) {
    if (index < 0 || index >= _history.length) return;
    final entry = _history[index];
    final targetKey = '${entry['session_key'] ?? ''}';
    final targetCaseId = (entry['case_id'] as num?)?.toInt();
    if (targetKey.isEmpty && targetCaseId == null) return;
    final currentKey = _sessionKey();
    if (targetKey.isNotEmpty && targetKey == currentKey) return;
    if (targetKey.isEmpty &&
        targetCaseId != null &&
        _currentCaseId() == targetCaseId) {
      return;
    }

    setState(() {
      // Keep the leave-behind visit editable when coming back.
      if (_sessionKey() != null &&
          (_previewBytes != null ||
              _teeth.isNotEmpty ||
              (_finalShade != null && _finalShade!.isNotEmpty) ||
              (_selected != '—' && _selected.isNotEmpty))) {
        _upsertSessionEntry();
      }

      final patient = entry['patient'];
      final caseRow = entry['case'];
      if (patient is Map) {
        _patient = Map<String, dynamic>.from(patient);
      }
      if (caseRow is Map) {
        _case = Map<String, dynamic>.from(caseRow);
      } else if (targetCaseId != null) {
        _case = {
          'id': targetCaseId,
          'patient_id': entry['patient_id'],
          'status': 'in_progress',
        };
      }
      final shadeId = '${entry['shade_detection_id'] ?? entry['id'] ?? ''}';
      _shadeDetectionId = shadeId.startsWith('shade-')
          ? shadeId.substring(6)
          : (targetKey.startsWith('shade-') ? targetKey.substring(6) : shadeId);

      final ws = entry['workspace'];
      if (ws is Map) {
        _restoreWorkspace(Map<String, dynamic>.from(ws));
      } else {
        _previewBytes = null;
        _previewImageSize = Size.zero;
        _teeth = [];
        _teethMemory = [];
        _isolatedToothIndex = null;
        _selectedToothIndex = null;
        _detected = '—';
        _selected = entry['shade'] as String? ?? '—';
        _confidence = (entry['conf'] as num?)?.toDouble() ?? 0;
        _topMatches = [];
        _overallTopMatches = [];
        _finalShade = entry['shade'] as String?;
        _pendingShade = null;
        _overallShadePick = false;
        _exitOutlineEdit(clearStatus: false);
        _photoTransformController.value = Matrix4.identity();
      }

      _error = null;
      _saveStatus =
          'Editing ${entry['name'] ?? 'patient'} · ${entry['shade'] ?? '—'}';
      _history = [
        entry,
        for (final h in _history)
          if (!identical(h, entry)) h,
      ];
    });
    AppHaptics.selection();
  }

  /// Replace-or-insert the Session row for the active visit.
  void _upsertSessionEntry({
    Object? savedId,
    String? summaryShade,
    bool? hasOverride,
    bool onlyIfExists = false,
  }) {
    final key = _sessionKey();
    if (key == null) return;
    var existing = _historyIndexForKey(key);
    if (existing < 0) {
      final caseId = _currentCaseId();
      if (caseId != null) existing = _historyIndexForCase(caseId);
    }
    if (onlyIfExists && existing < 0) return;

    final prevId = existing >= 0 ? _history[existing]['id'] : null;
    final entry = _sessionEntryFromCurrent(
      savedId: savedId ?? prevId,
      summaryShade: summaryShade,
      hasOverride: hasOverride,
    );
    entry['shade_detection_id'] = _shadeDetectionId;
    _history = [
      entry,
      for (var i = 0; i < _history.length; i++)
        if (i != existing) _history[i],
    ];
  }

  List<Map<String, dynamic>> _parseTeeth(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final zones = m['zones'];
      if (zones is Map) {
        m['zones'] = {
          for (final entry in zones.entries)
            entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
        };
      }
      return m;
    }).toList();
  }

  /// Result hero shade: override wins over AI detected.
  String _resultDisplayShade() {
    final tooth = _selectedTooth;
    if (tooth == null) return _detected;
    final zone = _zoneOf(tooth, _focusZone) ?? _zoneOf(tooth, 'middle');
    return _zoneEffective(zone) ?? _detected;
  }

  /// Sync Result / Similar shades / selection from the focused tooth+zone.
  void _syncUiFromSelection({bool resetSelectedToDetected = true}) {
    final tooth = _selectedTooth;
    if (tooth == null) {
      _detected = '—';
      _confidence = 0;
      _topMatches = [];
      if (resetSelectedToDetected) _selected = '—';
      _recomputeOverallTopMatches();
      return;
    }
    final zone = _zoneOf(tooth, _focusZone) ?? _zoneOf(tooth, 'middle');
    final detected = zone?['detected_shade'] as String?;
    final effective = _zoneEffective(zone);
    _detected = detected ?? '—';
    _confidence = _shadeMatchConfidence(zone, tooth);
    if (resetSelectedToDetected) {
      _selected = effective ?? detected ?? '—';
    }
    final raw = zone?['top_matches'];
    if (raw is List) {
      _topMatches = raw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .cast<Map<String, dynamic>>()
          .toList();
    } else {
      _topMatches = [];
    }
    _recomputeOverallTopMatches();
  }

  /// ΔE of zone sample vs effective shade (override or detected).
  double? _zoneMatchDeltaE(Map<String, dynamic>? zone) {
    if (zone == null) return null;
    final effective = _zoneEffective(zone);
    if (effective == null) return null;
    final sampled = zone['sampled_lab'];
    if (sampled is List && sampled.length >= 3) {
      final de = deltaEVsShade(
        [sampled[0] as num, sampled[1] as num, sampled[2] as num],
        effective,
      );
      if (de != null) return de;
    }
    final detected = zone['detected_shade'] as String?;
    if (effective == detected) {
      return (zone['delta_e_2000'] as num?)?.toDouble();
    }
    final tops = zone['top_matches'];
    if (tops is List) {
      for (final m in tops) {
        if (m is Map && m['shade'] == effective) {
          return (m['delta_e_2000'] as num?)?.toDouble();
        }
      }
    }
    return null;
  }

  /// Shade-match confidence from CIEDE2000 (Result %), not segmentation fill.
  double _shadeMatchConfidence(
    Map<String, dynamic>? zone,
    Map<String, dynamic>? tooth,
  ) {
    final de = _zoneMatchDeltaE(zone);
    if (de != null) return confidenceFromDeltaE(de);
    return (tooth?['confidence'] as num?)?.toDouble() ?? 0;
  }

  /// Overall Top matches: mode of effective shades (middle×3), ΔE tie-break only.
  void _recomputeOverallTopMatches() {
    final weight = <String, double>{};
    final bestDe = <String, double>{};

    void bump(String? shade, double w, double? de) {
      if (shade == null || shade.isEmpty || shade == '—') return;
      weight[shade] = (weight[shade] ?? 0) + w;
      if (de != null) {
        final prev = bestDe[shade];
        if (prev == null || de < prev) bestDe[shade] = de;
      }
    }

    for (final t in _teeth) {
      if (t['rejected'] == true) continue;
      for (final zName in kShadeZones) {
        final z = _zoneOf(t, zName);
        if (z == null) continue;
        final effective = _zoneEffective(z);
        if (effective == null) continue;
        final zoneW = zName == 'middle' ? 3.0 : 1.0;
        bump(effective, zoneW, _zoneMatchDeltaE(z));
      }
    }

    final ranked = weight.keys.toList()
      ..sort((a, b) {
        final c = (weight[b] ?? 0).compareTo(weight[a] ?? 0);
        if (c != 0) return c;
        return (bestDe[a] ?? 99).compareTo(bestDe[b] ?? 99);
      });

    _overallTopMatches = [
      for (final s in ranked.take(5))
        {
          'shade': s,
          if (bestDe[s] != null)
            'delta_e_2000': double.parse(bestDe[s]!.toStringAsFixed(2)),
        },
    ];
  }

  void _ensureToothFocused() {
    if (_selectedToothIndex != null || _teeth.isEmpty) return;
    Map<String, dynamic>? first;
    for (final t in _teeth) {
      if (t['rejected'] != true) {
        first = t;
        break;
      }
    }
    first ??= _teeth.first;
    _selectedToothIndex = (first['tooth_index'] as num).toInt();
    _focusZone = 'middle';
    _syncUiFromSelection(resetSelectedToDetected: false);
  }

  void _selectTooth(int index, {String? zone}) {
    if (_editOutlineMode) return; // finish or cancel edit first
    final switchingTooth = _selectedToothIndex != index;
    final nextZone = zone ?? (switchingTooth ? 'middle' : _focusZone);
    final same = !switchingTooth && nextZone == _focusZone;
    setState(() {
      _selectedToothIndex = index;
      // If already in triple-tap focus mode, move focus with the selection.
      if (_isolatedToothIndex != null) {
        _isolatedToothIndex = index;
      }
      _focusZone = nextZone;
      if (!same) {
        _pendingShade = null;
        _overallShadePick = false;
      }
      _syncUiFromSelection(resetSelectedToDetected: _pendingShade == null);
      if (_pendingShade != null) _selected = _pendingShade!;
      _saveStatus = null;
    });
    if (switchingTooth) AppHaptics.selection();
  }

  // Triple-tap tracking on the photo overlay (same tooth within window).
  int? _toothTapIndex;
  int _toothTapCount = 0;
  DateTime? _toothTapAt;

  /// Single tap selects (restores full set from memory); triple-tap isolates focus.
  void _onToothTap(int index) {
    if (_editOutlineMode || _busy) return;
    final now = DateTime.now();
    if (_toothTapIndex == index &&
        _toothTapAt != null &&
        now.difference(_toothTapAt!) < const Duration(milliseconds: 500)) {
      _toothTapCount += 1;
    } else {
      _toothTapCount = 1;
    }
    _toothTapIndex = index;
    _toothTapAt = now;

    if (_toothTapCount >= 3) {
      _toothTapCount = 0;
      _isolateTooth(index);
      return;
    }

    setState(() {
      _ensureTeethFromMemory(preferIndex: index);
      // Stay in isolate focus mode but move it to the newly tapped tooth.
      if (_isolatedToothIndex != null) {
        _isolatedToothIndex = index;
      }
    });
    _selectTooth(index);
  }

  /// Focus Result details on [index]; keep every detected tooth in memory/overlay.
  void _isolateTooth(int index) {
    if (_editOutlineMode || _busy) return;
    setState(() {
      if (_teethMemory.isEmpty) _rememberTeeth();
      _ensureTeethFromMemory(preferIndex: index);
    });
    if (!_hasToothIndex(index)) return;

    final label = () {
      for (final t in _teeth) {
        if ((t['tooth_index'] as num?)?.toInt() == index) {
          return t['label']?.toString() ?? 'Tooth ${index + 1}';
        }
      }
      return 'Tooth ${index + 1}';
    }();

    setState(() {
      _isolatedToothIndex = index;
      _selectedToothIndex = index;
      _focusZone = 'middle';
      _pendingShade = null;
      _overallShadePick = false;
      _syncUiFromSelection(resetSelectedToDetected: true);
      _saveStatus =
          'Focused on $label — tap another tooth to switch (all kept in memory).';
      _upsertSessionEntry(onlyIfExists: true);
    });
    AppHaptics.success();
    _toast(
      '$label focused — tap any other tooth to move there',
      bg: AppColors.navy,
    );
  }


  void _toast(String msg, {Color? bg}) {
    if (!mounted) return;
    if (bg == AppColors.success) {
      AppSnackBars.success(context, msg);
    } else if (bg == AppColors.danger) {
      AppSnackBars.error(context, msg);
    } else {
      AppSnackBars.info(context, msg);
    }
  }

  void _commitPendingOverride({required int index, required String zone}) {
    final shade = _pendingShade;
    if (shade == null || shade == '—' || !kAllowedShades.contains(shade)) {
      _toast('Choose a shade first, then tap Override');
      return;
    }
    setState(() {
      _selectedToothIndex = index;
      _focusZone = zone;
      final tooth = _selectedTooth;
      final z = tooth == null ? null : _zoneOf(tooth, zone);
      if (z != null) {
        final detected = z['detected_shade'] as String?;
        z['override_shade'] =
            (detected != null && shade == detected) ? null : shade;
      }
      _selected = shade;
      _pendingShade = null;
      _overallShadePick = false;
      _syncUiFromSelection(resetSelectedToDetected: false);
      _selected = shade;
      _saveStatus = null;
    });
    _toast(
      'Tooth ${index + 1} · ${capitalizeZone(zone)} → $shade',
      bg: AppColors.success,
    );
    // Persist so Session gets the accepted match (was onlyIfExists before).
    _persist(acceptAi: false);
  }

  void _beginZoneOverride(int index, String zone) {
    if (_editOutlineMode || _busy) return;
    if (_pendingShade != null) {
      _commitPendingOverride(index: index, zone: zone);
      return;
    }
    // No pending pick — focus the zone so Manual Override targets it.
    _selectTooth(index, zone: zone);
    if (!mounted) return;
    _toast(
      'Tooth ${index + 1} · ${capitalizeZone(zone)} — choose a shade, then tap Override',
      bg: AppColors.navy,
    );
  }

  void _deleteSelectedTooth() {
    final idx = _selectedToothIndex;
    if (idx == null || _editOutlineMode) return;
    _teethUndo.add((
      teeth: _cloneTeeth(_teeth),
      selected: _selectedToothIndex,
      isolated: _isolatedToothIndex,
    ));
    final remaining = <Map<String, dynamic>>[];
    for (final t in _teeth) {
      final ti = (t['tooth_index'] as num?)?.toInt();
      if (ti == idx) continue;
      remaining.add(Map<String, dynamic>.from(t));
    }
    // Re-index left→right so T1..Tn stay contiguous after a delete.
    remaining.sort((a, b) {
      final ax = _toothSortX(a);
      final bx = _toothSortX(b);
      return ax.compareTo(bx);
    });
    for (var i = 0; i < remaining.length; i++) {
      remaining[i]['tooth_index'] = i;
      remaining[i]['label'] = 'Tooth ${i + 1}';
    }
    setState(() {
      _teeth = remaining;
      _rememberTeeth();
      if (_isolatedToothIndex == idx) {
        _isolatedToothIndex = remaining.isEmpty ? null : 0;
      } else if (_isolatedToothIndex != null) {
        // Indices were renumbered — drop isolate focus to avoid stale id.
        _isolatedToothIndex = _selectedToothIndex;
      }
      if (remaining.isEmpty) {
        _selectedToothIndex = null;
        _isolatedToothIndex = null;
        _detected = '—';
        _confidence = 0;
        _topMatches = [];
        _selected = '—';
        _saveStatus = 'Removed tooth — tap Undo to restore, or re-detect.';
      } else {
        // Prefer the neighbor that was to the right, else the new last.
        final next = idx.clamp(0, remaining.length - 1);
        _selectedToothIndex = next;
        if (_isolatedToothIndex != null) _isolatedToothIndex = next;
        _syncUiFromSelection();
        _saveStatus =
            'Removed tooth. ${remaining.length} remaining — tap Undo to restore.';
      }
      _upsertSessionEntry(onlyIfExists: true);
    });
    AppHaptics.warn();
  }

  void _undoDeletedTooth() {
    if (_teethUndo.isEmpty || _editOutlineMode) return;
    final snap = _teethUndo.removeLast();
    setState(() {
      _teeth = _cloneTeeth(snap.teeth);
      _rememberTeeth();
      _selectedToothIndex = snap.selected;
      _isolatedToothIndex = snap.isolated;
      _syncUiFromSelection();
      _saveStatus = 'Restored deleted tooth.';
      _upsertSessionEntry(onlyIfExists: true);
    });
    AppHaptics.success();
  }

  bool get _canUndo =>
      (_editOutlineMode && _outlineHistory.canUndo) ||
      (!_editOutlineMode && _teethUndo.isNotEmpty);

  void _undoFromOverlay() {
    if (_editOutlineMode) {
      _undoOutlineEdit();
      return;
    }
    _undoDeletedTooth();
  }

  Size get _overlayImageSize {
    if (_previewImageSize.width > 1 && _previewImageSize.height > 1) {
      return _previewImageSize;
    }
    return _analysisImageSize;
  }

  void _setPreviewJpeg(Uint8List jpeg, {int width = 0, int height = 0}) {
    _previewBytes = jpeg;
    _previewImageSize = (width > 1 && height > 1)
        ? Size(width.toDouble(), height.toDouble())
        : Size.zero;
  }

  Map<String, dynamic> _emptyZone() => {
        'detected_shade': null,
        'delta_e_2000': null,
        'override_shade': null,
        'sampled_lab': null,
        'top_matches': <Map<String, dynamic>>[],
      };

  void _addTooth() {
    if (_editOutlineMode || _busy) return;
    if (_previewBytes == null) {
      setState(() => _error = 'Upload a photo before adding a tooth.');
      return;
    }
    if (_teeth.length >= 12) {
      setState(() => _error = 'Maximum of 12 teeth on this analysis.');
      return;
    }

    final reference = _selectedTooth ?? (_teeth.isNotEmpty ? _teeth.last : null);
    final refHandles = reference == null ? null : toothEditHandles(reference);
    final refBox = reference == null ? null : toothGeometryBBox(reference);

    // Match the selected (or last) crown size; fall back to a frontal-incisor default.
    final size = (refBox != null && refBox.width > 0.02 && refBox.height > 0.04)
        ? Size(refBox.width, refBox.height)
        : const Size(0.10, 0.22);

    var right = 0.0;
    var left = 1.0;
    var sumCy = 0.0;
    var nCy = 0;
    for (final t in _teeth) {
      final b = toothGeometryBBox(t);
      if (b == null) continue;
      right = math.max(right, b.right);
      left = math.min(left, b.left);
      sumCy += b.center.dy;
      nCy++;
    }
    final cy = nCy > 0
        ? sumCy / nCy
        : (refBox?.center.dy ?? 0.48);
    final gap = math.max(0.012, size.width * 0.12);

    List<List<double>> outline;
    List<double> bulges;
    if (refHandles != null && refHandles.length >= 3) {
      final src = outlineBBox(refHandles);
      var dx = (right + gap + size.width / 2) - src.center.dx;
      var shifted = translateOutline(refHandles, dx, cy - src.center.dy);
      if (outlineBBox(shifted).right > 0.97 && _teeth.isNotEmpty) {
        dx = (left - gap - size.width / 2) - src.center.dx;
        shifted = translateOutline(refHandles, dx, cy - src.center.dy);
      }
      outline = clampOutlineToImage(shifted);
      bulges = toothEdgeBulges(reference!, outline.length) ??
          zeroBulges(outline.length);
    } else {
      var cx = _teeth.isEmpty ? 0.50 : right + gap + size.width / 2;
      if (cx + size.width / 2 > 0.97 && _teeth.isNotEmpty) {
        cx = left - gap - size.width / 2;
      }
      final box = Rect.fromCenter(
        center: Offset(cx.clamp(0.08, 0.92), cy.clamp(0.22, 0.78)),
        width: size.width,
        height: size.height,
      );
      outline = clampOutlineToImage(crownOutlineForBBox(box));
      bulges = zeroBulges(outline.length);
    }

    final box = outlineBBox(outline);
    final idx = _teeth.length;
    final tooth = <String, dynamic>{
      'tooth_index': idx,
      'label': 'Tooth ${idx + 1}',
      'confidence': 0.5,
      'rejected': false,
      'reject_reason': null,
      'zones': {for (final z in kShadeZones) z: _emptyZone()},
      'geometry': {
        'outline': OutlineEditHistory.cloneVerts(outline),
        'edit_handles': OutlineEditHistory.cloneVerts(outline),
        'edge_bulges': List<double>.from(bulges),
        'bbox': {
          'x': box.left,
          'y': box.top,
          'w': box.width,
          'h': box.height,
        },
        'label': {
          'x': box.center.dx,
          'y': (box.top - 0.02).clamp(0.0, 1.0),
        },
        'zone_lines': <List<List<double>>>[],
        'zone_outlines': <String, dynamic>{},
      },
    };

    setState(() {
      _teeth = [..._teeth, tooth];
      _rememberTeeth();
      _selectedToothIndex = idx;
      _focusZone = 'middle';
      _error = null;
      _syncUiFromSelection();
      _saveStatus =
          'Added Tooth ${idx + 1} — hold inside the outline and drag it onto the tooth, then Apply.';
      _upsertSessionEntry(onlyIfExists: true);
    });
    _startOutlineEdit();
    AppHaptics.success();
  }

  double _toothSortX(Map<String, dynamic> tooth) {
    final geo = tooth['geometry'];
    if (geo is Map) {
      final label = geo['label'];
      if (label is Map && label['x'] is num) {
        return (label['x'] as num).toDouble();
      }
      final bbox = geo['bbox'];
      if (bbox is Map && bbox['x'] is num) {
        final x = (bbox['x'] as num).toDouble();
        final w = (bbox['w'] as num?)?.toDouble() ?? 0;
        return x + w / 2;
      }
    }
    return (tooth['tooth_index'] as num?)?.toDouble() ?? 0;
  }

  void _startOutlineEdit() {
    final tooth = _selectedTooth;
    if (tooth == null) return;
    final geo = tooth['geometry'];
    if (geo is! Map) return;
    final handles = geo['edit_handles'];
    final List<List<double>> verts;
    if (handles is List && handles.length >= 3) {
      // Prefer stored edit skeleton (do not re-simplify — keeps bulge indices).
      verts = [
        for (final p in handles)
          if (p is List && p.length >= 2)
            [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
      ];
    } else {
      final raw = geo['outline'];
      if (raw is! List || raw.length < 3) return;
      verts = simplifyOutlineForEdit(raw, maxPoints: 12, minPoints: 8);
    }
    if (verts.length < 3) return;
    final stored = geo['edge_bulges'];
    final bulges = (stored is List && stored.length == verts.length)
        ? [
            for (final b in stored) (b as num).toDouble(),
          ]
        : zeroBulges(verts.length);
    setState(() {
      _editOutlineMode = true;
      _sessionCollapsedBeforeEdit ??= _sessionCollapsed;
      _sessionCollapsed = true;
      _editOutline = verts;
      _editOutlineBackup = OutlineEditHistory.cloneVerts(verts);
      _editBulges = bulges;
      _editBulgesBackup = OutlineEditHistory.cloneBulges(bulges);
      _activeHandleIndex = null;
      _activeEdgeIndex = null;
      _movingOutline = false;
      _bodyDragLast = null;
      _clearMagnifier();
      _outlineBeforeDrag = null;
      _outlineHistory.clear();
      _saveStatus =
          'Drag inside to move · drag corners · hold mid-edge to curve · Apply.';
    });
  }

  void _cancelOutlineEdit() {
    setState(() => _exitOutlineEdit());
  }

  void _resetOutlineEdit() {
    final bak = _editOutlineBackup;
    final bakB = _editBulgesBackup;
    if (bak == null || bakB == null) return;
    setState(() {
      _editOutline = OutlineEditHistory.cloneVerts(bak);
      _editBulges = OutlineEditHistory.cloneBulges(bakB);
      _activeHandleIndex = null;
      _activeEdgeIndex = null;
      _movingOutline = false;
      _bodyDragLast = null;
      _clearMagnifier();
      _outlineBeforeDrag = null;
      _outlineHistory.clear();
    });
  }

  void _commitOutlineDrag() {
    final before = _outlineBeforeDrag;
    final current = _editOutline;
    final bulges = _editBulges;
    _outlineBeforeDrag = null;
    if (before == null || current == null || bulges == null) return;
    final now = OutlineEditHistory.snapOf(current, bulges);
    if (OutlineEditHistory.same(before, now)) return;
    _outlineHistory.record(before);
  }

  void _clearMagnifier() {
    _magnifierFocal.value = null;
    _magnifierViewSize = null;
  }

  void _exitOutlineEdit({bool clearStatus = true}) {
    if (_sessionCollapsedBeforeEdit != null) {
      _sessionCollapsed = _sessionCollapsedBeforeEdit!;
      _sessionCollapsedBeforeEdit = null;
    }
    _editOutlineMode = false;
    _editOutline = null;
    _editOutlineBackup = null;
    _editBulges = null;
    _editBulgesBackup = null;
    _activeHandleIndex = null;
    _activeEdgeIndex = null;
    _movingOutline = false;
    _bodyDragLast = null;
    _clearMagnifier();
    _outlineBeforeDrag = null;
    _outlineHistory.clear();
    if (clearStatus) _saveStatus = null;
  }

  void _clearUploadedPhoto() {
    setState(() {
      _previewBytes = null;
      _previewFilename = 'tooth.jpg';
      _previewImageSize = Size.zero;
      _teeth = [];
      _teethMemory = [];
      _teethUndo.clear();
      _isolatedToothIndex = null;
      _selectedToothIndex = null;
      _analysisImageSize = Size.zero;
      _detected = '—';
      _selected = '—';
      _confidence = 0;
      _topMatches = [];
      _overallTopMatches = [];
      _finalShade = null;
      _pendingShade = null;
      _overallShadePick = false;
      _exitOutlineEdit(clearStatus: false);
      _photoTransformController.value = Matrix4.identity();
      _error = null;
      _saveStatus = 'Photo removed';
      _upsertSessionEntry(onlyIfExists: true);
    });
  }

  void _endOutlineDrag() {
    _commitOutlineDrag();
    setState(() {
      _activeHandleIndex = null;
      _activeEdgeIndex = null;
      _movingOutline = false;
      _bodyDragLast = null;
      _clearMagnifier();
    });
  }

  void _undoOutlineEdit() {
    final current = _editOutline;
    final bulges = _editBulges;
    if (current == null || bulges == null || !_outlineHistory.canUndo) return;
    final prev = _outlineHistory.undo(OutlineEditHistory.snapOf(current, bulges));
    if (prev == null) return;
    setState(() {
      _editOutline = prev.verts;
      _editBulges = prev.bulges;
      _activeHandleIndex = null;
      _activeEdgeIndex = null;
      _clearMagnifier();
    });
  }

  void _redoOutlineEdit() {
    final current = _editOutline;
    final bulges = _editBulges;
    if (current == null || bulges == null || !_outlineHistory.canRedo) return;
    final next = _outlineHistory.redo(OutlineEditHistory.snapOf(current, bulges));
    if (next == null) return;
    setState(() {
      _editOutline = next.verts;
      _editBulges = next.bulges;
      _activeHandleIndex = null;
      _activeEdgeIndex = null;
      _clearMagnifier();
    });
  }

  Future<void> _applyOutlineEdit() async {
    final bytes = _previewBytes;
    final outline = _editOutline;
    final bulges = _editBulges;
    final idx = _selectedToothIndex;
    if (bytes == null || outline == null || bulges == null || idx == null) {
      return;
    }

    // Densify Bezier bulges so backend fillPoly keeps mid-edge bends.
    final sampled = sampleCurvedOutline(outline, bulges, samplesPerEdge: 8);

    setState(() {
      _busy = true;
      _error = null;
      _saveStatus = 'Updating shade from edited outline…';
    });
    try {
      final result = await widget.api.resampleShadeOutline(
        bytes: bytes,
        filename: _previewFilename,
        outline: sampled,
        toothIndex: idx,
      );
      final toothRaw = result['tooth'];
      if (toothRaw is! Map) {
        throw Exception('Resample returned no tooth');
      }
      final updated = Map<String, dynamic>.from(toothRaw);
      final zones = updated['zones'];
      if (zones is Map) {
        updated['zones'] = {
          for (final e in zones.entries)
            e.key.toString(): Map<String, dynamic>.from(e.value as Map),
        };
      }
      // Keep curved display polyline + sparse handles/bulges for re-edit.
      final geo = Map<String, dynamic>.from(
        (updated['geometry'] is Map)
            ? Map<String, dynamic>.from(updated['geometry'] as Map)
            : <String, dynamic>{},
      );
      geo['outline'] = sampled;
      geo['edit_handles'] = OutlineEditHistory.cloneVerts(outline);
      geo['edge_bulges'] = OutlineEditHistory.cloneBulges(bulges);
      geo['edited'] = true;
      updated['geometry'] = geo;
      setState(() {
        _teeth = [
          for (final t in _teeth)
            ((t['tooth_index'] as num?)?.toInt() == idx) ? updated : t,
        ];
        _rememberTeeth();
        _exitOutlineEdit(clearStatus: false);
        _syncUiFromSelection();
        _saveStatus =
            'Outline applied — zone shades refreshed for T${idx + 1}.';
      });
      AppHaptics.success();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _saveStatus = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _applyShadeChoice(String shade, {bool overall = false}) {
    if (shade.isEmpty || shade == '—' || !kAllowedShades.contains(shade)) return;

    // Zone-level preview only — Override on the zone chip commits this pick.
    // overall: Result "Top matches" — Save override works immediately.
    setState(() {
      _ensureToothFocused();
      _selected = shade;
      _pendingShade = overall ? null : shade;
      _overallShadePick = overall;
      _saveStatus = null;
      _error = null;
    });
    if (!mounted) return;
    if (overall) {
      _toast('$shade selected — tap Save override to apply', bg: AppColors.navy);
      return;
    }
    if (_selectedToothIndex == null) {
      _toast('Select a tooth zone first');
      return;
    }
    _toast(
      '$shade selected — tap Override on Tooth ${_selectedToothIndex! + 1} · ${capitalizeZone(_focusZone)} to apply',
      bg: AppColors.navy,
    );
  }

  List<Map<String, dynamic>> _teethPayloadForSave() {
    return _teeth.map((t) {
      final zonesIn = t['zones'];
      final zonesOut = <String, dynamic>{};
      if (zonesIn is Map) {
        for (final name in kShadeZones) {
          final z = zonesIn[name];
          if (z is! Map) continue;
          zonesOut[name] = {
            'detected_shade': z['detected_shade'],
            'delta_e_2000': z['delta_e_2000'],
            'override_shade': z['override_shade'],
          };
        }
      }
      return {
        'tooth_index': t['tooth_index'],
        'confidence': t['confidence'],
        'rejected': t['rejected'] == true,
        'reject_reason': t['reject_reason'],
        'zones': zonesOut,
      };
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant ShadePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _onPageActivated();
    }
  }

  @override
  void dispose() {
    _dragTick.dispose();
    _magnifierFocal.dispose();
    _photoTransformController.dispose();
    super.dispose();
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
      await _consumeShadeHandoff();
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
          _allShadeItems = [];
          _shadeDetectionId = null;
        });
      }
      return;
    }
    if (_patient == null || _pid(_patient!) != _pid(sel)) {
      await _selectPatient(sel, publish: false);
    }
    await _consumeShadeHandoff();
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
        _shadeDetectionId = null;
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
      _saveStatus = null;
      _error = null;
      _allShadeItems = [];
      _shadeDetectionId = null;
    });
    // Cases API is optional for Upload & detect. GDPR patient ids are UUIDs;
    // legacy createCase(int) only works for numeric ids when cases are mounted.
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _case = null);
    }
    await _loadShadeDetections();
  }

  Future<void> _loadShadeDetections() async {
    final patient = _patient;
    if (patient == null) {
      if (mounted) {
        setState(() => _allShadeItems = []);
      }
      return;
    }
    final pid = _pid(patient);
    if (pid.isEmpty) return;
    try {
      final rows = await widget.api.listShadeDetections(pid);
      if (!mounted) return;
      setState(() => _allShadeItems = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Camera handoff: open copied detection and run the same suggest pipeline.
  Future<void> _consumeShadeHandoff() async {
    final id = widget.patientSession.takePendingShadeDetectionId();
    if (id == null || id.isEmpty || _patient == null) return;

    // Ensure the copied row is present (list may be stale after camera copy).
    await _loadShadeDetections();
    if (!mounted) return;

    Map<String, dynamic>? item;
    for (final row in _allShadeItems) {
      if ('${row['id'] ?? ''}' == id) {
        item = row;
        break;
      }
    }
    if (item == null) {
      setState(
        () => _error =
            'Photo is not in Shade Detection yet. Open Shade Detection again.',
      );
      return;
    }
    await _openShadeItem(item, runAi: true);
  }

  Future<void> _openShadeItem(
    Map<String, dynamic> item, {
    bool runAi = false,
  }) async {
    final url = '${item['file_url'] ?? ''}'.trim();
    final name = '${item['file_name'] ?? 'tooth.jpg'}';
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _saveStatus = runAi ? 'Mapping teeth…' : null;
      _shadeDetectionId = '${item['id'] ?? ''}'.trim();
    });
    try {
      final bytes = await widget.api.downloadMediaBytes(url);
      if (!mounted) return;
      final baked = bakeExifOrientationSized(bytes);
      _photoTransformController.value = Matrix4.identity();
      setState(() {
        _setPreviewJpeg(
          baked.bytes,
          width: baked.width,
          height: baked.height,
        );
        _previewFilename = name;
        _exitOutlineEdit(clearStatus: false);
        _teeth = [];
        _rememberTeeth();
        _isolatedToothIndex = null;
        _selectedToothIndex = null;
        _finalShade = null;
        _detected = '—';
        _confidence = 0;
        _topMatches = [];
        _overallTopMatches = [];
      });
      if (runAi) {
        await _applySuggestFromBytes(baked.bytes, name);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openNewPatientPage() {
    widget.patientSession.requestNavigateToNewPatient();
  }

  /// Same mapping pipeline as gallery Upload & detect (`POST /api/ai/shade/suggest`).
  Future<void> _applySuggestFromBytes(Uint8List data, String name) async {
    // Bake EXIF so preview pixels match backend transpose (camera-roll photos).
    final baked = bakeExifOrientationSized(data);
    if (mounted && !identical(baked.bytes, _previewBytes)) {
      setState(() {
        _setPreviewJpeg(
          baked.bytes,
          width: baked.width,
          height: baked.height,
        );
      });
    }
    final result = await widget.api.suggestShade(baked.bytes, name);
    if (!mounted) return;
    _applySuggestResult(result);
  }

  void _applySuggestResult(Map<String, dynamic> result) {
    final teeth = _parseTeeth(result['teeth']);
    Map<String, dynamic>? first;
    for (final t in teeth) {
      if (t['rejected'] != true) {
        first = t;
        break;
      }
    }
    first ??= teeth.isEmpty ? null : teeth.first;

    setState(() {
      _teeth = teeth;
      _rememberTeeth();
      _teethUndo.clear();
      _isolatedToothIndex = null;
      _selectedToothIndex = (first?['tooth_index'] as num?)?.toInt();
      _focusZone = 'middle';
      final iw = (result['image_width'] as num?)?.toDouble() ?? 0;
      final ih = (result['image_height'] as num?)?.toDouble() ?? 0;
      _analysisImageSize = (iw > 0 && ih > 0) ? Size(iw, ih) : Size.zero;
      _finalShade = null;
      _syncUiFromSelection();
      _saveStatus = teeth.isEmpty
          ? 'No teeth detected — try another photo'
          : 'Mapped ${teeth.length} tooth${teeth.length == 1 ? '' : 'teeth'} — Accept or Save override to session';
    });
  }

  Future<void> _runAiFromGallery() async {
    if (_patient == null) {
      setState(() => _error = 'Select a patient first.');
      return;
    }
    setState(() {
      _error = null;
      _saveStatus = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _error = 'Could not read image bytes. Try another photo.');
        return;
      }

      if (!mounted) return;
      final confirmed = await confirmPatientMediaUpload(context);
      if (!confirmed || !mounted) return;

      final name = file.name.isNotEmpty ? file.name : 'tooth.jpg';
      final baked = bakeExifOrientationSized(Uint8List.fromList(bytes));
      final data = baked.bytes;
      final pid = _pid(_patient!);

      setState(() => _busy = true);
      final uploaded = await runWithToothLoadingDialog(
        context,
        message: 'Uploading…',
        action: () => widget.api.uploadShadeDetection(
          patientId: pid,
          bytes: data,
          filename: name,
        ),
      );
      if (!mounted) return;

      setState(() {
        _allShadeItems = [uploaded, ..._allShadeItems];
        _shadeDetectionId = '${uploaded['id'] ?? ''}'.trim();
        _setPreviewJpeg(data, width: baked.width, height: baked.height);
        _previewFilename = name;
        _photoTransformController.value = Matrix4.identity();
        _exitOutlineEdit(clearStatus: false);
      });

      await _applySuggestFromBytes(data, name);
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _persist({required bool acceptAi}) async {
    if (_patient == null) {
      setState(
        () => _error = _patients.isEmpty
            ? 'Add a patient first, then save the shade to their record.'
            : 'Select a patient from the list first.',
      );
      return;
    }
    if (_detected == '—' && acceptAi && _teeth.isEmpty) {
      setState(() => _error = 'Upload a tooth photo first so AI can detect a shade.');
      return;
    }
    final finalShade = acceptAi ? _detected : _selected;
    if (finalShade == '—' || !kAllowedShades.contains(finalShade)) {
      setState(() => _error = 'Pick a shade before saving.');
      return;
    }
    if (!acceptAi &&
        _pendingShade != null &&
        _pendingShade != '—' &&
        _selectedTooth != null) {
      final zone = _zoneOf(_selectedTooth!, _focusZone);
      final committed = zone?['override_shade'] as String?;
      if (committed != _pendingShade) {
        setState(
          () => _error =
              'Tap Override on the zone chip to confirm $_pendingShade first.',
        );
        return;
      }
    }

    // Stamp Accept AI / override onto the target zone before save.
    // Overall Top-match picks apply to the body (middle) zone of the focused tooth.
    final tooth = _selectedTooth;
    if (tooth != null) {
      final zoneName =
          (!acceptAi && _overallShadePick) ? 'middle' : _focusZone;
      final zone = _zoneOf(tooth, zoneName);
      if (zone != null) {
        final detected = zone['detected_shade'] as String?;
        if (acceptAi) {
          zone['override_shade'] = null;
        } else if (detected != null && finalShade != detected) {
          zone['override_shade'] = finalShade;
        } else if (detected == finalShade) {
          zone['override_shade'] = null;
        } else {
          zone['override_shade'] = finalShade;
        }
      }
      if (!acceptAi && _overallShadePick) {
        _focusZone = 'middle';
      }
      _syncUiFromSelection(resetSelectedToDetected: false);
      _selected = finalShade;
    }

    final overridden = !acceptAi && finalShade != _detected;
    setState(() {
      _saving = true;
      _saveStatus = null;
      _error = null;
    });
    try {
      Map<String, dynamic> saved;
      final caseId = _currentCaseId();
      final shadeId = _shadeDetectionId?.trim() ?? '';
      if (caseId != null) {
        if (_teeth.isNotEmpty) {
          saved = await widget.api.saveShadeAnalysis(
            caseId: caseId,
            teeth: _teethPayloadForSave(),
            selectedToothIndex: _selectedToothIndex ?? 0,
          );
        } else {
          saved = await widget.api.saveShade(
            caseId: caseId,
            aiSuggested: _detected == '—' ? null : _detected,
            confidence: _confidence > 0 ? _confidence : null,
            finalShade: finalShade,
            overridden: overridden,
          );
        }
        _selected = finalShade;
        try {
          await widget.api.markCaseInProgressIfPending(
            caseId,
            _case?['status']?.toString(),
          );
          if (mounted && _case != null) {
            setState(() => _case = {..._case!, 'status': 'in_progress'});
          }
        } catch (_) {}
      } else {
        saved = {
          'id': shadeId.isEmpty
              ? 'session-${DateTime.now().millisecondsSinceEpoch}'
              : shadeId,
          'summary_shade': finalShade,
          'has_override': overridden,
        };
        if (shadeId.isNotEmpty) {
          try {
            saved = await widget.api.saveShadeDetectionAnalysis(
              shadeId: shadeId,
              teeth: _teethPayloadForSave(),
              selectedToothIndex: _selectedToothIndex ?? 0,
              summaryShade: finalShade,
              hasOverride: overridden,
              detectedShade: _detected == '—' ? null : _detected,
              confidence: _confidence > 0 ? _confidence : null,
              overridden: overridden,
              finalShade: finalShade,
            );
          } catch (_) {
            // Session save still proceeds if the detection row has no analysis column yet.
          }
        }
        _selected = finalShade;
      }
      if (!mounted) return;
      setState(() {
        _finalShade = finalShade;
        _selected = finalShade;
        _pendingShade = null;
        _overallShadePick = false;
        _upsertSessionEntry(
          savedId: saved['id'] ?? shadeId,
          summaryShade: saved['summary_shade']?.toString() ?? finalShade,
          hasOverride: overridden || saved['has_override'] == true,
        );
        _saveStatus = null;
        _error = null;
      });
      if (mounted) {
        final who =
            '${_patient?['first_name'] ?? ''} ${_patient?['last_name'] ?? ''}'
                .trim();
        AppSnackBars.success(
          context,
          overridden
              ? 'Saved override $finalShade${who.isEmpty ? '' : ' for $who'}'
              : 'Accepted AI $finalShade${who.isEmpty ? '' : ' for $who'}',
        );
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteHistoryAt(int index) async {
    if (_busy || index < 0 || index >= _history.length) return;
    final entry = _history[index];
    final shade = entry['shade']?.toString() ?? 'shade';
    final ok = await AppDialogs.confirm(
      context,
      title: 'Remove save?',
      message: 'Delete $shade from this session.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!ok || !mounted) return;

    final shadeId = entry['id'];
    final caseId = entry['case_id'] ?? _case?['id'];
    setState(() => _busy = true);
    try {
      if (shadeId is num && caseId is num) {
        if (entry['is_analysis'] == true) {
          await widget.api.deleteShadeAnalysis(
            caseId: caseId.toInt(),
            analysisId: shadeId.toInt(),
          );
        } else {
          await widget.api.deleteShade(
            caseId: caseId.toInt(),
            shadeId: shadeId.toInt(),
          );
        }
      } else {
        AppHaptics.warn();
      }
      if (!mounted) return;
      setState(() {
        _history.removeAt(index);
        _saveStatus = null;
        _error = null;
      });
      if (mounted) AppSnackBars.success(context, 'Removed $shade from session');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onHandleDragStart(Offset local, Size box) {
    final outline = _editOutline;
    final bulges = _editBulges;
    if (outline == null || bulges == null) return;
    final imgSize = _overlayImageSize == Size.zero ? box : _overlayImageSize;
    final scale =
        _photoTransformController.value.getMaxScaleOnAxis().clamp(1.0, 4.0);
    final hi = hitTestOutlineHandle(
      local: local,
      box: box,
      imageSize: imgSize,
      outline: outline,
      radius: 32 / scale,
    );
    final ei = hi == null
        ? hitTestOutlineEdge(
            local: local,
            box: box,
            imageSize: imgSize,
            outline: outline,
            maxDist: 22 / scale,
          )
        : null;
    final moving = hi == null &&
        ei == null &&
        hitTestOutlineBody(
          local: local,
          box: box,
          imageSize: imgSize,
          outline: outline,
          bulges: bulges,
        );
    if (hi == null && ei == null && !moving) return;
    setState(() {
      _activeHandleIndex = hi;
      _activeEdgeIndex = ei;
      _movingOutline = moving;
      _bodyDragLast = moving ? local : null;
      _magnifierViewSize = moving ? null : box;
      _outlineBeforeDrag = OutlineEditHistory.snapOf(outline, bulges);
    });
    if (!moving) _magnifierFocal.value = local;
  }

  void _onHandleDragUpdate(Offset local, Size box) {
    final outline = _editOutline;
    final bulges = _editBulges;
    if (outline == null || bulges == null) return;
    final imgSize = _overlayImageSize == Size.zero ? box : _overlayImageSize;
    final dest = containRect(box, imgSize);
    final hi = _activeHandleIndex;
    final ei = _activeEdgeIndex;
    if (_movingOutline) {
      final last = _bodyDragLast;
      if (last == null) return;
      final from = localToNorm(last, dest);
      final to = localToNorm(local, dest);
      final next = clampOutlineToImage(
        translateOutline(outline, to[0] - from[0], to[1] - from[1]),
      );
      for (var i = 0; i < outline.length && i < next.length; i++) {
        outline[i][0] = next[i][0];
        outline[i][1] = next[i][1];
      }
      _bodyDragLast = local;
      _dragTick.value++;
      return;
    }
    if (hi != null) {
      final norm = localToNorm(local, dest);
      outline[hi] = [norm[0], norm[1]];
    } else if (ei != null && ei < outline.length) {
      final a = normToLocal(outline[ei], dest);
      final b = normToLocal(outline[(ei + 1) % outline.length], dest);
      final ab = b - a;
      final len = ab.distance;
      if (len > 1e-6) {
        final mid = Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5);
        final nrm = Offset(-ab.dy / len, ab.dx / len);
        final signed =
            (local.dx - mid.dx) * nrm.dx + (local.dy - mid.dy) * nrm.dy;
        final scale = dest.shortestSide.clamp(1.0, 10000.0);
        while (bulges.length < outline.length) {
          bulges.add(0);
        }
        bulges[ei] = (signed / scale).clamp(-0.09, 0.09);
      }
    } else {
      return;
    }
    _magnifierFocal.value = local;
    _dragTick.value++;
  }

  void _onEdgeDoubleTap(Offset local, Size box) {
    final outline = _editOutline;
    final bulges = _editBulges;
    if (outline == null || bulges == null) return;
    final imgSize = _overlayImageSize == Size.zero ? box : _overlayImageSize;
    final scale =
        _photoTransformController.value.getMaxScaleOnAxis().clamp(1.0, 4.0);
    // Prefer edge; if on vertex, use nearest edge.
    var ei = hitTestOutlineEdge(
      local: local,
      box: box,
      imageSize: imgSize,
      outline: outline,
      maxDist: 28 / scale,
    );
    if (ei == null) {
      final hi = hitTestOutlineHandle(
        local: local,
        box: box,
        imageSize: imgSize,
        outline: outline,
        radius: 32 / scale,
      );
      if (hi == null) return;
      ei = hi; // insert after this vertex's outgoing edge
    }
    final dest = containRect(box, imgSize);
    final a = normToLocal(outline[ei], dest);
    final b = normToLocal(outline[(ei + 1) % outline.length], dest);
    final onSeg = closestPointOnSegment(local, a, b);
    final norm = localToNorm(onSeg, dest);
    setState(() {
      _outlineHistory.record(OutlineEditHistory.snapOf(outline, bulges));
      outline.insert(ei! + 1, [norm[0], norm[1]]);
      while (bulges.length < outline.length - 1) {
        bulges.add(0);
      }
      bulges[ei] = 0;
      bulges.insert(ei + 1, 0);
      _activeHandleIndex = ei + 1;
      _activeEdgeIndex = null;
      _saveStatus = 'Point added — drag to refine, or curve the new edges.';
    });
    AppHaptics.selection();
  }


  @override
  Widget build(BuildContext context) {
    _error = AppSnackBars.drain(context, _error);
    if (_loading) {
      return const ToothPageLoader(message: 'Loading shade detection…');
    }

    final portrait = AppBreakpoints.isPortrait(context);
    final sessionCollapsed =
        _sessionCollapsed || (portrait && !_sessionPinnedOpen);

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
          PageHeader(
            icon: Icons.palette_outlined,
            title: AppLocalizations.of(context).shadeTitle,
            subtitle:
                'Upload a tooth photo → AI detects VITA shade → confirm or override',
            actions: [
              PatientPickerButton(
                patients: _patients,
                selected: _patient,
                caseId: _case?['id'],
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
              ),
              FilledButton.icon(
                onPressed: _busy || _patient == null ? null : _runAiFromGallery,
                icon: _busy
                    ? const ToothLoadingIndicator(
                        size: 16,
                        compact: true,
                        color: Colors.white,
                      )
                    : const Icon(Icons.upload_file, size: 18),
                label: Text(_busy ? 'Detecting…' : 'Upload & detect'),
              ),
            ],
          ),
          if (_saveStatus != null) ...[
            const SizedBox(height: 10),
            Text(
              _saveStatus!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.success),
            ),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, workspace) {
                final stackPhotoResult = portrait ||
                    workspace.maxWidth < AppBreakpoints.shadeStack;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 5,
                      child: LayoutBuilder(
                        builder: (context, colConstraints) {
                          final actionSlotH = 66.0;
                          final overrideH = stackPhotoResult
                              ? (colConstraints.maxHeight * 0.24)
                                  .clamp(130.0, 200.0)
                              : (colConstraints.maxHeight * 0.34)
                                  .clamp(170.0, 300.0);
                          // Keep action bar mounted whenever a photo is loaded so
                          // the photo Expanded never resizes on select / add.
                          final showActions = !_busy && _previewBytes != null;
                          final editing = _editOutlineMode;
                          final showLoupe = editing &&
                              _magnifierViewSize != null &&
                              _previewBytes != null;
                          return Column(
                            children: [
                              Expanded(
                                child: Padding(
                                  // Room for white card glows (blur ~14) so they
                                  // aren't clipped by the action bar / column.
                                  padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
                                  child: _ShadePhotoResultSplit(
                                    editing: editing,
                                    stacked: stackPhotoResult,
                                    photo: ShadePhotoPane(
                                  previewBytes: _previewBytes,
                                  busy: _busy,
                                  editOutlineMode: _editOutlineMode,
                                  teeth: _teeth,
                                  selectedToothIndex: _selectedToothIndex,
                                  isolatedToothIndex: _isolatedToothIndex,
                                  analysisImageSize: _overlayImageSize,
                                  focusZone: _focusZone,
                                  editOutline: _editOutline,
                                  editBulges: _editBulges,
                                  activeHandleIndex: _activeHandleIndex,
                                  activeEdgeIndex: _activeEdgeIndex,
                                  photoTransformController:
                                      _photoTransformController,
                                  dragTick: _dragTick,
                                  canUndo: _canUndo,
                                  canRedo: _editOutlineMode &&
                                      _outlineHistory.canRedo,
                                  onUpload: _runAiFromGallery,
                                  onClearPhoto: _clearUploadedPhoto,
                                  onSelectTooth: _onToothTap,
                                  onHandleDragStart: _onHandleDragStart,
                                  onHandleDragUpdate: _onHandleDragUpdate,
                                  onHandleDragEnd: _endOutlineDrag,
                                  onEdgeDoubleTap: _onEdgeDoubleTap,
                                  onUndo: _undoFromOverlay,
                                  onRedo: _redoOutlineEdit,
                                ),
                                result: ShadeResultPane(
                                  teeth: _teethForResultPane,
                                  selectedToothIndex: _selectedToothIndex,
                                  focusZone: _focusZone,
                                  pendingShade: _pendingShade,
                                  detected: _resultDisplayShade(),
                                  confidence: _confidence,
                                  selected: _selected,
                                  finalShade: _finalShade,
                                  overallTopMatches: _overallTopMatches,
                                  saving: _saving,
                                  swatch: shadeSwatch,
                                  zoneEffective: _zoneEffective,
                                  zoneOf: _zoneOf,
                                  zoneOverridden: _zoneOverridden,
                                  onSelectTooth: (index, {zone}) {
                                    if (zone != null) {
                                      _selectTooth(index, zone: zone);
                                    } else {
                                      _onToothTap(index);
                                    }
                                  },
                                  onDeleteTooth: _deleteSelectedTooth,
                                  onBeginZoneOverride: _beginZoneOverride,
                                  onOverallShade: (s) =>
                                      _applyShadeChoice(s, overall: true),
                                  onAcceptAi: () => _persist(acceptAi: true),
                                  onSaveOverride: () =>
                                      _persist(acceptAi: false),
                                  magnifierFocal: _magnifierFocal,
                                  magnifierViewSize: _magnifierViewSize,
                                  previewBytes: _previewBytes,
                                  analysisImageSize: _overlayImageSize,
                                  dragTick: _dragTick,
                                  editOutline: _editOutline,
                                  editBulges: _editBulges,
                                  activeHandleIndex: _activeHandleIndex,
                                  activeEdgeIndex: _activeEdgeIndex,
                                ),
                                loupe: showLoupe
                                    ? Positioned(
                                        right: 16,
                                        bottom: 52,
                                        width: 240,
                                        height: 240,
                                        child: IgnorePointer(
                                          child: ShadeOutlineLoupe(
                                            focalListenable: _magnifierFocal,
                                            viewSize: _magnifierViewSize!,
                                            previewBytes: _previewBytes!,
                                            analysisImageSize:
                                                _overlayImageSize,
                                            dragTick: _dragTick,
                                            teeth: _teeth,
                                            selectedToothIndex:
                                                _selectedToothIndex,
                                            focusZone: _focusZone,
                                            editOutline: _editOutline,
                                            editBulges: _editBulges,
                                            activeHandleIndex:
                                                _activeHandleIndex,
                                            activeEdgeIndex: _activeEdgeIndex,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          // Keep the mounted action bar stable without leaving
                          // a large empty gap before the first upload.
                          SizedBox(
                            height: showActions ? actionSlotH : 12,
                            width: double.infinity,
                            child: showActions
                                ? ShadeActionBar(
                                    editOutlineMode: _editOutlineMode,
                                    hasPreview: _previewBytes != null,
                                    canEditTooth:
                                        _selectedToothIndex != null,
                                    onCancel: _cancelOutlineEdit,
                                    onReset: _resetOutlineEdit,
                                    onApply: _applyOutlineEdit,
                                    onAdjustEdges: _startOutlineEdit,
                                    onDelete: _deleteSelectedTooth,
                                    onAddTooth: _addTooth,
                                    onUpload: _runAiFromGallery,
                                    maxWidth: colConstraints.maxWidth,
                                  )
                                : null,
                          ),
                          ClipRect(
                            child: AnimatedAlign(
                              duration: AppMotion.page,
                              curve: AppMotion.spring,
                              alignment: Alignment.topCenter,
                              heightFactor: editing ? 0 : 1,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: showActions ? 4 : 0,
                                  left: 2,
                                  right: 2,
                                ),
                                child: SizedBox(
                                  height: overrideH,
                                  width: double.infinity,
                                  child: ShadeOverridePane(
                                    focusZone: _focusZone,
                                    selectedToothIndex: _selectedToothIndex,
                                    selected: _selected,
                                    topMatches: _topMatches,
                                    overallTopMatches: _overallTopMatches,
                                    swatch: shadeSwatch,
                                    onShadeChoice: _applyShadeChoice,
                                    onOverallShadeChoice: (s) =>
                                        _applyShadeChoice(s, overall: true),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ShadeSessionPane(
                  collapsed: sessionCollapsed,
                  history: _history,
                  activeSessionKey: _sessionKey(),
                  swatch: shadeSwatch,
                  onCollapseChanged: (v) => setState(() {
                    _sessionCollapsed = v;
                    _sessionPinnedOpen = !v;
                  }),
                  onOpen: _openHistoryAt,
                  onDelete: _deleteHistoryAt,
                ),
              ],
            );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Animates photo ↔ result split. [editing] 0 = 50/50, 1 = photo fills the row.
class _ShadePhotoResultSplit extends StatefulWidget {
  const _ShadePhotoResultSplit({
    required this.editing,
    required this.photo,
    required this.result,
    this.stacked = false,
    this.loupe,
  });

  final bool editing;
  final Widget photo;
  final Widget result;
  final bool stacked;
  final Widget? loupe;

  @override
  State<_ShadePhotoResultSplit> createState() => _ShadePhotoResultSplitState();
}

class _ShadePhotoResultSplitState extends State<_ShadePhotoResultSplit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.page,
    reverseDuration: AppMotion.normal,
    value: widget.editing ? 1 : 0,
  );

  late final Animation<double> _expand = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.spring,
    reverseCurve: AppMotion.easeOut,
  );

  @override
  void didUpdateWidget(covariant _ShadePhotoResultSplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editing == oldWidget.editing) return;
    if (widget.editing) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = math.max(0.0, (constraints.maxWidth - 12) / 2);
        final resultH = widget.stacked
            ? math.min(
                constraints.maxHeight * 0.48,
                math.max(220.0, constraints.maxHeight * 0.42),
              )
            : math.min(
                280.0,
                math.max(160.0, constraints.maxHeight * 0.36),
              );
        return AnimatedBuilder(
          animation: _expand,
          builder: (context, child) {
            final split = (1 - _expand.value).clamp(0.0, 1.0);
            final resultOpacity = Curves.easeOutCubic.transform(split);
            final resultPane = IgnorePointer(
              ignoring: split < 0.08,
              child: Opacity(
                opacity: resultOpacity,
                child: widget.result,
              ),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                if (widget.stacked)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: widget.photo),
                      SizedBox(height: 12 * split),
                      ClipRect(
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: split,
                          child: SizedBox(
                            height: resultH,
                            width: double.infinity,
                            child: resultPane,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: widget.photo),
                      SizedBox(width: 12 * split),
                      ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: split,
                          child: SizedBox(
                            width: half,
                            child: resultPane,
                          ),
                        ),
                      ),
                    ],
                  ),
                ?widget.loupe,
              ],
            );
          },
        );
      },
    );
  }
}

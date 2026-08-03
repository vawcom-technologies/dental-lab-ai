import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/patient_picker.dart';
import '../../core/widgets/ui_kit.dart';
import 'tooth_overlay.dart';

class ShadePage extends StatefulWidget {
  const ShadePage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ShadePage> createState() => _ShadePageState();
}

class _ShadePageState extends State<ShadePage> {
  static const _zones = ['cervical', 'middle', 'incisal'];

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
  String? _saveStatus;
  String? _error;
  Uint8List? _previewBytes;
  String _previewFilename = 'tooth.jpg';
  List<Map<String, dynamic>> _topMatches = [];
  /// Aggregated across all teeth/zones for the Result card (not zone-similar).
  List<Map<String, dynamic>> _overallTopMatches = [];
  List<Map<String, dynamic>> _history = [];

  // Per-tooth / per-zone analysis (added onto existing UI)
  List<Map<String, dynamic>> _teeth = [];
  int? _selectedToothIndex;
  String _focusZone = 'middle';
  int? _analysisId;
  Size _analysisImageSize = Size.zero;
  /// Shade picked in Manual Override but not yet committed via zone Override.
  String? _pendingShade;
  /// Result-card overall Top match pick — Save override without zone Override.
  bool _overallShadePick = false;

  // Manual outline nudge (dentist adjusts auto edges slightly)
  bool _editOutlineMode = false;
  List<List<double>>? _editOutline;
  List<List<double>>? _editOutlineBackup;
  int? _activeHandleIndex;

  final _manualOverrideKey = GlobalKey();

  final _vita = const [
    'A1', 'A2', 'A3', 'A3.5', 'A4',
    'B1', 'B2', 'B3', 'B4',
    'C1', 'C2', 'C3', 'C4',
    'D2', 'D3', 'D4',
  ];

  Color _swatch(String shade) {
    const map = {
      'A1': Color(0xFFF2E0C9),
      'A2': Color(0xFFECD2B4),
      'A3': Color(0xFFE2C09C),
      'A3.5': Color(0xFFD6B08A),
      'A4': Color(0xFFC69E7A),
      'B1': Color(0xFFF4E6D2),
      'B2': Color(0xFFECD8BC),
      'B3': Color(0xFFE0C4A0),
      'B4': Color(0xFFD2B28C),
      'C1': Color(0xFFE6D6C4),
      'C2': Color(0xFFD6C2AC),
      'C3': Color(0xFFC4AE96),
      'C4': Color(0xFFB09A84),
      'D2': Color(0xFFE4D0BA),
      'D3': Color(0xFFD2BAA0),
      'D4': Color(0xFFC4AC92),
    };
    return map[shade] ?? AppColors.border;
  }

  Map<String, dynamic>? get _selectedTooth {
    if (_selectedToothIndex == null) return null;
    for (final t in _teeth) {
      if ((t['tooth_index'] as num?)?.toInt() == _selectedToothIndex) return t;
    }
    return null;
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

  int _historyIndexForCase(int caseId) {
    final byCase = _history.indexWhere(
      (h) => (h['case_id'] as num?)?.toInt() == caseId,
    );
    if (byCase >= 0) return byCase;
    // Fallback for older session rows / same client this visit.
    final patientId = _patient == null ? null : _pid(_patient!);
    if (patientId == null) return -1;
    return _history.indexWhere(
      (h) => (h['patient_id'] as num?)?.toInt() == patientId,
    );
  }

  bool _teethHaveAnyOverride() {
    for (final t in _teeth) {
      for (final z in _zones) {
        if (_zoneOverridden(_zoneOf(t, z))) return true;
      }
    }
    return false;
  }

  Map<String, dynamic> _sessionEntryFromCurrent({
    Object? savedId,
    String? summaryShade,
    bool? hasOverride,
  }) {
    final caseId = _currentCaseId();
    final teethSnapshots = _teeth.map((t) {
      final zones = <String, String?>{};
      for (final z in _zones) {
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
    };
  }

  /// Replace-or-insert the Session row for the active case.
  /// When [onlyIfExists] is true, skip if this client was never saved this visit.
  void _upsertSessionEntry({
    Object? savedId,
    String? summaryShade,
    bool? hasOverride,
    bool onlyIfExists = false,
  }) {
    final caseId = _currentCaseId();
    if (caseId == null) return;
    final existing = _historyIndexForCase(caseId);
    if (onlyIfExists && existing < 0) return;

    final prevId = existing >= 0 ? _history[existing]['id'] : null;
    final entry = _sessionEntryFromCurrent(
      savedId: savedId ?? prevId,
      summaryShade: summaryShade,
      hasOverride: hasOverride,
    );
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

  /// Shade-match confidence from CIEDE2000 (Result %), not segmentation fill.
  double _shadeMatchConfidence(
    Map<String, dynamic>? zone,
    Map<String, dynamic>? tooth,
  ) {
    final de = (zone?['delta_e_2000'] as num?)?.toDouble();
    if (de != null) {
      // ΔE 0 → ~0.97, ΔE 1 → ~0.78, ΔE 2 → ~0.64, ΔE 3.5 → ~0.50, ΔE 7 → ~0.33
      return (1.0 / (1.0 + de / 3.5)).clamp(0.05, 0.97);
    }
    return (tooth?['confidence'] as num?)?.toDouble() ?? 0;
  }

  /// Most prominent shades across the whole analysis (Result "Top matches").
  void _recomputeOverallTopMatches() {
    final weight = <String, double>{};
    final bestDe = <String, double>{};

    void bump(String shade, double w, double? de) {
      if (shade.isEmpty || shade == '—') return;
      weight[shade] = (weight[shade] ?? 0) + w;
      if (de != null) {
        final prev = bestDe[shade];
        if (prev == null || de < prev) bestDe[shade] = de;
      }
    }

    for (final t in _teeth) {
      if (t['rejected'] == true) continue;
      for (final zName in _zones) {
        final z = _zoneOf(t, zName);
        if (z == null) continue;
        final zoneW = zName == 'middle' ? 3.0 : 1.0;
        final detected = z['detected_shade'] as String?;
        final de = (z['delta_e_2000'] as num?)?.toDouble();
        if (detected != null) {
          bump(detected, zoneW * 2.5, de);
        }
        final tops = z['top_matches'];
        if (tops is! List) continue;
        for (var i = 0; i < tops.length; i++) {
          final m = tops[i];
          if (m is! Map) continue;
          final s = m['shade']?.toString();
          if (s == null || s.isEmpty) continue;
          final mde = (m['delta_e_2000'] as num?)?.toDouble() ?? de;
          bump(s, zoneW * (1.0 / (1.0 + i)) * 0.45, mde);
        }
      }
    }

    final ranked = weight.keys.toList()
      ..sort((a, b) {
        final sa = (weight[a] ?? 0) / (1.0 + (bestDe[a] ?? 9));
        final sb = (weight[b] ?? 0) / (1.0 + (bestDe[b] ?? 9));
        final c = sb.compareTo(sa);
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
    setState(() {
      final same =
          _selectedToothIndex == index && (zone == null || zone == _focusZone);
      _selectedToothIndex = index;
      _focusZone = zone ?? 'middle';
      if (!same) {
        _pendingShade = null;
        _overallShadePick = false;
      }
      _syncUiFromSelection(resetSelectedToDetected: _pendingShade == null);
      if (_pendingShade != null) _selected = _pendingShade!;
      _saveStatus = null;
    });
  }

  void _commitPendingOverride({required int index, required String zone}) {
    final shade = _pendingShade;
    if (shade == null || shade == '—' || !_vita.contains(shade)) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a shade first, then tap Override'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
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
      // Keep an already-saved Session row in sync without a re-save.
      _upsertSessionEntry(onlyIfExists: true);
    });
    final zoneLabel = zone[0].toUpperCase() + zone.substring(1);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tooth ${index + 1} · $zoneLabel → $shade'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.success,
      ),
    );
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
    final zoneLabel = zone[0].toUpperCase() + zone.substring(1);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tooth ${index + 1} · $zoneLabel — choose a shade, then tap Override',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.navy,
      ),
    );
  }

  void _deleteSelectedTooth() {
    final idx = _selectedToothIndex;
    if (idx == null || _editOutlineMode) return;
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
      _analysisId = null; // local edit — force a fresh save payload
      if (remaining.isEmpty) {
        _selectedToothIndex = null;
        _detected = '—';
        _confidence = 0;
        _topMatches = [];
        _selected = '—';
        _saveStatus = 'Removed tooth — re-detect or upload if needed.';
      } else {
        // Prefer the neighbor that was to the right, else the new last.
        final next = idx.clamp(0, remaining.length - 1);
        _selectedToothIndex = next;
        _syncUiFromSelection();
        _saveStatus =
            'Removed tooth. ${remaining.length} remaining (renumbered left → right).';
      }
      _upsertSessionEntry(onlyIfExists: true);
    });
    AppHaptics.warn();
  }

  Map<String, dynamic> _emptyZone() => {
        'detected_shade': null,
        'delta_e_2000': null,
        'override_shade': null,
        'effective_shade': null,
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

    // Place the new outline to the right of the current rightmost crown.
    var cx = 0.50;
    var cy = 0.48;
    if (_teeth.isNotEmpty) {
      var maxX = 0.0;
      var sumY = 0.0;
      var n = 0;
      for (final t in _teeth) {
        maxX = math.max(maxX, _toothSortX(t));
        final geo = t['geometry'];
        if (geo is Map && geo['label'] is Map && geo['label']['y'] is num) {
          sumY += (geo['label']['y'] as num).toDouble();
          n++;
        }
      }
      cx = (maxX + 0.07).clamp(0.08, 0.92);
      if (n > 0) cy = (sumY / n + 0.04).clamp(0.28, 0.72);
    }
    const hw = 0.035;
    const hh = 0.07;
    final outline = <List<double>>[
      [cx - hw, cy - hh],
      [cx + hw, cy - hh],
      [cx + hw, cy + hh],
      [cx - hw, cy + hh],
    ];
    final idx = _teeth.length;
    final tooth = <String, dynamic>{
      'tooth_index': idx,
      'label': 'Tooth ${idx + 1}',
      'confidence': 0.5,
      'rejected': false,
      'reject_reason': null,
      'zones': {for (final z in _zones) z: _emptyZone()},
      'geometry': {
        'outline': outline,
        'bbox': {
          'x': cx - hw,
          'y': cy - hh,
          'w': hw * 2,
          'h': hh * 2,
        },
        'label': {'x': cx, 'y': (cy - hh - 0.02).clamp(0.0, 1.0)},
        'zone_lines': <List<List<double>>>[],
        'zone_outlines': <String, dynamic>{},
        'edited': true,
      },
    };

    setState(() {
      _teeth = [..._teeth, tooth];
      _analysisId = null;
      _selectedToothIndex = idx;
      _focusZone = 'middle';
      _error = null;
      _syncUiFromSelection();
      _saveStatus =
          'Added Tooth ${idx + 1} — Adjust edges to map it, then set shades.';
      _upsertSessionEntry(onlyIfExists: true);
    });
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
    final raw = geo['outline'];
    if (raw is! List || raw.length < 3) return;
    final simplified = simplifyOutlineForEdit(raw, maxPoints: 6, minPoints: 4);
    setState(() {
      _editOutlineMode = true;
      _editOutline = simplified.map((p) => [p[0], p[1]]).toList();
      _editOutlineBackup = simplified.map((p) => [p[0], p[1]]).toList();
      _activeHandleIndex = null;
      _saveStatus =
          'Drag the 4–6 handles to nudge corners/sides, then Apply.';
    });
  }

  void _cancelOutlineEdit() {
    setState(() {
      _editOutlineMode = false;
      _editOutline = null;
      _editOutlineBackup = null;
      _activeHandleIndex = null;
      _saveStatus = null;
    });
  }

  Future<void> _applyOutlineEdit() async {
    final bytes = _previewBytes;
    final outline = _editOutline;
    final idx = _selectedToothIndex;
    if (bytes == null || outline == null || idx == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _saveStatus = 'Updating shade from edited outline…';
    });
    try {
      final result = await widget.api.resampleShadeOutline(
        bytes: bytes,
        filename: _previewFilename,
        outline: outline,
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
      setState(() {
        _teeth = [
          for (final t in _teeth)
            ((t['tooth_index'] as num?)?.toInt() == idx) ? updated : t,
        ];
        _editOutlineMode = false;
        _editOutline = null;
        _editOutlineBackup = null;
        _activeHandleIndex = null;
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

  void _applyShadeChoice(String shade) {
    if (shade.isEmpty || shade == '—' || !_vita.contains(shade)) return;

    // Zone-level preview only — Override on the zone chip commits this pick.
    // Used by Manual Override similar shades + VITA grid.
    setState(() {
      _ensureToothFocused();
      _selected = shade;
      _pendingShade = shade;
      _overallShadePick = false;
      _saveStatus = null;
      _error = null;
    });
    if (!mounted) return;
    if (_selectedToothIndex == null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a tooth zone first'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final zoneLabel = _focusZone[0].toUpperCase() + _focusZone.substring(1);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$shade selected — tap Override on Tooth ${_selectedToothIndex! + 1} · $zoneLabel to apply',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.navy,
      ),
    );
  }

  /// Case-level pick from Result "Top matches" — Save override works immediately.
  void _applyOverallShadeChoice(String shade) {
    if (shade.isEmpty || shade == '—' || !_vita.contains(shade)) return;
    setState(() {
      _ensureToothFocused();
      _selected = shade;
      _pendingShade = null;
      _overallShadePick = true;
      _saveStatus = null;
      _error = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$shade selected — tap Save override to apply'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.navy,
      ),
    );
  }

  List<Map<String, dynamic>> _teethPayloadForSave() {
    return _teeth.map((t) {
      final zonesIn = t['zones'];
      final zonesOut = <String, dynamic>{};
      if (zonesIn is Map) {
        for (final name in _zones) {
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

  Future<void> _bootstrap() async {
    try {
      await _reloadPatients(selectFirst: true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _pid(Map<String, dynamic> row) => (row['id'] as num).toInt();

  Future<void> _reloadPatients({bool selectFirst = false}) async {
    final patients = await widget.api.listPatients();
    if (!mounted) return;
    setState(() {
      _patients = patients;
      _error = null;
    });
    if (patients.isEmpty) {
      setState(() {
        _patient = null;
        _case = null;
      });
      return;
    }
    if (selectFirst || _patient == null) {
      await _selectPatient(patients.first);
      return;
    }
    final currentId = _pid(_patient!);
    final stillThere = patients.where((p) => _pid(p) == currentId);
    if (stillThere.isEmpty) {
      await _selectPatient(patients.first);
    } else {
      await _selectPatient(stillThere.first);
    }
  }

  Future<void> _selectPatient(Map<String, dynamic> patient) async {
    setState(() {
      _patient = patient;
      _saveStatus = null;
      _error = null;
    });
    try {
      final patientId = _pid(patient);
      final cases = await widget.api.listCases();
      final mine = cases
          .where((c) => (c['patient_id'] as num).toInt() == patientId)
          .toList();
      final caseRow = mine.isEmpty
          ? await widget.api.createCase(patientId)
          : mine.first;
      if (!mounted) return;
      setState(() => _case = caseRow);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _case = null;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _quickAddPatient() async {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add patient'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstCtrl,
                decoration: const InputDecoration(labelText: 'First name *'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastCtrl,
                decoration: const InputDecoration(labelText: 'Last name *'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true) {
      firstCtrl.dispose();
      lastCtrl.dispose();
      return;
    }
    final first = firstCtrl.text.trim();
    final last = lastCtrl.text.trim();
    firstCtrl.dispose();
    lastCtrl.dispose();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _error = 'First and last name are required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.api.createPatient({
        'first_name': first,
        'last_name': last,
      });
      await _reloadPatients();
      await _selectPatient(created);
      if (mounted) {
        setState(() => _saveStatus = 'Patient $first $last ready for shade');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAiFromGallery() async {
    setState(() {
      _busy = true;
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

      final name = file.name.isNotEmpty ? file.name : 'tooth.jpg';
      setState(() {
        _previewBytes = Uint8List.fromList(bytes);
        _previewFilename = name;
        _editOutlineMode = false;
        _editOutline = null;
        _editOutlineBackup = null;
      });

      final result = await widget.api.suggestShade(bytes, name);
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
        _analysisId = null;
        _selectedToothIndex = (first?['tooth_index'] as num?)?.toInt();
        _focusZone = 'middle';
        final iw = (result['image_width'] as num?)?.toDouble() ?? 0;
        final ih = (result['image_height'] as num?)?.toDouble() ?? 0;
        _analysisImageSize = (iw > 0 && ih > 0) ? Size(iw, ih) : Size.zero;
        _finalShade = null;
        _syncUiFromSelection();
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persist({required bool acceptAi}) async {
    if (_case == null || _patient == null) {
      setState(
        () => _error = _patients.isEmpty
            ? 'Add a patient first, then save the shade to their case.'
            : 'Select a patient from the list first.',
      );
      return;
    }
    if (_detected == '—' && acceptAi && _teeth.isEmpty) {
      setState(() => _error = 'Upload a tooth photo first so AI can detect a shade.');
      return;
    }
    final finalShade = acceptAi ? _detected : _selected;
    if (finalShade == '—' || !_vita.contains(finalShade)) {
      setState(() => _error = 'Pick a VITA shade before saving.');
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
    }

    final overridden = !acceptAi && finalShade != _detected;
    setState(() {
      _saving = true;
      _saveStatus = null;
      _error = null;
    });
    try {
      Map<String, dynamic> saved;
      if (_teeth.isNotEmpty) {
        saved = await widget.api.saveShadeAnalysis(
          caseId: _case!['id'] as int,
          teeth: _teethPayloadForSave(),
          selectedToothIndex: _selectedToothIndex ?? 0,
        );
        _analysisId = (saved['id'] as num?)?.toInt();
        // Merge zone ids from server for later patches
        final serverTeeth = _parseTeeth(saved['teeth']);
        if (serverTeeth.isNotEmpty) {
          // Keep local outlines after save — API tooth serialize omits geometry.
          final byIndex = {
            for (final t in _teeth)
              (t['tooth_index'] as num?)?.toInt(): t,
          };
          _teeth = [
            for (final st in serverTeeth)
              () {
                final row = Map<String, dynamic>.from(st);
                final idx = (st['tooth_index'] as num?)?.toInt();
                final local = idx == null ? null : byIndex[idx];
                if (local != null && local['geometry'] != null) {
                  row['geometry'] = local['geometry'];
                }
                if (local != null && local['label'] != null) {
                  row['label'] = local['label'];
                }
                // Keep top_matches / Lab samples — API serialize omits them.
                final localZones = local?['zones'];
                final serverZones = row['zones'];
                if (localZones is Map && serverZones is Map) {
                  final mergedZones = <String, dynamic>{};
                  for (final name in _zones) {
                    final sz = serverZones[name];
                    final lz = localZones[name];
                    if (sz is Map) {
                      final z = Map<String, dynamic>.from(sz);
                      if (lz is Map) {
                        if (z['top_matches'] == null && lz['top_matches'] != null) {
                          z['top_matches'] = lz['top_matches'];
                        }
                        if (z['sampled_lab'] == null && lz['sampled_lab'] != null) {
                          z['sampled_lab'] = lz['sampled_lab'];
                        }
                      }
                      mergedZones[name] = z;
                    } else if (lz is Map) {
                      mergedZones[name] = Map<String, dynamic>.from(lz);
                    }
                  }
                  row['zones'] = mergedZones;
                }
                return row;
              }(),
          ];
          _syncUiFromSelection(resetSelectedToDetected: false);
          _selected = finalShade;
        }
      } else {
        saved = await widget.api.saveShade(
          caseId: _case!['id'] as int,
          aiSuggested: _detected == '—' ? null : _detected,
          confidence: _confidence > 0 ? _confidence : null,
          finalShade: finalShade,
          overridden: overridden,
        );
      }
      await widget.api.markCaseInProgressIfPending(
        _case!['id'] as int,
        _case!['status']?.toString(),
      );
      _case = {..._case!, 'status': 'in_progress'};
      setState(() {
        _finalShade = finalShade;
        _selected = finalShade;
        _pendingShade = null;
        _overallShadePick = false;
        _saveStatus = overridden
            ? 'Saved override $finalShade on case #${_case!['id']}'
            : 'Accepted AI $finalShade on case #${_case!['id']}';
        _upsertSessionEntry(
          savedId: saved['id'],
          summaryShade: saved['summary_shade']?.toString() ?? finalShade,
          hasOverride: overridden || saved['has_override'] == true,
        );
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteHistoryAt(int index) async {
    if (index < 0 || index >= _history.length) return;
    final entry = _history[index];
    final shade = entry['shade']?.toString() ?? 'shade';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove save?'),
        content: Text('Delete $shade from this session.'),
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
    if (ok != true || !mounted) return;

    final shadeId = entry['id'];
    final caseId = entry['case_id'] ?? _case?['id'];
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
        if (entry['is_analysis'] == true &&
            shadeId is num &&
            _analysisId == shadeId.toInt()) {
          _analysisId = null;
        }
        _saveStatus = 'Removed $shade from session';
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  static const _actionBtnText = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  ButtonStyle _compactActionFilled(Color bg, {double minH = 34, double fontSize = 11}) =>
      FilledButton.styleFrom(
        backgroundColor: bg,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: Size(0, minH),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: _actionBtnText.copyWith(fontSize: fontSize),
      );

  ButtonStyle _compactActionOutlined({
    required Color fg,
    required Color side,
    double minH = 34,
    double fontSize = 11,
  }) =>
      OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: side),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: Size(0, minH),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: _actionBtnText.copyWith(fontSize: fontSize),
      );

  Widget _toothActionBar(double maxWidth) {
    final wide = maxWidth >= 520;
    final gap = wide ? 10.0 : 6.0;
    final iconSize = wide ? 16.0 : 14.0;
    final fontSize = wide ? 13.0 : 11.0;
    final minH = wide ? 42.0 : 36.0;
    final padH = wide ? 14.0 : 10.0;
    final padV = wide ? 10.0 : 8.0;

    Widget label(String text) => FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text, maxLines: 1, softWrap: false),
        );

    final Row actions;
    if (_editOutlineMode) {
      actions = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _cancelOutlineEdit,
              style: _compactActionOutlined(
                fg: AppColors.navy,
                side: AppColors.border,
                minH: minH,
                fontSize: fontSize,
              ),
              child: label('Cancel'),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                final bak = _editOutlineBackup;
                if (bak == null) return;
                setState(() {
                  _editOutline = bak.map((p) => [p[0], p[1]]).toList();
                  _activeHandleIndex = null;
                });
              },
              style: _compactActionOutlined(
                fg: AppColors.muted,
                side: AppColors.border,
                minH: minH,
                fontSize: fontSize,
              ),
              child: label('Reset'),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _applyOutlineEdit,
              icon: Icon(Icons.check, size: iconSize),
              label: label('Apply'),
              style: _compactActionFilled(
                AppColors.dentalBlue,
                minH: minH,
                fontSize: fontSize,
              ),
            ),
          ),
        ],
      );
    } else {
      final canEditTooth = _selectedToothIndex != null;
      actions = Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: canEditTooth ? _startOutlineEdit : null,
              icon: Icon(Icons.open_with, size: iconSize),
              label: label('Adjust edges'),
              style: _compactActionFilled(
                AppColors.navy,
                minH: minH,
                fontSize: fontSize,
              ),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: canEditTooth ? _deleteSelectedTooth : null,
              icon: Icon(Icons.delete_outline, size: iconSize),
              label: label('Delete'),
              style: _compactActionOutlined(
                fg: AppColors.danger,
                side: AppColors.danger,
                minH: minH,
                fontSize: fontSize,
              ),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _addTooth,
              icon: Icon(Icons.add, size: iconSize),
              label: label('Add tooth'),
              style: _compactActionOutlined(
                fg: AppColors.navy,
                side: AppColors.navy,
                minH: minH,
                fontSize: fontSize,
              ),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: FilledButton.icon(
              onPressed: _runAiFromGallery,
              icon: Icon(Icons.upload_file, size: iconSize),
              label: label(_previewBytes == null ? 'Upload' : 'Re-upload'),
              style: _compactActionFilled(
                AppColors.dentalBlue,
                minH: minH,
                fontSize: fontSize,
              ),
            ),
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.neo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        child: actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).shadeTitle,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      'Upload a tooth photo → AI detects VITA shade → confirm or override',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              PatientPickerButton(
                patients: _patients,
                selected: _patient,
                caseId: (_case?['id'] as num?)?.toInt(),
                enabled: !_busy,
                onSelect: _selectPatient,
                onAdd: _quickAddPatient,
                onRefresh: () async {
                  setState(() => _busy = true);
                  try {
                    await _reloadPatients();
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _runAiFromGallery,
                icon: Icon(_busy ? Icons.hourglass_top : Icons.upload_file, size: 18),
                label: Text(_busy ? 'Detecting…' : 'Upload & detect'),
              ),
            ],
          ),
          SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _error != null
                  ? Text(
                      _error!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.danger),
                    )
                  : (_saveStatus != null
                      ? Text(
                          _saveStatus!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.success),
                        )
                      : null),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: LayoutBuilder(
                    builder: (context, colConstraints) {
                      final actionSlotH = 66.0;
                      final overrideH = (colConstraints.maxHeight * 0.34)
                          .clamp(170.0, 300.0);
                      // Keep action bar mounted whenever a photo is loaded so
                      // the photo Expanded never resizes on select / add.
                      final showActions = !_busy && _previewBytes != null;
                      return Column(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                            Expanded(
                              flex: 3,
                              child: SectionCard(
                                padding: EdgeInsets.zero,
                                child: ClipRRect(
                                  borderRadius: AppRadii.border,
                                  child: Container(
                                    color: const Color(0xFF15263F),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (_previewBytes != null)
                                          Image.memory(
                                            _previewBytes!,
                                            fit: BoxFit.contain,
                                            gaplessPlayback: true,
                                            filterQuality: FilterQuality.low,
                                          )
                                        else
                                          const Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.add_photo_alternate_outlined,
                                                  color: Colors.white54,
                                                  size: 44,
                                                ),
                                                SizedBox(height: 10),
                                                Text(
                                                  'Upload a close-up tooth / smile photo',
                                                  style: TextStyle(color: Colors.white70),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (_previewBytes != null &&
                                            _teeth.isNotEmpty &&
                                            !_busy)
                                          Positioned.fill(
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                final box = Size(
                                                  constraints.maxWidth,
                                                  constraints.maxHeight,
                                                );
                                                final imgSize =
                                                    _analysisImageSize ==
                                                            Size.zero
                                                        ? box
                                                        : _analysisImageSize;
                                                return GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTapDown: _editOutlineMode
                                                      ? null
                                                      : (details) {
                                                          final hit =
                                                              hitTestTooth(
                                                            local: details
                                                                .localPosition,
                                                            box: box,
                                                            imageSize: imgSize,
                                                            teeth: _teeth,
                                                          );
                                                          if (hit != null) {
                                                            _selectTooth(hit);
                                                          }
                                                        },
                                                  onPanStart: !_editOutlineMode
                                                      ? null
                                                      : (details) {
                                                          final outline =
                                                              _editOutline;
                                                          if (outline == null) {
                                                            return;
                                                          }
                                                          final hi =
                                                              hitTestOutlineHandle(
                                                            local: details
                                                                .localPosition,
                                                            box: box,
                                                            imageSize: imgSize,
                                                            outline: outline,
                                                          );
                                                          setState(() =>
                                                              _activeHandleIndex =
                                                                  hi);
                                                        },
                                                  onPanUpdate: !_editOutlineMode
                                                      ? null
                                                      : (details) {
                                                          final hi =
                                                              _activeHandleIndex;
                                                          final outline =
                                                              _editOutline;
                                                          if (hi == null ||
                                                              outline == null) {
                                                            return;
                                                          }
                                                          final dest =
                                                              containRect(
                                                            box,
                                                            imgSize,
                                                          );
                                                          final norm =
                                                              localToNorm(
                                                            details
                                                                .localPosition,
                                                            dest,
                                                          );
                                                          setState(() {
                                                            outline[hi] = [
                                                              norm[0],
                                                              norm[1],
                                                            ];
                                                          });
                                                        },
                                                  onPanEnd: !_editOutlineMode
                                                      ? null
                                                      : (_) => setState(() =>
                                                          _activeHandleIndex =
                                                              null),
                                                  child: CustomPaint(
                                                    painter: ToothOverlayPainter(
                                                      teeth: _teeth,
                                                      selectedToothIndex:
                                                          _selectedToothIndex,
                                                      imageSize: imgSize,
                                                      focusZone: _focusZone,
                                                      editMode:
                                                          _editOutlineMode,
                                                      editOutline: _editOutline,
                                                      activeHandleIndex:
                                                          _activeHandleIndex,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        if (_busy)
                                          Container(
                                            color: Colors.black45,
                                            child: const Center(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CircularProgressIndicator(
                                                    color: Colors.white,
                                                  ),
                                                  SizedBox(height: 12),
                                                  Text(
                                                    'Analyzing shade…',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        if (_teeth.isNotEmpty && !_busy)
                                          Positioned(
                                            left: 12,
                                            right: 12,
                                            bottom: 12,
                                            child: Text(
                                              _editOutlineMode
                                                  ? 'Drag a few corner/side handles to reshape the tooth, then Apply.'
                                                  : 'Tap a tooth to select. Adjust edges, add, or delete.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.85),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                shadows: const [
                                                  Shadow(
                                                    blurRadius: 6,
                                                    color: Colors.black54,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        if (!_busy &&
                                            (_teeth.isEmpty ||
                                                _selectedToothIndex == null))
                                          Positioned(
                                            left: 12,
                                            right: 12,
                                            bottom: 48,
                                            child: FilledButton.icon(
                                              onPressed: _runAiFromGallery,
                                              icon: const Icon(
                                                Icons.upload_file,
                                                size: 18,
                                              ),
                                              label: Text(
                                                _previewBytes == null
                                                    ? 'Upload tooth photo'
                                                    : 'Upload another',
                                              ),
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.dentalBlue,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: SectionCard(
                                padding: const EdgeInsets.all(14),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SingleChildScrollView(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: constraints.maxHeight,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            const Text(
                                              'Result',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                            ),
                                            if (_teeth.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              ..._teeth.map((t) {
                                                final idx =
                                                    (t['tooth_index'] as num)
                                                        .toInt();
                                                final rejected =
                                                    t['rejected'] == true;
                                                final active =
                                                    _selectedToothIndex == idx;
                                                final label =
                                                    t['label']?.toString() ??
                                                        'Tooth ${idx + 1}';
                                                return Padding(
                                                  padding: const EdgeInsets.only(
                                                    bottom: 8,
                                                  ),
                                                  child: Material(
                                                    color: Colors.transparent,
                                                    child: InkWell(
                                                      onTap: () =>
                                                          _selectTooth(idx),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        12,
                                                      ),
                                                      child: Ink(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(10),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: active
                                                              ? AppColors
                                                                  .dentalBlue
                                                                  .withValues(
                                                                  alpha: 0.12,
                                                                )
                                                              : AppColors.neo,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                          border: Border.all(
                                                            color: active
                                                                ? AppColors
                                                                    .dentalBlue
                                                                : AppColors
                                                                    .border,
                                                            width: active
                                                                ? 1.8
                                                                : 1,
                                                          ),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                Text(
                                                                  label,
                                                                  style:
                                                                      const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                    fontSize: 13,
                                                                  ),
                                                                ),
                                                                if (rejected) ...[
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Text(
                                                                    t['reject_reason']
                                                                            ?.toString() ??
                                                                        'flagged',
                                                                    style:
                                                                        const TextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      color: AppColors
                                                                          .warning,
                                                                    ),
                                                                  ),
                                                                ],
                                                                const Spacer(),
                                                                if (active) ...[
                                                                  IconButton(
                                                                    tooltip:
                                                                        'Delete tooth',
                                                                    onPressed:
                                                                        _deleteSelectedTooth,
                                                                    icon:
                                                                        const Icon(
                                                                      Icons
                                                                          .delete_outline,
                                                                      size: 20,
                                                                      color: AppColors
                                                                          .danger,
                                                                    ),
                                                                    visualDensity:
                                                                        VisualDensity
                                                                            .compact,
                                                                    padding:
                                                                        EdgeInsets
                                                                            .zero,
                                                                    constraints:
                                                                        const BoxConstraints(
                                                                      minWidth:
                                                                          36,
                                                                      minHeight:
                                                                          36,
                                                                    ),
                                                                  ),
                                                                  const Text(
                                                                    'Selected',
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      color: AppColors
                                                                          .dentalBlue,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ],
                                                            ),
                                                            const SizedBox(
                                                              height: 8,
                                                            ),
                                                            Row(
                                                              children: [
                                                                for (final zName
                                                                    in _zones) ...[
                                                                  if (zName !=
                                                                      _zones
                                                                          .first)
                                                                    const SizedBox(
                                                                      width: 6,
                                                                    ),
                                                                  Expanded(
                                                                    child:
                                                                        _MiniZoneChip(
                                                                      label: zName[0]
                                                                              .toUpperCase() +
                                                                          zName.substring(
                                                                            1,
                                                                          ),
                                                                      shade: () {
                                                                        final focusedZone =
                                                                            active &&
                                                                                _focusZone ==
                                                                                    zName;
                                                                        if (focusedZone &&
                                                                            _pendingShade !=
                                                                                null) {
                                                                          return _pendingShade;
                                                                        }
                                                                        return _zoneEffective(
                                                                          _zoneOf(
                                                                            t,
                                                                            zName,
                                                                          ),
                                                                        );
                                                                      }(),
                                                                      overridden:
                                                                          _zoneOverridden(
                                                                        _zoneOf(
                                                                          t,
                                                                          zName,
                                                                        ),
                                                                      ),
                                                                      pending: active &&
                                                                          _focusZone ==
                                                                              zName &&
                                                                          _pendingShade !=
                                                                              null,
                                                                      focused: active &&
                                                                          _focusZone ==
                                                                              zName,
                                                                      swatch:
                                                                          _swatch,
                                                                      onTap: () {
                                                                        _selectTooth(
                                                                          idx,
                                                                          zone:
                                                                              zName,
                                                                        );
                                                                      },
                                                                      onOverride: () {
                                                                        _beginZoneOverride(
                                                                          idx,
                                                                          zName,
                                                                        );
                                                                      },
                                                                    ),
                                                                  ),
                                                                ],
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ],
                                            const SizedBox(height: 10),
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: AppColors.aiPurpleSoft,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: AppColors.aiPurple.withValues(alpha: 0.35),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 52,
                                                    height: 52,
                                                    decoration: BoxDecoration(
                                                      color: _detected == '—'
                                                          ? AppColors.border
                                                          : _swatch(_detected),
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(color: AppColors.border),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          _detected == '—' ? 'No detection yet' : _detected,
                                                          style: const TextStyle(
                                                            fontSize: 28,
                                                            fontWeight: FontWeight.w800,
                                                            color: AppColors.navy,
                                                            height: 1.1,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          _confidence > 0
                                                              ? '${(_confidence * 100).round()}% match · $_focusZone'
                                                              : 'Upload a photo to analyze',
                                                          style: const TextStyle(
                                                            fontSize: 12,
                                                            color: AppColors.muted,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: LinearProgressIndicator(
                                                value: _confidence.clamp(0, 1),
                                                minHeight: 6,
                                                backgroundColor: AppColors.border,
                                                color: AppColors.aiPurple,
                                              ),
                                            ),
                                            if (_pendingShade != null) ...[
                                              const SizedBox(height: 10),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: AppColors.warningSoft,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Pending: $_pendingShade — tap Override on the zone chip to confirm',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.warning,
                                                  ),
                                                ),
                                              ),
                                            ] else if (_selected != '—' && _selected != _detected) ...[
                                              const SizedBox(height: 10),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: AppColors.warningSoft,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Override selected: $_selected',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.warning,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (_finalShade != null) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                'Saved final: $_finalShade',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.success,
                                                ),
                                              ),
                                            ],
                                            if (_overallTopMatches.isNotEmpty) ...[
                                              const SizedBox(height: 12),
                                              const Text(
                                                'Top matches',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              const Text(
                                                'Across all teeth',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: _overallTopMatches.take(5).map((m) {
                                                  final s = m['shade']?.toString() ?? '';
                                                  if (s.isEmpty) {
                                                    return const SizedBox.shrink();
                                                  }
                                                  final active = _selected == s &&
                                                      _pendingShade == null;
                                                  final de = m['delta_e_2000'] ?? m['distance'];
                                                  return InkWell(
                                                    onTap: () => _applyOverallShadeChoice(s),
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: _swatch(s).withValues(alpha: 0.45),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(
                                                          color: active ? AppColors.navy : AppColors.border,
                                                          width: active ? 1.5 : 1,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        de == null
                                                            ? s
                                                            : '$s · ΔE ${de is num ? de.toStringAsFixed(1) : de}',
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w700,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ],
                                            const SizedBox(height: 14),
                                            FilledButton(
                                              onPressed: _saving || _detected == '—'
                                                  ? null
                                                  : () => _persist(acceptAi: true),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: AppColors.navy,
                                                minimumSize: const Size.fromHeight(40),
                                              ),
                                              child: Text(
                                                _saving
                                                    ? 'Saving…'
                                                    : (_detected == '—' ? 'Accept AI' : 'Accept $_detected'),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            OutlinedButton(
                                              onPressed: _saving ? null : () => _persist(acceptAi: false),
                                              style: OutlinedButton.styleFrom(
                                                minimumSize: const Size.fromHeight(40),
                                              ),
                                              child: Text(
                                                _selected == '—' || _selected == _detected
                                                    ? 'Save override'
                                                    : 'Save override ($_selected)',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                          // Fixed slots so selecting a tooth / override pulse
                          // never steals height from the photo Expanded.
                          SizedBox(
                            height: actionSlotH,
                            child: showActions
                                ? Align(
                                    alignment: Alignment.center,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return _toothActionBar(
                                          constraints.maxWidth,
                                        );
                                      },
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: overrideH,
                            child: SingleChildScrollView(
                              child: KeyedSubtree(
                                key: _manualOverrideKey,
                                child: _manualOverrideCard(),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: MediaQuery.sizeOf(context).width < 900 ? 160 : 200,
                  child: SectionCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Session', style: TextStyle(fontWeight: FontWeight.w700)),
                        const Text(
                          'Saves this visit',
                          style: TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _history.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No saves yet',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _history.length,
                                  itemBuilder: (context, i) {
                                    final h = _history[i];
                                    final teethRaw = h['teeth'];
                                    final toothSummaries = <Map<String, dynamic>>[];
                                    if (teethRaw is List) {
                                      for (final t in teethRaw) {
                                        if (t is Map) {
                                          toothSummaries.add(
                                            Map<String, dynamic>.from(t),
                                          );
                                        }
                                      }
                                    }
                                    final caseKey =
                                        (h['case_id'] as num?)?.toInt() ?? i;
                                    return _Recent(
                                      key: ValueKey('session-$caseKey'),
                                      name: h['name'] as String? ?? 'Patient',
                                      shade: h['shade'] as String,
                                      conf: (h['conf'] as num?)?.toDouble() ?? 0,
                                      color: _swatch(h['shade'] as String),
                                      isOverride: h['override'] == true,
                                      teeth: toothSummaries,
                                      swatch: _swatch,
                                      onDelete: () => _deleteHistoryAt(i),
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

  Widget _manualOverrideCard() {
    final zoneLabel = _focusZone[0].toUpperCase() + _focusZone.substring(1);
    final toothLabel = _selectedToothIndex == null
        ? null
        : 'T${_selectedToothIndex! + 1} · $zoneLabel';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;
        final chipW = wide ? 48.0 : 42.0;

        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Manual Override — VITA Classical',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if (toothLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Editing $toothLabel',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dentalBlue,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final guideW = wide ? 200.0 : 148.0;
                  final guideH = wide ? 168.0 : 132.0;
                  final guide = SizedBox(
                    width: guideW,
                    height: guideH,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/clinical/vita-classical-a1-d4.png',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  );

                  final vitaWrap = Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _vita.map((s) {
                      final selected = _selected == s;
                      return InkWell(
                        onTap: () => _applyShadeChoice(s),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: chipW,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? AppColors.navy
                                  : AppColors.border,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                height: wide ? 22 : 18,
                                decoration: BoxDecoration(
                                  color: _swatch(s),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                s,
                                style: TextStyle(
                                  fontSize: wide ? 10 : 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );

                  if (_topMatches.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(alignment: Alignment.centerLeft, child: guide),
                        const SizedBox(height: 10),
                        vitaWrap,
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Similar shades',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        toothLabel == null
                            ? 'For the focused zone'
                            : 'For $toothLabel',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final m in _topMatches.take(5)) ...[
                                    _SimilarShadeChip(
                                      shade: m['shade']?.toString() ?? '',
                                      deltaE: m['delta_e_2000'] ??
                                          m['distance'],
                                      selected: _selected ==
                                          m['shade']?.toString(),
                                      swatch: _swatch,
                                      onTap: () {
                                        final s = m['shade']?.toString();
                                        if (s != null && s.isNotEmpty) {
                                          _applyShadeChoice(s);
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: wide ? 12 : 8),
                          guide,
                        ],
                      ),
                      const SizedBox(height: 10),
                      vitaWrap,
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniZoneChip extends StatelessWidget {
  const _MiniZoneChip({
    required this.label,
    required this.shade,
    required this.overridden,
    required this.focused,
    required this.swatch,
    required this.onTap,
    required this.onOverride,
    this.pending = false,
  });

  final String label;
  final String? shade;
  final bool overridden;
  final bool pending;
  final bool focused;
  final Color Function(String) swatch;
  final VoidCallback onTap;
  final VoidCallback onOverride;

  @override
  Widget build(BuildContext context) {
    final swatchBox = Container(
      height: 18,
      decoration: BoxDecoration(
        color: shade == null ? AppColors.border : swatch(shade!),
        borderRadius: BorderRadius.circular(4),
      ),
    );

    final borderColor = pending
        ? AppColors.warning
        : (overridden
            ? AppColors.warning
            : (focused ? AppColors.dentalBlue : AppColors.border));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.neo,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: focused || overridden || pending ? 1.5 : 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: focused ? 0.35 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (focused)
                      ImageFiltered(
                        imageFilter:
                            ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
                        child: swatchBox,
                      )
                    else
                      swatchBox,
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      shade ?? '—',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: (overridden || pending)
                            ? AppColors.warning
                            : AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              if (focused)
                Positioned.fill(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 72,
                        maxHeight: 28,
                      ),
                      child: Material(
                        color: AppColors.navy.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(7),
                        child: InkWell(
                          onTap: onOverride,
                          borderRadius: BorderRadius.circular(7),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            child: Text(
                              'Override',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
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

class _SimilarShadeChip extends StatelessWidget {
  const _SimilarShadeChip({
    required this.shade,
    required this.deltaE,
    required this.selected,
    required this.swatch,
    required this.onTap,
  });

  final String shade;
  final Object? deltaE;
  final bool selected;
  final Color Function(String) swatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (shade.isEmpty) return const SizedBox.shrink();
    final deText = deltaE is num
        ? 'ΔE ${(deltaE as num).toStringAsFixed(1)}'
        : (deltaE?.toString() ?? '');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 72,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
        decoration: BoxDecoration(
          color: swatch(shade).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 28,
              decoration: BoxDecoration(
                color: swatch(shade),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              shade,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: AppColors.navy,
              ),
            ),
            if (deText.isNotEmpty)
              Text(
                deText,
                style: const TextStyle(fontSize: 10, color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _Recent extends StatefulWidget {
  const _Recent({
    super.key,
    required this.name,
    required this.shade,
    required this.conf,
    required this.color,
    required this.onDelete,
    required this.swatch,
    this.teeth = const [],
    this.isOverride = false,
  });

  final String name;
  final String shade;
  final double conf;
  final Color color;
  final bool isOverride;
  final List<Map<String, dynamic>> teeth;
  final Color Function(String) swatch;
  final VoidCallback onDelete;

  @override
  State<_Recent> createState() => _RecentState();
}

class _RecentState extends State<_Recent> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final teeth = widget.teeth;
    final countLabel = teeth.isEmpty
        ? null
        : (teeth.length == 1 ? '1 tooth' : '${teeth.length} teeth');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.neo,
        borderRadius: BorderRadius.circular(12),
        boxShadow: NeoShadows.soft(depth: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: teeth.isEmpty
                      ? null
                      : () => setState(() => _expanded = !_expanded),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      if (countLabel != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              countLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                            Icon(
                              _expanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Text(
                widget.shade,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(width: 2),
              Tooltip(
                message: 'Remove from session',
                child: InkWell(
                  onTap: widget.onDelete,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (widget.isOverride) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'OVERRIDE',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (_expanded && teeth.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final t in teeth) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t['label']?.toString() ??
                          'Tooth ${((t['tooth_index'] as num?)?.toInt() ?? 0) + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final z in const ['cervical', 'middle', 'incisal'])
                          _SessionZoneChip(
                            zone: z[0].toUpperCase(),
                            shade: (t['zones'] is Map)
                                ? (t['zones'] as Map)[z]?.toString()
                                : null,
                            swatch: widget.swatch,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ] else if (teeth.isEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: widget.conf.clamp(0, 1),
                minHeight: 5,
                backgroundColor: AppColors.border,
                color: AppColors.aiPurple,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.conf > 0
                  ? '${(widget.conf * 100).round()}% confidence'
                  : 'Manual selection',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionZoneChip extends StatelessWidget {
  const _SessionZoneChip({
    required this.zone,
    required this.shade,
    required this.swatch,
  });

  final String zone;
  final String? shade;
  final Color Function(String) swatch;

  @override
  Widget build(BuildContext context) {
    final has = shade != null && shade!.isNotEmpty && shade != '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: has ? swatch(shade!).withValues(alpha: 0.55) : AppColors.border,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$zone ${has ? shade : '—'}',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

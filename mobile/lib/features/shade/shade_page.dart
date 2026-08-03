import 'dart:typed_data';

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
  String? _note;
  String? _finalShade;
  bool _busy = false;
  bool _saving = false;
  bool _loading = true;
  String? _saveStatus;
  String? _error;
  Uint8List? _previewBytes;
  String _previewFilename = 'tooth.jpg';
  List<Map<String, dynamic>> _topMatches = [];
  final List<Map<String, dynamic>> _history = [];

  // Per-tooth / per-zone analysis (added onto existing UI)
  List<Map<String, dynamic>> _teeth = [];
  int? _selectedToothIndex;
  String _focusZone = 'middle';
  int? _analysisId;
  Size _analysisImageSize = Size.zero;

  // Manual outline nudge (dentist adjusts auto edges slightly)
  bool _editOutlineMode = false;
  List<List<double>>? _editOutline;
  List<List<double>>? _editOutlineBackup;
  int? _activeHandleIndex;

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

  /// Sync the existing Result / Top matches / swatch selection from the focused tooth+zone.
  void _syncUiFromSelection({bool resetSelectedToDetected = true}) {
    final tooth = _selectedTooth;
    if (tooth == null) {
      _detected = '—';
      _confidence = 0;
      _topMatches = [];
      if (resetSelectedToDetected) _selected = '—';
      return;
    }
    final zone = _zoneOf(tooth, _focusZone) ?? _zoneOf(tooth, 'middle');
    final detected = zone?['detected_shade'] as String?;
    final effective = _zoneEffective(zone);
    _detected = detected ?? '—';
    _confidence = (tooth['confidence'] as num?)?.toDouble() ?? 0;
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
  }

  void _selectTooth(int index, {String? zone}) {
    if (_editOutlineMode) return; // finish or cancel edit first
    setState(() {
      _selectedToothIndex = index;
      _focusZone = zone ?? 'middle';
      _syncUiFromSelection();
      _saveStatus = null;
    });
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
    });
    AppHaptics.warn();
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
    setState(() {
      _selected = shade;
      _saveStatus = null;
      final tooth = _selectedTooth;
      if (tooth != null) {
        final zone = _zoneOf(tooth, _focusZone);
        if (zone != null) {
          // Keep detected; store dentist choice as override when it differs
          final detected = zone['detected_shade'] as String?;
          zone['override_shade'] = (detected != null && shade == detected) ? null : shade;
        }
      }
    });
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
        _note = result['note'] as String? ??
            'Per-tooth zone shades detected. Confirm or override below.';
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

    // Stamp Accept AI / override onto the focused zone before save
    final tooth = _selectedTooth;
    if (tooth != null) {
      final zone = _zoneOf(tooth, _focusZone);
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
          _teeth = serverTeeth;
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
        _saveStatus = overridden
            ? 'Saved override $finalShade on case #${_case!['id']}'
            : 'Accepted AI $finalShade on case #${_case!['id']}';
        _history.insert(0, {
          'id': saved['id'],
          'case_id': _case!['id'],
          'name':
              '${_patient?['first_name'] ?? ''} ${_patient?['last_name'] ?? ''}'.trim(),
          'shade': finalShade,
          'conf': _confidence,
          'override': overridden || saved['has_override'] == true,
          'is_analysis': _teeth.isNotEmpty,
        });
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
          if (_saveStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _saveStatus!,
                style: const TextStyle(color: AppColors.success),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
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
                                        if (_detected != '—' && !_busy)
                                          Positioned(
                                            left: 12,
                                            top: 12,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppColors.navy,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                _selectedToothIndex == null
                                                    ? 'AI: $_detected · ${(_confidence * 100).round()}%'
                                                    : 'T${_selectedToothIndex! + 1} · $_focusZone · $_detected',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (_teeth.isNotEmpty && !_busy)
                                          Positioned(
                                            left: 12,
                                            right: 12,
                                            bottom: 56,
                                            child: Text(
                                              _editOutlineMode
                                                  ? 'Drag a few corner/side handles to reshape the tooth, then Apply.'
                                                  : 'Tap a tooth to select. Adjust edges, or Delete tooth if one crown was split into two.',
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
                                        if (_teeth.isNotEmpty &&
                                            !_busy &&
                                            _selectedToothIndex != null)
                                          Positioned(
                                            left: 12,
                                            right: 12,
                                            bottom: 12,
                                            child: _editOutlineMode
                                                ? Row(
                                                    children: [
                                                      Expanded(
                                                        child: OutlinedButton(
                                                          onPressed:
                                                              _cancelOutlineEdit,
                                                          style: OutlinedButton
                                                              .styleFrom(
                                                            foregroundColor:
                                                                Colors.white,
                                                            side:
                                                                const BorderSide(
                                                              color:
                                                                  Colors.white70,
                                                            ),
                                                          ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: OutlinedButton(
                                                          onPressed: () {
                                                            final bak =
                                                                _editOutlineBackup;
                                                            if (bak == null) {
                                                              return;
                                                            }
                                                            setState(() {
                                                              _editOutline = bak
                                                                  .map(
                                                                    (p) => [
                                                                      p[0],
                                                                      p[1],
                                                                    ],
                                                                  )
                                                                  .toList();
                                                              _activeHandleIndex =
                                                                  null;
                                                            });
                                                          },
                                                          style: OutlinedButton
                                                              .styleFrom(
                                                            foregroundColor:
                                                                Colors.white,
                                                            side:
                                                                const BorderSide(
                                                              color:
                                                                  Colors.white54,
                                                            ),
                                                          ),
                                                          child: const Text(
                                                            'Reset',
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        flex: 2,
                                                        child: FilledButton.icon(
                                                          onPressed:
                                                              _applyOutlineEdit,
                                                          icon: const Icon(
                                                            Icons.check,
                                                            size: 18,
                                                          ),
                                                          label: const Text(
                                                            'Apply',
                                                          ),
                                                          style: FilledButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                AppColors
                                                                    .dentalBlue,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : Row(
                                                    children: [
                                                      Expanded(
                                                        child: FilledButton.icon(
                                                          onPressed:
                                                              _startOutlineEdit,
                                                          icon: const Icon(
                                                            Icons.open_with,
                                                            size: 18,
                                                          ),
                                                          label: const Text(
                                                            'Adjust edges',
                                                          ),
                                                          style: FilledButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                AppColors.navy,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: OutlinedButton.icon(
                                                          onPressed:
                                                              _deleteSelectedTooth,
                                                          icon: const Icon(
                                                            Icons.delete_outline,
                                                            size: 18,
                                                          ),
                                                          label: const Text(
                                                            'Delete',
                                                          ),
                                                          style: OutlinedButton
                                                              .styleFrom(
                                                            foregroundColor:
                                                                Colors.white,
                                                            side:
                                                                const BorderSide(
                                                              color: Color(
                                                                0xFFFF8A80,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: FilledButton.icon(
                                                          onPressed:
                                                              _runAiFromGallery,
                                                          icon: const Icon(
                                                            Icons.upload_file,
                                                            size: 18,
                                                          ),
                                                          label: Text(
                                                            _previewBytes == null
                                                                ? 'Upload'
                                                                : 'Re-upload',
                                                          ),
                                                          style: FilledButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                AppColors
                                                                    .dentalBlue,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                          )
                                        else
                                          Positioned(
                                            left: 12,
                                            right: 12,
                                            bottom: 12,
                                            child: FilledButton.icon(
                                              onPressed:
                                                  _busy ? null : _runAiFromGallery,
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
                                              const Text(
                                                'Teeth (left → right on photo)',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.muted,
                                                ),
                                              ),
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
                                                                      shade: _zoneEffective(
                                                                        _zoneOf(
                                                                          t,
                                                                          zName,
                                                                        ),
                                                                      ),
                                                                      overridden:
                                                                          _zoneOverridden(
                                                                        _zoneOf(
                                                                          t,
                                                                          zName,
                                                                        ),
                                                                      ),
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
                                                              ? '${(_confidence * 100).round()}% · $_focusZone zone'
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
                                            if (_selected != '—' && _selected != _detected) ...[
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
                                            if (_topMatches.isNotEmpty) ...[
                                              const SizedBox(height: 12),
                                              const Text(
                                                'Top matches',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: _topMatches.take(5).map((m) {
                                                  final s = m['shade']?.toString() ?? '';
                                                  final active = _selected == s;
                                                  final de = m['delta_e_2000'] ?? m['distance'];
                                                  return InkWell(
                                                    onTap: () => _applyShadeChoice(s),
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
                                            const SizedBox(height: 10),
                                            Text(
                                              _note ??
                                                  'Natural light, close-up tooth photos work best. Confirm or override below.',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                height: 1.35,
                                                color: AppColors.muted,
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
                      const SizedBox(height: 12),
                      SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Manual Override — VITA Classical',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/clinical/vita-classical-a1-d4.png',
                                height: 90,
                                width: double.infinity,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _vita.map((s) {
                                final selected = _selected == s;
                                return InkWell(
                                  onTap: () => _applyShadeChoice(s),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 48,
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: selected ? AppColors.navy : AppColors.border,
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: _swatch(s),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          s,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 200,
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
                                    return _Recent(
                                      name: h['name'] as String? ?? 'Patient',
                                      shade: h['shade'] as String,
                                      conf: (h['conf'] as num?)?.toDouble() ?? 0,
                                      color: _swatch(h['shade'] as String),
                                      isOverride: h['override'] == true,
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
}

class _MiniZoneChip extends StatelessWidget {
  const _MiniZoneChip({
    required this.label,
    required this.shade,
    required this.overridden,
    required this.focused,
    required this.swatch,
    required this.onTap,
  });

  final String label;
  final String? shade;
  final bool overridden;
  final bool focused;
  final Color Function(String) swatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.neo,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: overridden
                ? AppColors.warning
                : (focused ? AppColors.dentalBlue : AppColors.border),
            width: focused || overridden ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 18,
              decoration: BoxDecoration(
                color: shade == null ? AppColors.border : swatch(shade!),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              shade ?? '—',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: overridden ? AppColors.warning : AppColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({
    required this.name,
    required this.shade,
    required this.conf,
    required this.color,
    required this.onDelete,
    this.isOverride = false,
  });

  final String name;
  final String shade;
  final double conf;
  final Color color;
  final bool isOverride;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
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
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
              Text(
                shade,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(width: 2),
              Tooltip(
                message: 'Remove from session',
                child: InkWell(
                  onTap: onDelete,
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
          if (isOverride) ...[
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
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: conf.clamp(0, 1),
              minHeight: 5,
              backgroundColor: AppColors.border,
              color: AppColors.aiPurple,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            conf > 0 ? '${(conf * 100).round()}% confidence' : 'Manual selection',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/patient_picker.dart';
import '../../core/widgets/ui_kit.dart';

/// Scan-body diameter → manufacturer / tooth (provisional table until client data).
class ScanBodyPage extends StatefulWidget {
  const ScanBodyPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ScanBodyPage> createState() => _ScanBodyPageState();
}

class _ScanBodyPageState extends State<ScanBodyPage> {
  final _diameterCtrl = TextEditingController(text: '4.0');

  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _case;

  List<Map<String, dynamic>> _table = [];
  Map<String, dynamic>? _match;
  Uint8List? _previewBytes;
  Offset? _circleCenter;
  double? _circleRadius;
  Size? _imageSize;

  double _pixelsPerMm = 20;
  bool _needsCalibration = false;
  bool _scaleLocked = false; // only send ppm after user calibrated

  bool _loading = true;
  bool _busy = false;
  bool _saving = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _diameterCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final rows = await widget.api.scanBodyTable();
      final patients = await widget.api.listPatients();
      setState(() {
        _table = rows;
        _patients = patients;
      });
      if (patients.isNotEmpty) await _selectPatient(patients.first);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectPatient(Map<String, dynamic> patient) async {
    setState(() {
      _patient = patient;
      _status = null;
      _error = null;
    });
    final cases = await widget.api.listCases();
    final mine = cases.where((c) => c['patient_id'] == patient['id']).toList();
    final caseRow = mine.isEmpty
        ? await widget.api.createCase(patient['id'] as int)
        : mine.first;
    setState(() => _case = caseRow);
    await _restoreSaved(caseRow['id'] as int);
  }

  Future<void> _reloadPatients() async {
    final patients = await widget.api.listPatients();
    if (!mounted) return;
    setState(() => _patients = patients);
    if (patients.isEmpty) {
      setState(() {
        _patient = null;
        _case = null;
      });
      return;
    }
    final currentId = _patient?['id'];
    final stillThere = patients.where((p) => p['id'] == currentId);
    if (_patient == null || stillThere.isEmpty) {
      await _selectPatient(patients.first);
    } else {
      await _selectPatient(stillThere.first);
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
        setState(() => _status = 'Patient $first $last ready for scan body');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreSaved(int caseId) async {
    try {
      final saved = await widget.api.latestScanBody(caseId);
      if (saved == null || !mounted) return;
      final d = saved['detected_diameter'] ?? saved['table_diameter_mm'];
      setState(() {
        if (d != null) _diameterCtrl.text = '$d';
        _match = {
          'detected_diameter': saved['detected_diameter'],
          'table_diameter_mm': saved['table_diameter_mm'],
          'matched_tooth_position': saved['matched_tooth_position'],
          'matched_manufacturer': saved['matched_manufacturer'],
          'matched_platform': saved['matched_platform'],
          'confidence_score': saved['confidence_score'],
          'note': 'Restored saved match for this case.',
          'provisional': true,
        };
        _status =
            'Restored ${saved['matched_manufacturer'] ?? 'match'} · '
            'tooth ${saved['matched_tooth_position'] ?? '—'}';
      });
    } catch (_) {}
  }

  void _applyMatch(Map<String, dynamic> result) {
    final d = result['detected_diameter'];
    // Only overwrite the mm field when we have a real calibrated/manual reading
    if (d != null) {
      _diameterCtrl.text = '$d';
    }
    final ppm = result['pixels_per_mm'];
    if (ppm is num && ppm > 0) {
      _pixelsPerMm = ppm.toDouble();
    }

    Offset? center;
    double? radius;
    Size? imgSize;
    final c = result['center'];
    if (c is Map) {
      final x = (c['x'] as num?)?.toDouble();
      final y = (c['y'] as num?)?.toDouble();
      if (x != null && y != null) center = Offset(x, y);
    }
    final r = result['pixel_radius'];
    if (r is num) radius = r.toDouble();
    final size = result['image_size'];
    if (size is Map) {
      final w = (size['width'] as num?)?.toDouble();
      final h = (size['height'] as num?)?.toDouble();
      if (w != null && h != null) imgSize = Size(w, h);
    }

    setState(() {
      _match = result;
      _circleCenter = center;
      _circleRadius = radius;
      _imageSize = imgSize;
      _needsCalibration = result['needs_calibration'] == true;
      _scaleLocked = result['calibrated'] == true;
      _error = null;
    });
  }

  Future<void> _matchManual() async {
    if (_busy) return;
    final mm = double.tryParse(_diameterCtrl.text.trim());
    if (mm == null || mm <= 0) {
      setState(() => _error = 'Enter a valid diameter in mm');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final result = await widget.api.matchScanBody(mm);
      _applyMatch(result);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detectFromPhoto({double? knownDiameterMm}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      Uint8List bytes;
      String name;
      if (_previewBytes != null && knownDiameterMm != null) {
        bytes = _previewBytes!;
        name = 'scan_body.jpg';
      } else {
        final picked = await FilePicker.pickFiles(
          type: FileType.image,
          withData: true,
          allowMultiple: false,
        );
        if (picked == null || picked.files.isEmpty) return;
        final file = picked.files.first;
        final raw = file.bytes;
        if (raw == null || raw.isEmpty) {
          setState(() => _error = 'Could not read image bytes.');
          return;
        }
        bytes = Uint8List.fromList(raw);
        name = file.name.isNotEmpty ? file.name : 'scan_body.jpg';
        setState(() => _previewBytes = bytes);
      }

      final result = await widget.api.detectScanBody(
        bytes,
        name,
        // Never send a blind default scale — that invented values like 23 mm.
        pixelsPerMm: knownDiameterMm == null && _scaleLocked ? _pixelsPerMm : null,
        knownDiameterMm: knownDiameterMm,
      );
      _applyMatch(result);
      if (result['detected_diameter'] == null) {
        setState(
          () => _status =
              'Circle found in pixels — enter diameter in mm (3–6), or tap a table row.',
        );
      } else if (result['needs_calibration'] == true) {
        setState(
          () => _status =
              'Circle detected — calibrate scale or confirm diameter for accuracy.',
        );
      } else {
        setState(() => _status = 'Matched from photo (${result['detected_diameter']} mm).');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reDetectWithScale() async {
    if (_previewBytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _scaleLocked = true;
    });
    try {
      final result = await widget.api.detectScanBody(
        _previewBytes!,
        'scan_body.jpg',
        pixelsPerMm: _pixelsPerMm,
      );
      _applyMatch(result);
      if (result['detected_diameter'] == null) {
        setState(
          () => _status =
              'Scale ${_pixelsPerMm.toStringAsFixed(0)} px/mm is outside 3–6 mm range — adjust or calibrate.',
        );
      } else {
        setState(
          () => _status =
              'Measured ${result['detected_diameter']} mm at ${_pixelsPerMm.toStringAsFixed(1)} px/mm.',
        );
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _calibrateWithKnown() async {
    final mm = double.tryParse(_diameterCtrl.text.trim());
    if (mm == null || mm <= 0) {
      setState(() => _error = 'Enter the known diameter in millimetres (mm)');
      return;
    }
    if (mm < 2.5 || mm > 7.0) {
      setState(
        () => _error =
            'Scan-body diameters are typically 3–6 mm (not metres). Check your value.',
      );
      return;
    }
    if (_previewBytes == null || _circleRadius == null) {
      setState(() => _error = 'Detect a circle from a photo first');
      return;
    }
    setState(() => _scaleLocked = true);
    await _detectFromPhoto(knownDiameterMm: mm);
  }

  Future<void> _useTableRow(Map<String, dynamic> row, {bool override = true}) async {
    final mm = (row['diameter_mm'] as num).toDouble();
    _diameterCtrl.text = mm.toString();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.matchScanBody(mm);
      // Force selection to this exact row when user picks from table
      result['matched_tooth_position'] = row['tooth_position'];
      result['matched_manufacturer'] = row['manufacturer'];
      result['matched_platform'] = row['platform'];
      result['table_diameter_mm'] = row['diameter_mm'];
      result['detected_diameter'] = mm;
      result['confidence_score'] = 0.99;
      result['ambiguous'] = false;
      result['note'] = override
          ? 'Selected from reference table.'
          : result['note'];
      _applyMatch(result);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_case == null) {
      setState(() => _error = 'Select a patient first');
      return;
    }
    if (_match == null) {
      setState(() => _error = 'Match a diameter first');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final detected = (_match!['detected_diameter'] as num?)?.toDouble();
      final table = (_match!['table_diameter_mm'] as num?)?.toDouble();
      final overridden = detected != null &&
          table != null &&
          (detected - table).abs() > 0.05;
      await widget.api.saveScanBody(
        caseId: _case!['id'] as int,
        detectedDiameter: detected,
        tableDiameterMm: table,
        tooth: _match!['matched_tooth_position']?.toString(),
        manufacturer: _match!['matched_manufacturer']?.toString(),
        platform: _match!['matched_platform']?.toString(),
        confidence: (_match!['confidence_score'] as num?)?.toDouble(),
        overridden: overridden || _match!['ambiguous'] == true,
        detectionMethod: _match!['detection_method']?.toString() ?? 'manual',
      );
      await widget.api.markCaseInProgressIfPending(
        _case!['id'] as int,
        _case!['status']?.toString(),
      );
      _case = {..._case!, 'status': 'in_progress'};
      setState(
        () => _status =
            'Saved ${_match!['matched_manufacturer']} · '
            'tooth ${_match!['matched_tooth_position']} on case #${_case!['id']}',
      );
      if (mounted) {
        AppSnackBars.success(
          context,
          'Saved ${_match!['matched_manufacturer']} · '
          'tooth ${_match!['matched_tooth_position']} on case #${_case!['id']}',
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

  double? get _matchedTableMm =>
      (_match?['table_diameter_mm'] as num?)?.toDouble();

  List<Map<String, dynamic>> get _candidates {
    final raw = _match?['candidates'];
    if (raw is! List) return const [];
    return raw.cast<Map<String, dynamic>>();
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
                      AppLocalizations.of(context).scanBodyTitle,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    const Text(
                      'Platform Ø in millimetres (mm) — typically 3–6 mm, not metres',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              PatientPickerButton(
                patients: _patients,
                selected: _patient,
                caseId: (_case?['id'] as num?)?.toInt(),
                enabled: !_busy && !_saving,
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
                onPressed: _saving || _match == null ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'Saving…' : 'Save to case'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: AppRadii.border,
            ),
            child: const Text(
              'Provisional reference table — swap for Elite Dent manufacturer data before production.',
              style: TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status!, style: const TextStyle(color: AppColors.success)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: AdaptiveSplit(
              panelFraction: 0.42,
              minPanelWidth: 320,
              maxPanelWidth: 460,
              narrowPanelHeight: 300,
              panel: SectionCard(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Measurement',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _diameterCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Platform diameter (mm)',
                              hintText: 'e.g. 4.1',
                              helperText:
                                  'Outer scan-body platform width in millimetres',
                              suffixText: 'mm',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            onSubmitted: (_) => _matchManual(),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _table.take(8).map((row) {
                              final mm = row['diameter_mm'];
                              final selected = _matchedTableMm == (mm as num).toDouble();
                              return ChoiceChip(
                                label: Text('$mm'),
                                selected: selected,
                                onSelected: (_) => _useTableRow(row),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _busy ? null : _matchManual,
                                  icon: const Icon(Icons.search, size: 18),
                                  label: Text(_busy ? 'Working…' : 'Match table'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy ? null : () => _detectFromPhoto(),
                                  icon: const Icon(Icons.image_search_outlined, size: 18),
                                  label: Text(
                                    _previewBytes == null
                                        ? 'Detect from photo'
                                        : 'New photo',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_previewBytes != null) ...[
                            const SizedBox(height: 14),
                            const Text(
                              'Scale calibration',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _needsCalibration
                                  ? 'Photo has no scale yet — enter mm from a caliper, tap a table row, or calibrate.'
                                  : 'Scale locked · refine if reading looks off.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                            Row(
                              children: [
                                const SizedBox(
                                  width: 64,
                                  child: Text(
                                    'px/mm',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: _pixelsPerMm.clamp(5, 80),
                                    min: 5,
                                    max: 80,
                                    onChanged: (v) =>
                                        setState(() => _pixelsPerMm = v),
                                    onChangeEnd: (_) => _reDetectWithScale(),
                                  ),
                                ),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    _pixelsPerMm.toStringAsFixed(0),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _busy ? null : _calibrateWithKnown,
                                icon: const Icon(Icons.straighten, size: 16),
                                label: const Text(
                                  'Calibrate using diameter above',
                                ),
                              ),
                            ),
                          ],
                          if (_match != null) ...[
                            const SizedBox(height: 8),
                            const Divider(),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text(
                                  'Result',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const Spacer(),
                                if (_match!['ambiguous'] == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.warningSoft,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Ambiguous — confirm',
                                      style: TextStyle(
                                        color: AppColors.warning,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _ResultTile(
                              label: 'Detected',
                              value: _match!['detected_diameter'] == null
                                  ? (_match!['pixel_diameter'] != null
                                      ? 'Ø ${_match!['pixel_diameter']} px (enter mm)'
                                      : '—')
                                  : '${_match!['detected_diameter']} mm',
                            ),
                            if (_match!['pixel_diameter'] != null &&
                                _match!['detected_diameter'] != null)
                              _ResultTile(
                                label: 'Pixels',
                                value: 'Ø ${_match!['pixel_diameter']} px',
                              ),
                            _ResultTile(
                              label: 'Table match',
                              value:
                                  '${_match!['table_diameter_mm'] ?? '—'} mm',
                            ),
                            _ResultTile(
                              label: 'Tooth',
                              value:
                                  '${_match!['matched_tooth_position'] ?? '—'}',
                            ),
                            _ResultTile(
                              label: 'Manufacturer',
                              value:
                                  '${_match!['matched_manufacturer'] ?? '—'}',
                            ),
                            _ResultTile(
                              label: 'Platform',
                              value: '${_match!['matched_platform'] ?? '—'}',
                            ),
                            _ResultTile(
                              label: 'Confidence',
                              value: _match!['confidence_score'] == null
                                  ? '—'
                                  : '${(((_match!['confidence_score'] as num) * 100).round())}%',
                            ),
                            if (_candidates.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Top candidates',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ..._candidates.map((c) {
                                final mm = c['diameter_mm'];
                                final conf = ((c['confidence_score'] as num?)?.toDouble() ?? 0) *
                                    100;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: InkWell(
                                    onTap: () => _useTableRow(c),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '$mm mm · ${c['manufacturer']} · tooth ${c['tooth_position']}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        Text(
                                          '${conf.round()}%',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              _match!['note']?.toString() ?? '',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              content: Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: SectionCard(
                          padding: EdgeInsets.zero,
                          child: ClipRRect(
                            borderRadius: AppRadii.border,
                            child: _previewBytes == null
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.radio_button_checked_outlined,
                                          size: 40,
                                          color: AppColors.muted
                                              .withValues(alpha: 0.55),
                                        ),
                                        const SizedBox(height: 10),
                                        const Text(
                                          'Load a scan-body photo',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.navy,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'AI finds the circular platform; you enter mm (3–6) or calibrate.',
                                          style: TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        FilledButton.icon(
                                          onPressed:
                                              _busy ? null : () => _detectFromPhoto(),
                                          icon: const Icon(
                                            Icons.upload_file,
                                            size: 18,
                                          ),
                                          label: const Text('Detect from photo'),
                                        ),
                                      ],
                                    ),
                                  )
                                : Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ColoredBox(
                                        color: const Color(0xFF121A28),
                                        child: Image.memory(
                                          _previewBytes!,
                                          fit: BoxFit.contain,
                                          filterQuality: FilterQuality.high,
                                        ),
                                      ),
                                      if (_circleCenter != null &&
                                          _circleRadius != null &&
                                          _imageSize != null)
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: _CircleOverlayPainter(
                                              center: _circleCenter!,
                                              radius: _circleRadius!,
                                              imageSize: _imageSize!,
                                            ),
                                          ),
                                        ),
                                      Positioned(
                                        left: 10,
                                        top: 10,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            _circleRadius == null
                                                ? 'No circle'
                                                : _match?['detected_diameter'] !=
                                                        null
                                                    ? '⌀ ${_match!['detected_diameter']} mm'
                                                    : '⌀ ${(_circleRadius! * 2).toStringAsFixed(0)} px · enter mm',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        flex: 4,
                        child: SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reference table (${_table.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _table.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No reference rows loaded',
                                          style: TextStyle(
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: _table.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, i) {
                                          final row = _table[i];
                                          final mm =
                                              (row['diameter_mm'] as num)
                                                  .toDouble();
                                          final selected =
                                              _matchedTableMm == mm;
                                          return Material(
                                            color: selected
                                                ? AppColors.sidebarActive
                                                : Colors.transparent,
                                            child: ListTile(
                                              dense: true,
                                              title: Text(
                                                '${row['diameter_mm']} mm · ${row['manufacturer']}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                  color: selected
                                                      ? AppColors.navy
                                                      : null,
                                                ),
                                              ),
                                              subtitle: Text(
                                                'Tooth ${row['tooth_position']} · ${row['platform']}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                              trailing: TextButton(
                                                onPressed: () =>
                                                    _useTableRow(row),
                                                child: Text(
                                                  selected ? 'Selected' : 'Use',
                                                ),
                                              ),
                                              onTap: () => _useTableRow(row),
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
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws detected scan-body circle on top of BoxFit.contain photo.
class _CircleOverlayPainter extends CustomPainter {
  _CircleOverlayPainter({
    required this.center,
    required this.radius,
    required this.imageSize,
  });

  final Offset center;
  final double radius;
  final Size imageSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return;
    final fitted = applyBoxFit(BoxFit.contain, imageSize, size);
    final out = fitted.destination;
    final dx = (size.width - out.width) / 2;
    final dy = (size.height - out.height) / 2;
    final sx = out.width / imageSize.width;
    final sy = out.height / imageSize.height;

    final c = Offset(dx + center.dx * sx, dy + center.dy * sy);
    final r = radius * ((sx + sy) / 2);

    final ring = Paint()
      ..color = const Color(0xFF4A90E2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final fill = Paint()
      ..color = const Color(0xFF4A90E2).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, r, fill);
    canvas.drawCircle(c, r, ring);
    canvas.drawCircle(
      c,
      3,
      Paint()..color = const Color(0xFF4A90E2),
    );
  }

  @override
  bool shouldRepaint(covariant _CircleOverlayPainter old) =>
      old.center != center ||
      old.radius != radius ||
      old.imageSize != imageSize;
}

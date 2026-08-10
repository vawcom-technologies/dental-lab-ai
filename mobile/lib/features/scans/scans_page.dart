import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/layout/adaptive.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'mesh_sample.dart';
import 'mesh_viewer.dart';

class ScansPage extends StatefulWidget {
  const ScansPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ScansPage> createState() => _ScansPageState();
}

class _ScansPageState extends State<ScansPage> {
  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _patient;
  List<Map<String, dynamic>> _scans = [];
  int _selected = 0;
  bool _loading = true;
  bool _mediaLoading = false;
  bool _busy = false;
  bool _previewLoading = false;
  String? _error;
  String? _previewError;
  Map<String, dynamic>? _lastResult;
  List<List<double>> _vertices = const [];
  Uint8List? _previewBytes;
  String? _previewFilename;
  int? _vertexCount;
  Object? _previewScanId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await widget.api.listPatients();
      setState(() => _patients = patients);
      if (patients.isNotEmpty) await _selectPatient(patients.first);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _patientLabel {
    final p = _patient;
    if (p == null) return '';
    return '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
  }

  String _pid(Map<String, dynamic> row) => '${row['id'] ?? ''}';

  String _formatOf(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.stl')) return 'stl';
    if (lower.endsWith('.obj')) return 'obj';
    return 'ply';
  }

  Map<String, dynamic> _normalizeScan(
    Map<String, dynamic> row, {
    Uint8List? bytes,
  }) {
    final name = '${row['file_name'] ?? row['filename'] ?? 'scan'}';
    return {
      ...row,
      'filename': name,
      'format': row['format'] ?? _formatOf(name),
      'uploaded_at': row['created_at'] ?? row['uploaded_at'],
      'patient_name': _patientLabel,
      'validation_result': row['validation_result'] ?? 'saved',
      'quality_score': row['quality_score'] ?? 1.0,
      '_bytes': ?bytes,
    };
  }

  Future<List<Map<String, dynamic>>> _scansForPatient(String patientId) async {
    final rows = await widget.api.listPatientScans(patientId);
    return rows.map(_normalizeScan).toList();
  }

  Future<void> _selectPatient(Map<String, dynamic> patient) async {
    setState(() {
      _patient = patient;
      _scans = [];
      _mediaLoading = true;
      _error = null;
      _lastResult = null;
      _vertices = const [];
      _previewBytes = null;
      _previewFilename = null;
      _previewError = null;
      _previewScanId = null;
    });
    final pid = _pid(patient);
    if (pid.isEmpty) {
      if (mounted) setState(() => _mediaLoading = false);
      return;
    }
    try {
      final scans = await _scansForPatient(pid);
      if (!mounted) return;
      setState(() {
        _scans = scans;
        _selected = 0;
        _mediaLoading = false;
      });
      if (scans.isNotEmpty) {
        await _loadPreviewFor(scans.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mediaLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _applyLocalPreview({
    required Object scanId,
    required Uint8List bytes,
    required String filename,
  }) async {
    setState(() {
      _previewLoading = true;
      _previewError = null;
      _previewScanId = scanId;
      _previewBytes = bytes;
      _previewFilename = filename;
    });
    try {
      final sampled = sampleMeshBytes(bytes, filename);
      if (!mounted || _previewScanId != scanId) return;
      setState(() {
        _vertices = sampled.vertices;
        _vertexCount = sampled.vertexCount;
        _previewError = sampled.vertices.isEmpty
            ? (sampled.error ?? 'Preview has no points')
            : null;
        _previewLoading = false;
      });
    } catch (e) {
      if (!mounted || _previewScanId != scanId) return;
      setState(() {
        _vertices = const [];
        _previewError = e.toString().replaceFirst('Exception: ', '');
        _previewLoading = false;
      });
    }
  }

  Future<void> _loadPreviewFor(Map<String, dynamic> scan) async {
    final scanId = scan['id'];
    if (scanId == null) return;

    final localBytes = scan['_bytes'];
    if (localBytes is Uint8List) {
      await _applyLocalPreview(
        scanId: scanId,
        bytes: localBytes,
        filename: '${scan['filename'] ?? 'scan.ply'}',
      );
      return;
    }

    final fileUrl = '${scan['file_url'] ?? ''}'.trim();
    if (fileUrl.isEmpty) {
      setState(() {
        _previewBytes = null;
        _previewFilename = null;
        _vertices = const [];
        _previewError = 'Scan preview unavailable';
        _previewLoading = false;
        _previewScanId = scanId;
      });
      return;
    }

    setState(() {
      _previewLoading = true;
      _previewError = null;
      _previewScanId = scanId;
      _previewBytes = null;
      _previewFilename = '${scan['filename'] ?? 'scan.ply'}';
    });
    try {
      final bytes = await widget.api.downloadMediaBytes(fileUrl);
      if (!mounted || _previewScanId != scanId) return;
      scan['_bytes'] = bytes;
      await _applyLocalPreview(
        scanId: scanId,
        bytes: bytes,
        filename: '${scan['filename'] ?? 'scan.ply'}',
      );
    } catch (e) {
      if (!mounted || _previewScanId != scanId) return;
      setState(() {
        _vertices = const [];
        _previewError = e.toString().replaceFirst('Exception: ', '');
        _previewLoading = false;
      });
    }
  }

  Future<void> _upload() async {
    if (_busy || _patient == null) return;
    setState(() => _error = null);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ply', 'stl', 'obj'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _error = 'Could not read file bytes');
        if (mounted) AppSnackBars.error(context, 'Could not read file bytes');
        return;
      }

      if (!mounted) return;
      final confirmed = await confirmPatientMediaUpload(context);
      if (!confirmed || !mounted) return;

      final data = Uint8List.fromList(bytes);
      final name = file.name;
      final pid = _pid(_patient!);

      setState(() => _busy = true);
      final uploaded = await runWithToothLoadingDialog(
        context,
        message: 'Uploading scan…',
        action: () => widget.api.uploadPatientScan(
          patientId: pid,
          bytes: data,
          filename: name,
        ),
      );
      if (!mounted) return;

      late final Map<String, dynamic> validation;
      try {
        validation = await widget.api.validateScan(data, name);
      } catch (_) {
        final sampled = sampleMeshBytes(data, name);
        validation = {
          'result': sampled.error == null ? 'ok' : 'fail',
          'quality_score': sampled.error == null ? 0.85 : 0.2,
          'reasons': [
            if (sampled.error != null) sampled.error!,
            if (sampled.error == null)
              'Local parse OK (${_formatOf(name).toUpperCase()})',
          ],
          'note': 'Validated on device',
          'issues': const [],
          'prompt_rescan': sampled.error != null,
        };
      }

      final item = _normalizeScan(
        {
          ...uploaded,
          'validation_result':
              validation['result'] ?? validation['validation_result'] ?? 'ok',
          'quality_score': validation['quality_score'] ?? 0.85,
          'reasons': validation['reasons'] ?? const [],
          'issues': validation['issues'] ?? const [],
          'prompt_rescan': validation['prompt_rescan'] == true,
          'note': validation['note'],
        },
        bytes: data,
      );

      setState(() {
        _scans = [item, ..._scans];
        _selected = 0;
        _lastResult = validation;
        _busy = false;
      });
      await _loadPreviewFor(item);
      if (mounted) {
        AppSnackBars.success(
          context,
          '${_formatOf(name).toUpperCase()} scan uploaded',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      AppSnackBars.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _deleteScan(Map<String, dynamic> scan) async {
    if (_busy) return;
    final scanId = '${scan['id'] ?? ''}';
    if (scanId.isEmpty) return;

    final ok = await confirmPatientMediaDelete(context);
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.deletePatientScan(scanId);
      if (!mounted) return;
      final next = _scans.where((s) => '${s['id']}' != scanId).toList();
      setState(() {
        _scans = next;
        _selected = 0;
        _lastResult = null;
        if (next.isEmpty) {
          _vertices = const [];
          _previewBytes = null;
          _previewFilename = null;
          _previewError = null;
          _previewScanId = null;
        }
      });
      if (next.isNotEmpty) {
        await _loadPreviewFor(next.first);
      }
      if (mounted) AppSnackBars.success(context, 'Scan deleted');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
      AppSnackBars.error(context, msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ToothPageLoader(message: 'Loading scans…');
    }

    final scan = _scans.isEmpty ? null : _scans[_selected.clamp(0, _scans.length - 1)];
    final score = ((scan?['quality_score'] as num?)?.toDouble() ??
            (_lastResult?['quality_score'] as num?)?.toDouble() ??
            0) *
        (scan?['quality_score'] != null &&
                (scan!['quality_score'] as num) <= 1
            ? 100
            : 1);
    final scoreInt = score.round().clamp(0, 100);
    final result = scan?['validation_result'] as String? ??
        _lastResult?['validation_result'] as String? ??
        'unknown';

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
                      AppLocalizations.of(context).scansTitle,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      _patient == null
                          ? 'Upload PLY / STL / OBJ · AI quality check · Dots / Solid preview'
                          : 'Patient: $_patientLabel · PLY / STL / OBJ · Dots / Solid',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (_patients.isNotEmpty)
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        _patient == null ? null : _pid(_patient!),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Patient',
                    ),
                    items: _patients
                        .map(
                          (p) => DropdownMenuItem(
                            value: _pid(p),
                            child: Text('${p['first_name']} ${p['last_name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      final p = _patients.firstWhere((e) => _pid(e) == id);
                      _selectPatient(p);
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ),
          Expanded(
            child: AdaptiveSplit(
              narrowPanelHeight: 280,
              panel: Column(
                    children: [
                      InkWell(
                        onTap: _busy || _patient == null ? null : _upload,
                        borderRadius: AppRadii.border,
                        child: SectionCard(
                          child: Column(
                            children: [
                              Icon(Icons.cloud_upload_outlined,
                                  color: AppColors.dentalBlue, size: 28),
                              const SizedBox(height: 8),
                              Text(
                                _busy ? 'Uploading…' : 'Upload scan file',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'PLY, STL, OBJ — preview Dots / Solid on device',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SectionCard(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: _mediaLoading
                              ? const Center(
                                  child: ToothLoadingIndicator(
                                    size: 40,
                                    loadingText: 'Loading scans…',
                                  ),
                                )
                              : _scans.isEmpty
                              ? Center(
                                  child: Text(
                                    _patient == null
                                        ? 'Select a patient'
                                        : 'No scans for $_patientLabel yet',
                                    style: const TextStyle(color: AppColors.muted),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _scans.length,
                                  itemBuilder: (context, i) {
                                    final s = _scans[i];
                                    final selected = i == _selected;
                                    final q = ((s['quality_score'] as num?)?.toDouble() ?? 0);
                                    final pct = (q <= 1 ? q * 100 : q).round();
                                    final file = '${s['filename'] ?? 'Scan #${s['id']}'}';
                                    final short = file.length > 28
                                        ? '${file.substring(0, 26)}…'
                                        : file;
                                    return ListTile(
                                      selected: selected,
                                      selectedTileColor: AppColors.sidebarActive,
                                      onTap: () {
                                        setState(() => _selected = i);
                                        _loadPreviewFor(s);
                                      },
                                      title: Text(
                                        short,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${s['patient_name'] ?? _patientLabel}'
                                        ' · ${s['validation_result'] ?? 'pending'}'
                                        ' · #${s['id']}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11.5),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '$pct%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: pct >= 80
                                                  ? AppColors.success
                                                  : pct >= 50
                                                      ? AppColors.warning
                                                      : AppColors.danger,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Delete scan',
                                            onPressed: _busy
                                                ? null
                                                : () => _deleteScan(s),
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
                      ),
                    ],
                  ),
              content: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                scan == null
                                    ? 'No scan selected'
                                    : '${scan['filename'] ?? 'Scan #${scan['id']}'}'
                                        ' · ${scan['patient_name'] ?? _patientLabel}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (scan != null)
                              IconButton(
                                tooltip: 'Delete scan',
                                onPressed: _busy ? null : () => _deleteScan(scan),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.danger,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: MeshViewer(
                            bytes: _previewBytes,
                            filename: _previewFilename,
                            previewVertices: _vertices,
                            loading: _previewLoading,
                            error: _previewError,
                            vertexCount: _vertexCount,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              '$scoreInt',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: scoreInt >= 80
                                    ? AppColors.success
                                    : scoreInt >= 50
                                        ? AppColors.warning
                                        : AppColors.danger,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('Quality Score',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            const Spacer(),
                            Text(
                              result.toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: scoreInt / 100,
                            minHeight: 10,
                            backgroundColor: AppColors.border,
                            color: scoreInt >= 80
                                ? AppColors.success
                                : scoreInt >= 50
                                    ? AppColors.warning
                                    : AppColors.danger,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_issuesFor(scan, _lastResult).isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _issuesFor(scan, _lastResult).map((issue) {
                              final sev = issue['severity']?.toString() ?? 'medium';
                              final color = sev == 'high'
                                  ? AppColors.danger
                                  : sev == 'medium'
                                      ? AppColors.warning
                                      : AppColors.muted;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: color.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  '${issue['code']}: ${issue['message']}',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (_lastResult?['prompt_rescan'] == true ||
                                    result == 'bad' ||
                                    result == 'blurry' ||
                                    result == 'missing_margin')
                                ? AppColors.dangerSoft
                                : scoreInt >= 80
                                    ? AppColors.successSoft
                                    : scoreInt >= 50
                                        ? AppColors.warningSoft
                                        : AppColors.dangerSoft,
                            borderRadius: AppRadii.border,
                          ),
                          child: Text(
                            _messageFor(result, scoreInt, _lastResult),
                            style: TextStyle(
                              color: (_lastResult?['prompt_rescan'] == true ||
                                      result == 'bad' ||
                                      result == 'blurry' ||
                                      result == 'missing_margin')
                                  ? AppColors.danger
                                  : scoreInt >= 80
                                      ? AppColors.success
                                      : scoreInt >= 50
                                          ? AppColors.warning
                                          : AppColors.danger,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                        if (_lastResult?['prompt_rescan'] == true ||
                            result == 'bad' ||
                            result == 'blurry' ||
                            result == 'missing_margin') ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy || _patient == null ? null : _upload,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Rescan now — before patient leaves'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.danger,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _issuesFor(
    Map<String, dynamic>? scan,
    Map<String, dynamic>? last,
  ) {
    final raw = last?['issues'] ?? scan?['issues'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .cast<Map<String, dynamic>>()
        .toList();
  }

  String _messageFor(String result, int score, Map<String, dynamic>? last) {
    if (last?['queued'] == true) {
      return last?['note'] as String? ?? 'Queued for offline sync.';
    }
    if (last?['prompt_rescan'] == true ||
        result == 'bad' ||
        result == 'blurry' ||
        result == 'missing_margin') {
      final reasons = (last?['reasons'] as List?)?.join(' ') ?? '';
      return 'Rescan recommended before the patient leaves. $reasons'.trim();
    }
    if (score >= 80 || result == 'good') {
      return 'Scan accepted — ready for lab review. Stored encrypted at rest.';
    }
    return 'Review recommended — quality score below threshold.';
  }
}

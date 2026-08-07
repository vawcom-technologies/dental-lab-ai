import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/layout/adaptive.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/offline/sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'mesh_viewer.dart';

class ScansPage extends StatefulWidget {
  const ScansPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ScansPage> createState() => _ScansPageState();
}

class _ScansPageState extends State<ScansPage> {
  late final SyncService _sync = SyncService(api: widget.api);

  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _case;
  List<Map<String, dynamic>> _scans = [];
  int _selected = 0;
  bool _loading = true;
  bool _busy = false;
  bool _previewLoading = false;
  String? _error;
  String? _previewError;
  Map<String, dynamic>? _lastResult;
  Uint8List? _meshBytes;
  String? _meshFilename;
  List<List<double>> _previewVertices = const [];
  int? _vertexCount;
  int? _previewScanId;

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

  /// GDPR patients use UUID strings; legacy rows used ints.
  String _pid(Map<String, dynamic> row) => '${row['id'] ?? ''}';

  String get _patientLabel {
    final p = _patient;
    if (p == null) return '';
    return '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
  }

  Future<List<Map<String, dynamic>>> _scansForPatient(String patientId) async {
    if (patientId.isEmpty) return const [];
    final cases = await widget.api.listCases();
    final mine = cases.where((c) => '${c['patient_id']}' == patientId).toList()
      ..sort((a, b) {
        final ta = DateTime.tryParse('${a['updated_at'] ?? ''}') ?? DateTime(1970);
        final tb = DateTime.tryParse('${b['updated_at'] ?? ''}') ?? DateTime(1970);
        return tb.compareTo(ta);
      });

    Map<String, dynamic>? caseRow;
    if (mine.isEmpty) {
      // Legacy cases API only accepts numeric patient ids.
      final asInt = int.tryParse(patientId);
      if (asInt != null) {
        caseRow = await widget.api.createCase(asInt);
      }
    } else {
      caseRow = mine.first;
    }
    if (mounted) setState(() => _case = caseRow);
    if (caseRow == null) return const [];

    final all = <Map<String, dynamic>>[];
    final caseList = mine.isEmpty ? [caseRow] : mine;
    for (final c in caseList) {
      final cid = c['id'];
      if (cid is! int) continue;
      final rows = await widget.api.listScans(cid);
      for (final s in rows) {
        // Ensure patient linkage is always present on the row.
        s['patient_id'] = patientId;
        s['patient_name'] ??= _patientLabel;
        s['case_id'] ??= cid;
        all.add(s);
      }
    }
    all.sort((a, b) {
      final ta = DateTime.tryParse('${a['uploaded_at'] ?? ''}') ?? DateTime(1970);
      final tb = DateTime.tryParse('${b['uploaded_at'] ?? ''}') ?? DateTime(1970);
      return tb.compareTo(ta);
    });
    return all;
  }

  Future<void> _selectPatient(Map<String, dynamic> patient) async {
    setState(() {
      _patient = patient;
      _case = null;
      _scans = [];
      _lastResult = null;
      _meshBytes = null;
      _meshFilename = null;
      _previewVertices = const [];
      _previewError = null;
      _previewScanId = null;
    });
    final pid = _pid(patient);
    if (pid.isEmpty) return;
    final scans = await _scansForPatient(pid);
    if (!mounted) return;
    setState(() {
      _scans = scans;
      _selected = scans.isEmpty ? 0 : 0;
    });
    if (scans.isNotEmpty) {
      await _loadPreviewFor(scans.first);
    }
  }

  Future<void> _loadPreviewFor(Map<String, dynamic> scan) async {
    final caseId = scan['case_id'] as int? ?? _case?['id'] as int?;
    final scanId = scan['id'];
    if (caseId is! int || scanId is! int) return;
    setState(() {
      _previewLoading = true;
      _previewError = null;
      _previewScanId = scanId;
      if (_case == null || _case!['id'] != caseId) {
        _case = {'id': caseId, 'patient_id': scan['patient_id'] ?? _patient?['id']};
      }
    });
    try {
      // Full mesh file — point-preview API has no faces, so Solid cannot work from it.
      final file = await widget.api.fetchScanFile(
        caseId: caseId,
        scanId: scanId,
      );
      if (!mounted || _previewScanId != scanId) return;
      final name = file.filename.isNotEmpty
          ? file.filename
          : '${scan['filename'] ?? 'scan.ply'}';
      setState(() {
        _meshBytes = file.bytes;
        _meshFilename = name;
        _previewVertices = const [];
        _vertexCount = null;
        _previewError = null;
        _previewLoading = false;
      });
    } catch (_) {
      // Fallback: downsampled points (Dots only) if full-file download fails.
      try {
        final preview = await widget.api.fetchScanPreview(
          caseId: caseId,
          scanId: scanId,
        );
        if (!mounted || _previewScanId != scanId) return;
        final raw = preview['vertices'];
        final verts = <List<double>>[];
        if (raw is List) {
          for (final row in raw) {
            if (row is List && row.length >= 3) {
              verts.add([
                (row[0] as num).toDouble(),
                (row[1] as num).toDouble(),
                (row[2] as num).toDouble(),
              ]);
            }
          }
        }
        setState(() {
          _meshBytes = null;
          _meshFilename = null;
          _previewVertices = verts;
          _vertexCount = (preview['vertex_count'] as num?)?.toInt();
          _previewError = verts.isEmpty
              ? (preview['error']?.toString() ?? 'Preview has no points')
              : null;
          _previewLoading = false;
        });
      } catch (e) {
        if (!mounted || _previewScanId != scanId) return;
        setState(() {
          _meshBytes = null;
          _meshFilename = null;
          _previewVertices = const [];
          _previewError = e.toString().replaceFirst('Exception: ', '');
          _previewLoading = false;
        });
      }
    }
  }

  Future<int?> _ensureCaseId() async {
    final existing = _case?['id'];
    if (existing is int) return existing;
    if (_patient == null) return null;
    final asInt = int.tryParse(_pid(_patient!));
    if (asInt == null) return null;
    try {
      final row = await widget.api.createCase(asInt);
      if (mounted) setState(() => _case = row);
      final id = row['id'];
      return id is int ? id : (id as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<void> _upload() async {
    if (_busy || _patient == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Web needs withData; native prefers path for large PLYs.
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ply', 'stl', 'obj'],
        withData: kIsWeb,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? bytes;
      try {
        bytes = await file.xFile.readAsBytes();
      } catch (_) {
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          bytes = Uint8List.fromList(file.bytes!);
        }
      }
      if (bytes == null || bytes.isEmpty) {
        setState(() => _error = 'Could not read file bytes');
        if (mounted) AppSnackBars.error(context, 'Could not read file bytes');
        return;
      }
      final name = file.name.isNotEmpty ? file.name : 'scan.ply';
      final meshBytes = bytes;

      // Upload before preview so viewer failures cannot kill the pick flow.
      final caseId = await _ensureCaseId();
      Map<String, dynamic>? upload;
      if (caseId != null) {
        upload = await _sync.captureScan(
          caseId: caseId,
          bytes: meshBytes,
          filename: name,
        );
        await _sync.flush();
      }

      if (!mounted) return;
      setState(() {
        _meshBytes = meshBytes;
        _meshFilename = name;
        _previewVertices = const [];
        _vertexCount = null;
        _previewError = null;
        _previewScanId = null;
        _lastResult = upload;
      });

      if (caseId == null) {
        if (mounted) {
          AppSnackBars.success(
            context,
            'Preview ready (server upload needs a numeric case id)',
          );
        }
        return;
      }

      final scans = await _scansForPatient(_pid(_patient!));
      if (!mounted) return;
      final keptBytes = _meshBytes;
      final keptName = _meshFilename;
      setState(() {
        _scans = scans;
        _selected = 0;
      });
      if (keptBytes != null && keptBytes.isNotEmpty) {
        setState(() {
          _meshBytes = keptBytes;
          _meshFilename = keptName;
          _previewVertices = const [];
          _previewError = null;
          _previewLoading = false;
        });
      } else if (scans.isNotEmpty) {
        await _loadPreviewFor(scans.first);
      }
      if (mounted) AppSnackBars.success(context, 'Scan uploaded successfully');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = msg);
      AppSnackBars.error(context, msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteScan(Map<String, dynamic> scan) async {
    if (_busy) return;
    final caseId = scan['case_id'] as int? ?? _case?['id'] as int?;
    final scanId = scan['id'];
    if (caseId is! int || scanId is! int) return;

    final filename = '${scan['filename'] ?? 'Scan #$scanId'}';
    final patient = '${scan['patient_name'] ?? _patientLabel}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete scan?'),
        content: Text(
          'Remove $filename for $patient?\nThis cannot be undone.',
        ),
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
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.deleteScan(caseId: caseId, scanId: scanId);
      final pid = _patient == null ? '' : _pid(_patient!);
      if (pid.isEmpty) return;
      final scans = await _scansForPatient(pid);
      if (!mounted) return;
      setState(() {
        _scans = scans;
        _selected = 0;
        _lastResult = null;
        if (scans.isEmpty) {
          _meshBytes = null;
          _meshFilename = null;
          _previewVertices = const [];
          _previewError = null;
          _previewScanId = null;
        }
      });
      if (scans.isNotEmpty) {
        await _loadPreviewFor(scans.first);
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
      return const Center(child: CircularProgressIndicator());
    }

    final scan = _scans.isEmpty ? null : _scans[_selected.clamp(0, _scans.length - 1)];
    final rawScore = (scan?['quality_score'] as num?)?.toDouble() ??
        (_lastResult?['quality_score'] as num?)?.toDouble();
    // No mesh / no server score → never show a fake 0.
    final hasScore = rawScore != null && (scan != null || _lastResult != null);
    final scoreInt = !hasScore
        ? null
        : (rawScore <= 1 ? rawScore * 100 : rawScore).round().clamp(0, 100);
    final result = scan?['validation_result'] as String? ??
        _lastResult?['validation_result'] as String?;
    final canUpload = !_busy && _patient != null;

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
                          ? 'Upload PLY / STL / OBJ · AI quality check · 3D preview'
                          : 'Patient: $_patientLabel · scans stay linked to this case',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (_patients.isNotEmpty)
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    initialValue: _patient == null ? null : _pid(_patient!),
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
                      SizedBox(
                        width: double.infinity,
                        child: SectionCard(
                          padding: EdgeInsets.zero,
                          child: InkWell(
                            onTap: canUpload ? _upload : null,
                            borderRadius: AppRadii.border,
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.cloud_upload_outlined,
                                    color: canUpload
                                        ? AppColors.dentalBlue
                                        : AppColors.muted,
                                    size: 28,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _busy
                                        ? 'Uploading…'
                                        : _patient == null
                                            ? 'Select a patient to upload'
                                            : 'Upload scan file',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'PLY, STL, OBJ — opens Files on iPad',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SectionCard(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: _scans.isEmpty
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
                                    final q = (s['quality_score'] as num?)
                                        ?.toDouble();
                                    final pct = q == null
                                        ? null
                                        : (q <= 1 ? q * 100 : q).round();
                                    final file =
                                        '${s['filename'] ?? 'Scan #${s['id']}'}';
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
                                            pct == null ? '—' : '$pct%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: pct == null
                                                  ? AppColors.muted
                                                  : pct >= 80
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
                                _viewerTitle(scan),
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
                            bytes: _meshBytes,
                            filename: _meshFilename,
                            previewVertices: _previewVertices,
                            loading: _previewLoading,
                            error: _previewError,
                            vertexCount: _vertexCount,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              scoreInt?.toString() ?? '—',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: scoreInt == null
                                    ? AppColors.muted
                                    : scoreInt >= 80
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
                              (result ??
                                      (scan == null && !_hasLoadedMesh
                                          ? 'no scan'
                                          : 'pending'))
                                  .toUpperCase(),
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
                            value: scoreInt == null ? 0 : scoreInt / 100,
                            minHeight: 10,
                            backgroundColor: AppColors.border,
                            color: scoreInt == null
                                ? AppColors.border
                                : scoreInt >= 80
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
                            color: scoreInt == null
                                ? AppColors.border.withValues(alpha: 0.35)
                                : (_lastResult?['prompt_rescan'] == true ||
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
                              color: scoreInt == null
                                  ? AppColors.muted
                                  : (_lastResult?['prompt_rescan'] == true ||
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
                              onPressed: canUpload ? _upload : null,
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

  /// A mesh is on screen if we have raw bytes or a decoded point preview.
  bool get _hasLoadedMesh =>
      (_meshBytes != null && _meshBytes!.isNotEmpty) ||
      _previewVertices.isNotEmpty;

  /// Header keys off what's actually displayed — a freshly picked/uploaded file
  /// shows its name even before its server row lands in [_scans].
  String _viewerTitle(Map<String, dynamic>? scan) {
    if (scan != null) {
      final name = '${scan['filename'] ?? 'Scan #${scan['id']}'}';
      final who = scan['patient_name'] ?? _patientLabel;
      return '$who'.trim().isEmpty ? name : '$name · $who';
    }
    if (_hasLoadedMesh) {
      final name = _meshFilename ?? 'Scan preview';
      return _patientLabel.isEmpty ? name : '$name · $_patientLabel';
    }
    return 'No scan selected';
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

  String _messageFor(String? result, int? score, Map<String, dynamic>? last) {
    if (score == null && last?['queued'] != true) {
      return (_meshBytes != null && _meshBytes!.isNotEmpty) ||
              _previewVertices.isNotEmpty
          ? '3D preview ready — quality score appears after upload.'
          : 'Upload a PLY / STL / OBJ scan to see quality.';
    }
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
    if ((score ?? 0) >= 80 || result == 'good') {
      return 'Scan accepted — ready for lab review. Stored encrypted at rest.';
    }
    return 'Review recommended — quality score below threshold.';
  }
}

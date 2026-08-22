import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/layout/adaptive.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/patient_picker.dart';
import '../../core/widgets/ui_kit.dart';
import 'mesh_sample.dart';
import 'mesh_viewer.dart';

class ScansPage extends StatefulWidget {
  const ScansPage({
    super.key,
    required this.api,
    required this.patientSession,
    this.active = true,
  });

  final ApiClient api;
  final PatientSession patientSession;
  final bool active;

  @override
  State<ScansPage> createState() => _ScansPageState();
}

class _ScansPageState extends State<ScansPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _patient;
  List<Map<String, dynamic>> _scans = [];
  int _selected = 0;
  bool _loading = true;
  bool _mediaLoading = false;
  bool _busy = false;
  bool _previewLoading = false;
  String? _previewError;
  Map<String, dynamic>? _lastResult;
  List<List<double>> _vertices = const [];
  Uint8List? _previewBytes;
  String? _previewFilename;
  int? _vertexCount;
  Object? _previewScanId;
  final _meshViewerKey = GlobalKey();
  late final AnimationController _fsController;
  late final Animation<double> _fsExpand;

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
  void didUpdateWidget(covariant ScansPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _onPageActivated();
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
    });
    try {
      await widget.patientSession.ensureLoaded();
      if (!mounted) return;
      setState(() {
        _patients = List<Map<String, dynamic>>.from(
          widget.patientSession.patients,
        );
      });
      final sel = widget.patientSession.selected;
      if (sel != null) {
        await _selectPatient(sel, publish: false);
      } else if (_patients.isNotEmpty) {
        await _selectPatient(_patients.first);
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.error(context, friendlyError(e));
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
          _scans = [];
        });
      }
      return;
    }
    if (_patient == null || _pid(_patient!) != _pid(sel)) {
      await _selectPatient(sel, publish: false);
    }
  }

  String get _patientLabel {
    final p = _patient;
    if (p == null) return '';
    return '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
  }

  String _pid(Map<String, dynamic> row) => '${row['id'] ?? ''}';

  Future<void> _reloadPatients({bool selectFirst = false}) async {
    await widget.patientSession.refresh(keepSelection: !selectFirst);
    if (!mounted) return;
    setState(() {
      _patients = List<Map<String, dynamic>>.from(
        widget.patientSession.patients,
      );
    });
    if (_patients.isEmpty) {
      setState(() {
        _patient = null;
        _scans = [];
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

  Future<void> _selectPatient(
    Map<String, dynamic> patient, {
    bool publish = true,
  }) async {
    if (publish) widget.patientSession.select(patient);
    setState(() {
      _patient = patient;
      _scans = [];
      _mediaLoading = true;
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
      });
      AppSnackBars.error(context, friendlyError(e));
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
    try {
      // Web needs withData; native iPad prefers path + xFile (large PLYs).
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ply', 'stl', 'obj'],
        withData: true,
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
      });
      AppSnackBars.error(
        context,
        friendlyError(e),
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
      if (mounted) AppSnackBars.success(context, AppLocalizations.of(context).scansDeleted);
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyError(e);
      AppSnackBars.error(context, msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _meshViewer() {
    return MeshViewer(
      key: _meshViewerKey,
      bytes: _previewBytes,
      filename: _previewFilename,
      previewVertices: _vertices,
      loading: _previewLoading,
      error: _previewError,
      vertexCount: _vertexCount,
    );
  }

  @override
  Widget build(BuildContext context) {
    _previewError = AppSnackBars.drain(context, _previewError);
    if (_loading) {
      return const ToothPageLoader(message: 'Loading scans…');
    }

    final scan = _scans.isEmpty ? null : _scans[_selected.clamp(0, _scans.length - 1)];
    final result = scan?['validation_result'] as String? ??
        _lastResult?['validation_result'] as String? ??
        _lastResult?['result'] as String? ??
        'unknown';
    final needsRescan = _lastResult?['prompt_rescan'] == true ||
        result == 'bad' ||
        result == 'blurry' ||
        result == 'missing_margin';
    final canUpload = !_busy && _patient != null;
    final loc = AppLocalizations.of(context);

    return AnimatedBuilder(
      animation: _fsExpand,
      builder: (context, _) {
        final t = _fsExpand.value.clamp(0.0, 1.0);
        final chrome = (1.0 - t).clamp(0.0, 1.0);
        final pad = EdgeInsets.lerp(
          const EdgeInsets.fromLTRB(28, 24, 28, 24),
          EdgeInsets.zero,
          t,
        )!;
        return ColoredBox(
          color: Color.lerp(
                Theme.of(context).scaffoldBackgroundColor,
                const Color(0xFF15283F),
                t,
              ) ??
              const Color(0xFF15283F),
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
                          PageHeader(
                            icon: Icons.view_in_ar_outlined,
                            title: loc.scansTitle,
                            subtitle: loc.scansSubtitle,
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
                                    if (mounted) {
                                      setState(() => _busy = false);
                                    }
                                  }
                                },
                                emptyHint:
                                    'No patients yet — add one to upload scans.',
                              ),
                              FilledButton.icon(
                                onPressed: canUpload ? _upload : null,
                                icon: _busy
                                    ? const ToothLoadingIndicator(
                                        size: 16,
                                        compact: true,
                                        color: Colors.white,
                                      )
                                    : const Icon(
                                        Icons.cloud_upload_outlined,
                                        size: 18,
                                      ),
                                label: Text(
                                  _busy
                                      ? loc.scansUploading
                                      : loc.scansUpload,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: AdaptiveSplit(
                    narrowPanelHeight: 280 * chrome,
                    panelFraction: 0.32 * chrome.clamp(0.001, 1.0),
                    minPanelWidth: 260 * chrome,
                    maxPanelWidth: 380 * chrome,
                    gap: 12 * chrome,
                    panel: IgnorePointer(
                      ignoring: t > 0.2,
                      child: Opacity(
                        opacity: chrome,
                        child: Column(
                          children: [
                            InkWell(
                              onTap: canUpload ? _upload : null,
                              borderRadius: AppRadii.border,
                              child: SectionCard(
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.cloud_upload_outlined,
                                      color: AppColors.dentalBlue,
                                      size: 28,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _busy
                                          ? loc.scansUploading
                                          : loc.scansUpload,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      loc.scansSubtitle,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: SectionCard(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
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
                                                  ? loc.scansSelectPatient
                                                  : loc.scansEmptyFor(
                                                      _patientLabel,
                                                    ),
                                              style: const TextStyle(
                                                color: AppColors.muted,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          )
                                        : ListView.builder(
                                            itemCount: _scans.length,
                                            itemBuilder: (context, i) {
                                              final s = _scans[i];
                                              final selected = i == _selected;
                                              final file =
                                                  '${s['filename'] ?? 'Scan #${s['id']}'}';
                                              final short = file.length > 28
                                                  ? '${file.substring(0, 26)}…'
                                                  : file;
                                              return ListTile(
                                                selected: selected,
                                                selectedTileColor:
                                                    AppColors.sidebarActive,
                                                onTap: () {
                                                  setState(
                                                    () => _selected = i,
                                                  );
                                                  _loadPreviewFor(s);
                                                },
                                                title: Text(
                                                  short,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11.5,
                                                  ),
                                                ),
                                                trailing: IconButton(
                                                  tooltip: loc.scansDelete,
                                                  onPressed: _busy
                                                      ? null
                                                      : () => _deleteScan(s),
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 18,
                                                    color: AppColors.danger,
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
                    ),
                    content: SectionCard(
                      depth: chrome <= 0 ? 0 : chrome,
                      color: Color.lerp(
                        AppColors.card,
                        const Color(0xFF15283F),
                        t,
                      ),
                      padding: EdgeInsets.all(18 * chrome),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRect(
                            child: Align(
                              alignment: Alignment.topCenter,
                              heightFactor: chrome,
                              child: Opacity(
                                opacity: chrome,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        scan == null
                                            ? loc.scansNoneSelected
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
                                        tooltip: loc.scansDelete,
                                        onPressed: _busy
                                            ? null
                                            : () => _deleteScan(scan),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: AppColors.danger,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (chrome > 0.01) SizedBox(height: 16 * chrome),
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              clipBehavior: Clip.hardEdge,
                              children: [
                                _meshViewer(),
                                Positioned(
                                  right: 12,
                                  bottom: 12,
                                  child: SafeArea(
                                    child: _ScanFullscreenButton(
                                      fullscreen: t > 0.5,
                                      onTap: _toggleFullscreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ClipRect(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              heightFactor: chrome,
                              child: Opacity(
                                opacity: chrome,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 16),
                                    if (scan == null) ...[
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppColors.border
                                              .withValues(alpha: 0.35),
                                          borderRadius: AppRadii.border,
                                        ),
                                        child: Text(
                                          _patient == null
                                              ? 'Select a patient, then upload a scan to see quality results.'
                                              : 'No scan uploaded yet — upload a PLY, STL, or OBJ to run the quality check.',
                                          style: const TextStyle(
                                            color: AppColors.muted,
                                            fontWeight: FontWeight.w600,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 12),
                                      if (_issuesFor(scan, _lastResult)
                                          .isNotEmpty) ...[
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: _issuesFor(
                                            scan,
                                            _lastResult,
                                          ).map((issue) {
                                            final sev = issue['severity']
                                                    ?.toString() ??
                                                'medium';
                                            final color = sev == 'high'
                                                ? AppColors.danger
                                                : sev == 'medium'
                                                    ? AppColors.warning
                                                    : AppColors.muted;
                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: color.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: color.withValues(
                                                    alpha: 0.4,
                                                  ),
                                                ),
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
                                      if (needsRescan) ...[
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            onPressed:
                                                canUpload ? _upload : null,
                                            icon: const Icon(Icons.refresh),
                                            label: Text(loc.scansRescanNow),
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.danger,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
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
              ],
            ),
          ),
        );
      },
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
}

class _ScanFullscreenButton extends StatelessWidget {
  const _ScanFullscreenButton({
    required this.fullscreen,
    required this.onTap,
  });

  final bool fullscreen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Tooltip(
      message: fullscreen ? loc.commonExitFullscreen : loc.commonFullscreen,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

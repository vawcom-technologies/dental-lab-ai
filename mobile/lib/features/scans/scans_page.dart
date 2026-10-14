import 'dart:async';
import 'dart:typed_data';

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
import 'pick_mesh_file.dart';

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
  // Scans sent from the PC page, waiting for a patient; _incoming is the one being previewed.
  List<Map<String, dynamic>> _inbox = [];
  Map<String, dynamic>? _incoming;
  int _selected = 0;
  bool _loading = true;
  bool _mediaLoading = false;
  bool _busy = false;
  bool _previewLoading = false;
  String? _previewError;
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

  Future<void> _loadInbox() async {
    try {
      final items = await widget.api.listScanInbox();
      if (mounted) {
        // Photos arrive on the Camera tab.
        setState(() => _inbox = items.where((i) => i['kind'] != 'photo').toList());
      }
    } catch (_) {
      // Badge only; the sheet shows errors when opened.
    }
  }

  Future<void> _openInbox() async {
    await _loadInbox();
    if (!mounted) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: _inbox.isEmpty
            ? Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  AppLocalizations.of(context).tr('s.noIncoming'),
                  textAlign: TextAlign.center,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final item in _inbox)
                    ListTile(
                      leading: const Icon(Icons.view_in_ar_outlined),
                      title: Text('${item['file_name']}'),
                      subtitle: Text(
                        '${((item['byte_size'] as num? ?? 0) / 1048576).toStringAsFixed(1)} MB'
                        ' · ${'${item['created_at'] ?? ''}'.split('T').first}',
                      ),
                      onTap: () => Navigator.pop(ctx, item),
                    ),
                ],
              ),
      ),
    );
    if (picked != null) await _previewIncoming(picked);
  }

  Future<void> _previewIncoming(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    setState(() => _incoming = item);
    try {
      final bytes = await widget.api.downloadScanInboxFile(id);
      if (!mounted || _incoming == null) return;
      await _applyLocalPreview(
        scanId: 'inbox-$id',
        bytes: bytes,
        filename: '${item['file_name']}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _incoming = null);
      AppSnackBars.error(context, friendlyError(e));
    }
  }

  void _closeIncoming() {
    setState(() => _incoming = null);
    if (_scans.isNotEmpty) _loadPreviewFor(_scans.first);
  }

  Future<void> _assignIncoming() async {
    final item = _incoming;
    final patient = _patient;
    if (item == null || patient == null || _busy) return;
    final ok = await AppDialogs.confirm(
      context,
      title: AppLocalizations.of(context).tr('s.assignTitle'),
      message: AppLocalizations.of(context).trp('s.assignMsg', {'f': item['file_name'], 'p': _patientLabel}),
      confirmLabel: AppLocalizations.of(context).tr('s.assign'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.assignScanInbox('${item['id']}', _pid(patient));
      if (!mounted) return;
      setState(() {
        _incoming = null;
      });
      await _loadInbox();
      await _selectPatient(patient, publish: false);
      if (mounted) AppSnackBars.success(context, AppLocalizations.of(context).trp('s.added', {'p': _patientLabel}));
    } catch (e) {
      if (mounted) AppSnackBars.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteIncoming() async {
    final item = _incoming;
    if (item == null || _busy) return;
    final ok = await confirmPatientMediaDelete(context);
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.deleteScanInbox('${item['id']}');
      if (!mounted) return;
      setState(() {
        _incoming = null;
      });
      await _loadInbox();
      if (_scans.isNotEmpty) await _loadPreviewFor(_scans.first);
    } catch (e) {
      if (mounted) AppSnackBars.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bootstrap() async {
    unawaited(_loadInbox());
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
    unawaited(_loadInbox());
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
      // Quality state: null (not checked) → checking → done | error.
      '_q': null,
      // Typed empties until _qualityFields parses a result (raw JSON lists
      // from `...row` would break the viewer's cast).
      'rough_points': const <List<double>>[],
      'rough_radius': 0.0,
      '_bytes': ?bytes,
    }..addAll(row['validation_result'] == null ? const {} : _qualityFields(row));
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
      _incoming = null;
      _scans = [];
      _mediaLoading = true;
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
        // Quality runs on its own: a preview that fails must not leave it unchecked.
        unawaited(_checkAll(scans, patient));
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
    Map<String, dynamic>? scan,
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
            ? (sampled.error ?? AppLocalizations.of(context).tr('s.noPoints'))
            : null;
        _previewLoading = false;
      });
    } catch (e) {
      if (!mounted || _previewScanId != scanId) return;
      setState(() {
        _vertices = const [];
        _previewError = friendlyError(e);
        _previewLoading = false;
      });
    }
  }

  /// Server quality fields → scan map. Rough points are parsed once so the
  /// viewer gets a stable list identity.
  Map<String, dynamic> _qualityFields(Map<String, dynamic> v) {
    final raw = v['rough_points'];
    return {
      '_q': 'done',
      'validation_result': v['validation_result'],
      'issues': v['issues'] ?? const [],
      'reasons': v['reasons'] ?? const [],
      'prompt_rescan': v['prompt_rescan'] == true,
      'note': v['note'],
      'rough_points': raw is List
          ? [
              for (final p in raw)
                if (p is List && p.length >= 3)
                  [for (final c in p.take(3)) (c as num).toDouble()],
            ]
          : const <List<double>>[],
      'rough_radius': (v['rough_radius'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// Ask the server for this scan's result (it reads the stored file and
  /// caches the answer). Every outcome lands in a visible state.
  Future<void> _checkQuality(Map<String, dynamic> scan) async {
    final id = '${scan['id'] ?? ''}';
    if (id.isEmpty || scan['_q'] == 'done' || scan['_q'] == 'checking') return;
    setState(() => scan['_q'] = 'checking');
    try {
      final v = await widget.api.validatePatientScan(id);
      scan.addAll(_qualityFields(v));
    } catch (_) {
      scan['_q'] = 'error';
    }
    if (mounted) setState(() {});
  }

  /// One at a time so a patient with many old scans doesn't flood the server.
  Future<void> _checkAll(
    List<Map<String, dynamic>> scans,
    Map<String, dynamic> patient,
  ) async {
    for (final scan in scans) {
      if (!mounted || !identical(_patient, patient)) return;
      await _checkQuality(scan);
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
        scan: scan,
      );
      return;
    }

    final fileUrl = '${scan['file_url'] ?? ''}'.trim();
    if (fileUrl.isEmpty) {
      setState(() {
        _previewBytes = null;
        _previewFilename = null;
        _vertices = const [];
        _previewError = AppLocalizations.of(context).tr('s.prevUnavail');
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
        scan: scan,
      );
    } catch (e) {
      if (!mounted || _previewScanId != scanId) return;
      setState(() {
        _vertices = const [];
        _previewError = friendlyError(e);
        _previewLoading = false;
      });
    }
  }

  Future<void> _upload() async {
    if (_busy || _patient == null) return;
    try {
      final picked = await pickMeshFile(context);
      if (picked == null) return;
      final bytes = picked.bytes;
      if (bytes.isEmpty) {
        if (mounted) AppSnackBars.error(context, AppLocalizations.of(context).tr('s.readFail'));
        return;
      }

      if (!mounted) return;
      final confirmed = await confirmPatientMediaUpload(context);
      if (!confirmed || !mounted) return;

      final data = Uint8List.fromList(bytes);
      final name = picked.name;
      final pid = _pid(_patient!);

      setState(() => _busy = true);
      final uploaded = await runWithToothLoadingDialog(
        context,
        message: AppLocalizations.of(context).scansUploadingScan,
        action: () => widget.api.uploadPatientScan(
          patientId: pid,
          bytes: data,
          filename: name,
        ),
      );
      if (!mounted) return;

      // The upload response already carries the server's quality result.
      final item = _normalizeScan(uploaded, bytes: data);

      setState(() {
        _scans = [item, ..._scans];
        _selected = 0;
        _busy = false;
      });
      unawaited(_checkQuality(item)); // no-op unless the result was missing
      await _loadPreviewFor(item);
      if (mounted) {
        AppSnackBars.success(
          context,
          AppLocalizations.current.trp('s.uploaded', {'f': _formatOf(name).toUpperCase()}),
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

  Widget _meshViewer(Map<String, dynamic>? scan) {
    // Only the scan actually on screen (not an inbox preview) gets its patches.
    final shown = scan != null && '${scan['id']}' == '$_previewScanId';
    return MeshViewer(
      key: _meshViewerKey,
      bytes: _previewBytes,
      filename: _previewFilename,
      previewVertices: _vertices,
      loading: _previewLoading,
      error: _previewError,
      vertexCount: _vertexCount,
      roughPoints: shown
          ? scan['rough_points'] as List<List<double>>? ?? const []
          : const [],
      roughRadius: shown ? scan['rough_radius'] as double? ?? 0 : 0,
    );
  }

  Widget _scanListTile({
    required Map<String, dynamic> scan,
    required int index,
    required AppLocalizations loc,
  }) {
    final selected = index == _selected;
    final file = '${scan['filename'] ?? '${AppLocalizations.current.tr('s.scan')} #${scan['id']}'}';
    final short = file.length > 28 ? '${file.substring(0, 26)}…' : file;
    final subtitle =
        '${scan['patient_name'] ?? _patientLabel}'
        ' · ${scan['validation_result'] != null ? AppLocalizations.current.tr('sq.r.${scan['validation_result']}') : (scan['_q'] == 'error' ? '—' : '…')}'
        ' · #${scan['id']}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final showDelete = w >= 88;
        final showSubtitle = w >= 72;
        return Material(
          color: selected ? AppColors.sidebarActive : Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() => _selected = index);
              unawaited(_checkQuality(scan)); // retries a failed check
              _loadPreviewFor(scan);
            },
            child: Padding(
              padding: EdgeInsets.fromLTRB(showDelete ? 12 : 6, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          short,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (showSubtitle) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showDelete)
                    IconButton(
                      tooltip: loc.scansDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _busy ? null : () => _deleteScan(scan),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: AppColors.danger,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _previewError = AppSnackBars.drain(context, _previewError);
    if (_loading) {
      return ToothPageLoader(message: AppLocalizations.of(context).scansLoading);
    }

    final scan = _scans.isEmpty ? null : _scans[_selected.clamp(0, _scans.length - 1)];
    final result = scan?['validation_result'] as String? ?? 'unknown';
    final needsRescan = scan?['prompt_rescan'] == true || result == 'bad';
    final canUpload = !_busy && _patient != null;
    final loc = AppLocalizations.of(context);

    return AnimatedBuilder(
      animation: _fsExpand,
      builder: (context, _) {
        final t = _fsExpand.value.clamp(0.0, 1.0);
        final chrome = (1.0 - t).clamp(0.0, 1.0);
        final pad = EdgeInsets.lerp(
          AppBreakpoints.pagePadding(context),
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
                                emptyHint: loc.scansEmptyHintUpload,
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _openInbox,
                                icon: const Icon(Icons.inbox_outlined, size: 18),
                                label: Text(
                                  _inbox.isEmpty
                                      ? AppLocalizations.of(context).tr('c.incoming')
                                      : '${AppLocalizations.of(context).tr('c.incoming')} (${_inbox.length})',
                                ),
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
                          if (_incoming != null) ...[
                            SectionCard(
                              child: Row(
                                children: [
                                  const Icon(Icons.inbox_outlined,
                                      color: AppColors.dentalBlue),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      AppLocalizations.of(context).trp('s.incomingName', {'n': _incoming!['file_name']}),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: _patient == null || _busy
                                        ? null
                                        : _assignIncoming,
                                    child: Text(_patient == null
                                        ? AppLocalizations.of(context).tr('c.selPatFirst')
                                        : AppLocalizations.of(context).trp('s.assignTo', {'p': _patientLabel})),
                                  ),
                                  IconButton(
                                    tooltip: AppLocalizations.of(context).commonDelete,
                                    onPressed: _busy ? null : _deleteIncoming,
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                  IconButton(
                                    tooltip: AppLocalizations.of(context).commonClose,
                                    onPressed: _closeIncoming,
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
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
                        child: LayoutBuilder(
                          builder: (context, panelBox) {
                            final showUpload = panelBox.maxHeight >= 220;
                            return ClipRect(
                              child: Column(
                                children: [
                                  if (showUpload) ...[
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
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              loc.scansSubtitle,
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
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
                                  ],
                                  Expanded(
                                    child: SectionCard(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: _mediaLoading
                                          ? Center(
                                              child: ToothLoadingIndicator(
                                                size: 40,
                                                loadingText: AppLocalizations.of(context).tr('s.loading'),
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
                                                    return _scanListTile(
                                                      scan: _scans[i],
                                                      index: i,
                                                      loc: loc,
                                                    );
                                                  },
                                                ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
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
                                            : '${scan['filename'] ?? '${AppLocalizations.current.tr('s.scan')} #${scan['id']}'}'
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
                                _meshViewer(scan),
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
                                              ? loc.scansQualityNeedPatient
                                              : loc.scansQualityNeedUpload,
                                          style: const TextStyle(
                                            color: AppColors.muted,
                                            fontWeight: FontWeight.w600,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 12),
                                      _qualityStatus(scan, loc),
                                      if (_incoming == null &&
                                          _issuesFor(scan).isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        for (final issue in _issuesFor(scan))
                                          _issueCard(issue, loc),
                                        const SizedBox(height: 12),
                                      ],
                                      if (_incoming == null && needsRescan) ...[
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

  /// One line that is never blank: incoming / checking / couldn't check / good / issues found.
  /// "good" is the server's verdict: low-severity notes alone don't make a scan bad.
  Widget _qualityStatus(Map<String, dynamic> scan, AppLocalizations loc) {
    final q = scan['_q'];
    final (IconData? icon, Color color, String text) = _incoming != null
        ? (Icons.info_outline, AppColors.muted, loc.tr('s.qIncoming'))
        : q == 'error'
            ? (Icons.error_outline, AppColors.danger, loc.tr('s.qError'))
            : q != 'done'
                ? (null, AppColors.muted, loc.tr('s.qChecking'))
                : switch (scan['validation_result']) {
                    'good' => (Icons.check_circle_outline, AppColors.success, loc.tr('s.qGood')),
                    'bad' => (Icons.error_outline, AppColors.danger, loc.tr('s.qBad')),
                    _ => (Icons.warning_amber_rounded, AppColors.warning, loc.tr('s.qReview')),
                  };
    return Row(
      children: [
        if (icon != null)
          Icon(icon, size: 18, color: color)
        else
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
        if (_incoming == null && q == 'error')
          TextButton(
            onPressed: () => _checkQuality(scan),
            child: Text(loc.commonRetry),
          ),
      ],
    );
  }

  /// One finding in plain language: what's wrong, why it matters, what to do.
  /// Text comes from the app's translations by issue code; the server's
  /// (English, technical) message is only a fallback for codes this build
  /// doesn't know yet.
  Widget _issueCard(Map<String, dynamic> issue, AppLocalizations loc) {
    final code = '${issue['code']}';
    final sev = '${issue['severity'] ?? 'medium'}';
    final color = switch (sev) {
      'high' => AppColors.danger,
      'medium' => AppColors.warning,
      _ => AppColors.muted,
    };
    final known = loc.tr('sq.$code.t') != 'sq.$code.t';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.tr(known ? 'sq.$code.t' : 'sq.unknown.t'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                loc.tr('sq.sev.$sev'),
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            known ? loc.tr('sq.$code.d') : '${issue['message'] ?? ''}',
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _issuesFor(Map<String, dynamic>? scan) {
    final raw = scan?['issues'];
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

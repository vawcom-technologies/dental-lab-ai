import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/layout/adaptive.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/patient_picker.dart';
import '../../core/widgets/ui_kit.dart';
import '../cases/case_panel.dart';
import '../cases/case_store.dart';
import '../cases/submit_prompt.dart';
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
    widget.patientSession.cases.addListener(_onCase);
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
    widget.patientSession.cases.removeListener(_onCase);
    _fsController.dispose();
    super.dispose();
  }

  void _onCase() {
    if (mounted) setState(() {});
  }

  /// Case of the selected patient (status decides Delete vs Replace).
  CaseInfo? get _case => widget.patientSession.cases.of(_patient == null ? null : _pid(_patient!));

  /// Labs review only: no upload / delete / replace (server returns 403).
  /// Labs view; while reviewing they edit too, which saves as a suggestion.
  bool get _readOnly => widget.api.isLaboratory && !(_case?.canSuggest ?? false);

  void _refreshCase() {
    final p = _patient;
    if (p != null) widget.patientSession.cases.refresh(_pid(p));
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
      _refreshCase();
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
    widget.patientSession.cases.refresh(pid);
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

  /// [replaces]: id of the scan this one stands in for (locked case).
  Future<void> _upload({String? replaces}) async {
    if (_busy || _patient == null || _readOnly) return;
    if (!await confirmCaseChange(context, _case) || !mounted) return;
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
          replaces: replaces,
        ),
      );
      _refreshCase();
      if (!mounted) return;

      // The upload response already carries the server's quality result.
      final item = _normalizeScan(uploaded, bytes: data);

      setState(() {
        // The server removed the replaced scan.
        _scans = [item, ..._scans.where((s) => replaces == null || '${s['id']}' != replaces)];
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

  /// Attach library scans to the case (like shade Accept / smile Save).
  Future<void> _saveToCase() async {
    if (_busy || widget.api.isLaboratory || _patient == null) return;
    final pid = _pid(_patient!);
    final library = [
      for (final s in _scans)
        if (s['on_case'] != true) '${s['id'] ?? ''}',
    ].where((id) => id.isNotEmpty).toList();
    if (library.isEmpty) {
      AppSnackBars.info(context, AppLocalizations.of(context).tr('s.alreadyOnCase'));
      return;
    }
    if (!await confirmCaseChange(context, _case) || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.saveScansToCase(pid, scanIds: library);
      if (!mounted) return;
      final scans = await _scansForPatient(pid);
      if (!mounted) return;
      setState(() {
        _scans = scans;
        _busy = false;
      });
      _refreshCase();
      AppSnackBars.success(
        context,
        AppLocalizations.of(context).trp('s.savedToCase', {'n': '${library.length}'}),
      );
      await maybePromptSubmitToLab(
        context,
        cases: widget.patientSession.cases,
        patientId: pid,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnackBars.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _removeOrReplace(Map<String, dynamic> scan) => _deleteScan(scan);

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
      _refreshCase();
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

  /// The patient's scans (inspector's lower section), with a short empty
  /// state when there are none.
  Widget _scanLibrary(AppLocalizations loc, bool canUpload) {
    final Widget body;
    if (_mediaLoading) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: ToothLoadingIndicator(size: 36, loadingText: loc.tr('s.loading'))),
      );
    } else if (_scans.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        child: Column(
          children: [
            const AdminIcon(icon: Icons.view_in_ar_outlined, size: 52, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              _patient == null ? loc.scansSelectPatient : loc.scansEmptyFor(_patientLabel),
              textAlign: TextAlign.center,
              style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy),
            ),
            if (_patient != null && !_readOnly) ...[
              const SizedBox(height: 4),
              Text(loc.tr('s.formats'),
                  textAlign: TextAlign.center, style: AppFonts.style(fontSize: 12.5, color: AppColors.muted)),
            ],
          ],
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            for (var i = 0; i < _scans.length; i++) ...[
              if (i > 0) const SizedBox(height: 2),
              _scanListTile(scan: _scans[i], index: i, loc: loc),
            ],
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: SectionLabel(_scans.isEmpty ? loc.navScans : '${loc.navScans} (${_scans.length})'),
        ),
        body,
      ],
    );
  }

  Widget _scanListTile({
    required Map<String, dynamic> scan,
    required int index,
    required AppLocalizations loc,
  }) {
    final selected = index == _selected;
    final file = '${scan['filename'] ?? '${loc.tr('s.scan')} #${scan['id']}'}';
    final onCase = scan['on_case'] == true;
    final result = scan['validation_result'] as String?;
    final (Color dot, String quality) = switch (result) {
      'good' => (AppColors.success, loc.tr('sq.r.good')),
      'bad' => (AppColors.danger, loc.tr('sq.r.bad')),
      null => (AppColors.muted, scan['_q'] == 'error' ? '—' : loc.tr('s.qChecking')),
      _ => (AppColors.warning, loc.tr('sq.r.$result')),
    };
    final when = DateTime.tryParse('${scan['uploaded_at'] ?? scan['created_at'] ?? ''}')?.toLocal();
    final subtitle = [
      quality,
      onCase ? loc.tr('s.onCase') : loc.tr('s.libraryOnly'),
      if (when != null) adminWhen(context, when),
    ].join(' · ');
    // Rounded, inset rows: the selection reads as a pill inside the card,
    // never a strip that misses the card's edge.
    return Material(
      color: selected ? AppColors.dentalBlue.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _selected = index);
          unawaited(_checkQuality(scan)); // retries a failed check
          _loadPreviewFor(scan);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AdminIcon(
                    icon: Icons.view_in_ar_outlined,
                    size: 38,
                    color: selected ? AppColors.dentalBlue : AppColors.navy,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      file,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected ? AppColors.dentalBlue : AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (!_readOnly)
                IconButton(
                  tooltip: loc.scansDelete,
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : () => _removeOrReplace(scan),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: AppColors.danger,
                  ),
                ),
            ],
          ),
        ),
      ),
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
                            subtitleAsInfo: true,
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
                              if (!widget.api.isLaboratory)
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _openInbox,
                                icon: const Icon(Icons.inbox_outlined, size: 18),
                                label: Text(
                                  _inbox.isEmpty
                                      ? AppLocalizations.of(context).tr('c.incoming')
                                      : '${AppLocalizations.of(context).tr('c.incoming')} (${_inbox.length})',
                                ),
                              ),
                              if (!_readOnly)
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
                              if (!widget.api.isLaboratory)
                              FilledButton.icon(
                                onPressed: _busy ||
                                        _patient == null ||
                                        !_scans.any((s) => s['on_case'] != true)
                                    ? null
                                    : _saveToCase,
                                icon: const Icon(Icons.bookmark_added_outlined, size: 18),
                                label: Text(loc.tr('s.saveToCase')),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          CaseRejectionBanner(
                            info: _case,
                            margin: const EdgeInsets.only(bottom: 14),
                            store: widget.patientSession.cases,
                            patientId: _patient == null ? null : _pid(_patient!),
                            api: widget.api,
                          ),
                          if (_patient != null)
                            CaseFeedbackBar(
                            key: ValueKey('fb-scan-${_pid(_patient!)}'),
                            store: widget.patientSession.cases,
                            patientId: _pid(_patient!),
                            item: 'scan',
                            margin: const EdgeInsets.only(bottom: 14),
                          ),
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
                    // Viewer is the hero; the inspector sits on the right
                    // (portrait: under it) and fades out in fullscreen.
                    panelOnRight: true,
                    narrowContentFirst: true,
                    narrowPanelHeight: MediaQuery.sizeOf(context).height * 0.36 * chrome,
                    narrowContentMinHeight: 280,
                    panelFraction: 0.34 * chrome.clamp(0.001, 1.0),
                    minPanelWidth: 300 * chrome,
                    maxPanelWidth: 400 * chrome,
                    gap: 16 * chrome,
                    panel: IgnorePointer(
                      ignoring: t > 0.2,
                      child: Opacity(
                        opacity: chrome,
                        // Fullscreen shrinks this column to 0: keep the
                        // inspector at its own width and clip it instead of
                        // squeezing (and overflowing) its rows.
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final w = box.maxWidth < 300 ? 300.0 : box.maxWidth;
                            return ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.topLeft,
                                minWidth: w,
                                maxWidth: w,
                                child: _inspector(scan, loc, canUpload: canUpload, needsRescan: needsRescan),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    content: ClipRRect(
                      borderRadius: BorderRadius.circular(20 * chrome),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Hold the viewer: native action sheet for the
                          // shown scan, like holding the Shade photo. Drags
                          // still rotate the model (they win the gesture).
                          GestureDetector(
                            onLongPress: scan == null || t > 0.5 ? null : () => _showScanActions(scan),
                            child: _meshViewer(scan),
                          ),
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
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Right-hand card: the selected scan (name, quality, issues, its
  /// actions) on top, the patient's scans underneath.
  Widget _inspector(
    Map<String, dynamic>? scan,
    AppLocalizations loc, {
    required bool canUpload,
    required bool needsRescan,
  }) {
    final when = scan == null ? null : DateTime.tryParse('${scan['uploaded_at'] ?? scan['created_at'] ?? ''}')?.toLocal();
    final onCase = scan?['on_case'] == true;
    final selected = scan == null
        ? <Widget>[
            Text(
              _patient == null ? loc.scansQualityNeedPatient : loc.scansQualityNeedUpload,
              style: AppFonts.style(fontSize: 13.5, height: 1.4, color: AppColors.muted),
            ),
          ]
        : <Widget>[
            Text(
              '${scan['filename'] ?? '${loc.tr('s.scan')} #${scan['id']}'}',
              style: AppFonts.style(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy, height: 1.25),
            ),
            const SizedBox(height: 4),
            Text(
              [if (when != null) adminWhen(context, when), onCase ? loc.tr('s.onCase') : loc.tr('s.libraryOnly')].join(' · '),
              style: AppFonts.style(fontSize: 12.5, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            Builder(
              builder: (context) {
                final issues = _incoming == null ? _issuesFor(scan) : const <Map<String, dynamic>>[];
                final openDetails = issues.isNotEmpty ? () => _showScanIssues(scan) : null;
                final box = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: openDetails == null
                        ? null
                        : Border.all(color: AppColors.border.withValues(alpha: 0.7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _qualityStatus(scan, loc),
                      if (issues.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                loc.trp('sq.issueCount', {'n': issues.length}),
                                style: AppFonts.style(fontSize: 13.5, color: AppColors.muted),
                              ),
                            ),
                            Text(
                              loc.tr('sq.viewDetails'),
                              style: AppFonts.style(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.dentalBlue,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.dentalBlue),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
                if (openDetails == null) return box;
                return Pressable(
                  onTap: openDetails,
                  scale: 0.98,
                  builder: (_, _) => box,
                );
              },
            ),
            if (!_readOnly) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_incoming == null && needsRescan)
                    AppButtons.danger(
                      onPressed: canUpload ? _upload : null,
                      icon: Icons.refresh_rounded,
                      label: loc.scansRescanNow,
                      compact: true,
                    ),
                  AppButtons.ghost(
                    onPressed: _busy ? null : () => _removeOrReplace(scan),
                    icon: Icons.delete_outline_rounded,
                    label: loc.scansDelete,
                    compact: true,
                  ),
                ],
              ),
            ],
          ];
    return AdminCard(
      padding: EdgeInsets.zero,
      child: CustomScrollView(
        primary: false,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            sliver: SliverList.list(children: selected),
          ),
          SliverToBoxAdapter(
            child: Divider(height: 28, indent: 18, endIndent: 18, color: AppColors.border.withValues(alpha: 0.6)),
          ),
          SliverToBoxAdapter(child: _scanLibrary(loc, canUpload)),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
        ],
      ),
    );
  }

  /// Hold a scan: iPad action sheet with why it's bad, rescan and delete.
  Future<void> _showScanActions(Map<String, dynamic> scan) async {
    final loc = AppLocalizations.of(context);
    final issues = _incoming == null ? _issuesFor(scan) : const <Map<String, dynamic>>[];
    final bad = scan['prompt_rescan'] == true || scan['validation_result'] == 'bad';
    AppHaptics.selection();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('${scan['filename'] ?? '${loc.tr('s.scan')} #${scan['id']}'}'),
        message: Text(loc.tr(bad ? 's.qBad' : 'sq.holdMsg')),
        actions: [
          if (issues.isNotEmpty)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _showScanIssues(scan);
              },
              child: Text(loc.tr('sq.whyBad')),
            ),
          if (bad && !_readOnly && !_busy && _patient != null)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _upload();
              },
              child: Text(loc.scansRescanNow),
            ),
          if (!_readOnly)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(ctx);
                if (!_busy) _removeOrReplace(scan);
              },
              child: Text(loc.scansDelete),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(loc.cancel),
        ),
      ),
    );
  }

  /// Why a scan failed the quality check: each finding, how serious, what
  /// it means — in a centred iPad-style sheet, with Rescan.
  Future<void> _showScanIssues(Map<String, dynamic> scan) async {
    final loc = AppLocalizations.of(context);
    final issues = _issuesFor(scan);
    final bad = scan['prompt_rescan'] == true || scan['validation_result'] == 'bad';
    await AppDialogs.sheet<void>(
      context: context,
      maxWidth: 560,
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 12, 4),
                child: Row(
                  children: [
                    AdminIcon(
                      icon: bad ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                      color: bad ? AppColors.danger : AppColors.warning,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(loc.tr(bad ? 'sq.badTitle' : 'sq.reviewTitle'),
                              style: AppFonts.style(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy)),
                          Text('${scan['filename'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(fontSize: 12.5, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: loc.commonClose,
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
                  children: [for (final issue in issues) _issueCard(issue, loc)],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppButtons.ghost(onPressed: () => Navigator.pop(ctx), label: loc.commonClose, compact: true),
                    if (bad && !_readOnly) ...[
                      AppButtons.danger(
                        compact: true,
                        onPressed: _busy || _patient == null
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _upload();
                              },
                        icon: Icons.refresh_rounded,
                        label: loc.scansRescanNow,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 15),
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
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                loc.tr('sq.sev.$sev'),
                style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            known ? loc.tr('sq.$code.d') : '${issue['message'] ?? ''}',
            style: const TextStyle(fontSize: 15, height: 1.4),
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

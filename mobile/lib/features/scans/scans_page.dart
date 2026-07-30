import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/offline/sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

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
  String? _error;
  Map<String, dynamic>? _lastResult;

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

  Future<void> _selectPatient(Map<String, dynamic> patient) async {
    setState(() {
      _patient = patient;
      _case = null;
      _scans = [];
      _lastResult = null;
    });
    final cases = await widget.api.listCases();
    final mine = cases.where((c) => c['patient_id'] == patient['id']).toList();
    final caseRow = mine.isEmpty
        ? await widget.api.createCase(patient['id'] as int)
        : mine.first;
    final scans = await widget.api.listScans(caseRow['id'] as int);
    setState(() {
      _case = caseRow;
      _scans = scans;
      _selected = 0;
    });
  }

  Future<void> _upload() async {
    if (_case == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
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
        return;
      }
      final name = file.name;
      final upload = await _sync.captureScan(
        caseId: _case!['id'] as int,
        bytes: Uint8List.fromList(bytes),
        filename: name,
      );
      setState(() => _lastResult = upload);
      await _sync.flush();
      final scans = await widget.api.listScans(_case!['id'] as int);
      setState(() {
        _scans = scans;
        _selected = scans.isEmpty ? 0 : scans.length - 1;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
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
                    const Text(
                      'Upload PLY · AI quality check · encrypted at rest · offline queue',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (_patients.isNotEmpty)
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    initialValue: _patient?['id'] as int?,
                    decoration: const InputDecoration(isDense: true),
                    items: _patients
                        .map(
                          (p) => DropdownMenuItem(
                            value: p['id'] as int,
                            child: Text('${p['first_name']} ${p['last_name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      final p = _patients.firstWhere((e) => e['id'] == id);
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 300,
                  child: Column(
                    children: [
                      InkWell(
                        onTap: _busy || _case == null ? null : _upload,
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
                                'PLY, STL, OBJ — encrypted locally + server',
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
                          child: _scans.isEmpty
                              ? const Center(
                                  child: Text('No scans yet',
                                      style: TextStyle(color: AppColors.muted)),
                                )
                              : ListView.builder(
                                  itemCount: _scans.length,
                                  itemBuilder: (context, i) {
                                    final s = _scans[i];
                                    final selected = i == _selected;
                                    final q = ((s['quality_score'] as num?)?.toDouble() ?? 0);
                                    final pct = (q <= 1 ? q * 100 : q).round();
                                    return ListTile(
                                      selected: selected,
                                      selectedTileColor: AppColors.sidebarActive,
                                      onTap: () => setState(() => _selected = i),
                                      title: Text(
                                        'Scan #${s['id']}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${s['validation_result'] ?? 'pending'}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: Text(
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
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scan == null
                              ? 'No scan selected'
                              : 'Scan #${scan['id']} · ${_patient?['first_name'] ?? ''} ${_patient?['last_name'] ?? ''}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppColors.navy,
                              borderRadius: AppRadii.border,
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.remove_red_eye_outlined,
                                    color: Colors.white70, size: 36),
                                SizedBox(height: 10),
                                Text(
                                  'Interactive viewer — rotate, zoom, inspect',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
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
                              onPressed: _busy || _case == null ? null : _upload,
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
              ],
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

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

class PatientsPage extends StatefulWidget {
  const PatientsPage({
    super.key,
    required this.api,
    required this.dentistName,
    required this.onNewPatient,
  });

  final ApiClient api;
  final String dentistName;
  final VoidCallback onNewPatient;

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  bool _loading = true;
  String? _error;
  String _query = '';
  String _filter = 'all';

  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _cases = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.listPatients(),
        widget.api.listCases(),
      ]);
      if (!mounted) return;
      setState(() {
        _patients = results[0];
        _cases = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// Most recently updated case for a patient, if any.
  Map<String, dynamic>? _latestCaseFor(int patientId) {
    Map<String, dynamic>? best;
    DateTime? bestAt;
    for (final c in _cases) {
      if (c['patient_id'] != patientId) continue;
      final at = DateTime.tryParse('${c['updated_at'] ?? ''}');
      if (best == null ||
          (at != null && (bestAt == null || at.isAfter(bestAt)))) {
        best = c;
        bestAt = at;
      }
    }
    return best;
  }

  String _statusFor(int patientId) {
    final c = _latestCaseFor(patientId);
    if (c == null) return 'no_case';
    return CaseStatuses.normalize(c['status']?.toString());
  }

  List<Map<String, dynamic>> get _visible {
    var rows = [..._patients];
    if (_query.isNotEmpty) {
      rows = rows.where((p) {
        final name = '${p['first_name']} ${p['last_name']}'.toLowerCase();
        final id = 'pt-${p['id']}'.toLowerCase();
        return name.contains(_query) || id.contains(_query);
      }).toList();
    }
    if (_filter != 'all') {
      rows = rows.where((p) {
        final id = p['id'];
        if (id is! int) return false;
        return CaseStatuses.matchesFilter(_statusFor(id), _filter);
      }).toList();
    }
    rows.sort((a, b) {
      final an = '${a['last_name'] ?? ''} ${a['first_name'] ?? ''}'.toLowerCase();
      final bn = '${b['last_name'] ?? ''} ${b['first_name'] ?? ''}'.toLowerCase();
      return an.compareTo(bn);
    });
    return rows;
  }

  Future<void> _setStatus(Map<String, dynamic> patient, String status) async {
    final pid = patient['id'];
    if (pid is! int) return;
    try {
      var caseRow = _latestCaseFor(pid);
      caseRow ??= await widget.api.createCase(pid);
      final caseId = caseRow['id'];
      if (caseId is! int) return;
      final updated = await widget.api.updateCaseStatus(caseId, status);
      if (!mounted) return;
      setState(() {
        final i = _cases.indexWhere((c) => c['id'] == caseId);
        if (i >= 0) {
          _cases[i] = updated;
        } else {
          _cases = [..._cases, updated];
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _deletePatient(int id) async {
    try {
      await widget.api.deletePatient(id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final visible = _visible;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.people_alt_outlined,
            title: loc.patientsTitle,
            subtitle: loc.patientsSubtitle,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4, top: 10),
                child: Text(
                  _loading
                      ? '…'
                      : '${visible.length} shown · ${_patients.length} total',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: loc.refresh,
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
              FilledButton.icon(
                onPressed: widget.onNewPatient,
                icon: const Icon(Icons.add, size: 18),
                label: Text(loc.navNewPatient),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (_patients.isEmpty) return;
                  final id = _patients.first['id'] as int;
                  final xml = await widget.api.exportDatevXml(id);
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('DATEV XML skeleton'),
                      content: SizedBox(
                        width: 480,
                        height: 320,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            xml,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.code, size: 18),
                label: const Text('DATEV export'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            depth: 0.7,
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: loc.searchPatients,
                prefixIcon: const Icon(Icons.search, color: AppColors.muted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in CaseStatuses.filters)
                SoftFilterChip(
                  label: f.key == 'all' ? loc.filterAll : loc.statusLabel(f.key),
                  selected: _filter == f.key,
                  onTap: () => setState(() => _filter = f.key),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: SectionCard(
              padding: EdgeInsets.zero,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? Center(
                          child: Text(
                            _patients.isEmpty
                                ? 'No patients yet. Add the first record.'
                                : 'No patients match this status filter.',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: AppColors.border.withValues(alpha: 0.7),
                          ),
                          itemBuilder: (context, i) {
                            final p = visible[i];
                            final pid = p['id'] as int;
                            final name =
                                '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'
                                    .trim();
                            final caseRow = _latestCaseFor(pid);
                            final status = _statusFor(pid);
                            final caseLabel = caseRow == null
                                ? 'No open case'
                                : 'CASE-${(caseRow['id'] as int).toString().padLeft(4, '0')}';
                            final insurance =
                                (p['health_insurance'] as String?)?.trim();
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: InitialsAvatar(name: name.isEmpty ? '?' : name),
                              title: Text(
                                name.isEmpty ? 'Patient #$pid' : name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '$caseLabel · ${widget.dentistName}'
                                '${insurance == null || insurance.isEmpty ? '' : ' · $insurance'}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _StatusMenu(
                                    status: status,
                                    onChanged: (s) => _setStatus(p, s),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: 'Delete',
                                    onPressed: () => _deletePatient(pid),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.danger,
                                      size: 20,
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
    );
  }
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.status, required this.onChanged});

  final String status;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Change case status',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final key in CaseStatuses.all)
          PopupMenuItem(
            value: key,
            child: Row(
              children: [
                Icon(
                  key == status ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                  color: key == status ? AppColors.dentalBlue : AppColors.muted,
                ),
                const SizedBox(width: 10),
                Text(StatusStyle.of(key).label),
              ],
            ),
          ),
      ],
      child: StatusChip(statusKey: status),
    );
  }
}

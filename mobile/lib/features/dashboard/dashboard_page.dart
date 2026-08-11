import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_sidebar.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.dentistName,
    required this.api,
    required this.onNavigate,
    this.unreadMessages = 0,
  });

  final String dentistName;
  final ApiClient api;
  final ValueChanged<AppNavItem> onNavigate;
  final int unreadMessages;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _loading = true;
  String? _error;

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

  Map<int, Map<String, dynamic>> get _patientsById {
    final map = <int, Map<String, dynamic>>{};
    for (final p in _patients) {
      final id = p['id'];
      if (id is int) map[id] = p;
    }
    return map;
  }

  String get _shortName {
    final parts = widget.dentistName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return widget.dentistName;
    return parts.last;
  }

  String _greetingTitle(AppLocalizations loc) {
    final h = DateTime.now().hour;
    if (h < 12) return loc.goodMorning(_shortName);
    if (h < 17) return loc.goodAfternoon(_shortName);
    return loc.goodEvening(_shortName);
  }

  int get _completed =>
      _cases.where((c) => CaseStatuses.normalize('${c['status']}') == CaseStatuses.completed).length;
  int get _pending =>
      _cases.where((c) => CaseStatuses.normalize('${c['status']}') == CaseStatuses.pending).length;
  int get _inProgress =>
      _cases.where((c) => CaseStatuses.normalize('${c['status']}') == CaseStatuses.inProgress).length;
  int get _inReview =>
      _cases.where((c) => CaseStatuses.normalize('${c['status']}') == CaseStatuses.inReview).length;
  int get _rejected =>
      _cases.where((c) => CaseStatuses.normalize('${c['status']}') == CaseStatuses.rejected).length;
  int get _attention => _pending + _inProgress + _inReview + _rejected;

  int get _unreadMessages => widget.unreadMessages;

  String get _avgProcessingLabel {
    final completed = _cases
        .where((c) => CaseStatuses.normalize('${c['status']}') == CaseStatuses.completed)
        .toList();
    if (completed.isEmpty) return '—';
    var totalHours = 0.0;
    var counted = 0;
    for (final c in completed) {
      final created = DateTime.tryParse('${c['created_at'] ?? ''}');
      final updated = DateTime.tryParse('${c['updated_at'] ?? ''}');
      if (created == null || updated == null) continue;
      totalHours += updated.difference(created).inMinutes / 60.0;
      counted++;
    }
    if (counted == 0) return '—';
    final days = totalHours / counted / 24.0;
    if (days < 1) return '${(days * 24).toStringAsFixed(0)}h';
    return '${days.toStringAsFixed(1)}d';
  }

  List<_CaseRowData> get _recentRows {
    final byId = _patientsById;
    final sorted = [..._cases]..sort((a, b) {
          final ta = DateTime.tryParse('${a['updated_at'] ?? ''}') ?? DateTime(1970);
          final tb = DateTime.tryParse('${b['updated_at'] ?? ''}') ?? DateTime(1970);
          return tb.compareTo(ta);
        });
    return sorted.take(8).map((c) {
      final pid = c['patient_id'];
      final patient = pid is int ? byId[pid] : null;
      final name = patient == null
          ? 'Patient #$pid'
          : '${patient['first_name'] ?? ''} ${patient['last_name'] ?? ''}'.trim();
      final caseId = c['id'] is int ? c['id'] as int : 0;
      return _CaseRowData(
        caseLabel: 'CASE-${caseId.toString().padLeft(4, '0')}',
        patientName: name.isEmpty ? 'Unknown' : name,
        dentist: widget.dentistName,
        status: CaseStatuses.normalize('${c['status'] ?? 'pending'}'),
        updated: _relativeTime(DateTime.tryParse('${c['updated_at'] ?? ''}')),
      );
    }).toList();
  }

  List<_ActivityItem> get _activity {
    final items = <_ActivityItem>[];
    final byId = _patientsById;

    for (final c in _cases) {
      final updated = DateTime.tryParse('${c['updated_at'] ?? ''}');
      if (updated == null) continue;
      final pid = c['patient_id'];
      final patient = pid is int ? byId[pid] : null;
      final name = patient == null
          ? 'a patient'
          : '${patient['first_name'] ?? ''} ${patient['last_name'] ?? ''}'.trim();
      final status = '${c['status'] ?? ''}';
      final caseId = c['id'] is int ? c['id'] as int : 0;
      final label = switch (status) {
        'completed' => 'Case CASE-${caseId.toString().padLeft(4, '0')} marked complete — $name',
        'rejected' => 'Scan rejected for $name — rescan required',
        'in_review' => 'Case for $name moved to lab review',
        'in_progress' => 'Case for $name is in progress',
        'pending' => 'Case opened for $name — awaiting scan',
        _ => 'Case updated for $name',
      };
      items.add(_ActivityItem(at: updated, text: label));
    }

    items.sort((a, b) => b.at.compareTo(a.at));
    return items.take(10).toList();
  }

  String _subtitleText(AppLocalizations loc) {
    if (_cases.isEmpty) {
      return loc.dashNoCases;
    }
    final parts = <String>[];
    if (_attention > 0) {
      parts.add(
        '$_attention case${_attention == 1 ? '' : 's'} need${_attention == 1 ? 's' : ''} attention',
      );
    }
    if (_unreadMessages > 0) {
      parts.add(
        '$_unreadMessages unread message${_unreadMessages == 1 ? '' : 's'}',
      );
    }
    if (parts.isEmpty) {
      return '${_patients.length} patients · ${_cases.length} cases on file.';
    }
    return '${parts.join(' · ')}.';
  }

  static String _relativeTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.isUtc ? dt.toLocal() : dt;
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${local.day}.${local.month.toString().padLeft(2, '0')}.${local.year}';
  }

  static String _clock(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.grid_view_rounded,
            title: _greetingTitle(loc),
            subtitle: _loading ? loc.dashLoading : _subtitleText(loc),
            chromeActions: [
              AppButtons.icon(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: Icons.refresh_rounded,
              ),
            ],
            actions: [
              AppButtons.primary(
                onPressed: () => widget.onNavigate(AppNavItem.newPatient),
                icon: Icons.add_rounded,
                label: loc.navNewPatient,
              ),
              AppButtons.secondary(
                onPressed: () => widget.onNavigate(AppNavItem.messages),
                icon: Icons.chat_bubble_outline_rounded,
                label: _unreadMessages > 0
                    ? '${loc.navMessages} ($_unreadMessages)'
                    : loc.navMessages,
              ),
              if (widget.api.isDentist)
                AppButtons.secondary(
                  onPressed: () =>
                      widget.onNavigate(AppNavItem.laboratories),
                  icon: Icons.biotech_outlined,
                  label: loc.navLaboratories,
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final kpis = <Widget>[
                _KpiCard(
                  title: loc.dashCompletedCases,
                  value: _loading ? '…' : '$_completed',
                  hint: _patients.isEmpty
                      ? loc.dashNoPatientsHint
                      : '${_patients.length} patients on file',
                  hintColor: AppColors.success,
                ),
                _KpiCard(
                  title: loc.dashAvgProcessing,
                  value: _loading ? '…' : _avgProcessingLabel,
                  hint: _completed == 0
                      ? loc.dashBasedOnCompleted
                      : 'Across $_completed completed',
                  hintColor: AppColors.muted,
                ),
                _KpiCard(
                  title: loc.dashPendingScans,
                  value: _loading ? '…' : '$_pending',
                  hint: _inProgress == 0 && _inReview == 0
                      ? loc.dashNoneInProgress
                      : '$_inProgress in progress · $_inReview in review',
                  hintColor: _pending > 0 || _inProgress > 0 || _inReview > 0
                      ? AppColors.warning
                      : AppColors.success,
                ),
                _KpiCard(
                  title: loc.dashRejectedScans,
                  value: _loading ? '…' : '$_rejected',
                  hint: _rejected == 0
                      ? loc.dashNoRejections
                      : loc.dashNeedRescan,
                  hintColor: _rejected > 0 ? AppColors.danger : AppColors.success,
                ),
              ];
              // Portrait / narrow: two KPI cards per row instead of four.
              if (constraints.maxWidth < AppBreakpoints.stack) {
                return Column(
                  children: [
                    Row(children: [
                      Expanded(child: kpis[0]),
                      const SizedBox(width: 12),
                      Expanded(child: kpis[1]),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: kpis[2]),
                      const SizedBox(width: 12),
                      Expanded(child: kpis[3]),
                    ]),
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < kpis.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: kpis[i]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < AppBreakpoints.stack;
                final recentCases = SectionCard(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.dashRecentCases,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _TableHeader(),
                        const Divider(height: 1),
                        Expanded(
                          child: _loading
                              ? const ToothPageLoader(
                                  message: 'Loading recent cases…',
                                )
                              : _recentRows.isEmpty
                                  ? Center(
                                      child: Text(
                                        loc.dashNoCasesEmpty,
                                        style: const TextStyle(color: AppColors.muted),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _recentRows.length,
                                      itemBuilder: (context, i) {
                                        final row = _recentRows[i];
                                        return _PatientRow(
                                          id: row.caseLabel,
                                          name: row.patientName,
                                          dentist: row.dentist,
                                          status: row.status,
                                          updated: row.updated,
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  );
                final activityCard = SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.dashRecentActivity,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _loading
                              ? const ToothPageLoader(
                                  message: 'Loading activity…',
                                )
                              : _activity.isEmpty
                                  ? Text(
                                      loc.dashActivityEmpty,
                                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                                    )
                                  : ListView.builder(
                                      itemCount: _activity.length,
                                      itemBuilder: (context, i) {
                                        final a = _activity[i];
                                        return _Activity(
                                          time: _clock(a.at),
                                          text: a.text,
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: recentCases),
                      const SizedBox(height: 12),
                      Expanded(flex: 2, child: activityCard),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: recentCases),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: activityCard),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CaseRowData {
  const _CaseRowData({
    required this.caseLabel,
    required this.patientName,
    required this.dentist,

    required this.status,
    required this.updated,
  });

  final String caseLabel;
  final String patientName;
  final String dentist;
  final String status;
  final String updated;
}

class _ActivityItem {
  const _ActivityItem({required this.at, required this.text});

  final DateTime at;
  final String text;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.hint,
    required this.hintColor,
  });

  final String title;
  final String value;
  final String hint;
  final Color hintColor;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: TextStyle(color: hintColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(loc.colCaseId, style: _h)),
          Expanded(flex: 3, child: Text(loc.colPatient, style: _h)),
          Expanded(flex: 3, child: Text(loc.colDentist, style: _h)),
          Expanded(flex: 2, child: Text(loc.colStatus, style: _h)),
          Expanded(flex: 2, child: Text(loc.colUpdated, style: _h)),
        ],
      ),
    );
  }
}

const _h = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: AppColors.muted,
  letterSpacing: 0.4,
);

class _PatientRow extends StatelessWidget {
  const _PatientRow({
    required this.id,
    required this.name,
    required this.dentist,
    required this.status,
    required this.updated,
  });

  final String id;
  final String name;
  final String dentist;
  final String status;
  final String updated;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(id, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                InitialsAvatar(name: name, size: 32),
                const SizedBox(width: 8),
                Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(dentist, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(statusKey: status),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              updated,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Activity extends StatelessWidget {
  const _Activity({required this.time, required this.text});

  final String time;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: const BoxDecoration(
              color: AppColors.dentalBlue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
                const SizedBox(height: 2),
                Text(time, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

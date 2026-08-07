import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/touchable.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_sidebar.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    required this.api,
    required this.onNavigate,
  });

  final ApiClient api;
  final ValueChanged<AppNavItem> onNavigate;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _loading = true;
  String? _error;
  int _days = 30;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await widget.api.fetchReportsSummary(days: _days);
      if (!mounted) return;
      setState(() {
        _summary = summary;
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

  void _setPeriod(int days) {
    if (_days == days) return;
    setState(() => _days = days);
    _load();
  }

  Map<String, dynamic> get _cases =>
      (_summary?['cases'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get _patientsBlock =>
      (_summary?['patients'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get _clinical =>
      (_summary?['clinical'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get _messages =>
      (_summary?['messages'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get _notifications =>
      (_summary?['notifications'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get _byStatus =>
      (_cases['by_status'] as Map<String, dynamic>?) ?? const {};
  List<Map<String, dynamic>> get _throughput =>
      ((_summary?['throughput'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _attention =>
      ((_summary?['attention'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _topPatients =>
      ((_summary?['top_patients'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  int _n(dynamic v) => (v as num?)?.toInt() ?? 0;
  double? _d(dynamic v) => (v as num?)?.toDouble();

  String _avgLabel() {
    final hours = _d(_cases['avg_processing_hours']);
    if (hours == null) return '—';
    if (hours < 24) return '${hours.toStringAsFixed(0)}h';
    return '${(hours / 24).toStringAsFixed(1)}d';
  }

  String _rejectionLabel() {
    final rate = _d(_cases['rejection_rate']) ?? 0;
    return '${(rate * 100).toStringAsFixed(rate > 0 && rate < 0.01 ? 1 : 0)}%';
  }

  String _periodSubtitle(AppLocalizations loc) {
    final clinic = '${_summary?['clinic_name'] ?? ''}'.trim();
    final prefix = clinic.isEmpty ? loc.reportsSubtitle : clinic;
    final period = switch (_days) {
      7 => loc.reportsPeriod7,
      90 => loc.reportsPeriod90,
      0 => loc.reportsPeriodAll,
      _ => loc.reportsPeriod30,
    };
    return '$prefix · $period';
  }

  Future<void> _showClinicSummary() async {
    final loc = AppLocalizations.of(context);
    final text = _buildSummaryText(loc);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.reportsSummaryTitle),
        content: SizedBox(
          width: 520,
          height: 380,
          child: SingleChildScrollView(
            child: SelectableText(text, style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.reportsClose),
          ),
        ],
      ),
    );
  }

  String _buildSummaryText(AppLocalizations loc) {
    final clinic = '${_summary?['clinic_name'] ?? 'Elite Dent'}';
    final dentist = '${_summary?['dentist_name'] ?? ''}';
    final period = switch (_days) {
      7 => loc.reportsPeriod7,
      90 => loc.reportsPeriod90,
      0 => loc.reportsPeriodAll,
      _ => loc.reportsPeriod30,
    };
    final buf = StringBuffer()
      ..writeln('$clinic — $dentist')
      ..writeln('Period: $period')
      ..writeln('Generated: ${_summary?['generated_at'] ?? ''}')
      ..writeln()
      ..writeln('${loc.reportsPatients}: ${_n(_patientsBlock['total'])} '
          '(${_n(_patientsBlock['new_in_period'])} ${loc.reportsNewInPeriod})')
      ..writeln('${loc.reportsActiveCases}: ${_n(_cases['active'])}')
      ..writeln('${loc.reportsCompleted}: ${_n(_cases['by_status'] is Map ? (_byStatus['completed'] ?? 0) : 0)} '
          '(${_n(_cases['completed_in_period'])} ${loc.reportsCompletedInPeriod})')
      ..writeln('${loc.reportsAvgTime}: ${_avgLabel()}')
      ..writeln('${loc.reportsRejectionRate}: ${_rejectionLabel()}')
      ..writeln()
      ..writeln('${loc.reportsPipeline}:');
    for (final s in CaseStatuses.all) {
      buf.writeln('  · ${loc.statusLabel(s)}: ${_n(_byStatus[s])}');
    }
    buf
      ..writeln()
      ..writeln('${loc.reportsClinical}: ${_d(_clinical['coverage_pct'])?.toStringAsFixed(0) ?? '0'}%')
      ..writeln('  · ${loc.reportsWithScans}: ${_n(_clinical['cases_with_scans'])}')
      ..writeln('  · ${loc.reportsWithShade}: ${_n(_clinical['cases_with_shade'])}')
      ..writeln('  · ${loc.reportsWithShape}: ${_n(_clinical['cases_with_shape'])}')
      ..writeln('  · ${loc.reportsWithScanBody}: ${_n(_clinical['cases_with_scan_body'])}')
      ..writeln()
      ..writeln('${loc.reportsLabInbox}:')
      ..writeln('  · ${loc.reportsUnreadMessages}: ${_n(_messages['unread'])}')
      ..writeln('  · ${loc.reportsThreads}: ${_n(_messages['threads_with_messages'])}')
      ..writeln('  · ${loc.reportsUnreadNotifs}: ${_n(_notifications['unread'])}');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final totalCases = _n(_cases['total']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.bar_chart_rounded,
            title: loc.reportsTitle,
            subtitle: _loading ? loc.reportsLoading : _periodSubtitle(loc),
            actions: [
              IconButton(
                tooltip: loc.refresh,
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
              OutlinedButton.icon(
                onPressed: _loading || _summary == null ? null : _showClinicSummary,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text(loc.reportsSummaryExport),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftFilterChip(
                label: loc.reportsPeriod7,
                selected: _days == 7,
                enabled: !_loading,
                onTap: () => _setPeriod(7),
              ),
              SoftFilterChip(
                label: loc.reportsPeriod30,
                selected: _days == 30,
                enabled: !_loading,
                onTap: () => _setPeriod(30),
              ),
              SoftFilterChip(
                label: loc.reportsPeriod90,
                selected: _days == 90,
                enabled: !_loading,
                onTap: () => _setPeriod(90),
              ),
              SoftFilterChip(
                label: loc.reportsPeriodAll,
                selected: _days == 0,
                enabled: !_loading,
                onTap: () => _setPeriod(0),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading && _summary == null
                ? const ToothPageLoader(message: 'Loading reports…')
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _KpiRow(
                          loading: _loading,
                          items: [
                            _KpiData(
                              title: loc.reportsPatients,
                              value: '${_n(_patientsBlock['total'])}',
                              hint:
                                  '${_n(_patientsBlock['new_in_period'])} ${loc.reportsNewInPeriod}',
                              hintColor: AppColors.dentalBlue,
                            ),
                            _KpiData(
                              title: loc.reportsActiveCases,
                              value: '${_n(_cases['active'])}',
                              hint:
                                  '${_n(_cases['created_in_period'])} ${loc.reportsCreatedInPeriod}',
                              hintColor: AppColors.warning,
                            ),
                            _KpiData(
                              title: loc.reportsCompleted,
                              value: '${_n(_byStatus['completed'])}',
                              hint:
                                  '${_n(_cases['completed_in_period'])} ${loc.reportsCompletedInPeriod}',
                              hintColor: AppColors.success,
                            ),
                            _KpiData(
                              title: loc.reportsAvgTime,
                              value: _avgLabel(),
                              hint: loc.dashBasedOnCompleted,
                              hintColor: AppColors.muted,
                            ),
                            _KpiData(
                              title: loc.reportsRejectionRate,
                              value: _rejectionLabel(),
                              hint: _n(_byStatus['rejected']) == 0
                                  ? loc.dashNoRejections
                                  : loc.dashNeedRescan,
                              hintColor: _n(_byStatus['rejected']) > 0
                                  ? AppColors.danger
                                  : AppColors.success,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 980;
                            final pipeline = _PipelineCard(
                              loc: loc,
                              byStatus: _byStatus,
                              total: totalCases,
                            );
                            final throughput = _ThroughputCard(
                              loc: loc,
                              weeks: _throughput,
                            );
                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: pipeline),
                                  const SizedBox(width: 12),
                                  Expanded(flex: 2, child: throughput),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                pipeline,
                                const SizedBox(height: 12),
                                throughput,
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 980;
                            final clinical = _ClinicalCard(
                              loc: loc,
                              clinical: _clinical,
                              totalCases: totalCases,
                            );
                            final inbox = _InboxCard(
                              loc: loc,
                              messages: _messages,
                              notifications: _notifications,
                              onMessages: () =>
                                  widget.onNavigate(AppNavItem.messages),
                              onNotifications: () =>
                                  widget.onNavigate(AppNavItem.notifications),
                            );
                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: clinical),
                                  const SizedBox(width: 12),
                                  Expanded(flex: 2, child: inbox),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                clinical,
                                const SizedBox(height: 12),
                                inbox,
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 980;
                            final attention = _AttentionCard(
                              loc: loc,
                              rows: _attention,
                              onPatients: () =>
                                  widget.onNavigate(AppNavItem.patients),
                            );
                            final top = _TopPatientsCard(
                              loc: loc,
                              rows: _topPatients,
                              onPatients: () =>
                                  widget.onNavigate(AppNavItem.patients),
                            );
                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: attention),
                                  const SizedBox(width: 12),
                                  Expanded(flex: 2, child: top),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                attention,
                                const SizedBox(height: 12),
                                top,
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        _ExportsCard(
                          loc: loc,
                          onSummary: _showClinicSummary,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _KpiData {
  const _KpiData({
    required this.title,
    required this.value,
    required this.hint,
    required this.hintColor,
  });

  final String title;
  final String value;
  final String hint;
  final Color hintColor;
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.items, required this.loading});

  final List<_KpiData> items;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wrap = constraints.maxWidth < 1100;
        if (wrap) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in items)
                SizedBox(
                  width: (constraints.maxWidth - 12) / 2,
                  child: _KpiCard(data: item, loading: loading),
                ),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: _KpiCard(data: items[i], loading: loading)),
            ],
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data, required this.loading});

  final _KpiData data;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      depth: 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.title,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            loading ? '…' : data.value,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: data.hintColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({
    required this.loc,
    required this.byStatus,
    required this.total,
  });

  final AppLocalizations loc;
  final Map<String, dynamic> byStatus;
  final int total;

  int _n(String key) => (byStatus[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.reportsPipeline,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            total == 0 ? loc.reportsNoData : '$total ${loc.reportsCasesCol.toLowerCase()}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          for (final status in CaseStatuses.all) ...[
            _StatusBar(
              label: loc.statusLabel(status),
              count: _n(status),
              total: total,
              color: StatusStyle.of(status).fg,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            Text(
              '$count · ${(pct * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: AppColors.inset),
                FractionallySizedBox(
                  widthFactor: pct.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ThroughputCard extends StatelessWidget {
  const _ThroughputCard({required this.loc, required this.weeks});

  final AppLocalizations loc;
  final List<Map<String, dynamic>> weeks;

  @override
  Widget build(BuildContext context) {
    var maxVal = 1;
    for (final w in weeks) {
      final c = (w['created'] as num?)?.toInt() ?? 0;
      final d = (w['completed'] as num?)?.toInt() ?? 0;
      if (c > maxVal) maxVal = c;
      if (d > maxVal) maxVal = d;
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.reportsThroughput,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _LegendDot(color: AppColors.dentalBlue, label: loc.reportsCreated),
              const SizedBox(width: 14),
              _LegendDot(color: AppColors.success, label: loc.reportsCompleted),
            ],
          ),
          const SizedBox(height: 18),
          if (weeks.isEmpty)
            Text(
              loc.reportsNoData,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            )
          else
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final w in weeks)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _WeekBars(
                          created: (w['created'] as num?)?.toInt() ?? 0,
                          completed: (w['completed'] as num?)?.toInt() ?? 0,
                          maxVal: maxVal,
                          label: _weekLabel('${w['week_start'] ?? ''}'),
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

  static String _weekLabel(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({
    required this.created,
    required this.completed,
    required this.maxVal,
    required this.label,
  });

  final int created;
  final int completed;
  final int maxVal;
  final String label;

  @override
  Widget build(BuildContext context) {
    final hCreated = (created / maxVal).clamp(0.05, 1.0) * 120;
    final hDone = (completed / maxVal).clamp(0.05, 1.0) * 120;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  height: created == 0 ? 4 : hCreated,
                  decoration: BoxDecoration(
                    color: AppColors.dentalBlue.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Container(
                  height: completed == 0 ? 4 : hDone,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _ClinicalCard extends StatelessWidget {
  const _ClinicalCard({
    required this.loc,
    required this.clinical,
    required this.totalCases,
  });

  final AppLocalizations loc;
  final Map<String, dynamic> clinical;
  final int totalCases;

  int _n(String key) => (clinical[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final coverage = (clinical['coverage_pct'] as num?)?.toDouble() ?? 0;
    final items = [
      (loc.reportsWithScans, _n('cases_with_scans'), Icons.view_in_ar_outlined),
      (loc.reportsWithPhotos, _n('cases_with_photos'), Icons.photo_camera_outlined),
      (loc.reportsWithShade, _n('cases_with_shade'), Icons.palette_outlined),
      (loc.reportsWithShape, _n('cases_with_shape'), Icons.sentiment_satisfied_alt_outlined),
      (loc.reportsWithScanBody, _n('cases_with_scan_body'), Icons.architecture_outlined),
    ];

    return SectionCard(
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
                      loc.reportsClinical,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      loc.reportsClinicalHint,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.neo,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: NeoShadows.soft(depth: 0.35),
                ),
                child: Column(
                  children: [
                    Text(
                      '${coverage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      loc.reportsCoverage,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in items)
                _MetricTile(
                  icon: item.$3,
                  label: item.$1,
                  value: totalCases == 0
                      ? '0'
                      : '${item.$2}/$totalCases',
                ),
              _MetricTile(
                icon: Icons.folder_copy_outlined,
                label: loc.reportsTotalScans,
                value: '${_n('total_scans')}',
              ),
              _MetricTile(
                icon: Icons.colorize_outlined,
                label: loc.reportsTotalShades,
                value: '${_n('total_shade_saves')}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.neo,
        borderRadius: BorderRadius.circular(14),
        boxShadow: NeoShadows.soft(depth: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.dentalBlue),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.loc,
    required this.messages,
    required this.notifications,
    required this.onMessages,
    required this.onNotifications,
  });

  final AppLocalizations loc;
  final Map<String, dynamic> messages;
  final Map<String, dynamic> notifications;
  final VoidCallback onMessages;
  final VoidCallback onNotifications;

  int _n(Map<String, dynamic> m, String key) => (m[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.reportsLabInbox,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 16),
          _InboxStat(
            label: loc.reportsUnreadMessages,
            value: '${_n(messages, 'unread')}',
            color: _n(messages, 'unread') > 0 ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(height: 10),
          _InboxStat(
            label: loc.reportsThreads,
            value: '${_n(messages, 'threads_with_messages')}',
            color: AppColors.dentalBlue,
          ),
          const SizedBox(height: 10),
          _InboxStat(
            label: loc.reportsUnreadNotifs,
            value: '${_n(notifications, 'unread')}',
            color: _n(notifications, 'unread') > 0
                ? AppColors.review
                : AppColors.success,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onMessages,
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: Text(loc.reportsOpenMessages),
              ),
              OutlinedButton.icon(
                onPressed: onNotifications,
                icon: const Icon(Icons.notifications_none, size: 16),
                label: Text(loc.navNotifications),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InboxStat extends StatelessWidget {
  const _InboxStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.loc,
    required this.rows,
    required this.onPatients,
  });

  final AppLocalizations loc;
  final List<Map<String, dynamic>> rows;
  final VoidCallback onPatients;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.reportsAttention,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.navy,
                  ),
                ),
              ),
              TextButton(
                onPressed: onPatients,
                child: Text(loc.reportsOpenPatients),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                loc.reportsAttentionEmpty,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            )
          else
            ...rows.map((r) {
              final caseId = (r['case_id'] as num?)?.toInt() ?? 0;
              final name = '${r['patient_name'] ?? 'Patient'}';
              final status = CaseStatuses.normalize('${r['status']}');
              final artifacts = <String>[
                if (r['has_scan'] == true) 'Scan',
                if (r['has_shade'] == true) 'Shade',
                if (r['has_shape'] == true) 'Smile',
                if (r['has_scan_body'] == true) 'Body',
              ];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.neo,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.navy,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'CASE-${caseId.toString().padLeft(4, '0')}'
                              '${artifacts.isEmpty ? '' : ' · ${artifacts.join(' · ')}'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusChip(statusKey: status),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _TopPatientsCard extends StatelessWidget {
  const _TopPatientsCard({
    required this.loc,
    required this.rows,
    required this.onPatients,
  });

  final AppLocalizations loc;
  final List<Map<String, dynamic>> rows;
  final VoidCallback onPatients;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.reportsTopPatients,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.navy,
                  ),
                ),
              ),
              Touchable(
                onTap: onPatients,
                child: Text(
                  loc.navPatients,
                  style: const TextStyle(
                    color: AppColors.dentalBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              loc.reportsTopEmpty,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            )
          else
            ...rows.map((r) {
              final name = '${r['name'] ?? ''}';
              final cases = (r['cases'] as num?)?.toInt() ?? 0;
              final insurance = '${r['health_insurance'] ?? ''}'.trim();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    InitialsAvatar(name: name, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy,
                            ),
                          ),
                          if (insurance.isNotEmpty)
                            Text(
                              insurance,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '$cases ${loc.reportsCasesCol.toLowerCase()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.dentalBlue,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ExportsCard extends StatelessWidget {
  const _ExportsCard({
    required this.loc,
    required this.onSummary,
  });

  final AppLocalizations loc;
  final VoidCallback onSummary;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.reportsExports,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  loc.reportsExportsHint,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onSummary,
            icon: const Icon(Icons.description_outlined, size: 18),
            label: Text(loc.reportsSummaryExport),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
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
  bool _loading = false;
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
      final loc = AppLocalizations.of(context);
      final msg = friendlyError(e, loc);
      setState(() {
        _loading = false;
      });
      AppSnackBars.error(context, msg);
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
  Map<String, dynamic> get _byStatus =>
      (_cases['by_status'] as Map<String, dynamic>?) ?? const {};
  List<Map<String, dynamic>> get _attention =>
      ((_summary?['attention'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  int _n(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double? _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  String _avgLabel() {
    final hours = _d(_cases['avg_processing_hours']);
    if (hours == null) return '—';
    if (hours < 24) return '${hours.toStringAsFixed(0)}h';
    return '${(hours / 24).toStringAsFixed(1)}d';
  }

  String _periodLabel(AppLocalizations loc) {
    return switch (_days) {
      7 => loc.reportsPeriod7,
      90 => loc.reportsPeriod90,
      0 => loc.reportsPeriodAll,
      _ => loc.reportsPeriod30,
    };
  }

  String _headerSubtitle(AppLocalizations loc) {
    if (_loading && _summary == null) return loc.reportsLoading;
    final clinic = '${_summary?['clinic_name'] ?? ''}'.trim();
    if (clinic.isEmpty) return _periodLabel(loc);
    return '$clinic · ${_periodLabel(loc)}';
  }

  Future<void> _exportSummary() async {
    final loc = AppLocalizations.of(context);
    final text = _buildSummaryText(loc);
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(loc.reportsSummaryTitle),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            height: 280,
            child: SingleChildScrollView(
              child: Text(
                text,
                style: AppFonts.style(fontSize: 13, height: 1.4),
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
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
    final buf = StringBuffer()
      ..writeln('$clinic — $dentist')
      ..writeln('Period: ${_periodLabel(loc)}')
      ..writeln()
      ..writeln(
        '${loc.reportsPatients}: ${_n(_patientsBlock['total'])} '
        '(${_n(_patientsBlock['new_in_period'])} ${loc.reportsNewInPeriod})',
      )
      ..writeln('${loc.reportsActiveCases}: ${_n(_cases['active'])}')
      ..writeln(
        '${loc.reportsCompleted}: ${_n(_byStatus['completed'])} '
        '(${_n(_cases['completed_in_period'])} ${loc.reportsCompletedInPeriod})',
      )
      ..writeln('${loc.reportsAvgTime}: ${_avgLabel()}')
      ..writeln()
      ..writeln('${loc.reportsPipeline}:');
    for (final s in CaseStatuses.all) {
      buf.writeln('  · ${loc.statusLabel(s)}: ${_n(_byStatus[s])}');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final totalCases = CaseStatuses.all.fold<int>(
      0,
      (sum, s) => sum + _n(_byStatus[s]),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.insights_rounded,
            title: loc.reportsTitle,
            subtitle: _headerSubtitle(loc),
            chromeActions: [
              AppButtons.icon(
                tooltip: loc.refresh,
                onPressed: _loading ? null : _load,
                icon: Icons.refresh_rounded,
              ),
            ],
            actions: [
              AppButtons.secondary(
                onPressed:
                    _loading || _summary == null ? null : _exportSummary,
                icon: Icons.ios_share_rounded,
                label: loc.reportsSummaryExport,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PeriodControl(
            days: _days,
            enabled: !_loading,
            labels: (
              loc.reportsPeriod7,
              loc.reportsPeriod30,
              loc.reportsPeriod90,
              loc.reportsPeriodAll,
            ),
            onChanged: _setPeriod,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: AppSwitcher(
              child: KeyedSubtree(
                key: ValueKey('$_days|$_loading|${_summary != null}'),
                child: _loading && _summary == null
                    ? const ToothPageLoader(message: 'Loading reports…')
                    : LayoutBuilder(
                    builder: (context, constraints) {
                      final landscape = constraints.maxWidth >= 780;
                      final hero = _HeroMetrics(
                        loading: _loading,
                        forceHorizontal: landscape,
                        patients: _n(_patientsBlock['total']),
                        patientsHint:
                            '${_n(_patientsBlock['new_in_period'])} new',
                        active: _n(_cases['active']),
                        completed: _n(_cases['completed_in_period']),
                        completedHint: loc.reportsCompletedInPeriod,
                        avgTime: _avgLabel(),
                      );
                      final pipeline = _PipelineSection(
                        loc: loc,
                        byStatus: _byStatus,
                        total: totalCases,
                        expand: landscape,
                      );
                      final attention = _AttentionSection(
                        loc: loc,
                        rows: _attention,
                        expand: landscape,
                        onOpenPatients: () =>
                            widget.onNavigate(AppNavItem.patients),
                      );

                      // Landscape: full-width KPI strip, then equal-height columns.
                      if (landscape) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            hero,
                            const SizedBox(height: 18),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: pipeline),
                                  const SizedBox(width: 18),
                                  Expanded(child: attention),
                                ],
                              ),
                            ),
                          ],
                        );
                      }

                      return ListView(
                        children: [
                          hero,
                          const SizedBox(height: 18),
                          pipeline,
                          const SizedBox(height: 18),
                          attention,
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PeriodControl extends StatelessWidget {
  const _PeriodControl({
    required this.days,
    required this.enabled,
    required this.labels,
    required this.onChanged,
  });

  final int days;
  final bool enabled;
  final (String, String, String, String) labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = const [7, 30, 90, 0];
    final selected = values.indexOf(days).clamp(0, 3);
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 420,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: selected,
              backgroundColor: AppColors.inset,
              thumbColor: Colors.white,
              children: {
                0: _seg(labels.$1),
                1: _seg(labels.$2),
                2: _seg(labels.$3),
                3: _seg(labels.$4),
              },
              onValueChanged: (index) {
                if (index == null) return;
                onChanged(values[index]);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _seg(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        label,
        style: AppFonts.style(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

class _HeroMetrics extends StatelessWidget {
  const _HeroMetrics({
    required this.loading,
    required this.forceHorizontal,
    required this.patients,
    required this.patientsHint,
    required this.active,
    required this.completed,
    required this.completedHint,
    required this.avgTime,
  });

  final bool loading;
  final bool forceHorizontal;
  final int patients;
  final String patientsHint;
  final int active;
  final int completed;
  final String completedHint;
  final String avgTime;

  @override
  Widget build(BuildContext context) {
    final items = [
      (label: 'Patients', value: '$patients', hint: patientsHint),
      (label: 'Active', value: '$active', hint: 'In pipeline'),
      (label: 'Completed', value: '$completed', hint: completedHint),
      (label: 'Avg. time', value: avgTime, hint: 'To complete'),
    ];

    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      depth: 0.7,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal =
              forceHorizontal || constraints.maxWidth >= 560;
          if (!horizontal) {
            return Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: AppColors.border.withValues(alpha: 0.55),
                    ),
                  _HeroCell(item: items[i], loading: loading, compact: false),
                ],
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppColors.border.withValues(alpha: 0.55),
                    ),
                  Expanded(
                    child: _HeroCell(
                      item: items[i],
                      loading: loading,
                      compact: true,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroCell extends StatelessWidget {
  const _HeroCell({
    required this.item,
    required this.loading,
    required this.compact,
  });

  final ({String label, String value, String hint}) item;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 20,
        vertical: compact ? 18 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label.toUpperCase(),
            style: AppFonts.style(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          Text(
            loading ? '—' : item.value,
            style: AppFonts.style(
              color: AppColors.navy,
              fontSize: compact ? 30 : 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.style(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineSection extends StatelessWidget {
  const _PipelineSection({
    required this.loc,
    required this.byStatus,
    required this.total,
    this.expand = false,
  });

  final AppLocalizations loc;
  final Map<String, dynamic> byStatus;
  final int total;
  final bool expand;

  int _n(String key) {
    final v = byStatus[key];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.reportsPipeline,
          style: AppFonts.style(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          total == 0
              ? loc.reportsNoData
              : '$total ${loc.reportsCasesCol.toLowerCase()}',
          style: AppFonts.style(color: AppColors.muted, fontSize: 14),
        ),
      ],
    );

    final list = Column(
      children: [
        if (total > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final status in CaseStatuses.all)
                    if (_n(status) > 0)
                      Expanded(
                        flex: _n(status),
                        child: Container(
                          color: StatusStyle.of(status).fg,
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        for (final status in CaseStatuses.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: StatusStyle.of(status).fg,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    loc.statusLabel(status),
                    style: AppFonts.style(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Text(
                  '${_n(status)}',
                  style: AppFonts.style(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 22),
        if (expand)
          Expanded(child: SingleChildScrollView(child: list))
        else
          list,
      ],
    );

    final card = SectionCard(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      child: expand ? SizedBox.expand(child: body) : body,
    );
    return expand ? SizedBox.expand(child: card) : card;
  }
}

class _AttentionSection extends StatelessWidget {
  const _AttentionSection({
    required this.loc,
    required this.rows,
    required this.onOpenPatients,
    this.expand = false,
  });

  final AppLocalizations loc;
  final List<Map<String, dynamic>> rows;
  final VoidCallback onOpenPatients;
  final bool expand;

  /// Backend now sends patient UUID strings; older payloads used numeric ids.
  String _caseLabel(dynamic caseId) {
    if (caseId is num) {
      return 'CASE-${caseId.toInt().toString().padLeft(4, '0')}';
    }
    final raw = '$caseId'.trim();
    if (raw.isEmpty || raw == 'null') return 'CASE-—';
    final asInt = int.tryParse(raw);
    if (asInt != null) {
      return 'CASE-${asInt.toString().padLeft(4, '0')}';
    }
    final short = raw.length > 8 ? raw.substring(0, 8) : raw;
    return 'CASE-$short';
  }

  @override
  Widget build(BuildContext context) {
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                loc.reportsAttention,
                style: AppFonts.style(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppColors.navy,
                ),
              ),
            ),
              AppButtons.ghost(
                onPressed: onOpenPatients,
                label: loc.reportsOpenPatients,
                compact: true,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          rows.isEmpty
              ? loc.reportsAttentionEmpty
              : 'Cases that need a follow-up',
          style: AppFonts.style(color: AppColors.muted, fontSize: 14),
        ),
      ],
    );

    final empty = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 40,
            color: AppColors.success.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 12),
          Text(
            'All clear',
            style: AppFonts.style(
              fontWeight: FontWeight.w600,
              fontSize: 17,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );

    final list = Column(
      children: [
        for (final r in rows.take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.neo,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  InitialsAvatar(
                    name: '${r['patient_name'] ?? 'Patient'}',
                    size: 38,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r['patient_name'] ?? 'Patient'}',
                          style: AppFonts.style(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _caseLabel(r['case_id']),
                          style: AppFonts.style(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusChip(
                    statusKey: CaseStatuses.normalize('${r['status']}'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 16),
        if (expand)
          Expanded(child: rows.isEmpty ? empty : SingleChildScrollView(child: list))
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: empty,
          )
        else
          list,
      ],
    );

    final card = SectionCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      child: expand ? SizedBox.expand(child: body) : body,
    );
    return expand ? SizedBox.expand(child: card) : card;
  }
}

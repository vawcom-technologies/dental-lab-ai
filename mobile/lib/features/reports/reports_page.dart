import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/date_formats.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_sidebar.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.api, required this.onNavigate});

  final ApiClient api;
  final ValueChanged<AppNavItem> onNavigate;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _loading = false;
  int _days = 30;
  Map<String, dynamic>? _summary;
  final GlobalKey _shareBtnKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (_loading) return;
    if (!silent) setState(() => _loading = true);
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
      setState(() => _loading = false);
      AppSnackBars.error(context, friendlyError(e, loc));
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
  Map<String, dynamic> get _messages =>
      (_summary?['messages'] as Map<String, dynamic>?) ?? const {};
  List<Map<String, dynamic>> get _throughput =>
      ((_summary?['throughput'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _attention =>
      ((_summary?['attention'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  int _n(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
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

  String _buildSummaryText(AppLocalizations loc) {
    final clinic = '${_summary?['clinic_name'] ?? 'Elite Dent'}';
    final dentist = '${_summary?['dentist_name'] ?? ''}';
    final buf = StringBuffer()
      ..writeln('$clinic — $dentist')
      ..writeln(loc.reportsPeriodLine(_periodLabel(loc)))
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
      ..writeln()
      ..writeln('${loc.reportsPipeline}:');
    for (final s in CaseStatuses.all) {
      buf.writeln('  · ${loc.statusLabel(s)}: ${_n(_byStatus[s])}');
    }
    return buf.toString();
  }

  Rect _safeShareOrigin() {
    final box = _shareBtnKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && !box.size.isEmpty) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    final page = context.findRenderObject() as RenderBox?;
    if (page != null && page.hasSize && !page.size.isEmpty) {
      final center = page.localToGlobal(page.size.center(Offset.zero));
      return Rect.fromCenter(center: center, width: 1, height: 1);
    }
    return const Rect.fromLTWH(0, 0, 1, 1);
  }

  Future<void> _shareToSystem(String text, String subject) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: subject,
          sharePositionOrigin: _safeShareOrigin(),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      AppSnackBars.success(
        context,
        AppLocalizations.of(context).tr('reports.copied'),
      );
    }
  }

  Future<void> _shareSummary() async {
    final loc = AppLocalizations.of(context);
    final text = _buildSummaryText(loc);
    final subject = loc.reportsSummaryTitle;
    await showCupertinoModalPopup<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) {
        return _SharePreviewSheet(
          title: subject,
          body: text,
          hint: loc.tr('reports.shareHint'),
          shareLabel: loc.tr('reports.share'),
          copyLabel: loc.reportsCopy,
          cancelLabel: loc.cancel,
          onShare: () {
            Navigator.pop(ctx);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _shareToSystem(text, subject);
            });
          },
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (!mounted) return;
            AppSnackBars.success(context, loc.tr('reports.copied'));
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final patients = _n(_patientsBlock['total']);
    final newPatients = _n(_patientsBlock['new_in_period']);
    final active = _n(_cases['active']);
    final completedPeriod = _n(_cases['completed_in_period']);
    final statusCounts = {
      for (final s in CaseStatuses.all) s: _n(_byStatus[s]),
    };
    final totalCases = statusCounts.values.fold<int>(0, (a, b) => a + b);

    return Padding(
      padding: AppBreakpoints.pagePadding(
        context,
        landscape: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        portrait: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.insights_rounded,
            title: loc.reportsTitle,
            subtitle: _headerSubtitle(loc),
            actions: [
              _PeriodPills(days: _days, loc: loc, onChanged: _setPeriod),
              KeyedSubtree(
                key: _shareBtnKey,
                child: AppButtons.secondary(
                  onPressed: _loading || _summary == null
                      ? null
                      : _shareSummary,
                  icon: Icons.ios_share_rounded,
                  label: loc.reportsSummaryExport,
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AppSwitcher(
              child: KeyedSubtree(
                key: ValueKey('$_days|$_loading|${_summary != null}'),
                child: _loading && _summary == null
                    ? ToothPageLoader(message: loc.reportsLoading)
                    : _ReportsDashboard(
                        loc: loc,
                        loading: _loading,
                        patients: patients,
                        newPatients: newPatients,
                        active: active,
                        completedPeriod: completedPeriod,
                        avgHours: _d(_cases['avg_processing_hours']),
                        totalCases: totalCases,
                        statusCounts: statusCounts,
                        unread: _n(_messages['unread']),
                        weeks: _throughput,
                        attention: _attention,
                        onOpenPatients: () =>
                            widget.onNavigate(AppNavItem.patients),
                        onOpenMessages: () =>
                            widget.onNavigate(AppNavItem.messages),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsDashboard extends StatelessWidget {
  const _ReportsDashboard({
    required this.loc,
    required this.loading,
    required this.patients,
    required this.newPatients,
    required this.active,
    required this.completedPeriod,
    required this.avgHours,
    required this.totalCases,
    required this.statusCounts,
    required this.unread,
    required this.weeks,
    required this.attention,
    required this.onOpenPatients,
    required this.onOpenMessages,
  });

  final List<Map<String, dynamic>> weeks;
  final AppLocalizations loc;
  final bool loading;
  final int patients;
  final int newPatients;
  final int active;
  final int completedPeriod;
  final double avgHours;
  final int totalCases;
  final Map<String, int> statusCounts;
  final int unread;
  final List<Map<String, dynamic>> attention;
  final VoidCallback onOpenPatients;
  final VoidCallback onOpenMessages;

  int _n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  String _avgLabel() {
    if (avgHours <= 0) return '—';
    if (avgHours < 48) return '${avgHours.round()}h';
    return '${(avgHours / 24).toStringAsFixed(1)}d';
  }

  @override
  Widget build(BuildContext context) {
    final kpis = [
      _KpiSpec(
        icon: Icons.groups_outlined,
        label: loc.reportsPatients,
        value: '$patients',
        hint: loc.reportsNewCount(newPatients),
        pill: newPatients > 0 ? '+$newPatients' : null,
      ),
      _KpiSpec(
        icon: Icons.pending_actions_outlined,
        label: loc.reportsActiveShort,
        value: '$active',
        hint: loc.reportsInPipeline,
      ),
      _KpiSpec(
        icon: Icons.check_circle_outline_rounded,
        label: loc.reportsCompleted,
        value: '$completedPeriod',
        hint: loc.reportsCompletedInPeriod,
      ),
      _KpiSpec(
        icon: Icons.timer_outlined,
        label: loc.reportsAvgTimeShort,
        value: _avgLabel(),
        hint: loc.reportsToComplete,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final wide = w >= 820 && c.maxHeight >= 440;
        final gap = w < 700 ? 8.0 : 12.0;

        final kpiStrip = _KpiStrip(
          items: kpis,
          loading: loading,
          compact: w < 1100 || c.maxHeight < 640,
          twoByTwo: w < 640,
        );

        _AttentionCard attentionCard(bool expand) => _AttentionCard(
          loc: loc,
          rows: attention,
          unread: unread,
          expand: expand,
          onOpenPatients: onOpenPatients,
          onOpenMessages: onOpenMessages,
        );

        _PipelineCard pipeline(bool expand) => _PipelineCard(
          loc: loc,
          statusCounts: statusCounts,
          total: totalCases,
          expand: expand,
        );

        final pts = [
          for (final w in weeks)
            _WeekPt(
              DateTime.tryParse('${w['week_start']}') ?? DateTime.now(),
              _n(w['created']),
              _n(w['completed']),
            ),
        ];

        final intake = _ChartCard(
          title: loc.reportsIntake,
          subtitle: loc.reportsPerWeek,
          total: pts.fold<int>(0, (a, p) => a + p.created),
          emptyText: loc.reportsNoData,
          pts: pts,
          pick: (p) => p.created,
          color: AppColors.dentalBlue,
          bars: false,
        );
        final done = _ChartCard(
          title: loc.reportsCompletedWeekly,
          subtitle: loc.reportsPerWeek,
          total: pts.fold<int>(0, (a, p) => a + p.completed),
          emptyText: loc.reportsNoData,
          pts: pts,
          pick: (p) => p.completed,
          color: AppColors.aiPurple,
          bars: true,
        );

        if (wide) {
          return Column(
            children: [
              kpiStrip,
              SizedBox(height: gap),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: intake),
                    SizedBox(width: gap),
                    Expanded(flex: 2, child: pipeline(true)),
                  ],
                ),
              ),
              SizedBox(height: gap),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 2, child: done),
                    SizedBox(width: gap),
                    Expanded(flex: 3, child: attentionCard(true)),
                  ],
                ),
              ),
            ],
          );
        }

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            kpiStrip,
            SizedBox(height: gap),
            SizedBox(height: 220, child: intake),
            SizedBox(height: gap),
            pipeline(false),
            SizedBox(height: gap),
            SizedBox(height: 220, child: done),
            SizedBox(height: gap),
            attentionCard(false),
          ],
        );
      },
    );
  }
}

class _KpiSpec {
  const _KpiSpec({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    this.pill,
  });

  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final String? pill;
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({
    required this.items,
    required this.loading,
    required this.compact,
    required this.twoByTwo,
  });

  final List<_KpiSpec> items;
  final bool loading;
  final bool compact;
  final bool twoByTwo;

  @override
  Widget build(BuildContext context) {
    Widget card(int i) => _KpiCard(
      spec: items[i],
      loading: loading,
      compact: compact || twoByTwo,
    );

    if (twoByTwo) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: card(0)),
              const SizedBox(width: 8),
              Expanded(child: card(1)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: card(2)),
              const SizedBox(width: 8),
              Expanded(child: card(3)),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: card(i)),
        ],
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.spec,
    required this.loading,
    required this.compact,
  });

  final _KpiSpec spec;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        compact ? 10 : 14,
        compact ? 12 : 16,
        compact ? 10 : 14,
      ),
      depth: 0.4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(spec.icon, size: compact ? 15 : 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  spec.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ),
              if (spec.pill != null && !loading)
                _DeltaPill(text: spec.pill!, positive: true),
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            loading ? '—' : spec.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.style(
              fontSize: compact ? 22 : 28,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              letterSpacing: -0.8,
              height: 1.05,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Text(
              spec.hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.style(
                fontSize: 12,
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.text, required this.positive});

  final String text;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final fg = positive ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: (positive ? AppColors.successSoft : AppColors.dangerSoft),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: AppFonts.style(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _PeriodPills extends StatelessWidget {
  const _PeriodPills({
    required this.days,
    required this.loc,
    required this.onChanged,
  });

  final int days;
  final AppLocalizations loc;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = [
      (7, loc.reportsPeriod7),
      (30, loc.reportsPeriod30),
      (90, loc.reportsPeriod90),
      (0, loc.reportsPeriodAll),
    ];
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: GestureDetector(
                onTap: () => onChanged(item.$1),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: days == item.$1
                        ? AppColors.navy.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.$2,
                    style: AppFonts.style(
                      fontSize: 12,
                      fontWeight: days == item.$1
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: days == item.$1 ? AppColors.navy : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

TextStyle _cardTitle() => AppFonts.style(
  fontWeight: FontWeight.w700,
  fontSize: 15.5,
  color: AppColors.navy,
);

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({
    required this.loc,
    required this.statusCounts,
    required this.total,
    required this.expand,
  });

  final AppLocalizations loc;
  final Map<String, int> statusCounts;
  final int total;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final s in CaseStatuses.all)
        _PipelineRow(
          color: StatusStyle.of(s).fg,
          label: loc.statusLabel(s),
          count: statusCounts[s] ?? 0,
          total: total,
        ),
    ];

    final segs = [
      for (final r in rows)
        if (r.count > 0) r,
    ];

    final body = total == 0
        ? Center(
            child: Text(
              loc.reportsNoData,
              style: AppFonts.style(color: AppColors.muted),
            ),
          )
        : LayoutBuilder(
            builder: (context, c) {
              final ring = Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: _RingPainter(segs: segs, total: total),
                    child: Center(
                      child: Text(
                        '$total',
                        style: AppFonts.style(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  ),
                ),
              );
              final list = Column(
                mainAxisSize: MainAxisSize.min,
                children: rows,
              );
              return c.maxWidth >= 380
                  ? Row(
                      children: [
                        ring,
                        const SizedBox(width: 16),
                        Expanded(child: Center(child: list)),
                      ],
                    )
                  : Column(children: [ring, const SizedBox(height: 8), list]);
            },
          );

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.reportsPipeline, style: _cardTitle()),
          const SizedBox(height: 8),
          if (expand) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.segs, required this.total});
  final List<_PipelineRow> segs;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(arc, 0, math.pi * 2, false, p..color = AppColors.inset);
    var cur = -math.pi / 2;
    for (final s in segs) {
      final sweep = s.count / total * math.pi * 2;
      canvas.drawArc(
        arc,
        cur,
        math.max(sweep - 0.05, 0.01),
        false,
        p..color = s.color,
      );
      cur += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.segs != segs || old.total != total;
}

class _PipelineRow extends StatelessWidget {
  const _PipelineRow({
    required this.color,
    required this.label,
    required this.count,
    required this.total,
  });

  final Color color;
  final String label;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (count / total * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.style(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
          ),
          Text(
            '$count',
            style: AppFonts.style(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: AppFonts.style(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.loc,
    required this.rows,
    required this.unread,
    required this.expand,
    required this.onOpenPatients,
    required this.onOpenMessages,
  });

  final AppLocalizations loc;
  final List<Map<String, dynamic>> rows;
  final int unread;
  final bool expand;
  final VoidCallback onOpenPatients;
  final VoidCallback onOpenMessages;

  @override
  Widget build(BuildContext context) {
    final list = rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                loc.reportsAllClear,
                style: AppFonts.style(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.navy,
                ),
              ),
            ),
          )
        : ListView.separated(
            shrinkWrap: !expand,
            physics: expand ? null : const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = rows[i];
              final updated = DateTime.tryParse('${r['updated_at']}');
              return _AttentionRow(
                name: '${r['patient_name'] ?? loc.reportsPatientFallback}',
                date: updated == null
                    ? null
                    : formatAppDate(context, updated.toLocal(), 'MMM d'),
                status: CaseStatuses.normalize('${r['status']}'),
              );
            },
          );

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 14),
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(loc.reportsAttention, style: _cardTitle())),
              AppButtons.ghost(
                onPressed: onOpenPatients,
                label: loc.reportsOpenPatients,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (expand) Expanded(child: list) else list,
          if (unread > 0) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onOpenMessages,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.dentalBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.mail_outline_rounded,
                      size: 16,
                      color: AppColors.dentalBlue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${loc.reportsUnreadMessages}: $unread',
                        style: AppFonts.style(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.dentalBlue,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.dentalBlue,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.name,
    required this.date,
    required this.status,
  });

  final String name;
  final String? date;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.neo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          InitialsAvatar(name: name, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.navy,
                  ),
                ),
                if (date != null)
                  Text(
                    date!,
                    style: AppFonts.style(fontSize: 12, color: AppColors.muted),
                  ),
              ],
            ),
          ),
          StatusChip(statusKey: status),
        ],
      ),
    );
  }
}

class _WeekPt {
  const _WeekPt(this.start, this.created, this.completed);
  final DateTime start;
  final int created;
  final int completed;
}

class _ChartCard extends StatefulWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.total,
    required this.emptyText,
    required this.pts,
    required this.pick,
    required this.color,
    required this.bars,
  });

  final String title;
  final String subtitle;
  final int total;
  final String emptyText;
  final List<_WeekPt> pts;
  final int Function(_WeekPt) pick;
  final Color color;
  final bool bars;

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final vals = [for (final p in widget.pts) widget.pick(p)];
    final empty = vals.every((v) => v == 0);
    final sel = (_sel ?? vals.length - 1).clamp(
      0,
      math.max(vals.length - 1, 0),
    );
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: _cardTitle()),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${widget.total}',
                style: AppFonts.style(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.subtitle,
                style: AppFonts.style(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: empty
                ? Center(
                    child: Text(
                      widget.emptyText,
                      style: AppFonts.style(color: AppColors.muted),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, c) {
                      void pick(double x) {
                        final n = vals.length;
                        final i = (x / c.maxWidth * n).floor().clamp(0, n - 1);
                        if (i != _sel) setState(() => _sel = i);
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => pick(d.localPosition.dx),
                        onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _SeriesPainter(
                            values: vals,
                            labels: [
                              for (final p in widget.pts)
                                formatAppDate(context, p.start, 'MMM d'),
                            ],
                            selected: sel.toInt(),
                            color: widget.color,
                            bars: widget.bars,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SeriesPainter extends CustomPainter {
  _SeriesPainter({
    required this.values,
    required this.labels,
    required this.selected,
    required this.color,
    required this.bars,
  });

  final List<int> values;
  final List<String> labels;
  final int selected;
  final Color color;
  final bool bars;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width < 20 || size.height < 40) return;
    const bottom = 22.0;
    final chart = Rect.fromLTWH(0, 22, size.width, size.height - bottom - 22);
    final maxV = math.max(values.reduce(math.max), 1);
    final n = values.length;
    final slot = chart.width / n;

    double cx(int i) => bars
        ? chart.left + slot * (i + 0.5)
        : (n == 1 ? chart.center.dx : chart.left + chart.width * i / (n - 1));
    double cy(int v) => chart.bottom - v / maxV * chart.height;

    final grid = Paint()
      ..color = AppColors.border.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var g = 0; g < 3; g++) {
      final y = chart.top + chart.height * g / 2;
      for (var x = 0.0; x < chart.width; x += 9) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 5, chart.width), y),
          grid,
        );
      }
    }

    if (bars) {
      final bw = math.min(slot * 0.58, 34.0);
      for (var i = 0; i < n; i++) {
        final h = math.max(
          values[i] / maxV * chart.height,
          values[i] > 0 ? 3 : 0,
        );
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(cx(i) - bw / 2, chart.bottom - h, bw, h.toDouble()),
          const Radius.circular(6),
        );
        canvas.drawRRect(
          r,
          Paint()..color = color.withValues(alpha: i == selected ? 1 : 0.3),
        );
      }
    } else {
      final pts = [for (var i = 0; i < n; i++) Offset(cx(i), cy(values[i]))];
      final line = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 0; i < n - 1; i++) {
        final m = (pts[i].dx + pts[i + 1].dx) / 2;
        line.cubicTo(
          m,
          pts[i].dy,
          m,
          pts[i + 1].dy,
          pts[i + 1].dx,
          pts[i + 1].dy,
        );
      }
      final fill = Path.from(line)
        ..lineTo(pts.last.dx, chart.bottom)
        ..lineTo(pts.first.dx, chart.bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.02),
            ],
          ).createShader(chart),
      );
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      final s = pts[selected];
      canvas.drawLine(
        Offset(s.dx, chart.top),
        Offset(s.dx, chart.bottom),
        Paint()
          ..color = AppColors.navy.withValues(alpha: 0.15)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(s, 5.5, Paint()..color = Colors.white);
      canvas.drawCircle(s, 3.8, Paint()..color = color);
    }

    // value bubble over the selected point
    final top = bars
        ? Offset(cx(selected), cy(values[selected]))
        : Offset(cx(selected), cy(values[selected]));
    final tp = TextPainter(
      text: TextSpan(
        text: '${values[selected]}',
        style: AppFonts.style(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 16;
    final left = (top.dx - w / 2).clamp(0.0, size.width - w);
    final y = math.max(top.dy - 32, 0.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, y, w, tp.height + 8),
        const Radius.circular(8),
      ),
      Paint()..color = AppColors.navy,
    );
    tp.paint(canvas, Offset(left + 8, y + 4));

    final step = n > 8 ? 2 : 1;
    for (var i = 0; i < n; i += step) {
      final l = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: AppFonts.style(
            fontSize: 10.5,
            color: i == selected ? AppColors.navy : AppColors.muted,
            fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      l.paint(
        canvas,
        Offset(
          (cx(i) - l.width / 2).clamp(0.0, size.width - l.width),
          chart.bottom + 6,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter old) => true;
}

/// Native iOS share-sheet preview: read the clinic summary, then share or copy.
class _SharePreviewSheet extends StatelessWidget {
  const _SharePreviewSheet({
    required this.title,
    required this.body,
    required this.hint,
    required this.shareLabel,
    required this.copyLabel,
    required this.cancelLabel,
    required this.onShare,
    required this.onCopy,
  });

  final String title;
  final String body;
  final String hint;
  final String shareLabel;
  final String copyLabel;
  final String cancelLabel;
  final VoidCallback onShare;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final bg = CupertinoColors.systemGroupedBackground.resolveFrom(context);
    final card = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final size = MediaQuery.sizeOf(context);
    final maxH = size.height * 0.78;
    final sheetW = math.min(520.0, size.width - 20);

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: sheetW, maxHeight: maxH),
          child: SizedBox(
            width: sheetW,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Material(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey3
                              .resolveFrom(context),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: AppFonts.style(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: label,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: Text(
                          hint,
                          textAlign: TextAlign.center,
                          style: AppFonts.style(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: secondary,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: card,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: CupertinoScrollbar(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  16,
                                ),
                                child: SelectableText(
                                  body.trim(),
                                  style: AppFonts.style(
                                    fontSize: 15,
                                    height: 1.45,
                                    fontWeight: FontWeight.w400,
                                    color: label,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1, thickness: 0.5),
                      _IosAction(
                        label: shareLabel,
                        isDefault: true,
                        onPressed: onShare,
                      ),
                      const Divider(height: 1, thickness: 0.5),
                      _IosAction(label: copyLabel, onPressed: onCopy),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: _IosAction(
                  label: cancelLabel,
                  isDefault: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
            ),
        ),
      ),
    );
  }
}

class _IosAction extends StatelessWidget {
  const _IosAction({
    required this.label,
    required this.onPressed,
    this.isDefault = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 16),
      onPressed: onPressed,
      child: SizedBox(
        width: double.infinity,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppFonts.style(
            fontSize: 20,
            fontWeight: isDefault ? FontWeight.w600 : FontWeight.w400,
            color: CupertinoTheme.of(context).primaryColor,
          ),
        ),
      ),
    );
  }
}

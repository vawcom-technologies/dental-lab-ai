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
  Map<String, dynamic> get _clinical =>
      (_summary?['clinical'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get _messages =>
      (_summary?['messages'] as Map<String, dynamic>?) ?? const {};
  List<Map<String, dynamic>> get _attention =>
      ((_summary?['attention'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _throughput =>
      ((_summary?['throughput'] as List?) ?? const [])
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
      ..writeln(
        '${loc.reportsCoverageShort}: ${_d(_clinical['coverage_pct']).round()}%',
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
      builder: (ctx) => CupertinoActionSheet(
        title: Text(subject),
        message: Text(loc.tr('reports.shareHint')),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _shareToSystem(text, subject);
              });
            },
            child: Text(loc.tr('reports.share')),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              AppSnackBars.success(context, loc.tr('reports.copied'));
            },
            child: Text(loc.reportsCopy),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(loc.reportsClose),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final patients = _n(_patientsBlock['total']);
    final newPatients = _n(_patientsBlock['new_in_period']);
    final active = _n(_cases['active']);
    final completedPeriod = _n(_cases['completed_in_period']);
    final createdPeriod = _n(_cases['created_in_period']);
    final coveragePct = _d(_clinical['coverage_pct']);
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
              KeyedSubtree(
                key: _shareBtnKey,
                child: AppButtons.secondary(
                  onPressed:
                      _loading || _summary == null ? null : _shareSummary,
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
                        days: _days,
                        onPeriod: _setPeriod,
                        patients: patients,
                        newPatients: newPatients,
                        active: active,
                        completedPeriod: completedPeriod,
                        createdPeriod: createdPeriod,
                        coveragePct: coveragePct,
                        totalCases: totalCases,
                        statusCounts: statusCounts,
                        clinical: _clinical,
                        messages: _messages,
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
    required this.days,
    required this.onPeriod,
    required this.patients,
    required this.newPatients,
    required this.active,
    required this.completedPeriod,
    required this.createdPeriod,
    required this.coveragePct,
    required this.totalCases,
    required this.statusCounts,
    required this.clinical,
    required this.messages,
    required this.weeks,
    required this.attention,
    required this.onOpenPatients,
    required this.onOpenMessages,
  });

  final AppLocalizations loc;
  final bool loading;
  final int days;
  final ValueChanged<int> onPeriod;
  final int patients;
  final int newPatients;
  final int active;
  final int completedPeriod;
  final int createdPeriod;
  final double coveragePct;
  final int totalCases;
  final Map<String, int> statusCounts;
  final Map<String, dynamic> clinical;
  final Map<String, dynamic> messages;
  final List<Map<String, dynamic>> weeks;
  final List<Map<String, dynamic>> attention;
  final VoidCallback onOpenPatients;
  final VoidCallback onOpenMessages;

  int _n(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
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
        pillPositive: true,
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
        icon: Icons.auto_awesome_outlined,
        label: loc.reportsCoverageShort,
        value: '${coveragePct.round()}%',
        hint: loc.reportsCoverageHint,
        pillPositive: coveragePct >= 50,
      ),
    ];

    final coverageItems = [
      _CoverageItem(
        loc.reportsWithScans,
        _n(clinical['cases_with_scans']),
        patients,
        AppColors.dentalBlue,
      ),
      _CoverageItem(
        loc.reportsWithPhotos,
        _n(clinical['cases_with_photos']),
        patients,
        AppColors.aiPurple,
      ),
      _CoverageItem(
        loc.reportsWithShade,
        _n(clinical['cases_with_shade']),
        patients,
        AppColors.warning,
      ),
      _CoverageItem(
        loc.reportsWithShape,
        _n(clinical['cases_with_shape']),
        patients,
        AppColors.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final wide = w >= 920 && h >= 520;
        final medium = w >= 640;
        final gap = w < 700 ? 8.0 : 12.0;
        final compactKpi = w < 1100 || h < 640;

        final kpiStrip = _KpiStrip(
          items: kpis,
          loading: loading,
          compact: compactKpi,
          twoByTwo: !medium,
        );

        final activity = _ActivityCard(
          loc: loc,
          days: days,
          onPeriod: onPeriod,
          createdPeriod: createdPeriod,
          completedPeriod: completedPeriod,
          weeks: weeks,
        );

        final donut = _PipelineDonutCard(
          loc: loc,
          statusCounts: statusCounts,
          total: totalCases,
        );

        final coverage = _CoverageCard(
          loc: loc,
          pct: coveragePct,
          items: coverageItems,
        );

        final attentionCard = _AttentionCard(
          loc: loc,
          rows: attention,
          unread: _n(messages['unread']),
          onOpenPatients: onOpenPatients,
          onOpenMessages: onOpenMessages,
        );

        if (wide) {
          return Column(
            children: [
              kpiStrip,
              SizedBox(height: gap),
              Expanded(
                flex: 7,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 11, child: activity),
                    SizedBox(width: gap),
                    Expanded(flex: 7, child: donut),
                  ],
                ),
              ),
              SizedBox(height: gap),
              Expanded(
                flex: 5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: coverage),
                    SizedBox(width: gap),
                    Expanded(child: attentionCard),
                  ],
                ),
              ),
            ],
          );
        }

        if (medium) {
          return Column(
            children: [
              kpiStrip,
              SizedBox(height: gap),
              Expanded(flex: 6, child: activity),
              SizedBox(height: gap),
              Expanded(
                flex: 5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: donut),
                    SizedBox(width: gap),
                    Expanded(child: coverage),
                  ],
                ),
              ),
              SizedBox(height: gap),
              Expanded(flex: 4, child: attentionCard),
            ],
          );
        }

        return Column(
          children: [
            kpiStrip,
            SizedBox(height: gap),
            Expanded(flex: 5, child: activity),
            SizedBox(height: gap),
            Expanded(
              flex: 5,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: donut),
                  SizedBox(width: gap),
                  Expanded(child: coverage),
                ],
              ),
            ),
            SizedBox(height: gap),
            Expanded(flex: 4, child: attentionCard),
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
    this.pillPositive = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final String? pill;
  final bool pillPositive;
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
                _DeltaPill(text: spec.pill!, positive: spec.pillPositive),
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

class _ActivityCard extends StatefulWidget {
  const _ActivityCard({
    required this.loc,
    required this.days,
    required this.onPeriod,
    required this.createdPeriod,
    required this.completedPeriod,
    required this.weeks,
  });

  final AppLocalizations loc;
  final int days;
  final ValueChanged<int> onPeriod;
  final int createdPeriod;
  final int completedPeriod;
  final List<Map<String, dynamic>> weeks;

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> {
  int? _hover;

  List<_WeekPt> get _points {
    return [
      for (final w in widget.weeks)
        _WeekPt(
          start: DateTime.tryParse('${w['week_start']}') ?? DateTime.now(),
          created: _toInt(w['created']),
          completed: _toInt(w['completed']),
        ),
    ];
  }

  int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    final pts = _points;
    final selected = (_hover != null && _hover! < pts.length)
        ? pts[_hover!]
        : (pts.isEmpty ? null : pts.last);

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.reportsActivity,
                      style: AppFonts.style(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loc.reportsActivityHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _PeriodPills(days: widget.days, loc: loc, onChanged: widget.onPeriod),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${widget.createdPeriod + widget.completedPeriod}',
                style: AppFonts.style(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                  letterSpacing: -0.6,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              _LegendDot(color: AppColors.dentalBlue, label: loc.reportsOpened),
              const SizedBox(width: 12),
              _LegendDot(color: AppColors.aiPurple, label: loc.reportsFinished),
              const Spacer(),
              if (selected != null)
                Text(
                  formatAppDate(context, selected.start, 'MMM d'),
                  style: AppFonts.style(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: pts.every((p) => p.created == 0 && p.completed == 0)
                ? Center(
                    child: Text(
                      loc.reportsNoData,
                      style: AppFonts.style(color: AppColors.muted),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, c) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => _pick(d.localPosition.dx, c.maxWidth, pts.length),
                        onHorizontalDragUpdate: (d) =>
                            _pick(d.localPosition.dx, c.maxWidth, pts.length),
                        child: CustomPaint(
                          painter: _AreaChartPainter(
                            points: pts,
                            labels: [
                              for (final p in pts)
                                formatAppDate(context, p.start, 'MMM d'),
                            ],
                            selected: _hover ?? (pts.length - 1),
                            opened: loc.reportsOpened,
                            finished: loc.reportsFinished,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _pick(double x, double width, int n) {
    if (n <= 0 || width <= 0) return;
    final i = ((x / width) * n).floor().clamp(0, n - 1);
    if (i != _hover) setState(() => _hover = i);
  }
}

class _WeekPt {
  const _WeekPt({
    required this.start,
    required this.created,
    required this.completed,
  });

  final DateTime start;
  final int created;
  final int completed;
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                      fontWeight:
                          days == item.$1 ? FontWeight.w700 : FontWeight.w500,
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
        const SizedBox(width: 5),
        Text(
          label,
          style: AppFonts.style(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}

class _AreaChartPainter extends CustomPainter {
  _AreaChartPainter({
    required this.points,
    required this.labels,
    required this.selected,
    required this.opened,
    required this.finished,
  });

  final List<_WeekPt> points;
  final List<String> labels;
  final int selected;
  final String opened;
  final String finished;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width < 8 || size.height < 24) return;
    const bottom = 22.0;
    final chart = Rect.fromLTWH(0, 8, size.width, size.height - bottom - 8);
    if (chart.height <= 0) return;

    final maxVal = points
        .map((p) => math.max(p.created, p.completed))
        .fold<int>(0, math.max)
        .clamp(1, 999999);

    Offset pt(int i, int v) {
      final t = points.length == 1 ? 0.5 : i / (points.length - 1);
      final x = chart.left + t * chart.width;
      final y = chart.bottom - (v / maxVal) * chart.height;
      return Offset(x, y);
    }

    // Grid
    final grid = Paint()
      ..color = AppColors.border.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    for (var g = 0; g < 3; g++) {
      final y = chart.top + chart.height * (g / 2);
      _dashLine(canvas, Offset(chart.left, y), Offset(chart.right, y), grid);
    }

    final openedPts = [for (var i = 0; i < points.length; i++) pt(i, points[i].created)];
    final finishedPts = [
      for (var i = 0; i < points.length; i++) pt(i, points[i].completed)
    ];

    _fillSeries(canvas, chart, openedPts, AppColors.dentalBlue);
    _fillSeries(canvas, chart, finishedPts, AppColors.aiPurple);
    _strokeSeries(canvas, openedPts, AppColors.dentalBlue);
    _strokeSeries(canvas, finishedPts, AppColors.aiPurple);

    final sel = selected.clamp(0, points.length - 1);
    final sx = pt(sel, 0).dx;
    canvas.drawLine(
      Offset(sx, chart.top),
      Offset(sx, chart.bottom),
      Paint()
        ..color = AppColors.navy.withValues(alpha: 0.18)
        ..strokeWidth = 1.2,
    );

    _dot(canvas, pt(sel, points[sel].created), AppColors.dentalBlue);
    _dot(canvas, pt(sel, points[sel].completed), AppColors.aiPurple);

    _tooltip(
      canvas,
      size,
      Offset(sx, chart.top + 4),
      '${points[sel].created}  ·  ${points[sel].completed}',
    );

    final step = points.length > 8 ? 2 : 1;
    for (var i = 0; i < points.length; i += step) {
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: AppFonts.style(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: AppColors.muted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = pt(i, 0).dx - tp.width / 2;
      tp.paint(canvas, Offset(x.clamp(0, size.width - tp.width), chart.bottom + 6));
    }
  }

  void _fillSeries(Canvas canvas, Rect chart, List<Offset> pts, Color color) {
    if (pts.isEmpty) return;
    final line = _smooth(pts);
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
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(chart),
    );
  }

  void _strokeSeries(Canvas canvas, List<Offset> pts, Color color) {
    if (pts.isEmpty) return;
    canvas.drawPath(
      _smooth(pts),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  Path _smooth(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 1) return path;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final cx = (a.dx + b.dx) / 2;
      path.cubicTo(cx, a.dy, cx, b.dy, b.dx, b.dy);
    }
    return path;
  }

  void _dot(Canvas canvas, Offset o, Color color) {
    canvas.drawCircle(o, 5, Paint()..color = Colors.white);
    canvas.drawCircle(o, 3.6, Paint()..color = color);
  }

  void _tooltip(Canvas canvas, Size size, Offset at, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppFonts.style(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const pad = EdgeInsets.symmetric(horizontal: 8, vertical: 5);
    final w = tp.width + pad.horizontal;
    final h = tp.height + pad.vertical;
    var left = at.dx - w / 2;
    left = left.clamp(0.0, size.width - w);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, at.dy, w, h),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = AppColors.navy);
    tp.paint(canvas, Offset(left + pad.left, at.dy + pad.top));
  }

  void _dashLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      final x2 = math.min(x + dash, b.dx);
      canvas.drawLine(Offset(x, a.dy), Offset(x2, a.dy), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _AreaChartPainter old) =>
      old.points != points || old.selected != selected || old.labels != labels;
}

class _PipelineDonutCard extends StatelessWidget {
  const _PipelineDonutCard({
    required this.loc,
    required this.statusCounts,
    required this.total,
  });

  final AppLocalizations loc;
  final Map<String, int> statusCounts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final segs = [
      for (final s in CaseStatuses.all)
        if ((statusCounts[s] ?? 0) > 0)
          _DonutSeg(StatusStyle.of(s).fg, statusCounts[s]!, loc.statusLabel(s)),
    ];

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.reportsPipeline,
            style: AppFonts.style(
              fontWeight: FontWeight.w700,
              fontSize: 15.5,
              color: AppColors.navy,
            ),
          ),
          Expanded(
            child: total == 0
                ? Center(
                    child: Text(
                      loc.reportsNoData,
                      style: AppFonts.style(color: AppColors.muted),
                    ),
                  )
                : CustomPaint(
                    painter: _SemiDonutPainter(segments: segs, total: total),
                    child: const SizedBox.expand(),
                  ),
          ),
          if (segs.isNotEmpty)
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                for (final s in segs)
                  _LegendChip(
                    color: s.color,
                    label: s.label,
                    value: '${((s.value / total) * 100).round()}%',
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DonutSeg {
  const _DonutSeg(this.color, this.value, this.label);
  final Color color;
  final int value;
  final String label;
}

class _SemiDonutPainter extends CustomPainter {
  _SemiDonutPainter({required this.segments, required this.total});

  final List<_DonutSeg> segments;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || segments.isEmpty) return;
    final side = math.min(size.width, size.height * 1.35);
    final stroke = side * 0.16;
    final center = Offset(size.width / 2, size.height * 0.58);
    final radius = side / 2 - stroke / 2 - 4;
    if (radius < 18) return;
    final rect = Rect.fromCircle(center: center, radius: radius);

    const start = math.pi * 0.78;
    const sweep = math.pi * 1.44;

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = AppColors.inset,
    );

    var cursor = start;
    for (final seg in segments) {
      final s = (seg.value / total) * sweep;
      canvas.drawArc(
        rect,
        cursor,
        math.max(s - 0.02, 0.01),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = seg.color,
      );
      cursor += s;
    }

    final value = TextPainter(
      text: TextSpan(
        text: '$total',
        style: AppFonts.style(
          fontSize: radius * 0.42,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    value.paint(
      canvas,
      center - Offset(value.width / 2, value.height * 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _SemiDonutPainter old) =>
      old.segments != segments || old.total != total;
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppFonts.style(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
            Text(
              value,
              style: AppFonts.style(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CoverageItem {
  const _CoverageItem(this.label, this.count, this.total, this.color);
  final String label;
  final int count;
  final int total;
  final Color color;
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({
    required this.loc,
    required this.pct,
    required this.items,
  });

  final AppLocalizations loc;
  final double pct;
  final List<_CoverageItem> items;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.reportsClinical,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                    color: AppColors.navy,
                  ),
                ),
              ),
              Text(
                '${pct.round()}%',
                style: AppFonts.style(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            loc.reportsCoverageHint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.style(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Expanded(child: _CoverageBar(item: items[i])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverageBar extends StatelessWidget {
  const _CoverageBar({required this.item});

  final _CoverageItem item;

  @override
  Widget build(BuildContext context) {
    final t = item.total <= 0 ? 0.0 : (item.count / item.total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.style(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
            ),
            Text(
              '${item.count}',
              style: AppFonts.style(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: item.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 10,
                width: double.infinity,
                child: Stack(
                  children: [
                    const ColoredBox(
                      color: AppColors.inset,
                      child: SizedBox.expand(),
                    ),
                    FractionallySizedBox(
                      widthFactor: t,
                      child: ColoredBox(color: item.color.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ),
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
    required this.unread,
    required this.onOpenPatients,
    required this.onOpenMessages,
  });

  final AppLocalizations loc;
  final List<Map<String, dynamic>> rows;
  final int unread;
  final VoidCallback onOpenPatients;
  final VoidCallback onOpenMessages;

  String _caseLabel(dynamic caseId) {
    if (caseId is num) {
      return 'CASE-${caseId.toInt().toString().padLeft(4, '0')}';
    }
    final raw = '$caseId'.trim();
    if (raw.isEmpty || raw == 'null') return 'CASE-—';
    final asInt = int.tryParse(raw);
    if (asInt != null) return 'CASE-${asInt.toString().padLeft(4, '0')}';
    final short = raw.length > 8 ? raw.substring(0, 8) : raw;
    return 'CASE-$short';
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.reportsAttention,
                  style: AppFonts.style(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
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
          const SizedBox(height: 8),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      loc.reportsAllClear,
                      style: AppFonts.style(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.navy,
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, c) {
                      final cols = c.maxWidth >= 560 ? 2 : 1;
                      const rowH = 52.0;
                      const gap = 8.0;
                      final maxRows = math.max(
                        1,
                        ((c.maxHeight + gap) / (rowH + gap)).floor(),
                      );
                      final visible =
                          rows.take(cols * maxRows).toList(growable: false);
                      return GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisExtent: rowH,
                          crossAxisSpacing: gap,
                          mainAxisSpacing: gap,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final r = visible[i];
                          return _AttentionRow(
                            name:
                                '${r['patient_name'] ?? loc.reportsPatientFallback}',
                            caseLabel: _caseLabel(r['case_id']),
                            status: CaseStatuses.normalize('${r['status']}'),
                          );
                        },
                      );
                    },
                  ),
          ),
          if (unread > 0) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onOpenMessages,
              child: Text(
                '${loc.reportsUnreadMessages}: $unread',
                style: AppFonts.style(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.dentalBlue,
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
    required this.caseLabel,
    required this.status,
  });

  final String name;
  final String caseLabel;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.neo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          InitialsAvatar(name: name, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.navy,
                  ),
                ),
                Text(
                  caseLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(fontSize: 11, color: AppColors.muted),
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

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
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

  Rect? _shareOrigin() {
    final box = _shareBtnKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _load({bool silent = false}) async {
    if (_loading) return;
    if (!silent) {
      setState(() => _loading = true);
    }
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
      setState(() => _loading = false);
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
    final fromBtn = _shareOrigin();
    if (fromBtn != null && fromBtn.width > 0 && fromBtn.height > 0) {
      return fromBtn;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && !box.size.isEmpty) {
      final center = box.localToGlobal(box.size.center(Offset.zero));
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
      final loc = AppLocalizations.of(context);
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      AppSnackBars.success(context, loc.tr('reports.copied'));
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
              // Defer until the sheet is gone so the iPad popover can present.
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
    final totalCases = CaseStatuses.all.fold<int>(
      0,
      (sum, s) => sum + _n(_byStatus[s]),
    );
    final patients = _n(_patientsBlock['total']);
    final newPatients = _n(_patientsBlock['new_in_period']);
    final active = _n(_cases['active']);
    final completedPeriod = _n(_cases['completed_in_period']);
    final createdPeriod = _n(_cases['created_in_period']);

    final statusCounts = {
      for (final s in CaseStatuses.all) s: _n(_byStatus[s]),
    };

    return Padding(
      padding: AppBreakpoints.pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            icon: Icons.insights_rounded,
            title: loc.reportsTitle,
            subtitle: _headerSubtitle(loc),
            chromeActions: [
              IconButton(
                tooltip: loc.refresh,
                onPressed: _loading ? null : () => _load(silent: true),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
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
          const SizedBox(height: 10),
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
          const SizedBox(height: 12),
          Expanded(
            child: AppSwitcher(
              child: KeyedSubtree(
                key: ValueKey('$_days|$_loading|${_summary != null}'),
                child: _loading && _summary == null
                    ? ToothPageLoader(message: loc.reportsLoading)
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 860;
                          final tall = constraints.maxHeight >= 520;
                          return _DashboardBody(
                            wide: wide,
                            tall: tall,
                            loading: _loading,
                            loc: loc,
                            patients: patients,
                            newPatients: newPatients,
                            active: active,
                            completedPeriod: completedPeriod,
                            createdPeriod: createdPeriod,
                            totalCases: totalCases,
                            statusCounts: statusCounts,
                            attention: _attention,
                            onOpenPatients: () =>
                                widget.onNavigate(AppNavItem.patients),
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

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.wide,
    required this.tall,
    required this.loading,
    required this.loc,
    required this.patients,
    required this.newPatients,
    required this.active,
    required this.completedPeriod,
    required this.createdPeriod,
    required this.totalCases,
    required this.statusCounts,
    required this.attention,
    required this.onOpenPatients,
  });

  final bool wide;
  final bool tall;
  final bool loading;
  final AppLocalizations loc;
  final int patients;
  final int newPatients;
  final int active;
  final int completedPeriod;
  final int createdPeriod;
  final int totalCases;
  final Map<String, int> statusCounts;
  final List<Map<String, dynamic>> attention;
  final VoidCallback onOpenPatients;

  @override
  Widget build(BuildContext context) {
    final kpis = _KpiStrip(
      loading: loading,
      items: [
        _KpiData(
          icon: Icons.groups_rounded,
          label: loc.reportsPatients,
          value: '$patients',
          hint: loc.reportsNewCount(newPatients),
          tint: AppColors.dentalBlue,
          soft: const Color(0xFFEAF3FC),
          delta: newPatients > 0 ? '+$newPatients' : null,
          deltaPositive: true,
        ),
        _KpiData(
          icon: Icons.pending_actions_rounded,
          label: loc.reportsActiveShort,
          value: '$active',
          hint: loc.reportsInPipeline,
          tint: AppColors.warning,
          soft: AppColors.warningSoft,
        ),
        _KpiData(
          icon: Icons.add_circle_outline_rounded,
          label: loc.reportsCreated,
          value: '$createdPeriod',
          hint: loc.reportsCreatedInPeriod,
          tint: AppColors.aiPurple,
          soft: AppColors.aiPurpleSoft,
        ),
        _KpiData(
          icon: Icons.check_circle_rounded,
          label: loc.reportsCompleted,
          value: '$completedPeriod',
          hint: loc.reportsCompletedInPeriod,
          tint: AppColors.success,
          soft: AppColors.successSoft,
        ),
      ],
    );

    final bars = _PipelineBarsCard(
      loc: loc,
      statusCounts: statusCounts,
      total: totalCases,
      createdPeriod: createdPeriod,
      completedPeriod: completedPeriod,
    );

    final donut = _PipelineDonutCard(
      loc: loc,
      statusCounts: statusCounts,
      total: totalCases,
    );

    final attentionCard = _AttentionCard(
      loc: loc,
      rows: attention,
      onOpenPatients: onOpenPatients,
    );

    if (wide) {
      return Column(
        children: [
          kpis,
          SizedBox(height: tall ? 14 : 10),
          Expanded(
            flex: 11,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 7, child: bars),
                const SizedBox(width: 12),
                Expanded(flex: 5, child: donut),
              ],
            ),
          ),
          SizedBox(height: tall ? 14 : 10),
          Expanded(flex: 9, child: attentionCard),
        ],
      );
    }

    return Column(
      children: [
        kpis,
        const SizedBox(height: 10),
        Expanded(
          flex: 5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: bars),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: donut),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(flex: 4, child: attentionCard),
      ],
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
        width: AppBreakpoints.isPhone(context) ? double.infinity : 400,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Text(
        label,
        style: AppFonts.style(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

class _KpiData {
  const _KpiData({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.tint,
    required this.soft,
    this.delta,
    this.deltaPositive = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final Color tint;
  final Color soft;
  final String? delta;
  final bool deltaPositive;
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.items, required this.loading});

  final List<_KpiData> items;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _KpiCard(
              data: items[i],
              loading: loading,
              compact: MediaQuery.sizeOf(context).width < 900,
            ),
          ),
        ],
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.data,
    required this.loading,
    this.compact = false,
  });

  final _KpiData data;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 34.0 : 40.0;
    return SectionCard(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        compact ? 10 : 12,
        compact ? 10 : 14,
        compact ? 10 : 12,
      ),
      depth: 0.45,
      child: Row(
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: data.soft,
              borderRadius: BorderRadius.circular(compact ? 10 : 12),
            ),
            child: Icon(data.icon, size: compact ? 17 : 20, color: data.tint),
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        loading ? '—' : data.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(
                          fontSize: compact ? 18 : 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                          letterSpacing: -0.6,
                          height: 1.05,
                        ),
                      ),
                    ),
                    if (data.delta != null && !loading) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: data.deltaPositive
                              ? AppColors.successSoft
                              : AppColors.dangerSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          data.delta!,
                          style: AppFonts.style(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: data.deltaPositive
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (!compact)
                  Text(
                    data.hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.style(
                      fontSize: 11.5,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineBarsCard extends StatelessWidget {
  const _PipelineBarsCard({
    required this.loc,
    required this.statusCounts,
    required this.total,
    required this.createdPeriod,
    required this.completedPeriod,
  });

  final AppLocalizations loc;
  final Map<String, int> statusCounts;
  final int total;
  final int createdPeriod;
  final int completedPeriod;

  @override
  Widget build(BuildContext context) {
    final maxVal = statusCounts.values.fold<int>(0, math.max).clamp(1, 999999);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
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
                      loc.reportsPipeline,
                      style: AppFonts.style(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total == 0
                          ? loc.reportsNoData
                          : '$total ${loc.reportsCasesCol.toLowerCase()}',
                      style: AppFonts.style(
                        color: AppColors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              _MiniStat(
                label: loc.reportsCreated,
                value: '$createdPeriod',
                color: AppColors.aiPurple,
              ),
              const SizedBox(width: 10),
              _MiniStat(
                label: loc.reportsCompleted,
                value: '$completedPeriod',
                color: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: total == 0
                ? Center(
                    child: Text(
                      loc.reportsNoData,
                      style: AppFonts.style(color: AppColors.muted),
                    ),
                  )
                : CustomPaint(
                    painter: _StatusBarsPainter(
                      statuses: CaseStatuses.all,
                      counts: statusCounts,
                      maxVal: maxVal,
                      labels: {
                        for (final s in CaseStatuses.all) s: loc.statusLabel(s),
                      },
                    ),
                    child: const SizedBox.expand(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppFonts.style(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          Text(
            value,
            style: AppFonts.style(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBarsPainter extends CustomPainter {
  _StatusBarsPainter({
    required this.statuses,
    required this.counts,
    required this.maxVal,
    required this.labels,
  });

  final List<String> statuses;
  final Map<String, int> counts;
  final int maxVal;
  final Map<String, String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    if (statuses.isEmpty || size.width <= 0 || size.height <= 0) return;

    const labelH = 28.0;
    const valueH = 18.0;
    final chartH = size.height - labelH - valueH;
    if (chartH < 24) return;

    final n = statuses.length;
    final gap = size.width * 0.04;
    final barW = (size.width - gap * (n - 1)) / n;
    final radius = Radius.circular(math.min(12, barW / 2));

    for (var i = 0; i < n; i++) {
      final status = statuses[i];
      final count = counts[status] ?? 0;
      final style = StatusStyle.of(status);
      final x = i * (barW + gap);
      final h = chartH * (count / maxVal);
      final barH = h.clamp(4.0, chartH);
      final barTop = valueH + chartH - barH;

      final track = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, valueH, barW, chartH),
        topLeft: radius,
        topRight: radius,
      );
      canvas.drawRRect(
        track,
        Paint()..color = style.bg.withValues(alpha: 0.7),
      );

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, barTop, barW, barH),
        topLeft: radius,
        topRight: radius,
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            style.fg,
            style.fg.withValues(alpha: 0.55),
          ],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);

      final valueTp = TextPainter(
        text: TextSpan(
          text: '$count',
          style: AppFonts.style(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barW + 8);
      valueTp.paint(
        canvas,
        Offset(
          x + (barW - valueTp.width) / 2,
          barTop - valueTp.height - 2,
        ),
      );

      final raw = labels[status] ?? status;
      final short = raw.length > 10 ? '${raw.substring(0, 9)}…' : raw;
      final labelTp = TextPainter(
        text: TextSpan(
          text: short,
          style: AppFonts.style(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: barW + 6);
      labelTp.paint(
        canvas,
        Offset(
          x + (barW - labelTp.width) / 2,
          valueH + chartH + 8,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StatusBarsPainter old) =>
      old.counts != counts || old.maxVal != maxVal || old.labels != labels;
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
    final segments = [
      for (final s in CaseStatuses.all)
        if ((statusCounts[s] ?? 0) > 0)
          _DonutSeg(
            color: StatusStyle.of(s).fg,
            soft: StatusStyle.of(s).bg,
            value: statusCounts[s]!,
            label: loc.statusLabel(s),
          ),
    ];

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.reportsCasesCol,
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
                : LayoutBuilder(
                    builder: (context, c) {
                      final side = math.min(c.maxWidth, c.maxHeight);
                      return Center(
                        child: SizedBox(
                          width: side,
                          height: side,
                          child: CustomPaint(
                            painter: _DonutPainter(
                              segments: segments,
                              total: total,
                              centerLabel: '$total',
                              centerHint: loc.reportsCasesCol,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (segments.isNotEmpty)
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                for (final seg in segments)
                  _LegendChip(
                    color: seg.color,
                    label: seg.label,
                    value:
                        '${seg.value} · ${((seg.value / total) * 100).round()}%',
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DonutSeg {
  const _DonutSeg({
    required this.color,
    required this.soft,
    required this.value,
    required this.label,
  });

  final Color color;
  final Color soft;
  final int value;
  final String label;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.total,
    required this.centerLabel,
    required this.centerHint,
  });

  final List<_DonutSeg> segments;
  final int total;
  final String centerLabel;
  final String centerHint;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || segments.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final stroke = radius * 0.28;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    // Track
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.inset
        ..strokeCap = StrokeCap.butt,
    );

    var start = -math.pi / 2;
    for (final seg in segments) {
      final sweep = (seg.value / total) * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep * 0.992,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = seg.color
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }

    final valueTp = TextPainter(
      text: TextSpan(
        text: centerLabel,
        style: AppFonts.style(
          fontSize: radius * 0.42,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final hintTp = TextPainter(
      text: TextSpan(
        text: centerHint,
        style: AppFonts.style(
          fontSize: math.max(10, radius * 0.14),
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: radius * 1.2);

    valueTp.paint(
      canvas,
      center - Offset(valueTp.width / 2, valueTp.height * 0.7),
    );
    hintTp.paint(
      canvas,
      center + Offset(-hintTp.width / 2, valueTp.height * 0.15),
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
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
          height: 22,
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
                fontSize: 12,
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

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.loc,
    required this.rows,
    required this.onOpenPatients,
  });

  final AppLocalizations loc;
  final List<Map<String, dynamic>> rows;
  final VoidCallback onOpenPatients;

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
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
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
                      loc.reportsAttention,
                      style: AppFonts.style(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      rows.isEmpty
                          ? loc.reportsAttentionEmpty
                          : loc.reportsFollowUpHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(
                        color: AppColors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 36,
                          color: AppColors.success.withValues(alpha: 0.85),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          loc.reportsAllClear,
                          style: AppFonts.style(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, c) {
                      const gap = 8.0;
                      final cols = c.maxWidth >= 900
                          ? 3
                          : (c.maxWidth >= 520 ? 2 : 1);
                      // Fit as many rows as height allows (~52pt each).
                      final maxRows = math.max(
                        1,
                        ((c.maxHeight + gap) / (52.0 + gap)).floor(),
                      );
                      final visible =
                          rows.take(cols * maxRows).toList(growable: false);
                      final lineCount =
                          math.max(1, (visible.length / cols).ceil());

                      return Column(
                        children: [
                          for (var r = 0; r < lineCount; r++) ...[
                            if (r > 0) const SizedBox(height: gap),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = r * cols;
                                      i < visible.length && i < (r + 1) * cols;
                                      i++) ...[
                                    if (i > r * cols) const SizedBox(width: gap),
                                    Expanded(
                                      child: _AttentionRow(
                                        name:
                                            '${visible[i]['patient_name'] ?? loc.reportsPatientFallback}',
                                        caseLabel: _caseLabel(
                                          visible[i]['case_id'],
                                        ),
                                        status: CaseStatuses.normalize(
                                          '${visible[i]['status']}',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.neo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          InitialsAvatar(name: name, size: 32),
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
                    fontSize: 13.5,
                    color: AppColors.navy,
                  ),
                ),
                Text(
                  caseLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                    fontSize: 11,
                    color: AppColors.muted,
                  ),
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

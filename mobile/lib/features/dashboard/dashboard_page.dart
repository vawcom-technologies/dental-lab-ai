import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_sidebar.dart';
import '../admin/admin_top_bar.dart';
import '../appointments/models/appointment.dart';
import '../chat/widgets/quick_chat_card.dart';

typedef _Data = (
  List<Map<String, dynamic>> patients,
  List<Appointment> today,
);

String _patientName(Map<String, dynamic> p) =>
    '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();

String _statusOf(Map<String, dynamic> p) =>
    CaseStatuses.normalize('${p['status'] ?? ''}');

bool _needsAttention(Map<String, dynamic> p) {
  final s = _statusOf(p);
  return s == CaseStatuses.pending ||
      s == CaseStatuses.inProgress ||
      s == CaseStatuses.inReview ||
      s == CaseStatuses.rejected;
}

DateTime? _updatedAt(Map<String, dynamic> p) =>
    DateTime.tryParse('${p['updated_at'] ?? p['created_at'] ?? ''}');

bool _isToday(DateTime dt) {
  final n = DateTime.now();
  final local = dt.isUtc ? dt.toLocal() : dt;
  return local.year == n.year && local.month == n.month && local.day == n.day;
}

/// Dentist home in the admin/lab dashboard look: chairside KPIs, quick
/// tools, cases that need attention, recent patients and quick chat.
/// Fits one iPad screen; scrolls on a phone.
class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.api,
    required this.onOpen,
    this.active = true,
  });

  final ApiClient api;
  final void Function(AppNavItem page, int tab) onOpen;
  final bool active;

  static const _gap = 16.0;
  static const _tileH = 128.0;

  Future<_Data> _load() async {
    final r = await Future.wait<Object>([
      api.listPatients(forceRefresh: true),
      api.listAppointments(upcomingOnly: true, forceRefresh: true),
    ]);
    final patients = r[0] as List<Map<String, dynamic>>;
    final appts = (r[1] as List<Appointment>)
        .where(
          (a) =>
              a.status == AppointmentStatuses.scheduled &&
              _isToday(a.startTime),
        )
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return (patients, appts);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final phone = AppBreakpoints.isPhone(context);
    return Padding(
      padding: AppBreakpoints.pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) => Row(
              children: [
                const PhoneMenuButton(),
                Expanded(
                  child: AdminSearchLauncher(
                    hint: loc.tr('dash.searchHint'),
                    page: (chrome) => _DentistSearchPage(chrome: chrome),
                  ),
                ),
                if (c.maxWidth >= 720) ...[
                  const SizedBox(width: 12),
                  const AdminDateChip(),
                ],
                SizedBox(width: phone ? 8 : 12),
                const AdminTopActions(),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: AdminFuture<_Data>(
              active: active,
              load: _load,
              isEmpty: (_) => false,
              empty: const SizedBox.shrink(),
              bottomPadding: phone ? 24 : 0,
              builder: (context, d, reload) => phone
                  ? [
                      SliverToBoxAdapter(
                        child: _greeting(loc, compact: false),
                      ),
                      SliverToBoxAdapter(child: _narrow(context, loc, d)),
                    ]
                  : [
                      SliverLayoutBuilder(
                        builder: (context, sc) => SliverToBoxAdapter(
                          child: SizedBox(
                            height: sc.viewportMainAxisExtent,
                            child: LayoutBuilder(
                              builder: (context, c) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _greeting(
                                    loc,
                                    compact: c.maxHeight < 820,
                                  ),
                                  Expanded(
                                    child: _fit(
                                      context,
                                      loc,
                                      d,
                                      landscape: c.maxWidth > c.maxHeight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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

  Widget _greeting(AppLocalizations loc, {required bool compact}) {
    final h = DateTime.now().hour;
    final name = (api.userName ?? '').trim().split(' ').first;
    final title = h < 12
        ? loc.goodMorning(name.isEmpty ? loc.roleDentist : name)
        : (h < 17
            ? loc.goodAfternoon(name.isEmpty ? loc.roleDentist : name)
            : loc.goodEvening(name.isEmpty ? loc.roleDentist : name));
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 12 : 16, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.style(
              fontSize: compact ? 21 : 24,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              letterSpacing: -0.5,
            ),
          ),
          if (!compact)
            Text(
              loc.tr('dash.sub'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.style(fontSize: 14, color: AppColors.muted),
            ),
        ],
      ),
    );
  }

  Widget _row(List<Widget> cells) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, w) in cells.indexed) ...[
            if (i > 0) const SizedBox(width: _gap),
            Expanded(child: w),
          ],
        ],
      );

  Widget _fit(
    BuildContext context,
    AppLocalizations loc,
    _Data d, {
    required bool landscape,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final tileH = (c.maxHeight * 0.15).clamp(112.0, 128.0);
        return Column(
          children: [
            SizedBox(
              height: tileH,
              child: _tiles(context, loc, d, cols: 4, height: tileH),
            ),
            const SizedBox(height: _gap),
            Expanded(
              flex: landscape ? 6 : 5,
              child: _row([
                AdminAppear(index: 4, child: _quickActions(loc)),
                AdminAppear(index: 5, child: _attention(context, loc, d.$1)),
              ]),
            ),
            const SizedBox(height: _gap),
            Expanded(
              flex: 5,
              child: _row([
                AdminAppear(index: 6, child: _recent(context, loc, d.$1)),
                AdminAppear(index: 7, child: QuickChatCard(active: active)),
              ]),
            ),
          ],
        );
      },
    );
  }

  Widget _narrow(BuildContext context, AppLocalizations loc, _Data d) {
    return Column(
      children: [
        SizedBox(
          height: _tileH * 2 + _gap,
          child: _tiles(context, loc, d, cols: 2, height: _tileH),
        ),
        const SizedBox(height: _gap),
        AdminAppear(index: 4, child: _quickActions(loc, fill: false)),
        const SizedBox(height: _gap),
        AdminAppear(
          index: 5,
          child: _attention(context, loc, d.$1, fill: false),
        ),
        const SizedBox(height: _gap),
        AdminAppear(
          index: 6,
          child: _recent(context, loc, d.$1, fill: false),
        ),
        const SizedBox(height: _gap),
        AdminAppear(
          index: 7,
          child: QuickChatCard(fill: false, active: active),
        ),
      ],
    );
  }

  (String, Color) _pill(AppLocalizations loc, int n, {bool danger = false}) {
    if (n <= 0) {
      return (loc.tr('admin.pill.clear'), AppColors.success);
    }
    return (
      loc.tr('admin.pill.review'),
      danger ? AppColors.danger : AppColors.warning,
    );
  }

  Widget _tiles(
    BuildContext context,
    AppLocalizations loc,
    _Data d, {
    required int cols,
    required double height,
  }) {
    final (patients, today) = d;
    final attention = patients.where(_needsAttention).length;
    final rejected =
        patients.where((p) => _statusOf(p) == CaseStatuses.rejected).length;
    final chrome = AdminChrome.maybeOf(context);

    Widget grid(int unread) {
      final tiles = [
        KpiTile(
          icon: Icons.priority_high_rounded,
          label: loc.tr('dash.tile.attention'),
          value: attention,
          tint: AppColors.warning,
          pill: _pill(loc, attention),
          onTap: () => onOpen(AppNavItem.patients, 0),
        ),
        KpiTile(
          icon: Icons.calendar_today_outlined,
          label: loc.tr('dash.tile.today'),
          value: today.length,
          tint: AppColors.dentalBlue,
          pill: today.isEmpty
              ? (loc.tr('dash.pill.noneToday'), AppColors.success)
              : (loc.tr('admin.pill.review'), AppColors.dentalBlue),
          onTap: () => onOpen(AppNavItem.appointments, 0),
        ),
        KpiTile(
          icon: Icons.chat_bubble_outline_rounded,
          label: loc.tr('dash.tile.messages'),
          value: unread,
          tint: AppColors.review,
          pill: _pill(loc, unread),
          onTap: () => onOpen(AppNavItem.messages, 0),
        ),
        KpiTile(
          icon: Icons.replay_rounded,
          label: loc.tr('dash.tile.rejected'),
          value: rejected,
          tint: AppColors.danger,
          pill: _pill(loc, rejected, danger: true),
          onTap: () => onOpen(AppNavItem.patients, 0),
        ),
      ];
      return LayoutBuilder(
        builder: (context, c) {
          final w = (c.maxWidth - _gap * (cols - 1)) / cols;
          return Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: [
              for (final (i, t) in tiles.indexed)
                SizedBox(
                  width: w,
                  height: height,
                  child: AdminAppear(index: i, child: t),
                ),
            ],
          );
        },
      );
    }

    if (chrome == null) return grid(0);
    return ListenableBuilder(
      listenable: chrome.chat,
      builder: (_, _) => grid(chrome.chat.totalUnread),
    );
  }

  Widget _quickActions(AppLocalizations loc, {bool fill = true}) {
    final actions = [
      (
        Icons.person_add_alt_1_rounded,
        'dash.qa.newPatient',
        AppColors.success,
        AppNavItem.newPatient,
      ),
      (
        Icons.photo_camera_outlined,
        'dash.qa.camera',
        AppColors.dentalBlue,
        AppNavItem.camera,
      ),
      (
        Icons.palette_outlined,
        'dash.qa.shade',
        AppColors.warning,
        AppNavItem.shade,
      ),
      (
        Icons.view_in_ar_outlined,
        'dash.qa.scans',
        AppColors.review,
        AppNavItem.scans,
      ),
      (
        Icons.sentiment_satisfied_alt_outlined,
        'dash.qa.smile',
        AppColors.dentalBlue,
        AppNavItem.smilePreview,
      ),
      (
        Icons.calendar_today_outlined,
        'dash.qa.appointments',
        AppColors.navy,
        AppNavItem.appointments,
      ),
    ];
    return PanelCard(
      fill: fill,
      title: loc.tr('dash.quickActions'),
      subtitle: loc.tr('dash.quickActionsSub'),
      child: LayoutBuilder(
        builder: (context, c) {
          const g = 10.0;
          final w = (c.maxWidth - g) / 2;
          final rows = 3;
          final h = fill
              ? ((c.maxHeight - g * (rows - 1)) / rows).clamp(0.0, 72.0)
              : 56.0;
          return Wrap(
            spacing: g,
            runSpacing: g,
            children: [
              for (final (icon, key, color, page) in actions)
                SizedBox(
                  width: w,
                  height: h,
                  child: Pressable(
                    onTap: () => onOpen(page, 0),
                    scale: 0.95,
                    builder: (_, pressed) => AnimatedContainer(
                      duration: AppMotion.fast,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: pressed ? 0.16 : 0.09),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(icon, size: 20, color: color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              loc.tr(key),
                              maxLines: h < 44 ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(
                                fontSize: 12.5,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _attention(
    BuildContext context,
    AppLocalizations loc,
    List<Map<String, dynamic>> patients, {
    bool fill = true,
  }) {
    final rows = patients.where(_needsAttention).toList()
      ..sort((a, b) {
        final ta = _updatedAt(a) ?? DateTime(1970);
        final tb = _updatedAt(b) ?? DateTime(1970);
        return tb.compareTo(ta);
      });
    return PanelCard(
      fill: fill,
      title: loc.tr('dash.attention'),
      subtitle: plural(loc, 'admin.waitingCount', rows.length),
      action: (loc.tr('admin.seeAll'), () => onOpen(AppNavItem.patients, 0)),
      child: rows.isEmpty
          ? PanelEmpty(
              icon: Icons.verified_rounded,
              color: AppColors.success,
              text: loc.tr('dash.attentionNone'),
            )
          : _list(fill, [
              for (final p in rows.take(8))
                _PanelRow(
                  leading: UserAvatar(name: _patientName(p), size: 36),
                  title: _patientName(p).isEmpty ? '—' : _patientName(p),
                  sub: [
                    loc.statusLabel(_statusOf(p)),
                    if (_updatedAt(p) case final at?)
                      loc.trp('admin.updated', {
                        'when': adminWhen(context, at.toLocal()),
                      }),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  trailing: StatusChip(statusKey: _statusOf(p)),
                  onTap: () => onOpen(AppNavItem.patients, 0),
                ),
            ]),
    );
  }

  Widget _recent(
    BuildContext context,
    AppLocalizations loc,
    List<Map<String, dynamic>> patients, {
    bool fill = true,
  }) {
    final rows = [...patients]
      ..sort((a, b) {
        final ta = _updatedAt(a) ?? DateTime(1970);
        final tb = _updatedAt(b) ?? DateTime(1970);
        return tb.compareTo(ta);
      });
    return PanelCard(
      fill: fill,
      title: loc.tr('dash.recentPatients'),
      subtitle: loc.tr('dash.recentPatientsSub'),
      action: (loc.tr('admin.seeAll'), () => onOpen(AppNavItem.patients, 0)),
      child: rows.isEmpty
          ? PanelEmpty(
              icon: Icons.people_outline,
              color: AppColors.muted,
              text: loc.tr('dash.noPatientsHint'),
            )
          : _list(fill, [
              for (final p in rows.take(8))
                _PanelRow(
                  leading: UserAvatar(name: _patientName(p), size: 36),
                  title: _patientName(p).isEmpty ? '—' : _patientName(p),
                  sub: [
                    if (_updatedAt(p) case final at?)
                      loc.trp('admin.updated', {
                        'when': adminWhen(context, at.toLocal()),
                      }),
                  ].join(),
                  trailing: StatusChip(statusKey: _statusOf(p)),
                  onTap: () => onOpen(AppNavItem.patients, 0),
                ),
            ]),
    );
  }

  Widget _list(bool fill, List<Widget> rows) {
    final items = [
      for (final (i, r) in rows.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AdminAppear(index: i, child: r),
        ),
    ];
    return fill
        ? ListView(padding: EdgeInsets.zero, children: items)
        : Column(children: items);
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.leading,
    required this.title,
    required this.sub,
    required this.onTap,
    this.trailing,
  });

  final Widget leading;
  final String title, sub;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      builder: (_, pressed) => AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: pressed ? 0.9 : 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.style(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(
                        fontSize: 12.5,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Search the dentist's own patients; grows out of the top bar.
class _DentistSearchPage extends StatefulWidget {
  const _DentistSearchPage({required this.chrome});

  final AdminChrome chrome;

  @override
  State<_DentistSearchPage> createState() => _DentistSearchPageState();
}

class _DentistSearchPageState extends State<_DentistSearchPage> {
  String _q = '';

  late final _data = widget.chrome.api.listPatients(forceRefresh: true);

  bool _hit(Object? s) => '${s ?? ''}'.toLowerCase().contains(_q);

  void _go() {
    Navigator.pop(context);
    widget.chrome.onOpen(AppNavItem.patients, 0);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: AppBreakpoints.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: CupertinoSearchTextField(
                      autofocus: true,
                      placeholder: loc.tr('dash.searchHint'),
                      style: AppFonts.style(fontSize: 16, color: AppColors.navy),
                      backgroundColor: AppColors.card,
                      borderRadius: BorderRadius.circular(23),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 13,
                      ),
                      onChanged: (v) =>
                          setState(() => _q = v.trim().toLowerCase()),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: 14),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      loc.cancel,
                      style: AppFonts.style(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.dentalBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _data,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return AdminEmpty(
                        icon: Icons.cloud_off_rounded,
                        title: loc.tr('admin.loadFailed'),
                        subtitle: friendlyError(snap.error!),
                      );
                    }
                    if (!snap.hasData) return const ToothPageLoader();
                    final patients = snap.data!
                        .where(
                          (p) =>
                              _hit(_patientName(p)) ||
                              _hit(p['notes']) ||
                              _hit(p['insurance']),
                        )
                        .toList();
                    if (patients.isEmpty) {
                      return AdminEmpty(
                        icon: Icons.search_off_rounded,
                        title: loc.tr('admin.noMatches'),
                        subtitle: loc.tr('admin.noMatchesSub'),
                      );
                    }
                    return ListView(
                      children: [
                        for (final p in patients)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AdminCard(
                              onTap: _go,
                              padding: const EdgeInsets.all(12),
                              child: AdminRow(
                                leading: UserAvatar(
                                  name: _patientName(p),
                                  size: 38,
                                ),
                                title: _patientName(p).isEmpty
                                    ? '—'
                                    : _patientName(p),
                                badges: [
                                  StatusChip(statusKey: _statusOf(p)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

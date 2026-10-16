import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/l10n/date_formats.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_sidebar.dart';
import '../chat/models/chat_models.dart';
import '../chat/widgets/user_profile_sheet.dart';
import 'admin_models.dart';
import 'admin_signups_page.dart';
import 'admin_top_bar.dart';
import 'admin_widgets.dart';

typedef _Data = (AdminSummary, List<Signup>, List<AdminPatient>);

/// Admin home: top bar (search, date, bell, profile), KPI tiles, cases
/// donut, what needs attention, the signup queue, recent patient activity,
/// quick actions and quick chat.
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({
    super.key,
    required this.api,
    required this.onOpen,
    required this.onOpenStatus,
    this.active = true,
  });

  final ApiClient api;

  /// Go to an admin page, on the given tab.
  final void Function(AppNavItem page, int tab) onOpen;

  /// Go to Patients filtered to one status ('' = all).
  final ValueChanged<String> onOpenStatus;
  final bool active;

  // Phone layout (scrolls): fixed heights keep side-by-side cards even.
  // iPads fit one screen with flex instead; see [_fitWide] / [_fitPortrait].
  static const _tileH = 128.0;
  static const _midH = 340.0;
  static const _donutH = 300.0;
  static const _gap = 16.0;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: AppBreakpoints.pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(context),
          const SizedBox(height: 18),
          Expanded(
            child: AdminFuture<_Data>(
              active: active,
              load: () async {
                final r = await Future.wait<Object>([
                  api.adminSummary(),
                  api.adminSignups(),
                  api.adminPatients(),
                ]);
                final patients = (r[2] as List<Map<String, dynamic>>).map(AdminPatient.new).toList()
                  ..sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
                return (
                  AdminSummary(r[0] as Map<String, dynamic>),
                  (r[1] as List<Map<String, dynamic>>).map(Signup.new).toList(),
                  patients,
                );
              },
              isEmpty: (_) => false,
              empty: const SizedBox.shrink(),
              // iPad: exactly one screen tall, so the page never scrolls; it
              // only bounces for pull-to-refresh. Lists scroll inside cards.
              bottomPadding: AppBreakpoints.isPhone(context) ? 24 : 0,
              builder: (context, data, reload) => AppBreakpoints.isPhone(context)
                  ? [
                      SliverToBoxAdapter(child: _greeting(loc, compact: false)),
                      SliverToBoxAdapter(
                        child: LayoutBuilder(
                          builder: (context, c) => _narrow(context, loc, data, reload, c.maxWidth),
                        ),
                      ),
                    ]
                  : [
                      SliverLayoutBuilder(
                        builder: (context, sc) => SliverToBoxAdapter(
                          child: SizedBox(
                            height: sc.viewportMainAxisExtent,
                            child: LayoutBuilder(
                              builder: (context, c) {
                                final landscape = c.maxWidth > c.maxHeight;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _greeting(loc, compact: c.maxHeight < 820),
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, b) => landscape
                                            ? _fitWide(context, loc, data, reload, b.maxHeight)
                                            : _fitPortrait(context, loc, data, reload, b.maxHeight),
                                      ),
                                    ),
                                  ],
                                );
                              },
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

  Widget _topBar(BuildContext context) {
    final phone = AppBreakpoints.isPhone(context);
    return LayoutBuilder(
      builder: (context, c) => Row(
        children: [
          const PhoneMenuButton(),
          Expanded(child: const AdminSearchLauncher()),
          if (c.maxWidth >= 720) ...[const SizedBox(width: 12), const AdminDateChip()],
          SizedBox(width: phone ? 8 : 12),
          const AdminTopActions(),
        ],
      ),
    );
  }

  /// [compact] drops the subtitle to give the cards the room.
  Widget _greeting(AppLocalizations loc, {required bool compact}) {
    final h = DateTime.now().hour;
    final key = h < 12 ? 'admin.hiMorning' : (h < 18 ? 'admin.hiAfternoon' : 'admin.hiEvening');
    final name = (api.userName ?? '').trim().split(' ').first;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 12 : 16, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.trp(key, {'name': name.isEmpty ? loc.roleAdmin : name}),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.style(fontSize: compact ? 21 : 24, fontWeight: FontWeight.w700, color: AppColors.navy, letterSpacing: -0.5),
          ),
          if (!compact)
            Text(loc.tr('admin.dashSub'), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppFonts.style(fontSize: 14, color: AppColors.muted)),
        ],
      ),
    );
  }

  // ── Layouts ──────────────────────────────────────────────────────────────

  /// Tile row height for a body of height [h].
  static double _tileFor(double h) => (h * 0.15).clamp(112.0, 128.0);

  Widget _row(List<(int, Widget)> cells) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (flex, w)) in cells.indexed) ...[
            if (i > 0) const SizedBox(width: _gap),
            Expanded(flex: flex, child: w),
          ],
        ],
      );

  /// iPad landscape: tiles + signups/attention beside donut/quick actions,
  /// then recent activity beside quick chat. Fills [h] exactly.
  Widget _fitWide(BuildContext context, AppLocalizations loc, _Data d, VoidCallback reload, double h) {
    final (sum, signups, patients) = d;
    final tileH = _tileFor(h);
    return Column(
      children: [
        Expanded(
          flex: 11,
          child: _row([
            (
              13,
              Column(
                children: [
                  SizedBox(height: tileH, child: _tiles(loc, sum, cols: 4, height: tileH)),
                  const SizedBox(height: _gap),
                  Expanded(
                    child: _row([
                      (1, _appear(4, _signups(context, loc, signups, reload))),
                      (1, _appear(5, _attention(loc, sum))),
                    ]),
                  ),
                ],
              ),
            ),
            (
              7,
              Column(
                children: [
                  Expanded(flex: 3, child: _appear(2, _CasesDonut(summary: sum, onStatus: onOpenStatus))),
                  const SizedBox(height: _gap),
                  Expanded(flex: 2, child: _appear(3, _quickActions(loc, sum))),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: _gap),
        Expanded(
          flex: 8,
          child: _row([
            (13, _appear(6, _recent(context, loc, patients, table: true))),
            (7, _appear(7, _QuickChat(active: active))),
          ]),
        ),
      ],
    );
  }

  /// iPad portrait: one tile row, then three rows of paired cards. Fills
  /// [h] exactly.
  Widget _fitPortrait(BuildContext context, AppLocalizations loc, _Data d, VoidCallback reload, double h) {
    final (sum, signups, patients) = d;
    final tileH = _tileFor(h * 0.75);
    return Column(
      children: [
        SizedBox(height: tileH, child: _tiles(loc, sum, cols: 4, height: tileH)),
        const SizedBox(height: _gap),
        Expanded(
          flex: 5,
          child: _row([
            (1, _appear(2, _CasesDonut(summary: sum, onStatus: onOpenStatus))),
            (1, _appear(3, _quickActions(loc, sum))),
          ]),
        ),
        const SizedBox(height: _gap),
        Expanded(
          flex: 5,
          child: _row([
            (1, _appear(4, _signups(context, loc, signups, reload))),
            (1, _appear(5, _attention(loc, sum))),
          ]),
        ),
        const SizedBox(height: _gap),
        Expanded(
          flex: 5,
          child: _row([
            (1, _appear(6, _recent(context, loc, patients, table: false))),
            (1, _appear(7, _QuickChat(active: active))),
          ]),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context, AppLocalizations loc, _Data d, VoidCallback reload, double width) {
    final (sum, signups, patients) = d;
    final twoUp = width >= 640;
    Widget pair(Widget a, Widget b, double h) => twoUp
        ? SizedBox(
            height: h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(child: a), const SizedBox(width: _gap), Expanded(child: b)],
            ),
          )
        : Column(children: [SizedBox(height: h, child: a), const SizedBox(height: _gap), SizedBox(height: h, child: b)]);
    return Column(
      children: [
        SizedBox(height: _tileH * 2 + _gap, child: _tiles(loc, sum, cols: 2, height: _tileH)),
        const SizedBox(height: _gap),
        // Stacked on a phone, these two only need their content's height.
        if (twoUp)
          pair(
            _appear(2, _CasesDonut(summary: sum, onStatus: onOpenStatus)),
            _appear(3, _quickActions(loc, sum)),
            _donutH,
          )
        else ...[
          SizedBox(height: 210, child: _appear(2, _CasesDonut(summary: sum, onStatus: onOpenStatus))),
          const SizedBox(height: _gap),
          SizedBox(height: 200, child: _appear(3, _quickActions(loc, sum))),
        ],
        const SizedBox(height: _gap),
        pair(_appear(4, _signups(context, loc, signups, reload)), _appear(5, _attention(loc, sum)), _midH),
        const SizedBox(height: _gap),
        // Single column: these two size to their rows instead of a fixed box.
        _appear(6, _recent(context, loc, patients, table: false, fill: false)),
        const SizedBox(height: _gap),
        _appear(7, _QuickChat(fill: false, active: active)),
      ],
    );
  }

  Widget _appear(int i, Widget child) => AdminAppear(index: i, child: child);

  // ── KPI tiles ────────────────────────────────────────────────────────────

  Widget _tiles(AppLocalizations loc, AdminSummary s, {required int cols, required double height}) {
    final open = s.cases('pending') + s.cases('in_progress') + s.cases('in_review');
    final tiles = [
      _Kpi(
        icon: Icons.how_to_reg_outlined,
        label: loc.tr('admin.tile.signups'),
        value: s.pendingSignups,
        tint: AppColors.warning,
        pill: s.pendingSignups > 0 ? (loc.tr('admin.pill.review'), AppColors.warning) : (loc.tr('admin.pill.clear'), AppColors.success),
        onTap: () => onOpen(AppNavItem.adminSignups, 0),
      ),
      _Kpi(
        icon: Icons.medical_services_outlined,
        label: loc.tr('admin.tile.dentists'),
        value: s.dentists,
        tint: AppColors.dentalBlue,
        pill: s.unassignedDentists > 0
            ? (loc.trp('admin.pill.noLab', {'n': s.unassignedDentists}), AppColors.danger)
            : null,
        onTap: () => onOpen(AppNavItem.laboratories, s.unassignedDentists > 0 ? 1 : 0),
      ),
      _Kpi(
        icon: Icons.apartment_rounded,
        label: loc.tr('admin.tile.labs'),
        value: s.labs,
        tint: AppColors.review,
        pill: s.pendingRemovals > 0
            ? (plural(loc, 'admin.pill.removals', s.pendingRemovals), AppColors.warning)
            : null,
        onTap: () => onOpen(AppNavItem.laboratories, s.pendingRemovals > 0 ? 2 : 0),
      ),
      _Kpi(
        icon: Icons.folder_open_rounded,
        label: loc.tr('admin.tile.openCases'),
        value: open,
        tint: AppColors.success,
        pill: s.cases('in_review') > 0
            ? (loc.trp('admin.pill.inReview', {'n': s.cases('in_review')}), AppColors.review)
            : null,
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
              SizedBox(width: w, height: height, child: AdminAppear(index: i, child: t)),
          ],
        );
      },
    );
  }

  // ── Cards ────────────────────────────────────────────────────────────────

  Widget _signups(BuildContext context, AppLocalizations loc, List<Signup> signups, VoidCallback reload) {
    return _Panel(
      title: loc.tr('admin.signupQueue'),
      subtitle: plural(loc, 'admin.waitingCount', signups.length),
      action: (loc.tr('admin.seeAll'), () => onOpen(AppNavItem.adminSignups, 0)),
      child: signups.isEmpty
          ? _PanelEmpty(icon: Icons.task_alt_rounded, color: AppColors.success, text: loc.tr('admin.noSignups'))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                // ponytail: first five only; the Signups page has the full list.
                for (final (i, s) in signups.take(5).indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AdminAppear(
                      key: ValueKey(s.userId),
                      index: i,
                      child: _QueueItem(
                        signup: s,
                        onApprove: () async {
                          if (await approveSignup(context, api, s)) reload();
                        },
                        onReject: () async {
                          if (await rejectSignup(context, api, s)) reload();
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _attention(AppLocalizations loc, AdminSummary s) {
    final items = [
      if (s.unassignedPatients > 0)
        _Alert(Icons.assignment_late_outlined, AppColors.danger, 'admin.att.patients', 'admin.att.patientsSub',
            s.unassignedPatients, 'admin.sev.high', () => onOpen(AppNavItem.patients, 1)),
      if (s.pendingRemovals > 0)
        _Alert(Icons.person_remove_outlined, AppColors.warning, 'admin.att.removals', 'admin.att.removalsSub',
            s.pendingRemovals, 'admin.sev.medium', () => onOpen(AppNavItem.laboratories, 2)),
      if (s.unassignedDentists > 0)
        _Alert(Icons.person_off_outlined, AppColors.warning, 'admin.att.dentists', 'admin.att.dentistsSub',
            s.unassignedDentists, 'admin.sev.medium', () => onOpen(AppNavItem.laboratories, 1)),
      if (s.cases('rejected') > 0)
        _Alert(Icons.cancel_outlined, AppColors.dentalBlue, 'admin.att.rejected', 'admin.att.rejectedSub',
            s.cases('rejected'), 'admin.sev.low', () => onOpen(AppNavItem.patients, 0)),
    ];
    return _Panel(
      title: loc.tr('admin.attention'),
      subtitle: loc.tr('admin.attentionSub'),
      child: items.isEmpty
          ? _PanelEmpty(icon: Icons.verified_rounded, color: AppColors.success, text: loc.tr('admin.att.none'))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final (i, a) in items.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AdminAppear(index: i, child: _AlertRow(alert: a)),
                  ),
              ],
            ),
    );
  }

  Widget _quickActions(AppLocalizations loc, AdminSummary s) {
    final actions = [
      (Icons.how_to_reg_outlined, 'admin.qa.signups', AppColors.warning, s.pendingSignups, AppNavItem.adminSignups, 0),
      (Icons.add_link_rounded, 'admin.qa.assign', AppColors.dentalBlue, s.unassignedDentists, AppNavItem.laboratories, 1),
      (Icons.move_down_rounded, 'admin.qa.patients', AppColors.danger, s.unassignedPatients, AppNavItem.patients, 1),
      (Icons.block_rounded, 'admin.qa.rejectList', AppColors.review, 0, AppNavItem.adminSignups, 1),
    ];
    return _Panel(
      title: loc.tr('admin.quickActions'),
      child: LayoutBuilder(
        builder: (context, c) {
          const g = 10.0;
          final w = (c.maxWidth - g) / 2;
          final h = ((c.maxHeight - g) / 2).clamp(0.0, 80.0);
          return Wrap(
            spacing: g,
            runSpacing: g,
            children: [
              for (final (icon, key, color, n, page, tab) in actions)
                SizedBox(
                  width: w,
                  height: h,
                  child: Pressable(
                    onTap: () => onOpen(page, tab),
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
                          // Count sits on the icon's corner so the label keeps the width.
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(icon, size: 20, color: color),
                              if (n > 0)
                                Positioned(
                                  right: -8,
                                  top: -6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                                    constraints: const BoxConstraints(minWidth: 15),
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                    child: Text('$n',
                                        textAlign: TextAlign.center,
                                        style: AppFonts.style(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white)),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              loc.tr(key),
                              maxLines: h < 44 ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w600, color: AppColors.navy),
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

  /// [fill]: fixed card, rows scroll inside; else the card hugs its rows.
  Widget _recent(BuildContext context, AppLocalizations loc, List<AdminPatient> patients,
      {required bool table, bool fill = true}) {
    final rows = patients.take(6).toList();
    TextStyle head = AppFonts.style(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5);
    TextStyle cell = AppFonts.style(fontSize: 13.5, color: AppColors.navy);
    return _Panel(
      fill: fill,
      title: loc.tr('admin.recentPatients'),
      subtitle: loc.tr('admin.recentPatientsSub'),
      action: (loc.tr('admin.seeAll'), () => onOpen(AppNavItem.patients, 0)),
      child: rows.isEmpty
          ? _PanelEmpty(icon: Icons.people_outline, color: AppColors.muted, text: loc.tr('admin.noPatients'))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (table)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 4, child: Text(loc.tr('admin.col.patient').toUpperCase(), style: head)),
                        Expanded(flex: 3, child: Text(loc.tr('admin.owner').toUpperCase(), style: head)),
                        Expanded(flex: 3, child: Text(loc.tr('admin.lab').toUpperCase(), style: head)),
                        Expanded(flex: 3, child: Text(loc.tr('admin.col.status').toUpperCase(), style: head)),
                        Expanded(flex: 3, child: Text(loc.tr('admin.lastUpdate').toUpperCase(), style: head)),
                      ],
                    ),
                  ),
                _fit(
                  fill,
                  ListView.separated(
                    shrinkWrap: true,
                    physics: fill ? null : const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
                    itemBuilder: (context, i) {
                      final p = rows[i];
                      final owner = p.waitingForLab ? loc.trp('admin.waitingFor', {'lab': p.labName ?? '—'}) : p.ownerName ?? '—';
                      return AdminAppear(
                        index: i,
                        child: Pressable(
                          scale: 0.99,
                          onTap: () => onOpen(AppNavItem.patients, p.unassignedReason == null ? 0 : 1),
                          builder: (_, _) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            child: table
                                ? Row(
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: Row(
                                          children: [
                                            UserAvatar(name: p.name, size: 30),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                                  style: cell.copyWith(fontWeight: FontWeight.w600)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(flex: 3, child: Text(owner, maxLines: 1, overflow: TextOverflow.ellipsis, style: cell)),
                                      Expanded(
                                        flex: 3,
                                        child: Text(p.labName ?? loc.tr('admin.noLab'), maxLines: 1, overflow: TextOverflow.ellipsis, style: cell),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Align(alignment: Alignment.centerLeft, child: StatusChip(statusKey: p.status)),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(adminWhen(context, p.updatedAt), maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: cell.copyWith(color: AppColors.muted, fontSize: 12.5)),
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      UserAvatar(name: p.name, size: 34),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                                style: cell.copyWith(fontWeight: FontWeight.w600)),
                                            Text('$owner · ${p.labName ?? loc.tr('admin.noLab')}', maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppFonts.style(fontSize: 12, color: AppColors.muted)),
                                            // Under the name: half-width cards have no room beside it.
                                            const SizedBox(height: 4),
                                            StatusChip(statusKey: p.status),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
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

  /// Fills a fixed card ([expand]) or hugs its rows.
  static Widget _fit(bool expand, Widget child) => expand ? Expanded(child: child) : child;
}

// ── Pieces ────────────────────────────────────────────────────────────────

/// White card with a title row; [child] fills the rest.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.subtitle, this.action, this.fill = true});

  /// True: [child] fills a fixed-height card. False: card hugs [child].
  final bool fill;
  final String title;
  final String? subtitle;
  final (String, VoidCallback)? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy, letterSpacing: -0.3)),
                    if (subtitle != null)
                      Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.style(fontSize: 12.5, color: AppColors.muted)),
                  ],
                ),
              ),
              if (action != null)
                Pressable(
                  onTap: action!.$2,
                  scale: 0.94,
                  builder: (_, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(action!.$1,
                        style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.dentalBlue)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (fill) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class _PanelEmpty extends StatelessWidget {
  const _PanelEmpty({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AdminIcon(icon: icon, color: color, size: 48),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: AppFonts.style(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.navy)),
          ],
        ),
      );
}

/// Tinted KPI tile: icon and status pill on top, label and number below.
class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
    required this.onTap,
    this.pill,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color tint;
  final (String, Color)? pill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      builder: (_, pressed) => AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(tint.withValues(alpha: pressed ? 0.16 : 0.10), Colors.white),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: tint),
                const SizedBox(width: 8),
                if (pill != null)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                      child: Text(pill!.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.style(fontSize: 11, fontWeight: FontWeight.w700, color: pill!.$2)),
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy.withValues(alpha: 0.7))),
            const SizedBox(height: 2),
            AdminCount(value,
                style: AppFonts.style(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.navy, letterSpacing: -0.8)),
          ],
        ),
      ),
    );
  }
}

class _Alert {
  const _Alert(this.icon, this.color, this.title, this.sub, this.count, this.severity, this.onTap);

  final IconData icon;
  final Color color;
  final String title, sub, severity;
  final int count;
  final VoidCallback onTap;
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final _Alert alert;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final a = alert;
    return Pressable(
      onTap: a.onTap,
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
            AdminIcon(icon: a.icon, color: a.color, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(plural(loc, a.title, a.count),
                          style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                      AdminBadge(loc.tr(a.severity).toUpperCase(), color: a.color),
                    ],
                  ),
                  Text(loc.tr(a.sub), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppFonts.style(fontSize: 12.5, color: AppColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Compact signup row with Reject / Approve.
class _QueueItem extends StatelessWidget {
  const _QueueItem({required this.signup, required this.onApprove, required this.onReject});

  final Signup signup;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final s = signup;
    final name = s.name.isEmpty ? s.email : s.name;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UserAvatar(name: name, url: s.avatarUrl, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                    Text([?s.clinicName, s.email].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              roleBadge(context, s.role),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButtons.danger(onPressed: onReject, icon: Icons.close_rounded, label: loc.tr('admin.reject'), soft: true, compact: true),
              AppButtons.primary(onPressed: onApprove, icon: Icons.check_rounded, label: loc.tr('admin.approve'), compact: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// Donut of cases per status in status colours, total in the middle; the
/// arcs sweep in on load.
/// Donut of cases per status in status colours, total in the middle; the
/// arcs sweep in on load. Tapping a segment or legend row opens Patients
/// filtered to that status; the centre or "See all" opens every patient.
class _CasesDonut extends StatelessWidget {
  const _CasesDonut({required this.summary, required this.onStatus});

  final AdminSummary summary;

  /// '' = all statuses.
  final ValueChanged<String> onStatus;

  /// Status under a tap on a donut of [size], or '' for the centre hole.
  String _hit(Offset p, double size, List<(String, int)> counts) {
    final v = p - Offset(size / 2, size / 2);
    if (v.distance < size * 0.3) return '';
    final total = counts.fold(0, (a, b) => a + b.$2);
    if (total == 0) return '';
    // 0 at 12 o'clock, clockwise, like the painter.
    var angle = math.atan2(v.dy, v.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    var end = 0.0;
    for (final (s, n) in counts) {
      end += n / total * math.pi * 2;
      if (n > 0 && angle <= end) return s;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final counts = [for (final s in CaseStatuses.all) (s, summary.cases(s))];
    final total = counts.fold(0, (a, b) => a + b.$2);
    return AdminCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(loc.tr('admin.casesByStatus'),
                    style: AppFonts.style(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.navy, letterSpacing: -0.3)),
              ),
              Pressable(
                onTap: () => onStatus(''),
                scale: 0.94,
                builder: (_, _) => Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(loc.tr('admin.seeAll'),
                      style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.dentalBlue)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
            // Donut and legend shrink with the card so it never overflows.
            final size = math.min(136.0, math.min(c.maxHeight, c.maxWidth * 0.45));
            const rowH = 34.0; // roomy tap targets; the legend scales down in short cards
            final legendW = math.max(0.0, c.maxWidth - size - 12);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTapUp: (d) {
                    AppHaptics.selection();
                    onStatus(_hit(d.localPosition, size, counts));
                  },
                  child: SizedBox.square(
                    dimension: size,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 900),
                      curve: AppMotion.spring,
                      builder: (_, t, _) => CustomPaint(
                        painter: _DonutPainter(
                          [for (final (s, n) in counts) (StatusStyle.of(s).fg, n.toDouble())],
                          t,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AdminCount(total,
                                  style: AppFonts.style(fontSize: size * 0.18, fontWeight: FontWeight.w700, color: AppColors.navy, letterSpacing: -0.6)),
                              Text(loc.tr('admin.cases'), style: AppFonts.style(fontSize: 11.5, color: AppColors.muted)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Legend keeps its layout and scales down in short cards.
                SizedBox(
                  width: legendW,
                  child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                  width: legendW,
                  height: rowH * counts.length,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final (s, n) in counts)
                        Pressable(
                          onTap: () => onStatus(s),
                          scale: 0.97,
                          selectionHaptic: true,
                          builder: (_, pressed) => AnimatedContainer(
                            duration: AppMotion.fast,
                            height: rowH,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: pressed ? StatusStyle.of(s).fg.withValues(alpha: 0.10) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(color: StatusStyle.of(s).fg, borderRadius: BorderRadius.circular(3)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(loc.statusLabel(s), maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: AppFonts.style(fontSize: 12.5, color: AppColors.muted)),
                                ),
                                Text('$n', style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy)),
                                const SizedBox(width: 2),
                                Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.muted.withValues(alpha: 0.6)),
                              ],
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
            }),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.parts, this.t);

  final List<(Color, double)> parts;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.1;
    final rect = (Offset.zero & size).deflate(stroke / 2 + 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.surface;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    final total = parts.fold(0.0, (a, b) => a + b.$2);
    if (total <= 0) return;
    const gap = 0.06; // radians between segments
    var start = -math.pi / 2;
    final nonZero = parts.where((p) => p.$2 > 0).length;
    for (final (color, v) in parts) {
      if (v <= 0) continue;
      final sweep = (v / total) * math.pi * 2;
      final drawn = math.max(0.0, (sweep - (nonZero > 1 ? gap : 0)) * t);
      canvas.drawArc(
        rect,
        start + (nonZero > 1 ? gap / 2 : 0),
        drawn,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.t != t || old.parts != parts;
}

/// Latest conversations. Tapping one opens the thread right here in the
/// card (iOS push from the right); "Open" goes to the Messages page.
class _QuickChat extends StatefulWidget {
  const _QuickChat({this.fill = true, this.active = true});

  final bool fill;

  /// Dashboard visible; read receipts are only sent while it is.
  final bool active;

  @override
  State<_QuickChat> createState() => _QuickChatState();
}

class _QuickChatState extends State<_QuickChat> {
  Conversation? _open;
  AdminChrome? _chrome;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chrome = AdminChrome.maybeOf(context);
  }

  @override
  void didUpdateWidget(_QuickChat old) {
    super.didUpdateWidget(old);
    if (_open == null || old.active == widget.active) return;
    final chat = _chrome!.chat;
    if (widget.active) {
      // Messages may have switched the active thread meanwhile.
      chat.openConversation(_open!);
      chat.setViewingThread(true);
    } else {
      chat.setViewingThread(false);
    }
  }

  @override
  void dispose() {
    if (_open != null) _chrome?.chat.setViewingThread(false);
    super.dispose();
  }

  void _show(Conversation c) {
    final chat = _chrome!.chat;
    setState(() => _open = c);
    chat.openConversation(c);
    chat.setViewingThread(true);
  }

  void _back() {
    _chrome!.chat.setViewingThread(false);
    setState(() => _open = null);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final chrome = _chrome;
    if (chrome == null) return const SizedBox.shrink();
    final fill = widget.fill;
    return ListenableBuilder(
      listenable: chrome.chat,
      builder: (context, _) {
        final convs = [...chrome.chat.conversations]
          ..sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
        final open = _open;
        final Widget body;
        if (open != null) {
          body = KeyedSubtree(
            key: const ValueKey('thread'),
            child: _InlineThread(
              conv: open,
              onBack: _back,
              // Single column: give the thread a fixed body height.
              height: fill ? null : 360,
            ),
          );
        } else if (convs.isEmpty) {
          body = KeyedSubtree(
            key: const ValueKey('list'),
            child: _PanelEmpty(icon: Icons.chat_bubble_outline_rounded, color: AppColors.dentalBlue, text: loc.tr('admin.noChats')),
          );
        } else {
          body = ListView(
            key: const ValueKey('list'),
            shrinkWrap: !fill,
            physics: fill ? null : const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              for (final (i, c) in convs.take(5).indexed)
                AdminAppear(index: i, child: _ChatRow(conv: c, onTap: () => _show(c))),
            ],
          );
        }
        return _Panel(
          fill: fill,
          title: loc.tr('admin.quickChat'),
          subtitle: chrome.chat.totalUnread > 0 ? plural(loc, 'admin.unreadCount', chrome.chat.totalUnread) : loc.tr('admin.quickChatSub'),
          // Open: the Messages page, on this thread if one is showing.
          action: (
            loc.tr('admin.openMessages'),
            () => open == null ? chrome.onOpen(AppNavItem.messages, 0) : chrome.openChat(open),
          ),
          child: ClipRect(
            child: AnimatedSize(
              duration: AppMotion.normal,
              curve: AppMotion.spring,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: AppMotion.page,
                reverseDuration: AppMotion.page,
                switchInCurve: AppMotion.spring,
                switchOutCurve: AppMotion.spring,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  fit: fill ? StackFit.expand : StackFit.loose,
                  children: [...previous, ?current],
                ),
                transitionBuilder: (child, a) {
                  // Thread pushes in from the right; the list sits slightly left
                  // underneath, like a navigation stack.
                  final thread = child.key == const ValueKey('thread');
                  return SlideTransition(
                    position: Tween(
                      begin: thread ? const Offset(1, 0) : const Offset(-0.3, 0),
                      end: Offset.zero,
                    ).animate(a),
                    child: FadeTransition(opacity: thread ? const AlwaysStoppedAnimation(1) : a, child: child),
                  );
                },
                child: body,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One conversation inside the quick chat card: header with back, messages,
/// and a composer.
class _InlineThread extends StatefulWidget {
  const _InlineThread({required this.conv, required this.onBack, this.height});

  final Conversation conv;
  final VoidCallback onBack;
  final double? height;

  @override
  State<_InlineThread> createState() => _InlineThreadState();
}

class _InlineThreadState extends State<_InlineThread> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send(AdminChrome chrome) {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    chrome.chat.sendText(t);
    _text.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final chrome = AdminChrome.maybeOf(context)!;
    final chat = chrome.chat;
    final c = widget.conv;
    final name = (c.partner.name ?? '').trim().isEmpty ? (c.partner.email ?? '—') : c.partner.name!.trim();
    final showing = chat.activeConversation?.id == c.id;
    final messages = showing ? chat.messages : const <Message>[];
    final me = chat.currentUserId;

    final list = !showing || (chat.loadingMessages && messages.isEmpty)
        ? const Center(child: CupertinoActivityIndicator())
        : messages.isEmpty
            ? Center(
                child: Text(loc.tr('admin.chatEmpty'), style: AppFonts.style(fontSize: 13, color: AppColors.muted)),
              )
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: messages.length,
                itemBuilder: (context, i) {
                  final m = messages[messages.length - 1 - i];
                  return _Bubble(message: m, mine: m.senderId == me);
                },
              );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppButtons.icon(onPressed: widget.onBack, icon: Icons.arrow_back_ios_new_rounded, tooltip: loc.tr('admin.back')),
            Expanded(
              child: Pressable(
                onTap: () => showUserProfileSheet(context, c.partner),
                scale: 0.98,
                builder: (_, _) => Row(
                  children: [
                    UserAvatar(name: name, url: c.partner.avatarUrl, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                          if (c.partner.role != null)
                            Text(AppRoles.label(c.partner.role, loc),
                                style: AppFonts.style(fontSize: 11.5, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Divider(height: 12, color: AppColors.border.withValues(alpha: 0.5)),
        if (widget.height == null) Expanded(child: list) else SizedBox(height: widget.height, child: list),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _text,
                placeholder: loc.tr('admin.chatPlaceholder'),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(chrome),
                onChanged: (_) => setState(() {}),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                style: AppFonts.style(fontSize: 14.5, color: AppColors.navy),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedScale(
              scale: _text.text.trim().isEmpty ? 0.85 : 1,
              duration: AppMotion.fast,
              curve: AppMotion.spring,
              child: Pressable(
                onTap: _text.text.trim().isEmpty ? null : () => _send(chrome),
                enabled: _text.text.trim().isNotEmpty,
                scale: 0.9,
                builder: (_, _) => AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _text.text.trim().isEmpty ? AppColors.border : AppColors.navy,
                    shape: BoxShape.circle,
                  ),
                  child: Tooltip(
                    message: loc.tr('admin.send'),
                    child: const Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    return column;
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final m = message;
    final media = m.isImage
        ? (Icons.photo_outlined, loc.tr('admin.chatPhoto'))
        : m.isVoice
            ? (Icons.mic_none_rounded, loc.tr('admin.chatVoice'))
            : m.isVideo
                ? (Icons.videocam_outlined, loc.tr('admin.chatVideo'))
                : m.hasMedia
                    ? (Icons.description_outlined, loc.tr('admin.chatDocument'))
                    : null;
    final fg = mine ? Colors.white : AppColors.navy;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: mine ? AppColors.navy : AppColors.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (media != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(media.$1, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(media.$2, style: AppFonts.style(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
                  ],
                ),
              if (m.content.trim().isNotEmpty)
                Text(m.content, style: AppFonts.style(fontSize: 13.5, height: 1.3, color: fg)),
              if (m.createdAt != null)
                Text(
                  formatAppTime(context, m.createdAt!.toLocal()),
                  style: AppFonts.style(fontSize: 10.5, color: fg.withValues(alpha: 0.6)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.conv, required this.onTap});

  final Conversation conv;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (conv.partner.name ?? '').trim().isEmpty ? (conv.partner.email ?? '—') : conv.partner.name!.trim();
    final unread = conv.unreadCount > 0;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      builder: (_, pressed) => AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: pressed ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            UserAvatar(name: name, url: conv.partner.avatarUrl, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(fontSize: 14, fontWeight: unread ? FontWeight.w700 : FontWeight.w600, color: AppColors.navy)),
                  Text(conv.lastMessage?.content ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(fontSize: 12.5, color: unread ? AppColors.navy : AppColors.muted)),
                ],
              ),
            ),
            if (unread)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: AppColors.dentalBlue, borderRadius: BorderRadius.circular(999)),
                child: Text('${conv.unreadCount}', style: AppFonts.style(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}

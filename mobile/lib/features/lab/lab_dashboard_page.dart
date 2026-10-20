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
import '../chat/widgets/quick_chat_card.dart';
import '../patients/patient_models.dart';
import '../patients/patients_api_service.dart';

typedef _Data = (
  List<Map<String, dynamic>> transfers,
  List<Map<String, dynamic>> joins,
  List<PendingAccessRequest> tickets,
  List<Map<String, dynamic>> review,
  List<Map<String, dynamic>> dentists,
);

/// My lab tabs, for deep links into [LabPage].
abstract final class LabTab {
  static const dentists = 0, requests = 1, transfers = 2, sharing = 3;
}

String _patientName(Map<String, dynamic> p) => '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();

/// Lab home in the admin dashboard's look: what waits on the lab (transfers,
/// join requests, sharing tickets, cases to review), its dentists and quick
/// chat. Fits one iPad screen; scrolls on a phone.
class LabDashboardPage extends StatelessWidget {
  const LabDashboardPage({super.key, required this.api, required this.onOpen, this.onWaiting, this.active = true});

  /// How many items wait on the lab, after each load (the My lab badge).
  final ValueChanged<int>? onWaiting;

  final ApiClient api;
  final void Function(AppNavItem page, int tab) onOpen;
  final bool active;

  static const _gap = 16.0;
  static const _tileH = 128.0;

  String get _labId => api.userId ?? '';

  Future<_Data> _load() async {
    final r = await Future.wait<Object>([
      api.labTransfers(_labId),
      api.labRequests(_labId),
      PatientsApiService(api).listPendingAccessRequests(forceRefresh: true),
      api.listPatients(status: 'in_review', forceRefresh: true),
      api.labDentists(_labId),
    ]);
    final transfers = (r[0] as List<Map<String, dynamic>>).where((t) => t['waiting_on_us'] == true).toList();
    final joins = (r[1] as List<Map<String, dynamic>>).where((j) => j['kind'] == 'join' && j['status'] == 'pending').toList();
    final tickets = r[2] as List<PendingAccessRequest>;
    final waiting = transfers.length + joins.length + tickets.length;
    // Parent setState must not run while AdminFuture is still building.
    final notify = onWaiting;
    if (notify != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => notify(waiting));
    }
    return (
      transfers,
      joins,
      tickets,
      r[3] as List<Map<String, dynamic>>,
      (r[4] as List<Map<String, dynamic>>).where((d) => d['deleted'] != true).toList(),
    );
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
                    hint: loc.tr('labDash.searchHint'),
                    page: (chrome) => _LabSearchPage(chrome: chrome),
                  ),
                ),
                if (c.maxWidth >= 720) ...[const SizedBox(width: 12), const AdminDateChip()],
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
                  ? [SliverToBoxAdapter(child: _greeting(loc, compact: false)), SliverToBoxAdapter(child: _narrow(context, loc, d))]
                  : [
                      // One screen tall: never scrolls, only bounces to refresh.
                      SliverLayoutBuilder(
                        builder: (context, sc) => SliverToBoxAdapter(
                          child: SizedBox(
                            height: sc.viewportMainAxisExtent,
                            child: LayoutBuilder(
                              builder: (context, c) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _greeting(loc, compact: c.maxHeight < 820),
                                  Expanded(child: _fit(context, loc, d, landscape: c.maxWidth > c.maxHeight)),
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
    final key = h < 12 ? 'admin.hiMorning' : (h < 18 ? 'admin.hiAfternoon' : 'admin.hiEvening');
    final name = (api.userName ?? '').trim();
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 12 : 16, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.trp(key, {'name': name.isEmpty ? loc.roleLab : name}),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.style(fontSize: compact ? 21 : 24, fontWeight: FontWeight.w700, color: AppColors.navy, letterSpacing: -0.5),
          ),
          if (!compact)
            Text(
              loc.tr('labDash.sub'),
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
      for (final (i, w) in cells.indexed) ...[if (i > 0) const SizedBox(width: _gap), Expanded(child: w)],
    ],
  );

  /// iPad: tiles, then action/review, then dentists/chat. Landscape gives the
  /// first panel row more room; portrait splits evenly.
  Widget _fit(BuildContext context, AppLocalizations loc, _Data d, {required bool landscape}) {
    return LayoutBuilder(
      builder: (context, c) {
        final tileH = (c.maxHeight * 0.15).clamp(112.0, 128.0);
        return Column(
          children: [
            SizedBox(
              height: tileH,
              child: _tiles(loc, d, cols: 4, height: tileH),
            ),
            const SizedBox(height: _gap),
            Expanded(
              flex: landscape ? 6 : 5,
              child: _row([
                AdminAppear(index: 4, child: _action(context, loc, d)),
                AdminAppear(index: 5, child: _review(context, loc, d.$4)),
              ]),
            ),
            const SizedBox(height: _gap),
            Expanded(
              flex: 5,
              child: _row([
                AdminAppear(index: 6, child: _dentists(context, loc, d.$5)),
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
          child: _tiles(loc, d, cols: 2, height: _tileH),
        ),
        const SizedBox(height: _gap),
        AdminAppear(index: 4, child: _action(context, loc, d, fill: false)),
        const SizedBox(height: _gap),
        AdminAppear(index: 5, child: _review(context, loc, d.$4, fill: false)),
        const SizedBox(height: _gap),
        AdminAppear(index: 6, child: _dentists(context, loc, d.$5, fill: false)),
        const SizedBox(height: _gap),
        AdminAppear(index: 7, child: QuickChatCard(fill: false, active: active)),
      ],
    );
  }

  (String, Color) _pill(AppLocalizations loc, int n) =>
      n > 0 ? (loc.tr('admin.pill.review'), AppColors.warning) : (loc.tr('admin.pill.clear'), AppColors.success);

  Widget _tiles(AppLocalizations loc, _Data d, {required int cols, required double height}) {
    final (transfers, joins, tickets, review, _) = d;
    final tiles = [
      KpiTile(
        icon: Icons.swap_horiz_rounded,
        label: loc.tr('labDash.tile.transfers'),
        value: transfers.length,
        tint: AppColors.warning,
        pill: _pill(loc, transfers.length),
        onTap: () => onOpen(AppNavItem.lab, LabTab.transfers),
      ),
      KpiTile(
        icon: Icons.person_add_alt_1_rounded,
        label: loc.tr('labDash.tile.joins'),
        value: joins.length,
        tint: AppColors.dentalBlue,
        pill: _pill(loc, joins.length),
        onTap: () => onOpen(AppNavItem.lab, LabTab.requests),
      ),
      KpiTile(
        icon: Icons.verified_user_outlined,
        label: loc.tr('labDash.tile.tickets'),
        value: tickets.length,
        tint: AppColors.review,
        pill: _pill(loc, tickets.length),
        onTap: () => onOpen(AppNavItem.lab, LabTab.sharing),
      ),
      KpiTile(
        icon: Icons.fact_check_outlined,
        label: loc.tr('labDash.tile.review'),
        value: review.length,
        tint: AppColors.success,
        pill: _pill(loc, review.length),
        onTap: () => onOpen(AppNavItem.review, 0),
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

  /// Everything waiting on the lab, one row per item, newest kind first.
  Widget _action(BuildContext context, AppLocalizations loc, _Data d, {bool fill = true}) {
    final (transfers, joins, tickets, _, _) = d;
    final rows = <(IconData, Color, String, String, int)>[
      for (final t in transfers)
        (Icons.swap_horiz_rounded, AppColors.warning, '${t['patient_name'] ?? '—'}', loc.tr('labDash.row.transfer'), LabTab.transfers),
      for (final j in joins)
        (
          Icons.person_add_alt_1_rounded,
          AppColors.dentalBlue,
          '${(j['dentist'] is Map ? (j['dentist'] as Map)['name'] : null) ?? '—'}',
          loc.tr('labDash.row.join'),
          LabTab.requests,
        ),
      for (final r in tickets)
        (
          Icons.verified_user_outlined,
          AppColors.review,
          r.patientName,
          loc.trp('labDash.row.ticket', {'from': r.requestingUserName, 'to': r.targetUserName}),
          LabTab.sharing,
        ),
    ];
    return PanelCard(
      fill: fill,
      title: loc.tr('labDash.action'),
      subtitle: plural(loc, 'admin.waitingCount', rows.length),
      action: (loc.tr('admin.seeAll'), () => onOpen(AppNavItem.lab, rows.isEmpty ? LabTab.transfers : rows.first.$5)),
      child: rows.isEmpty
          ? PanelEmpty(icon: Icons.verified_rounded, color: AppColors.success, text: loc.tr('labDash.actionNone'))
          : _list(fill, [
              for (final (icon, color, title, sub, tab) in rows)
                _PanelRow(
                  leading: AdminIcon(icon: icon, color: color, size: 38),
                  title: title,
                  sub: sub,
                  onTap: () => onOpen(AppNavItem.lab, tab),
                ),
            ]),
    );
  }

  Widget _review(BuildContext context, AppLocalizations loc, List<Map<String, dynamic>> rows, {bool fill = true}) {
    return PanelCard(
      fill: fill,
      title: loc.tr('labDash.review'),
      subtitle: plural(loc, 'admin.waitingCount', rows.length),
      action: (loc.tr('admin.seeAll'), () => onOpen(AppNavItem.review, 0)),
      child: rows.isEmpty
          ? PanelEmpty(icon: Icons.task_alt_rounded, color: AppColors.success, text: loc.tr('review.empty'))
          : _list(fill, [
              for (final p in rows.take(8))
                _PanelRow(
                  leading: UserAvatar(name: _patientName(p), size: 36),
                  title: _patientName(p).isEmpty ? '—' : _patientName(p),
                  sub: [
                    if (DateTime.tryParse('${p['updated_at'] ?? ''}') case final at?)
                      loc.trp('admin.updated', {'when': adminWhen(context, at.toLocal())}),
                  ].join(),
                  onTap: () => onOpen(AppNavItem.review, 0),
                ),
            ]),
    );
  }

  Widget _dentists(BuildContext context, AppLocalizations loc, List<Map<String, dynamic>> rows, {bool fill = true}) {
    return PanelCard(
      fill: fill,
      title: loc.tr('labDash.dentists'),
      subtitle: dentistCount(loc, rows.length),
      action: (loc.tr('admin.seeAll'), () => onOpen(AppNavItem.lab, LabTab.dentists)),
      child: rows.isEmpty
          ? PanelEmpty(icon: Icons.medical_services_outlined, color: AppColors.muted, text: loc.tr('lab.noDentists'))
          : _list(fill, [
              for (final d in rows.take(8))
                _PanelRow(
                  leading: UserAvatar(name: '${d['name'] ?? ''}', url: d['avatar_url']?.toString(), size: 36),
                  title: '${d['name'] ?? d['email'] ?? '—'}',
                  sub: '${d['clinic_name'] ?? ''}',
                  onTap: () => onOpen(AppNavItem.lab, LabTab.dentists),
                ),
            ]),
    );
  }

  /// Scrolls inside a fixed card; a plain column when the card hugs it.
  Widget _list(bool fill, List<Widget> rows) {
    final items = [
      for (final (i, r) in rows.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AdminAppear(index: i, child: r),
        ),
    ];
    return fill ? ListView(padding: EdgeInsets.zero, children: items) : Column(children: items);
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({required this.leading, required this.title, required this.sub, required this.onTap});

  final Widget leading;
  final String title, sub;
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
                    style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(fontSize: 12.5, color: AppColors.muted),
                    ),
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

/// Search the lab's own dentists and patients; grows out of the top bar.
class _LabSearchPage extends StatefulWidget {
  const _LabSearchPage({required this.chrome});

  final AdminChrome chrome;

  @override
  State<_LabSearchPage> createState() => _LabSearchPageState();
}

class _LabSearchPageState extends State<_LabSearchPage> {
  String _q = '';

  ApiClient get api => widget.chrome.api;

  // ponytail: loads all and filters on device, like the admin search.
  late final _data = Future.wait([api.labDentists(api.userId ?? ''), api.listPatients(forceRefresh: true)]);

  bool _hit(Object? s) => '${s ?? ''}'.toLowerCase().contains(_q);

  void _go(AppNavItem page, int tab) {
    Navigator.pop(context);
    widget.chrome.onOpen(page, tab);
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
                      placeholder: loc.tr('labDash.searchHint'),
                      style: AppFonts.style(fontSize: 16, color: AppColors.navy),
                      backgroundColor: AppColors.card,
                      borderRadius: BorderRadius.circular(23),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: 14),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      loc.cancel,
                      style: AppFonts.style(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.dentalBlue),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<List<List<Map<String, dynamic>>>>(
                  future: _data,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return AdminEmpty(
                        icon: Icons.cloud_off_rounded,
                        title: loc.tr('admin.loadFailed'),
                        subtitle: friendlyError(snap.error!),
                      );
                    }
                    if (!snap.hasData) return const ToothPageLoader(inPlace: true);
                    final dentists = snap.data![0].where((d) => _hit(d['name']) || _hit(d['email']) || _hit(d['clinic_name'])).toList();
                    final patients = snap.data![1].where((p) => _hit(_patientName(p))).toList();
                    if (dentists.isEmpty && patients.isEmpty) {
                      return AdminEmpty(
                        icon: Icons.search_off_rounded,
                        title: loc.tr('admin.noMatches'),
                        subtitle: loc.tr('admin.noMatchesSub'),
                      );
                    }
                    return ListView(
                      children: [
                        for (final d in dentists)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AdminCard(
                              onTap: () => _go(AppNavItem.lab, LabTab.dentists),
                              padding: const EdgeInsets.all(12),
                              child: AdminRow(
                                leading: UserAvatar(name: '${d['name'] ?? ''}', url: d['avatar_url']?.toString(), size: 38),
                                title: '${d['name'] ?? d['email'] ?? '—'}',
                                badges: [AdminBadge(loc.roleDentist, color: AppColors.dentalBlue)],
                                lines: ['${d['clinic_name'] ?? d['email'] ?? ''}'],
                              ),
                            ),
                          ),
                        for (final p in patients)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AdminCard(
                              onTap: () => _go(AppNavItem.patients, 0),
                              padding: const EdgeInsets.all(12),
                              child: AdminRow(
                                leading: UserAvatar(name: _patientName(p), size: 38),
                                title: _patientName(p).isEmpty ? '—' : _patientName(p),
                                badges: [StatusChip(statusKey: '${p['status'] ?? ''}')],
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

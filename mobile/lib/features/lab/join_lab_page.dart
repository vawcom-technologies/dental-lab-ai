import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_coordinator.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/date_formats.dart';
import '../../core/layout/adaptive.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/ui_kit.dart';
import '../settings/settings_page.dart';
import 'bring_patients_sheet.dart';

/// Lab picker for dentists without a lab: request to join, wait for accept,
/// or **Request later** to use the app without a lab. Rechecks /me on resume;
/// [onReady] fires once they have a lab or deferred joining.
class JoinLabPage extends StatefulWidget {
  const JoinLabPage({super.key, required this.api, required this.onReady});

  final ApiClient api;
  final VoidCallback onReady;

  @override
  State<JoinLabPage> createState() => _JoinLabPageState();
}

class _JoinLabPageState extends State<JoinLabPage> with WidgetsBindingObserver {
  bool _checking = true;
  String _q = '';
  late Future<List<Map<String, dynamic>>> _labs = widget.api.searchLabs();

  ApiClient get api => widget.api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recheck();
  }

  /// Fresh /me: a lab may have accepted or declined meanwhile.
  Future<void> _recheck() async {
    setState(() => _checking = true);
    try {
      await api.fetchMe(forceRefresh: true);
      if (!mounted) return;
      // Ready when they have a lab, or chose Request later.
      if (!api.needsLab) return widget.onReady();
    } catch (e) {
      // The lab list still works; say why the status couldn't be checked.
      if (mounted) AppSnackBars.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _join(Map<String, dynamic> lab) async {
    final loc = AppLocalizations.of(context);
    final name = '${lab['name'] ?? ''}';
    final ok = await AppDialogs.confirm(
      context,
      title: loc.trp('join.confirmTitle', {'lab': name}),
      message: loc.tr('join.confirmMsg'),
      confirmLabel: loc.tr('join.request'),
    );
    if (!ok || !mounted) return;
    final bring = await pickPatientsToBring(
      context,
      api,
      title: loc.tr('join.bringTitle'),
      message: loc.tr('join.bringMsg'),
    );
    if (bring == null || !mounted) return;
    // 409 (already pending / already in a lab): the message says which; /me
    // then shows the real state either way.
    await adminRun(
      context,
      () => api.requestJoinLab('${lab['id']}', patientIds: bring),
      done: loc.trp('join.sent', {'lab': name}),
    );
    await _recheck();
  }

  Future<void> _requestLater() async {
    final loc = AppLocalizations.of(context);
    final ok = await AppDialogs.confirm(
      context,
      title: loc.tr('join.requestLaterTitle'),
      message: loc.tr('join.requestLaterMsg'),
      confirmLabel: loc.tr('join.requestLater'),
    );
    if (!ok || !mounted) return;
    final done = await adminRun(context, api.deferLabJoin, done: loc.tr('join.requestLaterDone'));
    if (done && mounted) widget.onReady();
  }

  Future<void> _withdraw() async {
    final loc = AppLocalizations.of(context);
    final ok = await AppDialogs.confirm(
      context,
      title: loc.tr('join.withdrawTitle'),
      message: loc.tr('join.withdrawMsg'),
      confirmLabel: loc.tr('join.withdraw'),
      isDestructive: true,
    );
    if (!ok || !mounted) return;
    await adminRun(context, api.withdrawJoinRequest, done: loc.tr('join.withdrawn'));
    await _recheck();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final pending = api.pendingJoin;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: AdminPage(
              icon: Icons.apartment_rounded,
              title: loc.tr('join.title'),
              subtitle: loc.tr('join.sub'),
              actions: [
                AppButtons.icon(
                  tooltip: loc.refresh,
                  onPressed: _checking ? null : _recheck,
                  icon: Icons.refresh_rounded,
                  busy: _checking,
                ),
                AppButtons.icon(
                  tooltip: loc.navSettings,
                  onPressed: () => Navigator.of(context).push(AppPageRoutes.cupertino(
                    Scaffold(backgroundColor: AppColors.surface, body: SafeArea(child: SettingsPage(api: api))),
                  )),
                  icon: Icons.settings_outlined,
                ),
                AppButtons.icon(
                  tooltip: loc.signOut,
                  onPressed: () => SessionCoordinator.signOut(api),
                  icon: Icons.logout_rounded,
                ),
              ],
              toolbar: [
                if (pending == null)
                  AdminSearchField(
                    hint: loc.tr('admin.searchLabs'),
                    onChanged: (q) {
                      setState(() {
                        _q = q;
                        _labs = api.searchLabs(q: q);
                      });
                    },
                  ),
              ],
              body: AnimatedSwitcher(
                duration: AppMotion.page,
                switchInCurve: AppMotion.spring,
                child: pending != null
                    ? _Waiting(key: const ValueKey('wait'), pending: pending, onWithdraw: _withdraw, onCheck: _recheck)
                    : _list(loc),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(AppLocalizations loc) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('labs|$_q'),
      future: _labs,
      builder: (context, snap) {
        if (snap.hasError) {
          return AdminEmpty(
            icon: Icons.cloud_off_rounded,
            title: loc.tr('admin.loadFailed'),
            subtitle: friendlyError(snap.error!),
            action: AppButtons.secondary(
              onPressed: () => setState(() => _labs = api.searchLabs(q: _q)),
              label: loc.tr('admin.retry'),
            ),
          );
        }
        if (!snap.hasData) return const ToothPageLoader();
        final labs = snap.data!;
        if (labs.isEmpty) {
          return Column(
            children: [
              Expanded(
                child: AdminEmpty(
                  icon: Icons.search_off_rounded,
                  title: loc.tr(_q.isEmpty ? 'join.noLabs' : 'admin.noMatches'),
                  subtitle: loc.tr(_q.isEmpty ? 'join.noLabsSub' : 'admin.noMatchesSub'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AppButtons.ghost(
                  onPressed: _checking ? null : _requestLater,
                  icon: Icons.schedule_rounded,
                  label: loc.tr('join.requestLater'),
                ),
              ),
            ],
          );
        }
        return IpadRefresh(
          onRefresh: () async {
            setState(() => _labs = api.searchLabs(q: _q));
            await _labs;
          },
          slivers: [
            adminSliverList<Map<String, dynamic>>(
              labs,
              id: (l) => '${l['id']}',
              (context, l) {
                final name = '${l['name'] ?? ''}';
                return AdminCard(
                  child: AdminRow(
                    leading: UserAvatar(name: name, url: l['avatar_url']?.toString(), size: 44),
                    title: name,
                    actions: [
                      AppButtons.primary(
                        onPressed: () => _join(l),
                        icon: Icons.person_add_alt_1_rounded,
                        label: loc.tr('join.request'),
                        compact: true,
                      ),
                    ],
                  ),
                );
              },
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                child: Center(
                  child: AppButtons.ghost(
                    onPressed: _checking ? null : _requestLater,
                    icon: Icons.schedule_rounded,
                    label: loc.tr('join.requestLater'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "Waiting for <lab> to accept" with Withdraw.
class _Waiting extends StatelessWidget {
  const _Waiting({super.key, required this.pending, required this.onWithdraw, required this.onCheck});

  final Map<String, dynamic> pending;
  final VoidCallback onWithdraw;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final lab = '${pending['lab_name'] ?? ''}';
    final at = DateTime.tryParse('${pending['created_at'] ?? ''}')?.toLocal();
    return Align(
      alignment: Alignment.topCenter,
      child: AdminCard(
        padding: EdgeInsets.all(AppBreakpoints.isPhone(context) ? 20 : 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AdminIcon(icon: Icons.hourglass_top_rounded, color: AppColors.warning, size: 64),
            const SizedBox(height: 16),
            Text(
              loc.trp('join.waiting', {'lab': lab}),
              textAlign: TextAlign.center,
              style: AppFonts.style(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.navy, letterSpacing: -0.3),
            ),
            const SizedBox(height: 6),
            Text(
              [loc.tr('join.waitingSub'), if (at != null) loc.trp('join.sentAt', {'when': formatAppDateTime(context, at)})].join('\n'),
              textAlign: TextAlign.center,
              style: AppFonts.style(fontSize: 14, height: 1.4, color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                AppButtons.danger(onPressed: onWithdraw, icon: Icons.undo_rounded, label: loc.tr('join.withdraw'), soft: true, compact: true),
                AppButtons.secondary(onPressed: onCheck, icon: Icons.refresh_rounded, label: loc.tr('join.checkAgain'), compact: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

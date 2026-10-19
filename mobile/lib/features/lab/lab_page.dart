import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import '../../core/widgets/page_kit.dart';
import '../patients/patient_models.dart';
import '../patients/patients_api_service.dart';
import 'lab_pickers.dart';
import 'transfer_text.dart';

/// The signed-in lab's hub: its dentists, join / removal requests, transfers
/// between labs, sharing tickets and visibility settings.
class LabPage extends StatefulWidget {
  const LabPage({
    super.key,
    required this.api,
    required this.onOpenPatient,
    this.tab,
    this.active = true,
  });

  /// Selected tab, owned by the shell so the dashboard can deep-link.
  final ValueNotifier<int>? tab;

  final ApiClient api;

  /// Opens a patient's detail (Patients page) — e.g. one waiting on us.
  final ValueChanged<String> onOpenPatient;
  final bool active;

  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> {
  late final _own = widget.tab == null ? ValueNotifier(0) : null;
  ValueNotifier<int> get _tab => widget.tab ?? _own!;

  ApiClient get api => widget.api;
  String get labId => api.userId ?? '';

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: _tab,
      builder: (context, t, _) => AdminPage(
        icon: Icons.apartment_rounded,
        title: loc.tr('lab.title'),
        subtitle: loc.tr('lab.sub'),
        toolbar: [
          AdminTabs(
            tab: _tab,
            labels: [
              loc.tr('lab.tab.dentists'),
              loc.tr('lab.tab.requests'),
              loc.tr('lab.tab.transfers'),
              loc.tr('lab.tab.sharing'),
              loc.tr('lab.tab.settings'),
            ],
          ),
        ],
        body: AdminSwap(
          index: t,
          builder: (i) {
            final on = widget.active && i == t;
            return switch (i) {
              0 => _dentists(loc, on),
              1 => _requests(loc, on),
              2 => _transfers(loc, on),
              3 => _sharing(loc, on),
              _ => _LabSettings(api: api, labId: labId),
            };
          },
        ),
      ),
    );
  }

  // ── Dentists ─────────────────────────────────────────────────────────────

  Future<bool> _requestRemoval(Map<String, dynamic> d) async {
    final loc = AppLocalizations.of(context);
    final name = '${d['name'] ?? ''}';
    final reason = await askRequiredText(
      context,
      title: loc.trp('lab.removeTitle', {'name': name}),
      message: loc.tr('lab.removeMsg'),
      hint: loc.tr('lab.reasonRequired'),
      confirmLabel: loc.tr('lab.requestRemoval'),
      destructive: true,
    );
    if (reason == null || !mounted) return false;
    // 409: one is already pending (the server says so).
    return adminRun(
      context,
      () => api.labRequestRemoval(labId, dentistId: '${d['id']}', reason: reason),
      done: loc.trp('lab.removalSent', {'name': name}),
    );
  }

  Widget _dentists(AppLocalizations loc, bool on) {
    return AdminFuture<List<Map<String, dynamic>>>(
      key: const ValueKey('dentists'),
      active: on,
      load: () => api.labDentists(labId),
      empty: AdminEmpty(
        icon: Icons.medical_services_outlined,
        title: loc.tr('lab.noDentists'),
        subtitle: loc.tr('lab.noDentistsSub'),
      ),
      builder: (context, rows, reload) => [
        adminSliverList<Map<String, dynamic>>(
          rows,
          id: (d) => '${d['id']}',
          (context, d) {
            final name = '${d['name'] ?? ''}';
            final deleted = d['deleted'] == true;
            return AdminCard(
              child: AdminRow(
                leading: UserAvatar(name: name, url: d['avatar_url']?.toString(), size: 42),
                title: name.isEmpty ? '${d['email'] ?? '—'}' : name,
                badges: [
                  if (deleted) AdminBadge(loc.tr('admin.deactivatedBadge'), color: AppColors.danger),
                ],
                lines: [
                  [?_str(d['clinic_name']), ?_str(d['email']), ?_str(d['phone'])].join(' · '),
                ],
                actions: [
                  if (!deleted)
                    AppButtons.danger(
                      onPressed: () async {
                        if (await _requestRemoval(d)) reload();
                      },
                      icon: Icons.person_remove_outlined,
                      label: loc.tr('lab.requestRemoval'),
                      soft: true,
                      compact: true,
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Requests ─────────────────────────────────────────────────────────────

  Widget _statusBadge(AppLocalizations loc, String status) => AdminBadge(
        loc.tr('lab.status.$status'),
        color: switch (status) {
          'pending' => AppColors.warning,
          'approved' => AppColors.success,
          'rejected' => AppColors.danger,
          _ => AppColors.muted,
        },
      );

  Widget _requests(AppLocalizations loc, bool on) {
    return AdminFuture<List<Map<String, dynamic>>>(
      key: const ValueKey('requests'),
      active: on,
      load: () => api.labRequests(labId),
      empty: AdminEmpty(
        icon: Icons.inbox_outlined,
        title: loc.tr('lab.noRequests'),
        subtitle: loc.tr('lab.noRequestsSub'),
      ),
      builder: (context, rows, reload) {
        // Pending joins first; then everything else, newest first.
        final joins = rows.where((r) => r['kind'] == 'join').toList()
          ..sort((a, b) => (a['status'] == 'pending' ? 0 : 1).compareTo(b['status'] == 'pending' ? 0 : 1));
        final removals = rows.where((r) => r['kind'] == 'remove').toList();
        Widget card(Map<String, dynamic> r) {
          final d = r['dentist'] is Map ? Map<String, dynamic>.from(r['dentist'] as Map) : <String, dynamic>{};
          final name = '${d['name'] ?? ''}';
          final pending = r['status'] == 'pending';
          final join = r['kind'] == 'join';
          return AdminCard(
            child: AdminRow(
              leading: UserAvatar(name: name, url: d['avatar_url']?.toString(), size: 42),
              title: name.isEmpty ? '—' : name,
              badges: [_statusBadge(loc, '${r['status']}')],
              lines: [
                [?_str(d['clinic_name']), ?_str(d['email'])].join(' · '),
                if (_str(r['reason']) case final reason?) '${loc.tr('admin.reason')}: $reason',
                adminWhen(context, DateTime.tryParse('${r['created_at'] ?? ''}')?.toLocal()),
              ],
              actions: [
                if (join && pending) ...[
                  AppButtons.secondary(
                    onPressed: () async {
                      final ok = await adminRun(context, () => api.labDecideJoin(labId, '${r['id']}', accept: false),
                          done: loc.trp('lab.joinRejected', {'name': name}));
                      if (ok) reload();
                    },
                    label: loc.tr('admin.reject'),
                    compact: true,
                  ),
                  AppButtons.primary(
                    onPressed: () async {
                      final ok = await adminRun(context, () => api.labDecideJoin(labId, '${r['id']}', accept: true),
                          done: loc.trp('lab.joinAccepted', {'name': name}));
                      if (ok) reload();
                    },
                    icon: Icons.check_rounded,
                    label: loc.tr('lab.accept'),
                    compact: true,
                  ),
                ],
              ],
            ),
          );
        }

        return [
          if (joins.isNotEmpty) ...[
            _header(loc.tr('lab.joinRequests')),
            adminSliverList(joins, id: (r) => 'j${r['id']}', (context, r) => card(r)),
          ],
          if (removals.isNotEmpty) ...[
            _header(loc.tr('lab.ourRemovals')),
            adminSliverList(removals, id: (r) => 'r${r['id']}', (context, r) => card(r)),
          ],
        ];
      },
    );
  }

  // ── Transfers ────────────────────────────────────────────────────────────

  Future<bool> _rejectTransfer(Map<String, dynamic> t) async {
    final loc = AppLocalizations.of(context);
    final reason = await AppDialogs.prompt(
      context,
      title: loc.trp('lab.rejectTransferTitle', {'p': '${t['patient_name'] ?? ''}'}),
      placeholder: loc.tr('admin.reasonOptional'),
      confirmLabel: loc.tr('admin.reject'),
      maxLines: 3,
    );
    if (reason == null || !mounted) return false;
    return adminRun(
      context,
      () => api.transferReject('${t['id']}', reason: reason.trim().isEmpty ? null : reason.trim()),
      done: loc.tr('lab.transferRejected'),
    );
  }

  Future<bool> _acceptTransfer(Map<String, dynamic> t) async {
    final loc = AppLocalizations.of(context);
    final d = await pickLabDentist(context, api,
        title: loc.tr('lab.acceptTransfer'),
        message: loc.trp('lab.acceptTransferMsg', {'p': '${t['patient_name'] ?? ''}'}));
    if (d == null || !mounted) return false;
    return adminRun(
      context,
      () => api.transferAccept('${t['id']}', dentistId: d.id),
      done: loc.trp('lab.transferAccepted', {'p': '${t['patient_name'] ?? ''}', 'd': d.name}),
    );
  }

  Widget _transfers(AppLocalizations loc, bool on) {
    return AdminFuture<List<Map<String, dynamic>>>(
      key: const ValueKey('transfers'),
      active: on,
      load: () async => (await api.labTransfers(labId))
        // Ours to act on first, then newest first.
        ..sort((a, b) {
          final w = (b['waiting_on_us'] == true ? 1 : 0) - (a['waiting_on_us'] == true ? 1 : 0);
          return w != 0 ? w : '${b['created_at']}'.compareTo('${a['created_at']}');
        }),
      empty: AdminEmpty(
        icon: Icons.swap_horiz_rounded,
        title: loc.tr('lab.noTransfers'),
        subtitle: loc.tr('lab.noTransfersSub'),
      ),
      builder: (context, rows, reload) => [
        adminSliverList<Map<String, dynamic>>(
          rows,
          id: (t) => '${t['id']}',
          (context, t) {
            final status = '${t['status']}';
            final waiting = t['waiting_on_us'] == true;
            String lab(Object? l) => l is Map ? '${l['name'] ?? '—'}' : '—';
            return AdminCard(
              selected: waiting,
              child: AdminRow(
                leading: AdminIcon(
                  icon: t['kind'] == 'handover' ? Icons.move_down_rounded : Icons.share_outlined,
                  color: waiting ? AppColors.warning : AppColors.dentalBlue,
                ),
                title: '${t['patient_name'] ?? '—'}',
                badges: [
                  AdminBadge(loc.tr('lab.kind.${t['kind']}'), color: AppColors.review),
                  AdminBadge(loc.tr('lab.transfer.$status'),
                      color: waiting ? AppColors.warning : status == 'accepted' ? AppColors.success : AppColors.muted),
                ],
                lines: [
                  // A sentence from our side, not "Lab A → Lab B".
                  transferSentence(loc, t, labId),
                  adminWhen(context, DateTime.tryParse('${t['created_at'] ?? ''}')?.toLocal()),
                  if (_str(t['reason']) case final reason?) '${loc.tr('admin.reason')}: $reason',
                ],
                actions: [
                  if (waiting) ...[
                    AppButtons.ghost(
                      onPressed: () => widget.onOpenPatient('${t['patient_id']}'),
                      icon: Icons.person_search_outlined,
                      label: loc.tr('lab.openPatient'),
                      compact: true,
                    ),
                    AppButtons.secondary(
                      onPressed: () async {
                        if (await _rejectTransfer(t)) reload();
                      },
                      label: loc.tr('admin.reject'),
                      compact: true,
                    ),
                    if (status == 'awaiting_sender')
                      AppButtons.primary(
                        onPressed: () async {
                          final ok = await adminRun(context, () => api.transferForward('${t['id']}'),
                              done: loc.trp('lab.forwarded', {'lab': lab(t['to_lab'])}));
                          if (ok) reload();
                        },
                        icon: Icons.send_rounded,
                        label: loc.tr('lab.forward'),
                        compact: true,
                      ),
                    if (status == 'awaiting_recipient')
                      AppButtons.primary(
                        onPressed: () async {
                          if (await _acceptTransfer(t)) reload();
                        },
                        icon: Icons.check_rounded,
                        label: loc.tr('lab.accept'),
                        compact: true,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Sharing tickets ──────────────────────────────────────────────────────

  Widget _sharing(AppLocalizations loc, bool on) {
    final service = PatientsApiService(api);
    return AdminFuture<List<PendingAccessRequest>>(
      key: const ValueKey('sharing'),
      active: on,
      load: () => service.listPendingAccessRequests(forceRefresh: true),
      empty: AdminEmpty(
        icon: Icons.verified_user_outlined,
        title: loc.tr('lab.noTickets'),
        subtitle: loc.tr('lab.noTicketsSub'),
      ),
      builder: (context, rows, reload) => [
        adminSliverList<PendingAccessRequest>(
          rows,
          id: (r) => r.id,
          (context, r) {
            Future<void> decide(bool approve) async {
              final ok = await adminRun(
                context,
                () => service.resolveAccessRequest(requestId: r.id, action: approve ? 'approve' : 'reject'),
                done: loc.tr(approve ? 'lab.ticketApproved' : 'lab.ticketRejected'),
              );
              if (ok) reload();
            }

            return AdminCard(
              child: AdminRow(
                leading: const AdminIcon(icon: Icons.share_outlined),
                title: r.patientName,
                lines: [
                  loc.trp('lab.ticketLine', {'from': r.requestingUserName, 'to': r.targetUserName}),
                  adminWhen(context, r.createdAt?.toLocal()),
                ],
                actions: [
                  AppButtons.ghost(
                    onPressed: () => widget.onOpenPatient(r.patientId),
                    icon: Icons.person_search_outlined,
                    label: loc.tr('lab.openPatient'),
                    compact: true,
                  ),
                  AppButtons.secondary(onPressed: () => decide(false), label: loc.tr('admin.reject'), compact: true),
                  AppButtons.primary(
                    onPressed: () => decide(true),
                    icon: Icons.check_rounded,
                    label: loc.tr('admin.approve'),
                    compact: true,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _header(String text) => SliverToBoxAdapter(
        child: Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 10), child: SectionLabel(text)),
      );
}

String? _str(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// Hide-settings with what each one does.
class _LabSettings extends StatefulWidget {
  const _LabSettings({required this.api, required this.labId});

  final ApiClient api;
  final String labId;

  @override
  State<_LabSettings> createState() => _LabSettingsState();
}

class _LabSettingsState extends State<_LabSettings> {
  bool? _hidden, _hideDentists;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _apply(widget.api.labSettings(widget.labId));
  }

  Future<void> _apply(Future<Map<String, dynamic>> call) async {
    try {
      final r = await call;
      if (!mounted) return;
      setState(() {
        _hidden = r['hidden_from_labs'] == true;
        _hideDentists = r['hide_dentists'] == true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      if (_hidden != null) AppSnackBars.error(context, friendlyError(e));
    }
  }

  /// Switch flips at once; on failure the server's values come back.
  Future<void> _set({bool? hidden, bool? hideDentists}) async {
    setState(() {
      _saving = true;
      _hidden = hidden ?? _hidden;
      _hideDentists = hideDentists ?? _hideDentists;
    });
    await _apply(widget.api.updateLabSettings(widget.labId, hiddenFromLabs: hidden, hideDentists: hideDentists));
    if (_error != null) await _apply(widget.api.labSettings(widget.labId));
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (_hidden == null) {
      return _error == null
          ? const ToothPageLoader()
          : AdminEmpty(icon: Icons.cloud_off_rounded, title: loc.tr('admin.loadFailed'), subtitle: friendlyError(_error!));
    }
    Widget row(String title, String body, bool value, ValueChanged<bool> onChanged) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppFonts.style(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy)),
                    const SizedBox(height: 4),
                    Text(body, style: AppFonts.style(fontSize: 13.5, height: 1.4, color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              CupertinoSwitch(value: value, onChanged: _saving ? null : onChanged),
            ],
          ),
        );
    return ListView(
      children: [
        AdminCard(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          child: Column(
            children: [
              row(loc.tr('lab.hideLab'), loc.tr('lab.hideLabMsg'), _hidden!, (v) => _set(hidden: v)),
              Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
              row(loc.tr('lab.hideDentists'), loc.tr('lab.hideDentistsMsg'), _hideDentists!,
                  (v) => _set(hideDentists: v)),
            ],
          ),
        ),
      ],
    );
  }
}

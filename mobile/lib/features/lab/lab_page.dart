import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/split_list.dart';
import '../chat/widgets/quick_chat_card.dart';
import '../patients/patient_models.dart';
import '../patients/patients_api_service.dart';
import 'lab_pickers.dart';
import 'transfer_text.dart';

/// The signed-in lab's hub: its dentists, join / removal requests, transfers
/// between labs and sharing tickets. Visibility settings live on Settings.
class LabPage extends StatefulWidget {
  const LabPage({
    super.key,
    required this.api,
    required this.onOpenPatient,
    this.onWaiting,
    this.tab,
    this.active = true,
  });

  /// Selected tab, owned by the shell so the dashboard can deep-link.
  final ValueNotifier<int>? tab;

  final ApiClient api;

  /// Opens a patient's detail (Patients page) — e.g. one waiting on us.
  final ValueChanged<String> onOpenPatient;

  /// Sidebar badge: transfers + joins + sharing tickets waiting on this lab.
  final ValueChanged<int>? onWaiting;
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
  void initState() {
    super.initState();
    if (widget.active) _refreshWaiting();
  }

  @override
  void didUpdateWidget(covariant LabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refreshWaiting();
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  /// Keep the sidebar lab badge in sync after approve/reject on this page.
  Future<void> _refreshWaiting() async {
    final notify = widget.onWaiting;
    if (notify == null || labId.isEmpty) return;
    try {
      final r = await Future.wait<Object>([
        api.labTransfers(labId),
        api.labRequests(labId),
        PatientsApiService(api).listPendingAccessRequests(forceRefresh: true),
      ]);
      final transfers = (r[0] as List<Map<String, dynamic>>)
          .where((t) => t['waiting_on_us'] == true)
          .length;
      final joins = (r[1] as List<Map<String, dynamic>>)
          .where((j) => j['kind'] == 'join' && j['status'] == 'pending')
          .length;
      final tickets = (r[2] as List<PendingAccessRequest>).length;
      if (mounted) notify(transfers + joins + tickets);
    } catch (_) {}
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
            ],
          ),
        ],
        body: AdminSwap(
          index: t.clamp(0, 3),
          builder: (i) {
            final on = widget.active && i == t;
            return switch (i) {
              0 => _dentists(loc, on),
              1 => _requests(loc, on),
              2 => _transfers(loc, on),
              _ => _sharing(loc, on),
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

  /// Dentist open in the side panel (wide screens).
  Map<String, dynamic>? _dentist;
  VoidCallback? _reloadDentists;

  Widget _dentistPanel(Map<String, dynamic> d, {VoidCallback? close}) => _DentistPanel(
        key: ValueKey('dentist-${d['id']}'),
        api: api,
        dentist: d,
        onOpenPatient: (id) {
          close?.call();
          widget.onOpenPatient(id);
        },
        onRemove: d['deleted'] == true
            ? null
            : () async {
                if (await _requestRemoval(d)) _reloadDentists?.call();
              },
      );

  Widget _dentists(AppLocalizations loc, bool on) {
    return LayoutBuilder(
      builder: (context, box) {
        final split = box.maxWidth >= 860;
        final list = AdminFuture<List<Map<String, dynamic>>>(
          key: const ValueKey('dentists'),
          active: on,
          load: () => api.labDentists(labId),
          empty: AdminEmpty(
            icon: Icons.medical_services_outlined,
            title: loc.tr('lab.noDentists'),
            subtitle: loc.tr('lab.noDentistsSub'),
          ),
          builder: (context, rows, reload) {
            _reloadDentists = reload;
            return [
              adminSliverList<Map<String, dynamic>>(
                rows,
                id: (d) => '${d['id']}',
                gap: 10,
                (context, d) {
                  final name = '${d['name'] ?? ''}';
                  final deleted = d['deleted'] == true;
                  return AdminCard(
                    selected: split && '${d['id']}' == '${_dentist?['id']}',
                    onTap: () {
                      if (split) {
                        setState(() => _dentist = d);
                        return;
                      }
                      AppDialogs.modalSheet<void>(
                        context: context,
                        builder: (ctx) => SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: SizedBox(
                                height: MediaQuery.sizeOf(ctx).height * 0.75,
                                child: _dentistPanel(d, close: () => Navigator.pop(ctx)),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: AdminRow(
                      leading: UserAvatar(name: name, url: d['avatar_url']?.toString(), size: 42),
                      title: name.isEmpty ? '${d['email'] ?? '—'}' : name,
                      badges: [
                        if (deleted) AdminBadge(loc.tr('admin.deactivatedBadge'), color: AppColors.danger),
                      ],
                      lines: [?(_str(d['clinic_name']) ?? _str(d['email']))],
                    ),
                  );
                },
              ),
            ];
          },
        );
        if (!split) return list;
        final d = _dentist;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: list),
            const SizedBox(width: 16),
            Expanded(
              flex: 6,
              child: AppSwitcher(
                child: d == null
                    ? AdminCard(
                        key: const ValueKey('pick'),
                        child: AdminEmpty(
                          icon: Icons.touch_app_outlined,
                          title: loc.tr('lab.pickDentist'),
                          subtitle: loc.tr('lab.pickDentistSub'),
                        ),
                      )
                    : _dentistPanel(d),
              ),
            ),
          ],
        );
      },
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
    return SplitList<Map<String, dynamic>>(
      key: const ValueKey('requests'),
      active: on,
      load: () async {
        final rows = await api.labRequests(labId);
        // Action inbox: pending joins/transfers + all removal requests, grouped.
        const order = {'join': 0, 'transfer': 1, 'remove': 2};
        return [
          for (final r in rows)
            if (r['kind'] == 'remove' ||
                ((r['kind'] == 'join' || r['kind'] == 'transfer') && r['status'] == 'pending'))
              r,
        ]..sort((a, b) => (order[a['kind']] ?? 3).compareTo(order[b['kind']] ?? 3));
      },
      empty: AdminEmpty(
        icon: Icons.inbox_outlined,
        title: loc.tr('lab.noRequests'),
        subtitle: loc.tr('lab.noRequestsSub'),
      ),
      item: (r, reload) {
        final d = r['dentist'] is Map ? Map<String, dynamic>.from(r['dentist'] as Map) : <String, dynamic>{};
        final name = '${d['name'] ?? ''}';
        final pending = r['status'] == 'pending';
        final join = r['kind'] == 'join';
        final transfer = r['kind'] == 'transfer';
        final toName = '${r['to_lab_name'] ?? ''}';
        final bringN = (r['patient_ids'] is List) ? (r['patient_ids'] as List).length : 0;
        final reason = _str(r['reason']);
        final when = adminWhen(context, DateTime.tryParse('${r['created_at'] ?? ''}')?.toLocal());
        return SplitItem(
          id: 'r${r['id']}',
          group: loc.tr(join ? 'lab.joinRequests' : transfer ? 'lab.transferRequests' : 'lab.ourRemovals'),
          leading: (size) => UserAvatar(name: name, url: d['avatar_url']?.toString(), size: size),
          title: name.isEmpty ? '—' : name,
          badges: [
            _statusBadge(loc, '${r['status']}'),
            if (transfer) AdminBadge(loc.tr('lab.transferBadge'), color: AppColors.dentalBlue),
          ],
          lines: [
            [?_str(d['clinic_name']), ?_str(d['email'])].join(' · '),
            if (transfer && toName.isNotEmpty) loc.trp('lab.transferTo', {'lab': toName}),
            if (bringN > 0) loc.trp('lab.bringCount', {'n': '$bringN'}),
            if (reason != null) '${loc.tr('admin.reason')}: $reason',
            when,
          ],
          details: [
            if (_str(d['clinic_name']) case final clinic?) (Icons.storefront_outlined, clinic),
            if (_str(d['email']) case final email?) (Icons.mail_outline_rounded, email),
            if (_str(d['phone']) case final phone?) (Icons.phone_outlined, phone),
            if (transfer && toName.isNotEmpty) (Icons.swap_horiz_rounded, loc.trp('lab.transferTo', {'lab': toName})),
            if (bringN > 0) (Icons.people_outline, loc.trp('lab.bringCount', {'n': '$bringN'})),
            if (reason != null) (Icons.notes_rounded, '${loc.tr('admin.reason')}: $reason'),
            (Icons.schedule_rounded, when),
          ],
          extras: _extras(loc, userId: _str(d['id'])),
          actions: [
            if ((join || transfer) && pending) ...[
              AppButtons.secondary(
                onPressed: () async {
                  final ok = await adminRun(
                    context,
                    () => api.labDecideJoin(labId, '${r['id']}', accept: false),
                    done: transfer
                        ? loc.trp('lab.dentistXferRejected', {'name': name})
                        : loc.trp('lab.joinRejected', {'name': name}),
                  );
                  if (ok) {
                    reload();
                    _refreshWaiting();
                  }
                },
                label: loc.tr('admin.reject'),
                compact: true,
              ),
              AppButtons.primary(
                onPressed: () async {
                  final ok = await adminRun(
                    context,
                    () => api.labDecideJoin(labId, '${r['id']}', accept: true),
                    done: transfer
                        ? loc.trp('lab.dentistXferAccepted', {'name': name})
                        : loc.trp('lab.joinAccepted', {'name': name}),
                  );
                  if (!ok || !mounted) return;
                  _refreshWaiting();
                  if (join) {
                    _tab.value = 0;
                  } else {
                    reload();
                  }
                },
                icon: Icons.check_rounded,
                label: loc.tr('lab.accept'),
                compact: true,
              ),
            ],
          ],
        );
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
    return SplitList<Map<String, dynamic>>(
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
      item: (t, reload) {
        final status = '${t['status']}';
        final waiting = t['waiting_on_us'] == true;
        final reason = _str(t['reason']);
        final when = adminWhen(context, DateTime.tryParse('${t['created_at'] ?? ''}')?.toLocal());
        String lab(Object? l) => l is Map ? '${l['name'] ?? '—'}' : '—';
        final handover = t['kind'] == 'handover';
        return SplitItem(
          id: 't${t['id']}',
          highlight: waiting,
          leading: (size) => AdminIcon(
            icon: handover ? Icons.move_down_rounded : Icons.share_outlined,
            color: waiting ? AppColors.warning : AppColors.dentalBlue,
            size: size,
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
            when,
            if (reason != null) '${loc.tr('admin.reason')}: $reason',
          ],
          details: [
            (Icons.swap_horiz_rounded, transferSentence(loc, t, labId)),
            (Icons.call_made_rounded, lab(t['from_lab'])),
            (Icons.call_received_rounded, lab(t['to_lab'])),
            if (reason != null) (Icons.notes_rounded, '${loc.tr('admin.reason')}: $reason'),
            (Icons.schedule_rounded, when),
          ],
          extras: _extras(loc, patientId: waiting ? _str(t['patient_id']) : null),
          actions: [
            if (waiting) ...[
              AppButtons.secondary(
                onPressed: () async {
                  if (await _rejectTransfer(t)) {
                    reload();
                    _refreshWaiting();
                  }
                },
                label: loc.tr('admin.reject'),
                compact: true,
              ),
              if (status == 'awaiting_sender')
                AppButtons.primary(
                  onPressed: () async {
                    final ok = await adminRun(context, () => api.transferForward('${t['id']}'),
                        done: loc.trp('lab.forwarded', {'lab': lab(t['to_lab'])}));
                    if (ok) {
                      reload();
                      _refreshWaiting();
                    }
                  },
                  icon: Icons.send_rounded,
                  label: loc.tr('lab.forward'),
                  compact: true,
                ),
              if (status == 'awaiting_recipient')
                AppButtons.primary(
                  onPressed: () async {
                    if (await _acceptTransfer(t)) {
                      reload();
                      _refreshWaiting();
                    }
                  },
                  icon: Icons.check_rounded,
                  label: loc.tr('lab.accept'),
                  compact: true,
                ),
            ],
          ],
        );
      },
    );
  }

  // ── Sharing tickets ──────────────────────────────────────────────────────

  Widget _sharing(AppLocalizations loc, bool on) {
    final service = PatientsApiService(api);
    return SplitList<PendingAccessRequest>(
      key: const ValueKey('sharing'),
      active: on,
      load: () => service.listPendingAccessRequests(forceRefresh: true),
      empty: AdminEmpty(
        icon: Icons.verified_user_outlined,
        title: loc.tr('lab.noTickets'),
        subtitle: loc.tr('lab.noTicketsSub'),
      ),
      item: (r, reload) {
        Future<void> decide(bool approve) async {
          final ok = await adminRun(
            context,
            () => service.resolveAccessRequest(requestId: r.id, action: approve ? 'approve' : 'reject'),
            done: loc.tr(approve ? 'lab.ticketApproved' : 'lab.ticketRejected'),
          );
          if (ok) {
            reload();
            _refreshWaiting();
          }
        }

        final when = adminWhen(context, r.createdAt?.toLocal());
        final line = loc.trp('lab.ticketLine', {'from': r.requestingUserName, 'to': r.targetUserName});
        return SplitItem(
          id: 's${r.id}',
          leading: (size) => AdminIcon(icon: Icons.share_outlined, size: size),
          title: r.patientName,
          lines: [line, when],
          details: [
            (Icons.share_outlined, line),
            (Icons.schedule_rounded, when),
          ],
          extras: _extras(loc, patientId: r.patientId, userId: r.requestingUserId),
          actions: [
            AppButtons.secondary(onPressed: () => decide(false), label: loc.tr('admin.reject'), compact: true),
            AppButtons.primary(
              onPressed: () => decide(true),
              icon: Icons.check_rounded,
              label: loc.tr('admin.approve'),
              compact: true,
            ),
          ],
        );
      },
    );
  }

  /// Open patient / Message, when the row has someone to reach.
  List<Widget> _extras(AppLocalizations loc, {String? patientId, String? userId}) => [
        if (patientId != null)
          AppButtons.ghost(
            onPressed: () => widget.onOpenPatient(patientId),
            icon: Icons.person_search_outlined,
            label: loc.tr('lab.openPatient'),
            compact: true,
          ),
        if (userId != null)
          AppButtons.ghost(
            onPressed: () => messageUser(context, userId),
            icon: Icons.chat_bubble_outline_rounded,
            label: loc.tr('case.message'),
            compact: true,
          ),
      ];
}

/// One of the lab's dentists: contact, quick actions and the patients the
/// lab can see from them (tap one to open it).
class _DentistPanel extends StatefulWidget {
  const _DentistPanel({
    super.key,
    required this.api,
    required this.dentist,
    required this.onOpenPatient,
    this.onRemove,
  });

  final ApiClient api;
  final Map<String, dynamic> dentist;
  final ValueChanged<String> onOpenPatient;
  final VoidCallback? onRemove;

  @override
  State<_DentistPanel> createState() => _DentistPanelState();
}

class _DentistPanelState extends State<_DentistPanel> {
  late Future<List<Map<String, dynamic>>> _patients = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final id = '${widget.dentist['id']}';
    final rows = await widget.api.listPatients();
    return [
      for (final p in rows)
        if ('${p['created_by'] ?? ''}' == id) p,
    ]..sort((a, b) => '${b['updated_at'] ?? ''}'.compareTo('${a['updated_at'] ?? ''}'));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final d = widget.dentist;
    final name = '${d['name'] ?? ''}'.trim();
    final id = '${d['id']}';
    final deleted = d['deleted'] == true;
    Widget contact(IconData icon, String? value) => value == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: CopyableText(value, style: AppFonts.style(fontSize: 14, color: AppColors.navy)),
                ),
              ],
            ),
          );

    return AdminCard(
      padding: EdgeInsets.zero,
      child: IpadRefresh(
        onRefresh: () async {
          final next = _load();
          setState(() => _patients = next);
          await next;
        },
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    UserAvatar(name: name, url: d['avatar_url']?.toString(), size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name.isEmpty ? '—' : name,
                              style: AppFonts.style(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.navy)),
                          if (_str(d['clinic_name']) case final clinic?)
                            Text(clinic, style: AppFonts.style(fontSize: 13.5, color: AppColors.muted)),
                          if (deleted) ...[
                            const SizedBox(height: 4),
                            AdminBadge(loc.tr('admin.deactivatedBadge'), color: AppColors.danger),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!deleted)
                      AppButtons.primary(
                        onPressed: () => messageUser(context, id),
                        icon: Icons.chat_bubble_outline_rounded,
                        label: loc.tr('case.message'),
                        compact: true,
                      ),
                    if (widget.onRemove != null)
                      AppButtons.danger(
                        onPressed: widget.onRemove,
                        icon: Icons.person_remove_outlined,
                        label: loc.tr('lab.requestRemoval'),
                        soft: true,
                        compact: true,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                contact(Icons.mail_outline_rounded, _str(d['email'])),
                contact(Icons.phone_outlined, _str(d['phone'])),
                const SizedBox(height: 22),
              ],
            ),
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _patients,
            builder: (context, snap) {
              final rows = snap.data;
              final Widget body;
              if (snap.hasError) {
                body = Text(friendlyError(snap.error!), style: AppFonts.style(fontSize: 13, color: AppColors.muted));
              } else if (rows == null) {
                body = const LinearProgressIndicator(minHeight: 2);
              } else {
                int count(String st) => rows.where((p) => p['status'] == st).length;
                body = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        for (final (i, (st, color)) in const [
                          ('in_review', AppColors.review),
                          ('rejected', AppColors.danger),
                          ('completed', AppColors.success),
                        ].indexed) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${count(st)}',
                                      style: AppFonts.style(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                                  Text(loc.statusLabel(st),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFonts.style(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (rows.isEmpty)
                      Text(loc.tr('lab.dentistNoPatients'), style: AppFonts.style(fontSize: 13, color: AppColors.muted))
                    else
                      for (final p in rows)
                        InkWell(
                          onTap: () => widget.onOpenPatient('${p['id']}'),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppFonts.style(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.navy),
                                  ),
                                ),
                                StatusChip(statusKey: '${p['status'] ?? ''}'),
                                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                              ],
                            ),
                          ),
                        ),
                  ],
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                sliver: SliverList.list(
                  children: [
                    SectionLabel(rows == null ? loc.navPatients : '${loc.navPatients} (${rows.length})'),
                    const SizedBox(height: 10),
                    body,
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

String? _str(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// Lab hide-from-directory toggles (used on the Settings page).
class LabVisibilitySettings extends StatefulWidget {
  const LabVisibilitySettings({super.key, required this.api, required this.labId});

  final ApiClient api;
  final String labId;

  @override
  State<LabVisibilitySettings> createState() => _LabVisibilitySettingsState();
}

class _LabVisibilitySettingsState extends State<LabVisibilitySettings> {
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

  /// Turning hide on: recommend staying visible, then confirm.
  Future<void> _onToggle({required bool enabling, required Future<void> Function() apply}) async {
    if (enabling) {
      final loc = AppLocalizations.of(context);
      final ok = await AppDialogs.confirm(
        context,
        title: loc.tr('lab.hideWarnTitle'),
        message: loc.tr('lab.hideWarnMsg'),
        confirmLabel: loc.tr('lab.hideWarnConfirm'),
        cancelLabel: loc.tr('lab.hideWarnKeep'),
        isDestructive: true,
      );
      if (!ok || !mounted) return;
    }
    await apply();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (_hidden == null) {
      return _error == null
          ? const SizedBox(height: 80, child: ToothPageLoader(inPlace: true))
          : Text(friendlyError(_error!), style: AppFonts.style(color: AppColors.danger));
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
    return AdminCard(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(
            loc.tr('lab.hideLab'),
            loc.tr('lab.hideLabMsg'),
            _hidden!,
            (v) => _onToggle(enabling: v, apply: () => _set(hidden: v)),
          ),
          Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
          row(
            loc.tr('lab.hideDentists'),
            loc.tr('lab.hideDentistsMsg'),
            _hideDentists!,
            (v) => _onToggle(enabling: v, apply: () => _set(hideDentists: v)),
          ),
        ],
      ),
    );
  }
}

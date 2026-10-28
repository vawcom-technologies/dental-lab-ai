import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/split_list.dart';
import '../../core/widgets/ui_kit.dart';
import '../chat/widgets/quick_chat_card.dart';
import '../admin/admin_models.dart';
import '../admin/admin_widgets.dart';
import '../lab/bring_patients_sheet.dart';

/// Admin "System Users": labs with their dentists, unassigned dentists, and
/// labs' requests to remove a dentist.
class LaboratoriesPage extends StatefulWidget {
  const LaboratoriesPage({
    super.key,
    required this.api,
    this.tab,
    this.active = true,
    this.onMessage,
  });

  final ApiClient api;

  /// 0 by lab, 1 unassigned dentists, 2 removal requests.
  final ValueNotifier<int>? tab;
  final bool active;

  /// Opens (or creates) a Messages thread with this user, then navigates.
  final Future<void> Function(String userId)? onMessage;

  @override
  State<LaboratoriesPage> createState() => _LaboratoriesPageState();
}

class _LaboratoriesPageState extends State<LaboratoriesPage> {
  late final ValueNotifier<int> _tab = widget.tab ?? ValueNotifier(0);
  final _search = TextEditingController();
  String _q = '';

  ApiClient get api => widget.api;

  @override
  void dispose() {
    if (widget.tab == null) _tab.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Chat in place, like the lab side; no trip to Messages.
  Future<void> _message(String userId) => messageUser(context, userId);

  Widget _messageButton(AppLocalizations loc, String id) => AppButtons.ghost(
        onPressed: () => _message(id),
        icon: Icons.chat_bubble_outline_rounded,
        label: loc.tr('case.message'),
        compact: true,
      );

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<bool> _move(AdminDentist d) async {
    final loc = AppLocalizations.of(context);
    final pick = await pickLab(
      context,
      api,
      title: loc.trp('admin.moveTitle', {'name': d.name}),
      message: loc.tr('admin.moveMsg'),
      excludeLabId: d.labId,
      noneLabel: d.labId == null ? null : loc.tr('admin.removeFromLab'),
    );
    if (pick == null || !mounted) return false;
    final to = pick.lab;
    final ok = await AppDialogs.confirm(
      context,
      title: to == null
          ? loc.trp('admin.removeTitle', {'name': d.name})
          : loc.trp('admin.moveConfirmTitle', {'name': d.name, 'lab': to.name}),
      message: [
        if (to != null) loc.trp('admin.moveNoApproval', {'lab': to.name}),
        if (d.labId != null)
          loc.trp('admin.leaveLabEffects', {'lab': d.labName ?? '—'}),
        if (to == null) loc.tr('admin.removeEffects'),
      ].join('\n\n'),
      confirmLabel: to == null ? loc.tr('admin.remove') : loc.tr('admin.move'),
      isDestructive: to == null,
    );
    if (!ok || !mounted) return false;
    var bring = <String>[];
    if (to != null) {
      // Admin force-move: optional patient bring (same as join/transfer).
      final picked = await pickPatientsToBring(
        context,
        api,
        title: loc.tr('join.bringTitle'),
        message: loc.tr('join.bringMsg'),
        ownerUserId: d.id,
      );
      if (picked == null || !mounted) return false;
      bring = picked;
    }
    return adminRun(
      context,
      () => api.adminSetDentistLab(d.id, to?.id, patientIds: bring),
      done: to == null
          ? loc.trp('admin.removedFromLab', {'name': d.name})
          : loc.trp('admin.moved', {'name': d.name, 'lab': to.name}),
    );
  }

  /// [dentist] decides the consequences copy; labs pass their dentist count.
  Future<bool> _delete(String id, String name, {required bool dentist, int dentists = 0}) async {
    final loc = AppLocalizations.of(context);
    final hard = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(loc.trp('admin.deleteTitle', {'name': name})),
        message: Text(
          dentist
              ? loc.tr('admin.deleteDentistEffects')
              : loc.trp('admin.deleteLabEffects', {'n': dentistCount(loc, dentists)}),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.tr('admin.deactivate')),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.tr('admin.deletePermanently')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(loc.cancel),
        ),
      ),
    );
    if (hard == null || !mounted) return false;
    return adminRun(
      context,
      () => api.adminDeleteUser(id, hard: hard),
      done: loc.trp(hard ? 'admin.deleted' : 'admin.deactivated', {'name': name}),
    );
  }

  /// Admin-only: replace this user's profile photo (users can't change it).
  Future<bool> _changePhoto(String id, String name) async {
    final loc = AppLocalizations.of(context);
    final photo = await pickProfilePhoto(context);
    if (photo == null || !mounted) return false;
    return adminRun(
      context,
      () => api.adminSetAvatar(id, bytes: photo.bytes, contentType: photo.contentType),
      done: loc.trp('avatar.changed', {'name': name}),
    );
  }

  Future<bool> _reactivate(String id, String name) async {
    final loc = AppLocalizations.of(context);
    final ok = await AppDialogs.confirm(
      context,
      title: loc.trp('admin.reactivateTitle', {'name': name}),
      message: loc.tr('admin.reactivateMsg'),
      confirmLabel: loc.tr('admin.reactivate'),
    );
    if (!ok || !mounted) return false;
    return adminRun(
      context,
      () => api.adminReactivateUser(id),
      done: loc.trp('admin.reactivated', {'name': name}),
    );
  }

  Widget _reactivateButton(AppLocalizations loc, String id, String name, VoidCallback reload) {
    return AppButtons.primary(
      onPressed: () async {
        if (await _reactivate(id, name)) reload();
      },
      icon: Icons.settings_backup_restore_rounded,
      label: loc.tr('admin.reactivate'),
      compact: true,
    );
  }

  Future<bool> _decide(RemovalRequest r, {required bool approve}) async {
    final loc = AppLocalizations.of(context);
    final ok = await AppDialogs.confirm(
      context,
      title: loc.trp(
        approve ? 'admin.approveRemovalTitle' : 'admin.denyRemovalTitle',
        {'name': r.dentistName, 'lab': r.labName},
      ),
      message: approve
          ? '${loc.trp('admin.leaveLabEffects', {'lab': r.labName})}\n\n${loc.tr('admin.removeEffects')}'
          : loc.tr('admin.denyRemovalMsg'),
      confirmLabel: loc.tr(approve ? 'admin.approve' : 'admin.deny'),
      isDestructive: approve,
    );
    if (!ok || !mounted) return false;
    return adminRun(
      context,
      () => api.adminDecideLabRequest(r.id, approve: approve),
      done: loc.tr(approve ? 'admin.removalApproved' : 'admin.removalDenied'),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (!api.isAdmin) {
      return Center(
        child: Text(
          loc.errNoPermission,
          style: AppFonts.style(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.navy,
          ),
        ),
      );
    }
    return ValueListenableBuilder<int>(
      valueListenable: _tab,
      builder: (context, t, _) => AdminPage(
        icon: Icons.manage_accounts_outlined,
        title: loc.labsTitle,
        subtitle: loc.tr('admin.usersSub'),
        toolbar: [
          AdminTabs(
            tab: _tab,
            labels: [
              loc.tr('admin.byLab'),
              loc.tr('admin.unassignedDentists'),
              loc.tr('admin.removalRequests'),
            ],
          ),
          if (t == 0)
            AdminSearchField(
              controller: _search,
              hint: loc.tr('admin.searchUsers'),
              onChanged: (q) => setState(() => _q = q.toLowerCase()),
            ),
        ],
        body: AdminSwap(
          index: t,
          builder: (i) => switch (i) {
            0 => _byLab(loc, widget.active && t == 0),
            1 => _unassigned(loc, widget.active && t == 1),
            _ => _removals(loc, widget.active && t == 2),
          },
        ),
      ),
    );
  }

  Widget _byLab(AppLocalizations loc, bool on) {
    bool hit(String? s) => (s ?? '').toLowerCase().contains(_q);
    return SplitList<(AdminLab, List<AdminDentist>)>(
      key: const ValueKey('by-lab'),
      active: on,
      // ponytail: loads every dentist and searches on device; switch to the
      // `q` query param if the user list grows past a few thousand.
      load: () async {
        final r = await Future.wait([api.adminLabs(), api.adminDentists()]);
        final labs = r[0].map(AdminLab.new).toList();
        final dentists = r[1].map(AdminDentist.new).toList();
        return [for (final lab in labs) (lab, dentists.where((d) => d.labId == lab.id).toList())];
      },
      // A lab matches by its own name/email (all its dentists), or through
      // matching dentists (only those).
      filter: (groups) => [
        for (final (lab, all) in groups)
          if (hit(lab.name) || hit(lab.email))
            (lab, all)
          else if (all.where((d) => hit(d.name) || hit(d.email) || hit(d.clinicName)).toList() case final ds
              when ds.isNotEmpty)
            (lab, ds),
      ],
      empty: AdminEmpty(
        icon: Icons.apartment_rounded,
        title: loc.tr('admin.noLabs'),
        subtitle: loc.tr('admin.noLabsSub'),
      ),
      filteredEmpty: AdminEmpty(
        icon: Icons.search_off_rounded,
        title: loc.tr('admin.noMatches'),
        subtitle: loc.tr('admin.noMatchesSub'),
      ),
      item: (g, reload) {
        final (lab, dentists) = g;
        final list = dentists.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 0, 6),
                child: Text(loc.tr('admin.labNoDentists'), style: AppFonts.style(fontSize: 13, color: AppColors.muted)),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, d) in dentists.indexed) ...[
                    if (i > 0) Divider(height: 1, color: AppColors.border.withValues(alpha: 0.6)),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: _dentistRow(loc, d, reload)),
                  ],
                ],
              );
        return SplitItem(
          id: lab.id,
          leading: (size) => UserAvatar(name: lab.name, url: lab.avatarUrl, size: size),
          title: lab.name,
          badges: [
            AdminBadge(dentistCount(loc, lab.dentistCount), color: AppColors.review),
            if (lab.hiddenFromLabs) AdminBadge(loc.tr('admin.hiddenFromLabs'), color: AppColors.muted),
            if (lab.hideDentists) AdminBadge(loc.tr('admin.dentistsHidden'), color: AppColors.muted),
            if (lab.deleted) AdminBadge(loc.tr('admin.deactivatedBadge'), color: AppColors.danger),
          ],
          lines: [[lab.email, ?lab.phone].join(' · ')],
          details: [
            (Icons.mail_outline_rounded, lab.email),
            if (lab.phone case final phone?) (Icons.phone_outlined, phone),
          ],
          extras: [if (!lab.deleted) _messageButton(loc, lab.id)],
          actions: lab.deleted
              ? [_reactivateButton(loc, lab.id, lab.name, reload)]
              : [
                  AppButtons.icon(
                    tooltip: loc.tr('admin.more'),
                    icon: Icons.more_horiz_rounded,
                    onPressed: () async {
                      final v = await adminChoose<String>(
                        context,
                        title: lab.name,
                        options: [
                          ('photo', loc.tr('avatar.change')),
                          ('delete', loc.tr('admin.deactivateOrDelete')),
                        ],
                      );
                      if (v == 'photo') {
                        if (await _changePhoto(lab.id, lab.name)) reload();
                        return;
                      }
                      if (v == 'delete' && await _delete(lab.id, lab.name, dentist: false, dentists: lab.dentistCount)) {
                        reload();
                      }
                    },
                  ),
                ],
          panelBody: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel('${loc.tr('lab.tab.dentists')} (${dentists.length})'),
              const SizedBox(height: 6),
              list,
            ],
          ),
          cardBody: list,
        );
      },
    );
  }

  List<Widget> _dentistActions(AppLocalizations loc, AdminDentist d, VoidCallback reload) => d.deleted
      ? [_reactivateButton(loc, d.id, d.name, reload)]
      : [
          AppButtons.secondary(
            onPressed: () async {
              if (await _move(d)) reload();
            },
            icon: d.labId == null ? Icons.add_link_rounded : Icons.swap_horiz_rounded,
            label: loc.tr(d.labId == null ? 'admin.assignLab' : 'admin.move'),
            compact: true,
          ),
          AppButtons.icon(
            tooltip: loc.tr('admin.more'),
            icon: Icons.more_horiz_rounded,
            onPressed: () async {
              final v = await adminChoose<String>(
                context,
                title: d.name,
                options: [
                  ('msg', loc.labsMessage),
                  ('photo', loc.tr('avatar.change')),
                  ('delete', loc.tr('admin.deactivateOrDelete')),
                ],
              );
              if (v == 'msg') return _message(d.id);
              if (v == 'photo') {
                if (await _changePhoto(d.id, d.name)) reload();
                return;
              }
              if (v == 'delete' && await _delete(d.id, d.name, dentist: true)) {
                reload();
              }
            },
          ),
        ];

  List<String> _dentistLines(AppLocalizations loc, AdminDentist d) => [
        dentistPlace(loc, d.labName, d.clinicName),
        d.email,
        if (d.unassignedReason != null)
          [
            loc.tr('admin.unassigned.${d.unassignedReason}'),
            if (d.unassignedAt != null) loc.trp('admin.since', {'when': adminWhen(context, d.unassignedAt)}),
          ].join(' · '),
      ];

  Widget _dentistRow(AppLocalizations loc, AdminDentist d, VoidCallback reload) {
    return AdminRow(
      leading: UserAvatar(name: d.name.isEmpty ? d.email : d.name, url: d.avatarUrl, size: 36),
      title: d.name.isEmpty ? d.email : d.name,
      badges: [
        if (d.deleted) AdminBadge(loc.tr('admin.deactivatedBadge'), color: AppColors.danger),
      ],
      lines: _dentistLines(loc, d),
      actions: _dentistActions(loc, d, reload),
    );
  }

  Widget _unassigned(AppLocalizations loc, bool on) {
    return SplitList<AdminDentist>(
      key: const ValueKey('unassigned'),
      active: on,
      load: () async => (await api.adminDentists(unassigned: true)).map(AdminDentist.new).toList(),
      empty: AdminEmpty(
        icon: Icons.verified_user_outlined,
        title: loc.tr('admin.noUnassignedDentists'),
        subtitle: loc.tr('admin.noUnassignedDentistsSub'),
      ),
      item: (d, reload) {
        final name = d.name.isEmpty ? d.email : d.name;
        final lines = _dentistLines(loc, d);
        return SplitItem(
          id: d.id,
          leading: (size) => UserAvatar(name: name, url: d.avatarUrl, size: size),
          title: name,
          badges: [if (d.deleted) AdminBadge(loc.tr('admin.deactivatedBadge'), color: AppColors.danger)],
          lines: lines,
          details: [
            (Icons.storefront_outlined, lines[0]),
            (Icons.mail_outline_rounded, d.email),
            if (d.phone case final phone?) (Icons.phone_outlined, phone),
            if (lines.length > 2) (Icons.link_off_rounded, lines[2]),
          ],
          extras: [if (!d.deleted) _messageButton(loc, d.id)],
          actions: _dentistActions(loc, d, reload),
        );
      },
    );
  }

  Widget _removals(AppLocalizations loc, bool on) {
    return SplitList<RemovalRequest>(
      key: const ValueKey('removals'),
      active: on,
      load: () async => (await api.adminRemovalRequests()).map(RemovalRequest.new).toList(),
      empty: AdminEmpty(
        icon: Icons.inbox_outlined,
        title: loc.tr('admin.noRemovals'),
        subtitle: loc.tr('admin.noRemovalsSub'),
      ),
      item: (r, reload) {
        final by = loc.trp('admin.requestedBy', {'lab': r.labName, 'when': adminWhen(context, r.createdAt)});
        final reason = '${loc.tr('admin.reason')}: ${r.reason ?? loc.tr('admin.noReason')}';
        return SplitItem(
          id: r.id,
          highlight: true,
          leading: (size) => AdminIcon(icon: Icons.person_remove_outlined, color: AppColors.warning, size: size),
          title: r.dentistName,
          lines: [by, reason],
          details: [(Icons.apartment_rounded, by), (Icons.notes_rounded, reason)],
          actions: [
            AppButtons.secondary(
              onPressed: () async {
                if (await _decide(r, approve: false)) reload();
              },
              label: loc.tr('admin.deny'),
              compact: true,
            ),
            AppButtons.primary(
              onPressed: () async {
                if (await _decide(r, approve: true)) reload();
              },
              icon: Icons.check_rounded,
              label: loc.tr('admin.approve'),
              compact: true,
            ),
          ],
        );
      },
    );
  }
}

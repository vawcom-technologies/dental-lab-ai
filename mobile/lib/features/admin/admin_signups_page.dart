import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

/// Approve: dentists may get a lab now, or choose one on first sign-in.
Future<bool> approveSignup(
  BuildContext context,
  ApiClient api,
  Signup s,
) async {
  final loc = AppLocalizations.of(context);
  final who = s.name.isEmpty ? s.email : s.name;
  String? labId;
  if (AppRoles.isDentist(s.role)) {
    final pick = await pickLab(
      context,
      api,
      title: loc.trp('admin.approveTitle', {'name': who}),
      message: loc.tr('admin.approveDentistMsg'),
      noneLabel: loc.tr('admin.approveNoLab'),
    );
    if (pick == null) return false;
    labId = pick.lab?.id;
  } else {
    final ok = await AppDialogs.confirm(
      context,
      title: loc.trp('admin.approveTitle', {'name': who}),
      message: loc.tr('admin.approveLabMsg'),
      confirmLabel: loc.tr('admin.approve'),
    );
    if (!ok) return false;
  }
  if (!context.mounted) return false;
  return adminRun(
    context,
    () => api.adminApproveSignup(s.userId, labId: labId),
    done: loc.trp('admin.approved', {'name': who}),
  );
}

/// Reject: optional reason, then a destructive confirm.
Future<bool> rejectSignup(
  BuildContext context,
  ApiClient api,
  Signup s,
) async {
  final loc = AppLocalizations.of(context);
  final who = s.name.isEmpty ? s.email : s.name;
  final reason = await AppDialogs.prompt(
    context,
    title: loc.trp('admin.rejectTitle', {'name': who}),
    message: loc.tr('admin.rejectReasonMsg'),
    placeholder: loc.tr('admin.reasonOptional'),
    confirmLabel: loc.tr('admin.continue'),
    maxLines: 3,
  );
  if (reason == null || !context.mounted) return false;
  final ok = await AppDialogs.confirm(
    context,
    title: loc.tr('admin.rejectConfirmTitle'),
    message: loc.trp('admin.rejectConfirmMsg', {'email': s.email}),
    confirmLabel: loc.tr('admin.reject'),
    isDestructive: true,
  );
  if (!ok || !context.mounted) return false;
  return adminRun(
    context,
    () => api.adminRejectSignup(s.userId, reason: reason.trim()),
    done: loc.trp('admin.rejected', {'name': who}),
  );
}

class SignupCard extends StatelessWidget {
  const SignupCard({
    super.key,
    required this.signup,
    required this.onApprove,
    required this.onReject,
  });

  final Signup signup;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final s = signup;
    return AdminCard(
      child: AdminRow(
        leading: UserAvatar(name: s.name.isEmpty ? s.email : s.name, url: s.avatarUrl, size: 44),
        title: s.name.isEmpty ? s.email : s.name,
        badges: [roleBadge(context, s.role)],
        lines: [
          [s.email, ?s.phone].join(' · '),
          if (s.clinicName != null) '${loc.tr('admin.clinic')}: ${s.clinicName}',
          if (s.createdAt != null)
            loc.trp('admin.signedUp', {'when': adminWhen(context, s.createdAt)}),
        ],
        actions: [
          AppButtons.danger(
            onPressed: onReject,
            icon: Icons.close_rounded,
            label: loc.tr('admin.reject'),
            soft: true,
            compact: true,
          ),
          AppButtons.primary(
            onPressed: onApprove,
            icon: Icons.check_rounded,
            label: loc.tr('admin.approve'),
            compact: true,
          ),
        ],
      ),
    );
  }
}

class AdminSignupsPage extends StatelessWidget {
  const AdminSignupsPage({
    super.key,
    required this.api,
    required this.tab,
    this.active = true,
  });

  final ApiClient api;

  /// 0 pending signups, 1 reject list.
  final ValueNotifier<int> tab;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return AdminPage(
      icon: Icons.how_to_reg_outlined,
      title: loc.tr('admin.signupsTitle'),
      subtitle: loc.tr('admin.signupsSub'),
      toolbar: [
        AdminTabs(
          tab: tab,
          labels: [loc.tr('admin.pending'), loc.tr('admin.rejectList')],
        ),
      ],
      body: ValueListenableBuilder<int>(
        valueListenable: tab,
        builder: (context, t, _) => AdminSwap(
          index: t,
          builder: (i) => i == 0
              ? _pending(context, loc, active && t == 0)
              : _rejected(context, loc, active && t == 1),
        ),
      ),
    );
  }

  Widget _pending(BuildContext context, AppLocalizations loc, bool on) {
    return AdminFuture<List<Signup>>(
      key: const ValueKey('signups'),
      active: on,
      load: () async => (await api.adminSignups()).map(Signup.new).toList(),
      empty: AdminEmpty(
        icon: Icons.how_to_reg_outlined,
        title: loc.tr('admin.noSignups'),
        subtitle: loc.tr('admin.noSignupsSub'),
      ),
      builder: (context, rows, reload) => [
        adminSliverList<Signup>(
          rows,
          id: (s) => s.userId,
          (context, s) => SignupCard(
            signup: s,
            onApprove: () async {
              if (await approveSignup(context, api, s)) reload();
            },
            onReject: () async {
              if (await rejectSignup(context, api, s)) reload();
            },
          ),
        ),
      ],
    );
  }

  Widget _rejected(BuildContext context, AppLocalizations loc, bool on) {
    return AdminFuture<List<RejectedSignup>>(
      key: const ValueKey('rejected'),
      active: on,
      load: () async =>
          (await api.adminRejected()).map(RejectedSignup.new).toList(),
      empty: AdminEmpty(
        icon: Icons.block_rounded,
        title: loc.tr('admin.noRejected'),
        subtitle: loc.tr('admin.noRejectedSub'),
      ),
      builder: (context, rows, reload) => [
        adminSliverList<RejectedSignup>(
          rows,
          id: (r) => r.id,
          (context, r) {
            return AdminCard(
              child: AdminRow(
                leading: const AdminIcon(
                  icon: Icons.block_rounded,
                  color: AppColors.danger,
                ),
                title: r.email,
                badges: [roleBadge(context, r.role)],
                lines: [
                  if (r.name.isNotEmpty) r.name,
                  '${loc.tr('admin.reason')}: ${r.reason ?? loc.tr('admin.noReason')}',
                  loc.trp('admin.rejectedBy', {
                    'when': adminWhen(context, r.rejectedAt),
                    'by': r.rejectedBy ?? '—',
                  }),
                ],
                actions: [
                  AppButtons.secondary(
                    onPressed: () async {
                      final ok = await AppDialogs.confirm(
                        context,
                        title: loc.tr('admin.unrejectTitle'),
                        message: loc.trp('admin.unrejectMsg', {'email': r.email}),
                        confirmLabel: loc.tr('admin.unreject'),
                      );
                      if (!ok || !context.mounted) return;
                      final done = await adminRun(
                        context,
                        () => api.adminRemoveRejected(r.id),
                        done: loc.trp('admin.unrejected', {'email': r.email}),
                      );
                      if (done) reload();
                    },
                    icon: Icons.undo_rounded,
                    label: loc.tr('admin.unreject'),
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
}

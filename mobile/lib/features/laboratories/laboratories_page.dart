import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'admin_user.dart';
import 'admin_users_controller.dart';

class LaboratoriesPage extends StatefulWidget {
  const LaboratoriesPage({
    super.key,
    required this.api,
    this.onMessageLab,
  });

  final ApiClient api;

  /// Opens (or creates) a Messages thread with this laboratory, then navigates.
  final Future<void> Function(AdminUser lab)? onMessageLab;

  @override
  State<LaboratoriesPage> createState() => _LaboratoriesPageState();
}

class _LaboratoriesPageState extends State<LaboratoriesPage> {
  late final AdminUsersController _controller;
  final _search = TextEditingController();
  bool _openingChat = false;

  @override
  void initState() {
    super.initState();
    _controller = AdminUsersController(widget.api);
    _controller.onError = (msg) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppSnackBars.error(context, msg);
      });
    };
    _controller.load();
  }

  @override
  void dispose() {
    _search.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _messageLab(AdminUser user) async {
    final open = widget.onMessageLab;
    if (open == null || _openingChat) return;
    if (!user.verified) {
      AppSnackBars.error(
        context,
        'Verify this laboratory before messaging.',
      );
      return;
    }
    setState(() => _openingChat = true);
    try {
      await open(user);
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  Future<void> _openLabDetails(AdminUser user) async {
    if (_openingChat || _controller.actionBusy) return;
    await AppDialogs.modalSheet<void>(
      context: context,
      builder: (ctx) => _LabDetailSheet(
        user: user,
        canMessage: widget.onMessageLab != null,
        onMessage: () {
          Navigator.pop(ctx);
          _messageLab(user);
        },
        onVerify: () {
          Navigator.pop(ctx);
          _verify(user);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _confirmDelete(user);
        },
      ),
    );
  }

  Future<void> _verify(AdminUser user) async {
    try {
      final message = await _controller.verifyUser(user.id);
      if (!mounted) return;
      AppSnackBars.success(context, message);
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _confirmDelete(AdminUser user) async {
    final loc = AppLocalizations.of(context);
    final choice = await showCupertinoModalPopup<_DeleteChoice>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(loc.labsDeleteTitle),
        message: Text(
          loc.labsDeleteBody(user.name.isEmpty ? user.email : user.name),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, _DeleteChoice.soft),
            child: Text(loc.labsSoftDelete),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, _DeleteChoice.hard),
            child: Text(loc.labsHardDelete),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(loc.cancel),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    try {
      final message = choice == _DeleteChoice.soft
          ? await _controller.softDeleteUser(user.id)
          : await _controller.hardDeleteUser(user.id);
      if (!mounted) return;
      AppSnackBars.success(context, message);
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final visible = _controller.visibleUsers;
        final unverified =
            _controller.users.where((u) => !u.verified).length;
        final blocked =
            _controller.loading || _controller.actionBusy || _openingChat;

        return BusyBarrier(
          busy: blocked && _controller.users.isNotEmpty,
          message: _openingChat
              ? 'Opening conversation…'
              : _controller.actionBusy
                  ? 'Updating…'
                  : 'Loading laboratories…',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  icon: Icons.biotech_outlined,
                  title: loc.labsTitle,
                  subtitle: loc.labsSubtitle,
                  chromeActions: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        _controller.loading
                            ? '…'
                            : loc.labsCount(
                                visible.length,
                                _controller.count,
                              ),
                        style: AppFonts.style(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    AppButtons.icon(
                      tooltip: loc.refresh,
                      onPressed: blocked ? null : _controller.refresh,
                      icon: Icons.refresh_rounded,
                      busy: _controller.loading,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                GlassSurface(
                  borderRadius: BorderRadius.circular(16),
                  blur: 14,
                  tint: Colors.white.withValues(alpha: 0.55),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: TextField(
                    controller: _search,
                    onChanged: _controller.setQuery,
                    enabled: !blocked,
                    style: AppFonts.style(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.navy,
                    ),
                    decoration: InputDecoration(
                      hintText: loc.labsSearchHint,
                      hintStyle: AppFonts.style(
                        color: AppColors.muted,
                        fontSize: 15,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.muted,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SoftFilterChip(
                      label: loc.filterAll,
                      selected: _controller.filter == AdminUserFilter.all,
                      onTap: () =>
                          _controller.setFilter(AdminUserFilter.all),
                    ),
                    SoftFilterChip(
                      label: unverified > 0
                          ? '${loc.labsFilterUnverified} ($unverified)'
                          : loc.labsFilterUnverified,
                      selected:
                          _controller.filter == AdminUserFilter.unverified,
                      onTap: () => _controller
                          .setFilter(AdminUserFilter.unverified),
                    ),
                    SoftFilterChip(
                      label: loc.labsFilterVerified,
                      selected:
                          _controller.filter == AdminUserFilter.verified,
                      onTap: () =>
                          _controller.setFilter(AdminUserFilter.verified),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _controller.loading && _controller.users.isEmpty
                      ? const ToothPageLoader(
                          message: 'Loading laboratories…',
                        )
                      : visible.isEmpty
                          ? _EmptyState(
                              title: _controller.users.isEmpty
                                  ? loc.labsEmpty
                                  : loc.labsEmptyFilter,
                              subtitle: _controller.users.isEmpty
                                  ? 'Verified labs will appear here.'
                                  : 'Try another filter or search.',
                            )
                          : ListView.separated(
                              itemCount: visible.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final user = visible[i];
                                return _LabCard(
                                  user: user,
                                  busy: blocked,
                                  canMessage: widget.onMessageLab != null,
                                  onOpen: () => _openLabDetails(user),
                                  onMessage: () => _messageLab(user),
                                  onVerify: () => _verify(user),
                                  onDelete: () => _confirmDelete(user),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _DeleteChoice { soft, hard }

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassSurface(
        borderRadius: BorderRadius.circular(22),
        blur: 16,
        tint: Colors.white.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeoIconBadge(
              icon: Icons.biotech_outlined,
              size: 56,
              iconSize: 26,
              color: AppColors.muted,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppFonts.style(
                color: AppColors.navy,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppFonts.style(
                color: AppColors.muted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabCard extends StatelessWidget {
  const _LabCard({
    required this.user,
    required this.busy,
    required this.canMessage,
    required this.onOpen,
    required this.onMessage,
    required this.onVerify,
    required this.onDelete,
  });

  final AdminUser user;
  final bool busy;
  final bool canMessage;
  final VoidCallback onOpen;
  final VoidCallback onMessage;
  final VoidCallback onVerify;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = user.name.trim().isEmpty ? user.email : user.name.trim();
    final role = AppRoles.label(user.role);
    final accent = user.verified ? AppColors.success : AppColors.warning;
    final messageEnabled = canMessage && user.verified && !busy;

    return GlassSurface(
      borderRadius: BorderRadius.circular(20),
      blur: 16,
      tint: Colors.white.withValues(alpha: 0.52),
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: busy ? null : onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final identity = Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _LabAvatar(title: title, verified: user.verified),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _RoleStatusBadge(
                            roleLabel: role.isEmpty ? 'Laboratory' : role,
                            statusLabel: user.verified
                                ? loc.labsVerified
                                : loc.labsUnverified,
                            color: accent,
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final actions = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    if (canMessage)
                      AppButtons.primary(
                        onPressed: messageEnabled ? onMessage : null,
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Message',
                        compact: true,
                      ),
                    if (!user.verified)
                      AppButtons.primary(
                        onPressed: busy ? null : onVerify,
                        icon: Icons.verified_outlined,
                        label: loc.labsVerify,
                        compact: true,
                      ),
                    AppButtons.danger(
                      onPressed: busy ? null : onDelete,
                      icon: Icons.delete_outline_rounded,
                      label: loc.labsDelete,
                      soft: true,
                      compact: true,
                    ),
                  ],
                );

                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 16),
                      actions,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LabDetailSheet extends StatelessWidget {
  const _LabDetailSheet({
    required this.user,
    required this.canMessage,
    required this.onMessage,
    required this.onVerify,
    required this.onDelete,
  });

  final AdminUser user;
  final bool canMessage;
  final VoidCallback onMessage;
  final VoidCallback onVerify;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = user.name.trim().isEmpty ? user.email : user.name.trim();
    final role = AppRoles.label(user.role);
    final accent = user.verified ? AppColors.success : AppColors.warning;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final messageEnabled = canMessage && user.verified;

    String? updated;
    final at = user.updatedAt;
    if (at != null) {
      final local = at.toLocal();
      updated =
          '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(22),
              blur: 22,
              tint: Colors.white.withValues(alpha: 0.78),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _LabAvatar(title: title, verified: user.verified),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AppFonts.style(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navy,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _RoleStatusBadge(
                              roleLabel: role.isEmpty ? 'Laboratory' : role,
                              statusLabel: user.verified
                                  ? loc.labsVerified
                                  : loc.labsUnverified,
                              color: accent,
                            ),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.all(6),
                        onPressed: () => Navigator.pop(context),
                        child: const Icon(
                          CupertinoIcons.xmark_circle_fill,
                          color: Color(0xFFC7C7CC),
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _LabDetailRow(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: user.email.isEmpty ? '—' : user.email,
                          ),
                          _LabDetailRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone',
                            value: (user.phone == null || user.phone!.isEmpty)
                                ? '—'
                                : user.phone!,
                          ),
                          _LabDetailRow(
                            icon: Icons.apartment_outlined,
                            label: 'Clinic / lab',
                            value: (user.clinicName == null ||
                                    user.clinicName!.isEmpty)
                                ? '—'
                                : user.clinicName!,
                          ),
                          _LabDetailRow(
                            icon: Icons.badge_outlined,
                            label: 'Role',
                            value: role.isEmpty ? 'Laboratory' : role,
                          ),
                          _LabDetailRow(
                            icon: Icons.verified_outlined,
                            label: 'Status',
                            value: user.verified
                                ? loc.labsVerified
                                : loc.labsUnverified,
                          ),
                          if (updated != null)
                            _LabDetailRow(
                              icon: Icons.schedule_outlined,
                              label: 'Updated',
                              value: updated,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      if (canMessage)
                        AppButtons.primary(
                          onPressed: messageEnabled ? onMessage : null,
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Message',
                          compact: true,
                        ),
                      if (!user.verified)
                        AppButtons.primary(
                          onPressed: onVerify,
                          icon: Icons.verified_outlined,
                          label: loc.labsVerify,
                          compact: true,
                        ),
                      AppButtons.danger(
                        onPressed: onDelete,
                        icon: Icons.delete_outline_rounded,
                        label: loc.labsDelete,
                        soft: true,
                        compact: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabDetailRow extends StatelessWidget {
  const _LabDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.dentalBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppFonts.style(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: AppFonts.style(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabAvatar extends StatelessWidget {
  const _LabAvatar({required this.title, required this.verified});

  final String title;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final bg = verified
        ? AppColors.dentalBlue.withValues(alpha: 0.14)
        : AppColors.warningSoft;
    final fg = verified ? AppColors.dentalBlue : AppColors.warning;
    final initials = _initials(title);

    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: NeoShadows.soft(depth: 0.4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
      ),
      child: initials == '·'
          ? Icon(Icons.biotech_outlined, color: fg, size: 26)
          : Text(
              initials,
              style: AppFonts.style(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.2,
              ),
            ),
    );
  }

  static String _initials(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '·';
    if (t.contains('@')) {
      final local = t.split('@').first;
      return local.isEmpty ? '·' : local[0].toUpperCase();
    }
    final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '·';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// Matches patients’ “Created by · Role” pattern: muted prefix + status pill.
class _RoleStatusBadge extends StatelessWidget {
  const _RoleStatusBadge({
    required this.roleLabel,
    required this.statusLabel,
    required this.color,
  });

  final String roleLabel;
  final String statusLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          roleLabel,
          style: AppFonts.style(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: AppFonts.style(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

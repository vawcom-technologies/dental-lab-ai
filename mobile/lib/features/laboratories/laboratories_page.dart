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
  const LaboratoriesPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<LaboratoriesPage> createState() => _LaboratoriesPageState();
}

class _LaboratoriesPageState extends State<LaboratoriesPage> {
  late final AdminUsersController _controller;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = AdminUsersController(widget.api);
    _controller.load();
  }

  @override
  void dispose() {
    _search.dispose();
    _controller.dispose();
    super.dispose();
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                          : loc.labsCount(visible.length, _controller.count),
                      style: AppFonts.style(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  AppButtons.icon(
                    tooltip: loc.refresh,
                    onPressed: _controller.loading || _controller.actionBusy
                        ? null
                        : _controller.refresh,
                    icon: Icons.refresh_rounded,
                    busy: _controller.loading,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _LabsToolbar(
                search: _search,
                onQuery: _controller.setQuery,
                filter: _controller.filter,
                onFilter: _controller.setFilter,
                unverifiedCount: unverified,
                loc: loc,
              ),
              if (_controller.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _controller.error!,
                  style: AppFonts.style(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: _controller.loading && _controller.users.isEmpty
                    ? const ToothPageLoader(message: 'Loading laboratories…')
                    : BusyBarrier(
                        busy: _controller.loading || _controller.actionBusy,
                        message: _controller.actionBusy
                            ? 'Updating…'
                            : 'Loading laboratories…',
                        child: visible.isEmpty
                            ? _EmptyState(
                                message: _controller.users.isEmpty
                                    ? loc.labsEmpty
                                    : loc.labsEmptyFilter,
                              )
                            : ListView.separated(
                                itemCount: visible.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, i) {
                                  final user = visible[i];
                                  return _LabCard(
                                    user: user,
                                    busy: _controller.actionBusy,
                                    onVerify: () => _verify(user),
                                    onDelete: () => _confirmDelete(user),
                                  );
                                },
                              ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _DeleteChoice { soft, hard }

class _LabsToolbar extends StatelessWidget {
  const _LabsToolbar({
    required this.search,
    required this.onQuery,
    required this.filter,
    required this.onFilter,
    required this.unverifiedCount,
    required this.loc,
  });

  final TextEditingController search;
  final ValueChanged<String> onQuery;
  final AdminUserFilter filter;
  final ValueChanged<AdminUserFilter> onFilter;
  final int unverifiedCount;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassSurface(
          borderRadius: BorderRadius.circular(16),
          blur: 14,
          tint: Colors.white.withValues(alpha: 0.55),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: TextField(
            controller: search,
            onChanged: onQuery,
            style: AppFonts.style(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.navy,
            ),
            decoration: InputDecoration(
              hintText: loc.labsSearchHint,
              hintStyle: AppFonts.style(color: AppColors.muted, fontSize: 15),
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
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
              selected: filter == AdminUserFilter.all,
              onTap: () => onFilter(AdminUserFilter.all),
            ),
            SoftFilterChip(
              label: unverifiedCount > 0
                  ? '${loc.labsFilterUnverified} ($unverifiedCount)'
                  : loc.labsFilterUnverified,
              selected: filter == AdminUserFilter.unverified,
              onTap: () => onFilter(AdminUserFilter.unverified),
            ),
            SoftFilterChip(
              label: loc.labsFilterVerified,
              selected: filter == AdminUserFilter.verified,
              onTap: () => onFilter(AdminUserFilter.verified),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
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
            message,
            textAlign: TextAlign.center,
            style: AppFonts.style(
              color: AppColors.muted,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LabCard extends StatelessWidget {
  const _LabCard({
    required this.user,
    required this.busy,
    required this.onVerify,
    required this.onDelete,
  });

  final AdminUser user;
  final bool busy;
  final VoidCallback onVerify;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = user.name.trim().isEmpty ? user.email : user.name.trim();
    final showEmailUnderName =
        user.name.trim().isNotEmpty && user.email.trim().isNotEmpty;
    final meta = [
      if (user.clinicName != null && user.clinicName!.trim().isNotEmpty)
        user.clinicName!.trim(),
      if (user.phone != null && user.phone!.trim().isNotEmpty)
        user.phone!.trim(),
      AppRoles.label(user.role),
    ].where((s) => s.isNotEmpty).toList();

    final accent = user.verified ? AppColors.success : AppColors.warning;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      depth: 0.75,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _LabAvatar(title: title, verified: user.verified),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (showEmailUnderName) ...[
                      const SizedBox(height: 3),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        meta.join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.style(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _StatusPill(
                      label: user.verified
                          ? loc.labsVerified
                          : loc.labsUnverified,
                      color: accent,
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!user.verified) ...[
                AppButtons.primary(
                  onPressed: busy ? null : onVerify,
                  icon: Icons.verified_outlined,
                  label: loc.labsVerify,
                  compact: true,
                ),
                const SizedBox(width: 8),
              ],
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
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        },
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
    final bg = verified ? AppColors.successSoft : AppColors.warningSoft;
    final fg = verified ? AppColors.success : AppColors.warning;
    final initials = _initials(title);

    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: NeoShadows.soft(depth: 0.45),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: initials.length == 1 && initials == '·'
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppFonts.style(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/app_roles.dart';
import '../../core/haptics/app_haptics.dart';
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
      AppHaptics.success();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      AppHaptics.warn();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _confirmDelete(AdminUser user) async {
    final loc = AppLocalizations.of(context);
    final choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.labsDeleteTitle),
        content: Text(
          loc.labsDeleteBody(user.name.isEmpty ? user.email : user.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancel),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, _DeleteChoice.soft),
            child: Text(loc.labsSoftDelete),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, _DeleteChoice.hard),
            child: Text(loc.labsHardDelete),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    try {
      final message = choice == _DeleteChoice.soft
          ? await _controller.softDeleteUser(user.id)
          : await _controller.hardDeleteUser(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                icon: Icons.biotech_outlined,
                title: loc.labsTitle,
                subtitle: loc.labsSubtitle,
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4, top: 10),
                    child: Text(
                      _controller.loading
                          ? '…'
                          : loc.labsCount(
                              visible.length,
                              _controller.count,
                            ),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: loc.refresh,
                    onPressed: _controller.loading || _controller.actionBusy
                        ? null
                        : _controller.refresh,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                depth: 0.7,
                child: TextField(
                  controller: _search,
                  onChanged: _controller.setQuery,
                  decoration: InputDecoration(
                    hintText: loc.labsSearchHint,
                    prefixIcon: const Icon(Icons.search, color: AppColors.muted),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SoftFilterChip(
                    label: loc.filterAll,
                    selected: _controller.filter == AdminUserFilter.all,
                    onTap: () => _controller.setFilter(AdminUserFilter.all),
                  ),
                  SoftFilterChip(
                    label: loc.labsFilterUnverified,
                    selected: _controller.filter == AdminUserFilter.unverified,
                    onTap: () =>
                        _controller.setFilter(AdminUserFilter.unverified),
                  ),
                  SoftFilterChip(
                    label: loc.labsFilterVerified,
                    selected: _controller.filter == AdminUserFilter.verified,
                    onTap: () =>
                        _controller.setFilter(AdminUserFilter.verified),
                  ),
                ],
              ),
              if (_controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _controller.error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              const SizedBox(height: 16),
              Expanded(
                child: SectionCard(
                  padding: EdgeInsets.zero,
                  child: _controller.loading && _controller.users.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : visible.isEmpty
                          ? Center(
                              child: Text(
                                _controller.users.isEmpty
                                    ? loc.labsEmpty
                                    : loc.labsEmptyFilter,
                                style: const TextStyle(color: AppColors.muted),
                              ),
                            )
                          : ListView.separated(
                              itemCount: visible.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: AppColors.border.withValues(alpha: 0.7),
                              ),
                              itemBuilder: (context, i) {
                                final user = visible[i];
                                return _UserTile(
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

class _UserTile extends StatelessWidget {
  const _UserTile({
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
    final title = user.name.isEmpty ? user.email : user.name;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: user.verified
            ? AppColors.successSoft
            : AppColors.warning.withValues(alpha: 0.18),
        child: Icon(
          Icons.biotech_outlined,
          color: user.verified ? AppColors.success : AppColors.warning,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(
              [
                if (user.clinicName != null) user.clinicName!,
                if (user.phone != null) user.phone!,
                AppRoles.label(user.role),
              ].where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: user.verified
                    ? AppColors.successSoft
                    : AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                user.verified ? loc.labsVerified : loc.labsUnverified,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: user.verified ? AppColors.success : AppColors.warning,
                ),
              ),
            ),
          ],
        ),
      ),
      isThreeLine: true,
      trailing: Wrap(
        spacing: 4,
        children: [
          if (!user.verified)
            IconButton(
              tooltip: loc.labsVerify,
              onPressed: busy ? null : onVerify,
              icon: const Icon(Icons.verified_outlined, size: 20),
              color: AppColors.dentalBlue,
            ),
          IconButton(
            tooltip: loc.labsDelete,
            onPressed: busy ? null : onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }
}

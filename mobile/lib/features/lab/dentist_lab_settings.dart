import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/ui_kit.dart';
import 'bring_patients_sheet.dart';

/// Settings block for dentists: join a lab (if none) or request a transfer.
class DentistLabSettings extends StatefulWidget {
  const DentistLabSettings({super.key, required this.api});

  final ApiClient api;

  @override
  State<DentistLabSettings> createState() => _DentistLabSettingsState();
}

class _DentistLabSettingsState extends State<DentistLabSettings> {
  bool _busy = false;

  ApiClient get api => widget.api;

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      await api.fetchMe(forceRefresh: true);
    } catch (e) {
      if (mounted) AppSnackBars.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openJoin() async {
    await Navigator.of(context).push(
      AppPageRoutes.cupertino(
        _JoinOrTransferPage(api: api, mode: _LabMode.join),
        title: AppLocalizations.of(context).tr('join.title'),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _openTransfer() async {
    await Navigator.of(context).push(
      AppPageRoutes.cupertino(
        _JoinOrTransferPage(api: api, mode: _LabMode.transfer),
        title: AppLocalizations.of(context).tr('join.transferTitle'),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _withdrawJoin() async {
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
    await _refresh();
  }

  Future<void> _withdrawTransfer() async {
    final loc = AppLocalizations.of(context);
    final ok = await AppDialogs.confirm(
      context,
      title: loc.tr('join.withdrawTransferTitle'),
      message: loc.tr('join.withdrawTransferMsg'),
      confirmLabel: loc.tr('join.withdraw'),
      isDestructive: true,
    );
    if (!ok || !mounted) return;
    await adminRun(context, api.withdrawLabTransfer, done: loc.tr('join.transferWithdrawn'));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final hasLab = (api.labId ?? '').isNotEmpty;
    final pending = api.pendingJoin;
    final xfer = api.pendingTransfer;

    String subtitle;
    VoidCallback? onTap;
    if (!hasLab && pending != null) {
      subtitle = loc.trp('join.waiting', {'lab': '${pending['lab_name'] ?? ''}'});
      onTap = _withdrawJoin;
    } else if (!hasLab) {
      subtitle = loc.tr('join.settingsJoinSub');
      onTap = _openJoin;
    } else if (xfer != null) {
      subtitle = loc.trp('join.transferWaiting', {
        'lab': '${xfer['to_lab_name'] ?? ''}',
      });
      onTap = _withdrawTransfer;
    } else {
      subtitle = loc.trp('join.settingsLab', {'lab': api.labName ?? '—'});
      onTap = _openTransfer;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            loc.tr('join.settingsSection').toUpperCase(),
            style: AppFonts.style(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            leading: Icon(
              hasLab ? Icons.swap_horiz_rounded : Icons.apartment_rounded,
              color: AppColors.dentalBlue,
            ),
            title: Text(
              !hasLab
                  ? (pending != null
                      ? loc.tr('join.pendingTitle')
                      : loc.tr('join.settingsJoin'))
                  : (xfer != null
                      ? loc.tr('join.transferPendingTitle')
                      : loc.tr('join.transferTitle')),
              style: AppFonts.style(
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: AppFonts.style(fontSize: 13, color: AppColors.muted),
            ),
            trailing: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    pending != null || xfer != null
                        ? Icons.undo_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
            onTap: _busy ? null : onTap,
          ),
        ),
      ],
    );
  }
}

enum _LabMode { join, transfer }

class _JoinOrTransferPage extends StatefulWidget {
  const _JoinOrTransferPage({required this.api, required this.mode});

  final ApiClient api;
  final _LabMode mode;

  @override
  State<_JoinOrTransferPage> createState() => _JoinOrTransferPageState();
}

class _JoinOrTransferPageState extends State<_JoinOrTransferPage> {
  String _q = '';
  late Future<List<Map<String, dynamic>>> _labs =
      widget.api.searchLabs();

  Future<void> _pick(Map<String, dynamic> lab) async {
    final loc = AppLocalizations.of(context);
    final name = '${lab['name'] ?? ''}';
    final join = widget.mode == _LabMode.join;
    final ok = await AppDialogs.confirm(
      context,
      title: join
          ? loc.trp('join.confirmTitle', {'lab': name})
          : loc.trp('join.transferConfirmTitle', {'lab': name}),
      message: join
          ? loc.tr('join.confirmMsg')
          : loc.tr('join.transferConfirmMsg'),
      confirmLabel: join ? loc.tr('join.request') : loc.tr('join.transferRequest'),
    );
    if (!ok || !mounted) return;
    final bring = await pickPatientsToBring(
      context,
      widget.api,
      title: loc.tr('join.bringTitle'),
      message: loc.tr('join.bringMsg'),
    );
    if (bring == null || !mounted) return;
    final done = await adminRun(
      context,
      () => join
          ? widget.api.requestJoinLab('${lab['id']}', patientIds: bring)
          : widget.api.requestLabTransfer(
              toLabId: '${lab['id']}',
              patientIds: bring,
            ),
      done: join
          ? loc.trp('join.sent', {'lab': name})
          : loc.trp('join.transferSent', {'lab': name}),
    );
    if (done && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: AdminPage(
          icon: Icons.apartment_rounded,
          title: widget.mode == _LabMode.join
              ? loc.tr('join.title')
              : loc.tr('join.transferTitle'),
          subtitle: widget.mode == _LabMode.join
              ? loc.tr('join.settingsJoinSub')
              : loc.tr('join.transferSub'),
          actions: [
            AppButtons.icon(
              tooltip: loc.commonClose,
              onPressed: () => Navigator.of(context).pop(),
              icon: Icons.close_rounded,
            ),
          ],
          toolbar: [
            AdminSearchField(
              hint: loc.tr('admin.searchLabs'),
              onChanged: (q) {
                setState(() {
                  _q = q;
                  _labs = widget.api.searchLabs(q: q);
                });
              },
            ),
          ],
          body: FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey('labs|$_q|${widget.mode}'),
            future: _labs,
            builder: (context, snap) {
              if (snap.hasError) {
                return AdminEmpty(
                  icon: Icons.cloud_off_rounded,
                  title: loc.tr('admin.loadFailed'),
                  subtitle: friendlyError(snap.error!),
                );
              }
              if (!snap.hasData) return const ToothPageLoader();
              final labs = [
                for (final l in snap.data!)
                  if (widget.mode != _LabMode.transfer ||
                      '${l['id']}' != (widget.api.labId ?? ''))
                    l,
              ];
              if (labs.isEmpty) {
                return AdminEmpty(
                  icon: Icons.search_off_rounded,
                  title: loc.tr(_q.isEmpty ? 'join.noLabs' : 'admin.noMatches'),
                  subtitle: loc.tr(
                    _q.isEmpty ? 'join.noLabsSub' : 'admin.noMatchesSub',
                  ),
                );
              }
              return ListView.separated(
                itemCount: labs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final l = labs[i];
                  final name = '${l['name'] ?? ''}';
                  return AdminCard(
                    child: AdminRow(
                      leading: UserAvatar(
                        name: name,
                        url: l['avatar_url']?.toString(),
                        size: 44,
                      ),
                      title: name,
                      actions: [
                        AppButtons.primary(
                          onPressed: () => _pick(l),
                          icon: Icons.person_add_alt_1_rounded,
                          label: widget.mode == _LabMode.join
                              ? loc.tr('join.request')
                              : loc.tr('join.transferRequest'),
                          compact: true,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

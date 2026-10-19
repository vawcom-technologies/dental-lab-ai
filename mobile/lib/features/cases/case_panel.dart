import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/date_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/ui_kit.dart';
import 'case_store.dart';

String _when(BuildContext context, DateTime? at) =>
    at == null ? '' : formatAppDateTime(context, at);

/// Display name of a case item key: `scan`, `shade`, `smile`.
String caseItemLabel(AppLocalizations loc, String key) => loc.tr('case.item.$key');

// ── Flows ──────────────────────────────────────────────────────────────────

/// "Submit to lab": warns about missing items and offers "Submit anyway".
Future<void> submitCaseToLab(BuildContext context, CaseStore store, String patientId) async {
  final loc = AppLocalizations.of(context);
  Future<void> send(bool confirm) =>
      AppDialogs.runWithLoading(context, action: () => store.submit(patientId, confirmIncomplete: confirm));
  try {
    await send(false);
    if (context.mounted) AppSnackBars.success(context, loc.tr('case.submitted'));
  } on CaseIncomplete catch (e) {
    if (!context.mounted) return;
    final names = e.missing.map((m) => caseItemLabel(loc, m)).join(', ');
    final ok = await AppDialogs.confirm(
      context,
      title: loc.tr('case.incompleteTitle'),
      message: loc.trp('case.incompleteMsg', {'items': names}),
      confirmLabel: loc.tr('case.submitAnyway'),
    );
    if (!ok || !context.mounted) return;
    try {
      await send(true);
      if (context.mounted) AppSnackBars.success(context, loc.tr('case.submitted'));
    } catch (e) {
      if (context.mounted) AppDialogs.alert(context, title: loc.tr('case.submitFailed'), message: friendlyError(e));
    }
  } catch (e) {
    // 400 = no lab yet; the server's message says so.
    if (context.mounted) AppDialogs.alert(context, title: loc.tr('case.submitFailed'), message: friendlyError(e));
  }
}

/// Lab review. Reject asks for remarks (required).
Future<void> reviewCase(BuildContext context, CaseStore store, String patientId, {required bool approve}) async {
  final loc = AppLocalizations.of(context);
  String? remarks;
  if (approve) {
    final ok = await AppDialogs.confirm(
      context,
      title: loc.tr('case.approveTitle'),
      message: loc.tr('case.approveMsg'),
      confirmLabel: loc.tr('case.approve'),
    );
    if (!ok) return;
  } else {
    remarks = await askRequiredText(
      context,
      title: loc.tr('case.rejectTitle'),
      message: loc.tr('case.rejectMsg'),
      hint: loc.tr('case.remarksRequired'),
      confirmLabel: loc.tr('case.reject'),
      destructive: true,
    );
    if (remarks == null) return;
  }
  if (!context.mounted) return;
  try {
    await AppDialogs.runWithLoading(
      context,
      action: () => store.review(patientId, approve: approve, remarks: remarks),
    );
    if (context.mounted) {
      AppSnackBars.success(context, loc.tr(approve ? 'case.approvedToast' : 'case.rejectedToast'));
    }
  } catch (e) {
    if (context.mounted) AppSnackBars.error(context, friendlyError(e));
  }
}

/// Before changing an item on a completed case: it reopens the case.
/// Returns true when the change may go ahead.
Future<bool> confirmCaseChange(BuildContext context, CaseInfo? info) async {
  if (info?.status != 'completed') return true;
  final loc = AppLocalizations.of(context);
  return AppDialogs.confirm(
    context,
    title: loc.tr('case.reopenTitle'),
    message: loc.tr('case.reopenMsg'),
    confirmLabel: loc.tr('case.reopenGo'),
  );
}

// ── Widgets ────────────────────────────────────────────────────────────────

/// The lab's remarks from the last rejection. Nothing when there are none.
class CaseRejectionBanner extends StatelessWidget {
  const CaseRejectionBanner({super.key, required this.info, this.margin = EdgeInsets.zero});

  final CaseInfo? info;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final r = info?.rejection;
    if (r == null) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context);
    final who = [?r.by, _when(context, r.at)].where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: AppColors.danger, width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.report_gmailerrorred_rounded, color: AppColors.danger, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.tr('case.rejectedBanner'),
                      style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.danger)),
                  if (who.isNotEmpty)
                    Text(who, style: AppFonts.style(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 6),
                  Text(r.remarks, style: AppFonts.style(fontSize: 14, height: 1.35, color: AppColors.navy)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status, items, lab actions and history of one patient's case. Loads on
/// first show; [CaseStore.refresh] elsewhere updates it.
class CasePanel extends StatefulWidget {
  const CasePanel({super.key, required this.store, required this.patientId});

  final CaseStore store;
  final String patientId;

  @override
  State<CasePanel> createState() => _CasePanelState();
}

class _CasePanelState extends State<CasePanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.store.refresh(widget.patientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final info = widget.store.of(widget.patientId);
        final error = widget.store.errorOf(widget.patientId);
        if (info == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: error == null
                  ? const CupertinoActivityIndicator()
                  : Text(friendlyError(error), style: AppFonts.style(fontSize: 13, color: AppColors.muted)),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(loc.tr('case.title'),
                      style: AppFonts.style(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy)),
                ),
                StatusChip(statusKey: info.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              info.labName == null || info.labName!.isEmpty
                  ? loc.tr('case.noLab')
                  : loc.trp(info.sharedWithLab ? 'case.labShared' : 'case.labNotShared', {'lab': info.labName}),
              style: AppFonts.style(fontSize: 12.5, color: AppColors.muted),
            ),
            if (info.owner case final o?) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  UserAvatar(name: '${o['name'] ?? ''}', url: o['avatar_url']?.toString(), size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${o['name'] ?? '—'}',
                            style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                        Text(
                          // Dentists always appear as "Lab · Clinic".
                          dentistPlace(loc, o['lab_name']?.toString(), o['clinic_name']?.toString()),
                          style: AppFonts.style(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (key, has) in [('scan', info.hasScan), ('shade', info.hasShade), ('smile', info.hasSmile)])
                  _ItemChip(label: caseItemLabel(loc, key), done: has),
              ],
            ),
            CaseRejectionBanner(info: info, margin: const EdgeInsets.only(top: 12)),
            if (info.canSubmit || info.canReview) const SizedBox(height: 12),
            if (info.canSubmit)
              AppButtons.primary(
                onPressed: () => submitCaseToLab(context, widget.store, widget.patientId),
                icon: Icons.send_rounded,
                label: loc.tr('case.submit'),
              ),
            if (info.canReview)
              Row(
                children: [
                  Expanded(
                    child: AppButtons.danger(
                      onPressed: () => reviewCase(context, widget.store, widget.patientId, approve: false),
                      icon: Icons.close_rounded,
                      label: loc.tr('case.reject'),
                      soft: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButtons.primary(
                      onPressed: () => reviewCase(context, widget.store, widget.patientId, approve: true),
                      icon: Icons.check_rounded,
                      label: loc.tr('case.approve'),
                    ),
                  ),
                ],
              ),
            if (info.events.isNotEmpty) ...[
              const SizedBox(height: 16),
              SectionLabel(loc.tr('case.history')),
              const SizedBox(height: 8),
              for (final (i, e) in info.events.indexed)
                _EventRow(event: e, last: i == info.events.length - 1),
            ],
          ],
        );
      },
    );
  }
}

class _ItemChip extends StatelessWidget {
  const _ItemChip({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.success : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: AppFonts.style(fontSize: 12.5, fontWeight: FontWeight.w600, color: done ? AppColors.navy : AppColors.muted)),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.last});

  final CaseHistoryEvent event;
  final bool last;

  static const _style = {
    'created': (Icons.add_circle_outline_rounded, AppColors.dentalBlue),
    'scan_added': (Icons.view_in_ar_outlined, AppColors.dentalBlue),
    'submitted': (Icons.send_rounded, AppColors.review),
    'updated': (Icons.edit_outlined, AppColors.muted),
    'reopened': (Icons.lock_open_rounded, AppColors.warning),
    'approved': (Icons.verified_rounded, AppColors.success),
    'rejected': (Icons.cancel_outlined, AppColors.danger),
    'admin_override': (Icons.admin_panel_settings_outlined, AppColors.navy),
    'reassigned': (Icons.swap_horiz_rounded, AppColors.warning),
    'lab_left': (Icons.link_off_rounded, AppColors.warning),
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final e = event;
    final (icon, color) = _style[e.type] ?? (Icons.circle_outlined, AppColors.muted);
    final key = 'case.event.${e.type}';
    final label = loc.tr(key) == key ? e.type : loc.tr(key);
    final move = e.toStatus == null ? null : [?e.fromStatus, e.toStatus!].map(loc.statusLabel).join(' → ');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, size: 15, color: color),
                ),
                if (!last) Expanded(child: Container(width: 2, color: AppColors.border)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppFonts.style(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  Text(
                    [?e.actor, ?move, _when(context, e.at)].where((s) => s.isNotEmpty).join(' · '),
                    style: AppFonts.style(fontSize: 12, color: AppColors.muted),
                  ),
                  if (e.remarks != null)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border(left: BorderSide(color: color, width: 3)),
                      ),
                      child: Text(e.remarks!, style: AppFonts.style(fontSize: 13, height: 1.35, color: AppColors.navy)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/date_formats.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/patient_records.dart';
import '../../core/widgets/touchable.dart';
import '../../core/widgets/ui_kit.dart';
import 'case_store.dart';
import '../chat/widgets/quick_chat_card.dart';
import 'case_tool_routes.dart';

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

/// Lab review. Reject: overall remarks + per-item ok / needs work (+ note).
Future<void> reviewCase(BuildContext context, CaseStore store, String patientId, {required bool approve}) async {
  final loc = AppLocalizations.of(context);
  String? remarks;
  List<Map<String, dynamic>>? items;
  if (approve) {
    final ok = await AppDialogs.confirm(
      context,
      title: loc.tr('case.approveTitle'),
      message: loc.tr(store.of(patientId)?.status == 'rejected' ? 'case.approveRejectedMsg' : 'case.approveMsg'),
      confirmLabel: loc.tr('case.approve'),
    );
    if (!ok) return;
  } else {
    final result = await askCaseRejectFeedback(context, store.of(patientId));
    if (result == null) return;
    remarks = result.remarks;
    items = result.items;
  }
  if (!context.mounted) return;
  try {
    await AppDialogs.runWithLoading(
      context,
      action: () => store.review(patientId, approve: approve, remarks: remarks, items: items),
    );
    if (context.mounted) {
      AppSnackBars.success(context, loc.tr(approve ? 'case.approvedToast' : 'case.rejectedToast'));
    }
  } catch (e) {
    if (context.mounted) AppSnackBars.error(context, friendlyError(e));
  }
}

typedef CaseRejectResult = ({String remarks, List<Map<String, dynamic>> items});

/// Sheet: overall remarks + scan/shade/smile verdicts, prefilled from the
/// lab's drafts; items the lab suggested changes for are always "needs work".
Future<CaseRejectResult?> askCaseRejectFeedback(BuildContext context, [CaseInfo? info]) {
  return AppDialogs.sheet<CaseRejectResult>(
    context: context,
    builder: (_) => _RejectFeedbackSheet(info: info),
  );
}

/// Owning dentist: accept or dismiss the lab's suggestion for [item].
Future<void> resolveCaseSuggestion(
  BuildContext context,
  CaseStore store,
  String patientId,
  String item, {
  required bool accept,
}) async {
  final loc = AppLocalizations.of(context);
  if (!accept) {
    final ok = await AppDialogs.confirm(
      context,
      title: loc.tr('case.dismissTitle'),
      message: loc.trp('case.dismissMsg', {'item': caseItemLabel(loc, item)}),
      confirmLabel: loc.tr('case.dismiss'),
    );
    if (!ok || !context.mounted) return;
  }
  try {
    await AppDialogs.runWithLoading(
      context,
      action: () => store.resolveSuggestion(patientId, item, accept: accept),
    );
    if (context.mounted) {
      AppSnackBars.success(context, loc.tr(accept ? 'case.acceptedToast' : 'case.dismissedToast'));
    }
  } catch (e) {
    if (context.mounted) AppSnackBars.error(context, friendlyError(e));
  }
}

/// Shows a suggested shade / smile image (scans are opened in the Scans page).
Future<void> _viewSuggestion(BuildContext context, ApiClient api, CaseSuggestion s) async {
  final loc = AppLocalizations.of(context);
  try {
    final bytes = await AppDialogs.runWithLoading(context, action: () => api.downloadMediaBytes(s.fileUrl));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain))),
            Padding(
              padding: const EdgeInsets.all(8),
              child: AppButtons.ghost(onPressed: () => Navigator.pop(ctx), label: loc.commonClose),
            ),
          ],
        ),
      ),
    );
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

/// The lab's last rejection: remarks, per-item verdicts, the lab's suggested
/// changes (Accept / Dismiss for the owning dentist) and Resubmit. Nothing
/// when there is no open rejection. Actions need [store] and [patientId].
class CaseRejectionBanner extends StatelessWidget {
  const CaseRejectionBanner({
    super.key,
    required this.info,
    this.margin = EdgeInsets.zero,
    this.store,
    this.patientId,
    this.api,
  });

  final CaseInfo? info;
  final EdgeInsets margin;
  final CaseStore? store;
  final String? patientId;

  /// For "View" on a suggested shade / smile image.
  final ApiClient? api;

  @override
  Widget build(BuildContext context) {
    final info = this.info;
    final r = info?.rejection;
    if (info == null || r == null) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context);
    final who = [?r.by, _when(context, r.at)].where((s) => s.isNotEmpty).join(' · ');
    final work = [for (final i in r.items) if (i.needsWork) i];
    final ok = [for (final i in r.items) if (!i.needsWork) caseItemLabel(loc, i.item)];
    final store = this.store, pid = patientId;
    final actions = store != null && pid != null;
    final pending = info.suggestions.values.toList();
    final text = AppFonts.style(fontSize: 13, height: 1.3, color: AppColors.navy);
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: AppColors.danger, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.report_gmailerrorred_rounded, color: AppColors.danger, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loc.tr('case.rejectedBanner'),
                          style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.danger)),
                      if (who.isNotEmpty) Text(who, style: AppFonts.style(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                if (info.updatedSinceRejection) const CaseUpdatedChip(),
              ],
            ),
            if (r.remarks.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(r.remarks, style: AppFonts.style(fontSize: 14, height: 1.35, color: AppColors.navy)),
            ],
            for (final item in work)
              _BorderedNote(
                color: AppColors.danger.withValues(alpha: 0.35),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.priority_high_rounded, size: 18, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${caseItemLabel(loc, item.item)} · ${loc.tr('case.itemNeedsWork')}',
                              style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.danger)),
                          if (item.note != null) ...[const SizedBox(height: 2), Text(item.note!, style: text)],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (ok.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${loc.tr('case.itemOk')}: ${ok.join(', ')}', style: text)),
                  ],
                ),
              ),
            for (final sg in pending)
              _BorderedNote(
                color: AppColors.review.withValues(alpha: 0.4),
                top: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_fix_high_rounded, size: 18, color: AppColors.review),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            loc.trp('case.suggested', {'item': caseItemLabel(loc, sg.item), 'lab': sg.by ?? info.labName ?? ''}),
                            style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy),
                          ),
                        ),
                      ],
                    ),
                    if (actions && info.isOwner) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          if (api != null && sg.item != 'scan')
                            SoftPillButton(
                              icon: Icons.visibility_outlined,
                              label: loc.tr('case.view'),
                              onPressed: () => _viewSuggestion(context, api!, sg),
                            ),
                          SoftPillButton(
                            icon: Icons.close_rounded,
                            label: loc.tr('case.dismiss'),
                            danger: true,
                            onPressed: () => resolveCaseSuggestion(context, store, pid, sg.item, accept: false),
                          ),
                          SoftPillButton(
                            icon: Icons.check_rounded,
                            label: loc.tr('case.accept'),
                            selected: true,
                            onPressed: () => resolveCaseSuggestion(context, store, pid, sg.item, accept: true),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            if (actions && info.canSubmit) ...[
              const SizedBox(height: 12),
              if (pending.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(loc.tr('case.resolveFirst'), style: AppFonts.style(fontSize: 12, color: AppColors.muted)),
                ),
              AppButtons.primary(
                onPressed: pending.isEmpty ? () => resubmitCase(context, store, pid, info) : null,
                icon: Icons.send_rounded,
                label: loc.tr('case.resubmit'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BorderedNote extends StatelessWidget {
  const _BorderedNote({required this.color, required this.child, this.top = 8});
  final Color color;
  final double top;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.only(top: top),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: child,
      );
}

/// Resubmit after a rejection; asks first when nothing changed since.
Future<void> resubmitCase(BuildContext context, CaseStore store, String patientId, CaseInfo info) async {
  if (!info.updatedSinceRejection) {
    final loc = AppLocalizations.of(context);
    final ok = await AppDialogs.confirm(
      context,
      title: loc.tr('case.resubmitUnchangedTitle'),
      message: loc.tr('case.resubmitUnchangedMsg'),
      confirmLabel: loc.tr('case.resubmit'),
    );
    if (!ok || !context.mounted) return;
  }
  await submitCaseToLab(context, store, patientId);
}

/// Lab, inside Scan / Shade / Smile while reviewing: "Good to go / Needs work"
/// plus a note for this item. Saved as a draft; prefills the reject sheet.
class CaseFeedbackBar extends StatefulWidget {
  const CaseFeedbackBar({
    super.key,
    required this.store,
    required this.patientId,
    required this.item,
    this.margin = EdgeInsets.zero,
  });

  final CaseStore store;
  final String patientId;
  final String item; // scan | shade | smile
  final EdgeInsets margin;

  @override
  State<CaseFeedbackBar> createState() => _CaseFeedbackBarState();
}

class _CaseFeedbackBarState extends State<CaseFeedbackBar> {
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadNote();
    // The case may still be loading: fill the saved note in once it arrives,
    // or the next save would send an empty note over it.
    if (widget.store.of(widget.patientId) == null) widget.store.addListener(_loadNote);
  }

  void _loadNote() {
    final info = widget.store.of(widget.patientId);
    if (info == null) return;
    widget.store.removeListener(_loadNote);
    if (_note.text.isEmpty) _note.text = info.feedback[widget.item]?.note ?? '';
  }

  @override
  void dispose() {
    widget.store.removeListener(_loadNote);
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(String? status) async {
    setState(() => _saving = true);
    try {
      await widget.store.saveFeedback(widget.patientId, widget.item, status: status, note: _note.text);
    } catch (e) {
      if (mounted) AppSnackBars.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final info = widget.store.of(widget.patientId);
        if (info == null || !info.canSuggest) return const SizedBox.shrink();
        final loc = AppLocalizations.of(context);
        final current = info.feedback[widget.item]?.status;
        final suggested = info.suggestions.containsKey(widget.item);
        return Padding(
          padding: widget.margin,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.review.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: AppColors.review, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(loc.trp('case.feedbackTitle', {'item': caseItemLabel(loc, widget.item)}),
                    style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                const SizedBox(height: 2),
                Text(loc.tr(suggested ? 'case.feedbackSuggested' : 'case.feedbackSub'),
                    style: AppFonts.style(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!suggested)
                      SoftPillButton(
                        label: loc.tr('case.itemOk'),
                        selected: current == 'ok',
                        onPressed: _saving ? null : () => _save(current == 'ok' ? null : 'ok'),
                      ),
                    SoftPillButton(
                      label: loc.tr('case.itemNeedsWork'),
                      selected: current == 'needs_work' || suggested,
                      danger: true,
                      onPressed: _saving ? null : () => _save('needs_work'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _note,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(current ?? 'needs_work'),
                  decoration: InputDecoration(
                    hintText: loc.tr('case.itemNoteHint'),
                    suffixIcon: IconButton(
                      tooltip: loc.tr('case.saveNote'),
                      icon: const Icon(Icons.check_rounded),
                      onPressed: _saving ? null : () => _save(current ?? 'needs_work'),
                    ),
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

/// One patient's case: who sent it, what's on it (tap an item to open it),
/// the lab's last rejection, the owner's submit and a folded history.
/// The lab's Approve / Reject is [CaseDecisionBar]; pass [decisions] to show
/// it inline, or pin the bar under a scroll view yourself.
class CasePanel extends StatefulWidget {
  const CasePanel({
    super.key,
    required this.store,
    required this.patientId,
    this.patients,
    this.api,
    this.decisions = true,
  });

  final CaseStore store;
  final String patientId;

  /// When set, case items open Scans / Shade / Smile for this patient.
  final PatientSession? patients;
  final ApiClient? api;
  final bool decisions;

  @override
  State<CasePanel> createState() => _CasePanelState();
}

class _CasePanelState extends State<CasePanel> {
  bool _history = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.store.of(widget.patientId) == null) widget.store.refresh(widget.patientId);
    });
  }

  VoidCallback? _opener(String tool) {
    final api = widget.api, patients = widget.patients;
    if (api == null || patients == null) return null;
    return () => openCaseTool(context, api: api, patients: patients, patientId: widget.patientId, tool: tool);
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
        final hint = _statusHint(loc, info);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CaseOwner(info: info),
            const SizedBox(height: 14),
            Row(
              children: [
                StatusChip(statusKey: info.status),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hint ??
                        (info.labName == null || info.labName!.isEmpty
                            ? loc.tr('case.noLab')
                            : loc.trp(info.sharedWithLab ? 'case.labShared' : 'case.labNotShared', {'lab': info.labName})),
                    style: AppFonts.style(fontSize: 12.5, color: AppColors.muted, height: 1.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionLabel(loc.tr('case.items')),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, c) {
                final tiles = [
                  for (final (key, icon, has) in [
                    ('scan', Icons.view_in_ar_outlined, info.hasScan),
                    ('shade', Icons.palette_outlined, info.hasShade),
                    ('smile', Icons.sentiment_satisfied_alt_outlined, info.hasSmile),
                  ])
                    _ItemTile(
                      label: caseItemLabel(loc, key),
                      icon: icon,
                      done: has,
                      feedback: info.feedback[key],
                      suggested: info.suggestions.containsKey(key),
                      onTap: _opener(key),
                    ),
                ];
                // Three across when there's room, else a list.
                if (c.maxWidth >= 420) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, t) in tiles.indexed) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: t),
                      ],
                    ],
                  );
                }
                return Column(
                  children: [
                    for (final (i, t) in tiles.indexed) ...[if (i > 0) const SizedBox(height: 8), t],
                  ],
                );
              },
            ),
            CaseRejectionBanner(
              info: info,
              margin: const EdgeInsets.only(top: 14),
              store: widget.store,
              patientId: widget.patientId,
              api: widget.api,
            ),
            if (info.canSubmit && info.rejection == null) ...[
              const SizedBox(height: 14),
              AppButtons.primary(
                onPressed: () => submitCaseToLab(context, widget.store, widget.patientId),
                icon: Icons.send_rounded,
                label: loc.tr('case.submit'),
              ),
            ],
            if (widget.decisions && info.canReview) ...[
              const SizedBox(height: 14),
              CaseDecisionBar(store: widget.store, patientId: widget.patientId, padding: EdgeInsets.zero),
            ],
            if (info.events.isNotEmpty) ...[
              const SizedBox(height: 14),
              Touchable(
                onTap: () => setState(() => _history = !_history),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: SectionLabel(loc.trp('case.historyCount', {'n': info.events.length}))),
                      AnimatedRotation(
                        turns: _history ? 0.5 : 0,
                        duration: AppMotion.normal,
                        child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: AppMotion.normal,
                curve: AppMotion.easeOut,
                alignment: Alignment.topCenter,
                child: _history
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          children: [
                            for (final (i, e) in info.events.indexed)
                              _EventRow(event: e, last: i == info.events.length - 1),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ],
        );
      },
    );
  }

  /// What the status means for the lab deciding it; null for everyone else.
  String? _statusHint(AppLocalizations loc, CaseInfo info) {
    if (!info.canReview) return null;
    return switch (info.status) {
      'rejected' => loc.tr('case.hintRejected'),
      _ => loc.tr('case.hintInReview'),
    };
  }
}

/// The dentist who owns the case, with Message for everyone else.
class _CaseOwner extends StatelessWidget {
  const _CaseOwner({required this.info});

  final CaseInfo info;

  @override
  Widget build(BuildContext context) {
    final o = info.owner;
    if (o == null) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context);
    final id = '${o['id'] ?? ''}';
    final name = '${o['name'] ?? ''}'.trim();
    return Row(
      children: [
        UserAvatar(name: name, url: o['avatar_url']?.toString(), size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name.isEmpty ? '—' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy)),
              Text(
                // Dentists always appear as "Lab · Clinic".
                dentistPlace(loc, o['lab_name']?.toString(), o['clinic_name']?.toString()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.style(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (!info.isOwner && id.isNotEmpty)
          AppButtons.secondary(
            onPressed: () => messageUser(context, id),
            icon: Icons.chat_bubble_outline_rounded,
            label: loc.tr('case.message'),
            compact: true,
          ),
      ],
    );
  }
}

/// The lab's decision: Reject / Approve while in review; on a rejected case,
/// Update feedback / Approve. Nothing for anyone who can't decide.
class CaseDecisionBar extends StatelessWidget {
  const CaseDecisionBar({
    super.key,
    required this.store,
    required this.patientId,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
  });

  final CaseStore store;
  final String patientId;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final info = store.of(patientId);
        if (info == null || !info.canReview) return const SizedBox.shrink();
        final loc = AppLocalizations.of(context);
        final rejected = info.status == 'rejected';
        final blocked = info.suggestions.isNotEmpty;
        return Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (blocked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(loc.tr('case.approveBlocked'),
                      style: AppFonts.style(fontSize: 12, color: AppColors.muted, height: 1.3)),
                ),
              Row(
                children: [
                  Expanded(
                    child: AppButtons.danger(
                      onPressed: () => reviewCase(context, store, patientId, approve: false),
                      icon: rejected ? Icons.edit_note_rounded : Icons.close_rounded,
                      label: loc.tr(rejected ? 'case.updateFeedback' : 'case.reject'),
                      soft: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButtons.primary(
                      // A lab change always goes back to the dentist: reject instead.
                      onPressed: blocked ? null : () => reviewCase(context, store, patientId, approve: true),
                      icon: Icons.check_rounded,
                      label: loc.tr('case.approve'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The whole case review for one patient — case, records, pinned decision —
/// behind a single loader, so nothing appears half-built.
class CaseReviewView extends StatefulWidget {
  const CaseReviewView({
    super.key,
    required this.store,
    required this.patientId,
    required this.api,
    this.patients,
    this.records = true,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 24),
  });

  final CaseStore store;
  final String patientId;
  final ApiClient api;
  final PatientSession? patients;
  final bool records;
  final EdgeInsets padding;

  @override
  State<CaseReviewView> createState() => _CaseReviewViewState();
}

class _CaseReviewViewState extends State<CaseReviewView> {
  late final Future<List<List<Map<String, dynamic>>>>? _records =
      widget.records ? loadPatientRecords(widget.api, widget.patientId) : null;
  late final Future<void> _ready = Future.wait<Object?>([
    widget.store.refresh(widget.patientId),
    // A records error shows inside Records; it mustn't block the case.
    if (_records != null) _records.then<Object?>((r) => r, onError: (_) => null),
  ]);

  @override
  Widget build(BuildContext context) {
    final patients = widget.patients;
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const ToothPageLoader(inPlace: true);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: widget.padding,
                children: [
                  CasePanel(
                    store: widget.store,
                    patientId: widget.patientId,
                    patients: patients,
                    api: patients == null ? null : widget.api,
                    decisions: false,
                  ),
                  if (_records != null)
                    PatientRecords(
                      api: widget.api,
                      patientId: widget.patientId,
                      rows: _records,
                      onOpen: patients == null
                          ? null
                          : (tool) => openCaseTool(
                                context,
                                api: widget.api,
                                patients: patients,
                                patientId: widget.patientId,
                                tool: tool,
                              ),
                    ),
                ],
              ),
            ),
            CaseDecisionBarDock(store: widget.store, patientId: widget.patientId),
          ],
        );
      },
    );
  }
}

/// [CaseDecisionBar] pinned under a scroll view, on a hairline divider.
class CaseDecisionBarDock extends StatelessWidget {
  const CaseDecisionBarDock({super.key, required this.store, required this.patientId});

  final CaseStore store;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!(store.of(patientId)?.canReview ?? false)) return const SizedBox.shrink();
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.6))),
          ),
          child: SafeArea(
            top: false,
            child: CaseDecisionBar(store: store, patientId: patientId),
          ),
        );
      },
    );
  }
}

/// One case item: saved or missing, the lab's draft verdict, and a tap that
/// opens it when [onTap] is set.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.label,
    required this.icon,
    required this.done,
    this.feedback,
    this.suggested = false,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool done;
  final CaseItemFeedback? feedback;
  final bool suggested;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final color = done ? AppColors.success : AppColors.muted;
    final (String state, Color stateColor) = suggested
        ? (loc.tr('case.tileSuggested'), AppColors.review)
        : switch (feedback?.status) {
            'ok' => (loc.tr('case.itemOk'), AppColors.success),
            'needs_work' => (loc.tr('case.itemNeedsWork'), AppColors.danger),
            _ => (loc.tr(done ? 'case.saved' : 'case.missing'), color),
          };
    final tile = Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (done ? AppColors.border : AppColors.muted).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          AdminIcon(icon: icon, color: done ? AppColors.dentalBlue : AppColors.muted, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(state,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.style(fontSize: 12, fontWeight: FontWeight.w600, color: stateColor)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.muted),
        ],
      ),
    );
    if (onTap == null) return tile;
    return Tooltip(
      message: loc.trp('case.openTool', {'item': label}),
      child: Pressable(onTap: onTap, scale: 0.97, builder: (_, _) => tile),
    );
  }
}

/// "Updated by dentist": a rejected case changed since the lab's review.
class CaseUpdatedChip extends StatelessWidget {
  const CaseUpdatedChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.review.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.edit_outlined, size: 13, color: AppColors.review),
          const SizedBox(width: 4),
          Flexible(
            child: Text(AppLocalizations.of(context).tr('case.updatedChip'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.style(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.review)),
          ),
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
    'lab_suggested': (Icons.auto_fix_high_rounded, AppColors.review),
    'suggestion_accepted': (Icons.check_circle_outline_rounded, AppColors.success),
    'suggestion_dismissed': (Icons.do_not_disturb_on_outlined, AppColors.muted),
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

class _RejectFeedbackSheet extends StatefulWidget {
  const _RejectFeedbackSheet({this.info});

  final CaseInfo? info;

  @override
  State<_RejectFeedbackSheet> createState() => _RejectFeedbackSheetState();
}

class _RejectFeedbackSheetState extends State<_RejectFeedbackSheet> {
  final _remarks = TextEditingController();
  final _notes = {
    for (final k in const ['scan', 'shade', 'smile']) k: TextEditingController(),
  };
  final _status = {
    for (final k in const ['scan', 'shade', 'smile']) k: 'ok',
  };

  Set<String> get _suggested => widget.info?.suggestions.keys.toSet() ?? const {};

  @override
  void initState() {
    super.initState();
    for (final MapEntry(:key, :value) in (widget.info?.feedback ?? const {}).entries) {
      if (!_status.containsKey(key)) continue;
      _status[key] = value.needsWork ? 'needs_work' : 'ok';
      _notes[key]!.text = value.note ?? '';
    }
    for (final k in _suggested) {
      if (_status.containsKey(k)) _status[k] = 'needs_work';
    }
  }

  @override
  void dispose() {
    _remarks.dispose();
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready {
    // With suggestions the server fills in "Lab made changes, please confirm".
    if (_remarks.text.trim().isEmpty && _suggested.isEmpty) return false;
    for (final k in _status.keys) {
      if (_status[k] == 'needs_work' && _notes[k]!.text.trim().isEmpty && !_suggested.contains(k)) return false;
    }
    return true;
  }

  void _submit() {
    if (!_ready) return;
    Navigator.pop(
      context,
      (
        remarks: _remarks.text.trim(),
        items: [
          for (final k in _status.keys)
            {
              'item': k,
              'status': _status[k],
              'note': _status[k] == 'needs_work' ? _notes[k]!.text.trim() : null,
            },
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(loc.tr('case.rejectTitle'),
                  style: AppFonts.style(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.navy)),
              const SizedBox(height: 6),
              Text(loc.tr('case.rejectMsg'), style: AppFonts.style(fontSize: 13, color: AppColors.muted)),
              const SizedBox(height: 14),
              TextField(
                controller: _remarks,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: loc.tr(_suggested.isEmpty ? 'case.remarksRequired' : 'case.remarksLabChanged'),
                ),
              ),
              const SizedBox(height: 16),
              Text(loc.tr('case.itemFeedback'),
                  style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy)),
              const SizedBox(height: 8),
              for (final key in _status.keys) ...[
                const SizedBox(height: 8),
                Text(caseItemLabel(loc, key),
                    style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.navy)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SoftPillButton(
                      label: loc.tr('case.itemOk'),
                      selected: _status[key] == 'ok',
                      // A suggested change always needs the dentist's confirmation.
                      onPressed: _suggested.contains(key) ? null : () => setState(() => _status[key] = 'ok'),
                    ),
                    const SizedBox(width: 8),
                    SoftPillButton(
                      label: loc.tr('case.itemNeedsWork'),
                      selected: _status[key] == 'needs_work',
                      danger: true,
                      onPressed: () => setState(() => _status[key] = 'needs_work'),
                    ),
                  ],
                ),
                if (_status[key] == 'needs_work') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notes[key],
                    minLines: 1,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(hintText: loc.tr('case.itemNoteHint')),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButtons.ghost(onPressed: () => Navigator.pop(context), label: loc.cancel),
                  const SizedBox(width: 8),
                  AppButtons.danger(
                    onPressed: _ready ? _submit : null,
                    icon: Icons.close_rounded,
                    label: loc.tr('case.reject'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

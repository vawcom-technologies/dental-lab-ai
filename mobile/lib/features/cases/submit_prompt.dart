import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/widgets/ui_kit.dart';
import 'case_store.dart';

/// After shade/smile Save or scans Save to case: if the case is ready,
/// ask before submitting (no silent auto-submit).
Future<void> maybePromptSubmitToLab(
  BuildContext context, {
  required CaseStore cases,
  required String patientId,
}) async {
  final info = await cases.refresh(patientId);
  if (!context.mounted || info == null || !info.readyToSubmit) return;
  final loc = AppLocalizations.of(context);
  final ok = await AppDialogs.confirm(
    context,
    title: loc.tr(info.status == 'rejected' ? 'case.resubmitReadyTitle' : 'case.submitReadyTitle'),
    message: loc.tr(info.status == 'rejected' ? 'case.resubmitReadyMsg' : 'case.submitReadyMsg'),
    confirmLabel: loc.tr(info.status == 'rejected' ? 'case.resubmit' : 'case.submit'),
  );
  if (!ok || !context.mounted) return;
  try {
    await AppDialogs.runWithLoading(
      context,
      action: () => cases.submit(patientId),
    );
    if (context.mounted) {
      AppSnackBars.success(context, loc.tr('case.submitted'));
    }
  } catch (e) {
    if (context.mounted) AppSnackBars.error(context, friendlyError(e));
  }
}

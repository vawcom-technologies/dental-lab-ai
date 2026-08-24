import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';
import 'app_dialogs.dart';
import '../l10n/app_localizations.dart';

/// Let the current pointer / mouse-tracker update finish before mutating the
/// overlay (show/pop dialog). Required on Flutter Web after file pickers and
/// dialog button presses — otherwise MouseTracker asserts
/// `!_debugDuringDeviceUpdate`.
Future<void> _settleGestures() async {
  await Future<void>.delayed(Duration.zero);
  final binding = WidgetsBinding.instance;
  if (binding.schedulerPhase != SchedulerPhase.idle) {
    await binding.endOfFrame;
  }
}

Future<bool> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  Color? confirmColor,
}) async {
  await _settleGestures();
  if (!context.mounted) return false;

  final ok = await AppDialogs.confirm(
    context,
    title: title,
    message: body,
    confirmLabel: confirmLabel,
    isDestructive: confirmColor == AppColors.danger,
  );

  // Dialog route removal also races the mouse tracker on web.
  await _settleGestures();
  return ok;
}

/// Confirm before uploading a picked clinical media file.
Future<bool> confirmPatientMediaUpload(BuildContext context) {
  return _showConfirmDialog(
    context,
    title: AppLocalizations.of(context).mediaUploadItem,
    body: AppLocalizations.of(context).mediaUploadBody,
    confirmLabel: AppLocalizations.of(context).mediaUploadConfirm,
  );
}

/// Confirm before permanently deleting clinical media.
Future<bool> confirmPatientMediaDelete(BuildContext context) {
  return _showConfirmDialog(
    context,
    title: AppLocalizations.of(context).mediaDeleteItem,
    body: AppLocalizations.of(context).mediaDeleteBody,
    confirmLabel: AppLocalizations.of(context).commonDelete,
    confirmColor: AppColors.danger,
  );
}

/// Blocking native iOS loading dialog while [action] runs.
Future<T> runWithToothLoadingDialog<T>(
  BuildContext context, {
  required Future<T> Function() action,
  String message = 'Uploading…',
}) async {
  await _settleGestures();
  if (!context.mounted) {
    throw StateError('Context unmounted before loading dialog');
  }

  try {
    return await AppDialogs.runWithLoading(
      context,
      action: action,
      message: message,
    );
  } finally {
    await _settleGestures();
  }
}

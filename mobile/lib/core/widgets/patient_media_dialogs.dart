import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';
import 'tooth_loader.dart';

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

  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: confirmColor == null
              ? null
              : FilledButton.styleFrom(backgroundColor: confirmColor),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  // Dialog route removal also races the mouse tracker on web.
  await _settleGestures();
  return ok == true;
}

/// Confirm before uploading a picked clinical media file.
Future<bool> confirmPatientMediaUpload(BuildContext context) {
  return _showConfirmDialog(
    context,
    title: 'Upload item?',
    body: 'Upload and save this item to the patient record?',
    confirmLabel: 'Upload',
  );
}

/// Confirm before permanently deleting clinical media.
Future<bool> confirmPatientMediaDelete(BuildContext context) {
  return _showConfirmDialog(
    context,
    title: 'Delete item?',
    body:
        'Are you sure you want to delete this item? This action cannot be undone.',
    confirmLabel: 'Delete',
    confirmColor: AppColors.danger,
  );
}

/// Blocking dialog with [ToothLoadingIndicator] while [action] runs.
Future<T> runWithToothLoadingDialog<T>(
  BuildContext context, {
  required Future<T> Function() action,
  String message = 'Uploading…',
}) async {
  await _settleGestures();
  if (!context.mounted) {
    throw StateError('Context unmounted before loading dialog');
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ToothLoadingIndicator(size: 48, loadingText: message),
      ),
    ),
  );

  try {
    return await action();
  } finally {
    // Pop after the current event loop turn so we are not still inside a
    // pointer/mouse-tracker update from the confirm dialog button.
    await _settleGestures();
    if (context.mounted && navigator.canPop()) {
      navigator.pop();
      await _settleGestures();
    }
  }
}

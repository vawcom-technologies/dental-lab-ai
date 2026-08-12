import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'tooth_loader.dart';

/// iOS-styled alerts / confirms / sheets used across the iPad app.
class AppDialogs {
  AppDialogs._();

  static Future<void> alert(
    BuildContext context, {
    required String title,
    String? message,
    String okLabel = 'OK',
  }) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: message == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message),
              ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(okLabel),
          ),
        ],
      ),
    );
  }

  /// Returns `true` when the user confirms.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'OK',
    bool isDestructive = false,
  }) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: message == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message),
              ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          CupertinoDialogAction(
            isDefaultAction: !isDestructive,
            isDestructiveAction: isDestructive,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Single-line text prompt (native alert + Cupertino field).
  static Future<String?> prompt(
    BuildContext context, {
    required String title,
    String? message,
    String? initial,
    String placeholder = '',
    String cancelLabel = 'Cancel',
    String confirmLabel = 'OK',
    bool obscureText = false,
    int maxLines = 1,
    /// When set, confirm stays disabled until the field equals this (trimmed).
    String? confirmEquals,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final matches = confirmEquals == null ||
                controller.text.trim() == confirmEquals;
            return CupertinoAlertDialog(
              title: Text(title),
              content: Column(
                children: [
                  if (message != null) ...[
                    const SizedBox(height: 8),
                    Text(message),
                  ],
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: controller,
                    placeholder: placeholder,
                    obscureText: obscureText,
                    maxLines: maxLines,
                    minLines: maxLines > 1 ? maxLines : 1,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    autofocus: true,
                    onChanged: confirmEquals == null
                        ? null
                        : (_) => setLocal(() {}),
                  ),
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(cancelLabel),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: matches
                      ? () => Navigator.of(ctx).pop(controller.text)
                      : null,
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        );
      },
    );
    // Dispose after the route finishes tearing down (avoids use-after-dispose
    // during the Cupertino dialog dismiss animation).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    return result;
  }

  /// Blocking loading dialog (native chrome).
  static Future<T> runWithLoading<T>(
    BuildContext context, {
    required Future<T> Function() action,
    String message = 'Please wait…',
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: CupertinoAlertDialog(
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CupertinoActivityIndicator(radius: 14),
                const SizedBox(height: 14),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      return await action();
    } finally {
      if (navigator.canPop()) navigator.pop();
    }
  }

  /// Form / multi-field sheet with frosted iOS chrome.
  static Future<T?> sheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    double maxWidth = 480,
  }) {
    return showCupertinoDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: GlassSurface(
                borderRadius: BorderRadius.circular(24),
                blur: 28,
                tint: Colors.white.withValues(alpha: 0.78),
                padding: EdgeInsets.zero,
                child: builder(ctx),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Present a content sheet from the bottom (detail / lists).
  static Future<T?> modalSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    return showCupertinoModalPopup<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: builder(ctx),
      ),
    );
  }
}

/// Optional tooth-branded loading dialog (prefer [AppDialogs.runWithLoading]
/// for fully native chrome).
class AppLoadingDialog {
  AppLoadingDialog._();

  static Future<T> show<T>(
    BuildContext context, {
    required Future<T> Function() action,
    String message = 'Loading…',
  }) {
    return AppDialogs.runWithLoading(
      context,
      action: action,
      message: message,
    );
  }
}

/// Kept for callers that still want the tooth spinner in a Cupertino alert.
Widget toothLoadingDialogContent({String message = 'Uploading…'}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: ToothLoadingIndicator(size: 40, loadingText: message),
  );
}

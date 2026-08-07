import 'package:flutter/material.dart';

import '../haptics/app_haptics.dart';
import '../theme/app_theme.dart';

/// App-wide floating snackbars: green for success, red for errors/rejections.
class AppSnackBars {
  AppSnackBars._();

  static const _duration = Duration(seconds: 3);

  /// Successful completion (create, save, grant, approve, sync, etc.).
  static void success(
    BuildContext context,
    String message, {
    bool haptic = true,
  }) {
    _show(
      context,
      message: message,
      background: AppColors.success,
      foreground: Colors.white,
      icon: Icons.check_circle_outline_rounded,
      haptic: haptic ? AppHaptics.success : null,
    );
  }

  /// Failures, permission denials, rejections, and validation problems.
  static void error(
    BuildContext context,
    String message, {
    bool haptic = true,
  }) {
    _show(
      context,
      message: message,
      background: AppColors.danger,
      foreground: Colors.white,
      icon: Icons.error_outline_rounded,
      haptic: haptic ? AppHaptics.warn : null,
    );
  }

  /// Neutral guidance that is neither success nor failure.
  static void info(BuildContext context, String message) {
    _show(
      context,
      message: message,
      background: AppColors.navy,
      foreground: Colors.white,
      icon: Icons.info_outline_rounded,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required Color background,
    required Color foreground,
    required IconData icon,
    Future<void> Function()? haptic,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final text = message.replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) return;

    haptic?.call();
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: _duration,
        backgroundColor: background,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

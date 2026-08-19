import 'package:flutter/material.dart';

import '../errors/user_facing_error.dart';
import '../haptics/app_haptics.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// App-wide floating soft-pill toasts (success / error / info).
///
/// Prefer this over inline banners so feedback stays consistent.
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
      background: AppColors.successSoft,
      foreground: AppColors.success,
      border: AppColors.success.withValues(alpha: 0.22),
      icon: Icons.check_circle_rounded,
      haptic: haptic ? AppHaptics.success : null,
    );
  }

  /// Failures, permission denials, rejections, and validation problems.
  static void error(
    BuildContext context,
    String message, {
    bool haptic = true,
  }) {
    final loc = _locOf(context);
    _show(
      context,
      message: friendlyError(message, loc),
      background: AppColors.dangerSoft,
      foreground: AppColors.danger,
      border: AppColors.danger.withValues(alpha: 0.22),
      icon: Icons.error_outline_rounded,
      haptic: haptic ? AppHaptics.warn : null,
    );
  }

  /// Neutral guidance that is neither success nor failure.
  static void info(
    BuildContext context,
    String message, {
    VoidCallback? onTap,
    Duration duration = _duration,
  }) {
    _show(
      context,
      message: message,
      background: const Color(0xFFEAF3FC),
      foreground: AppColors.navy,
      border: AppColors.dentalBlue.withValues(alpha: 0.22),
      icon: Icons.notifications_active_outlined,
      onTap: onTap,
      duration: duration,
    );
  }

  /// Call from `build` so a stored error/success is toasted once, not painted
  /// as permanent on-screen text. Assign the return value back to the field.
  static String? drain(
    BuildContext context,
    String? message, {
    bool error = true,
  }) {
    final text = message?.replaceFirst('Exception: ', '').trim();
    if (text == null || text.isEmpty) return null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (error) {
        AppSnackBars.error(context, text);
      } else {
        AppSnackBars.success(context, text);
      }
    });
    return null;
  }

  static AppLocalizations? _locOf(BuildContext context) {
    try {
      return AppLocalizations.of(context);
    } catch (_) {
      return null;
    }
  }

  static void _show(
    BuildContext context, {
    required String message,
    required Color background,
    required Color foreground,
    required Color border,
    required IconData icon,
    Future<void> Function()? haptic,
    VoidCallback? onTap,
    Duration duration = _duration,
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
        duration: duration,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        content: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
              boxShadow: NeoShadows.soft(depth: 0.45),
            ),
            child: Row(
              children: [
                Icon(icon, color: foreground, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: AppFonts.style(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

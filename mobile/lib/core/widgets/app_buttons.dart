import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'busy_action.dart';
import 'glass_surface.dart';
import 'pressable.dart';
import 'soft_pill_button.dart';

/// Canonical button styles for Elite Dent (iPad).
///
/// Prefer these helpers over ad-hoc [FilledButton.styleFrom] so chrome stays
/// consistent. Solid navy = primary; soft neo = secondary; blue text = ghost;
/// glass = floating chrome over media / gradients.
///
/// Compact / sub-actions use the shared pill shape with tactile press feedback.
class AppButtons {
  AppButtons._();

  static const _radius = 12.0;
  static const _pillRadius = 999.0;

  static BorderRadius _radiusFor({required bool compact}) =>
      BorderRadius.circular(compact ? _pillRadius : _radius);

  // ── Styles ──────────────────────────────────────────────────────────────

  static ButtonStyle primaryStyle({bool compact = false}) {
    return FilledButton.styleFrom(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.35),
      disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
      elevation: 0,
      shadowColor: Colors.transparent,
      overlayColor: Colors.white.withValues(alpha: 0.12),
      minimumSize: Size(compact ? 0 : 44, compact ? 36 : 44),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 8 : 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: _radiusFor(compact: compact)),
      textStyle: AppFonts.style(
        fontWeight: FontWeight.w600,
        fontSize: compact ? 13 : 16,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      animationDuration: const Duration(milliseconds: 120),
    );
  }

  static ButtonStyle secondaryStyle({bool compact = false}) {
    return OutlinedButton.styleFrom(
      foregroundColor: AppColors.navy,
      backgroundColor: AppColors.neo.withValues(alpha: 0.9),
      disabledForegroundColor: AppColors.muted,
      side: BorderSide(color: AppColors.border.withValues(alpha: 0.7)),
      elevation: 0,
      overlayColor: AppColors.navy.withValues(alpha: 0.06),
      minimumSize: Size(compact ? 0 : 44, compact ? 36 : 44),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 8 : 11,
      ),
      shape: RoundedRectangleBorder(borderRadius: _radiusFor(compact: compact)),
      textStyle: AppFonts.style(
        fontWeight: FontWeight.w600,
        fontSize: compact ? 13 : 16,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      animationDuration: const Duration(milliseconds: 120),
    );
  }

  static ButtonStyle ghostStyle({bool compact = false}) {
    return TextButton.styleFrom(
      foregroundColor: AppColors.dentalBlue,
      disabledForegroundColor: AppColors.muted,
      overlayColor: AppColors.dentalBlue.withValues(alpha: 0.08),
      minimumSize: Size(compact ? 0 : 44, compact ? 34 : 40),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 12,
        vertical: compact ? 8 : 8,
      ),
      shape: RoundedRectangleBorder(borderRadius: _radiusFor(compact: compact)),
      textStyle: AppFonts.style(
        fontWeight: FontWeight.w600,
        fontSize: compact ? 13 : 16,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      animationDuration: const Duration(milliseconds: 120),
    );
  }

  static ButtonStyle dangerStyle({bool compact = false}) {
    return FilledButton.styleFrom(
      backgroundColor: AppColors.danger,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.danger.withValues(alpha: 0.35),
      elevation: 0,
      overlayColor: Colors.white.withValues(alpha: 0.12),
      minimumSize: Size(compact ? 0 : 44, compact ? 36 : 44),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 8 : 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: _radiusFor(compact: compact)),
      textStyle: AppFonts.style(
        fontWeight: FontWeight.w600,
        fontSize: compact ? 13 : 16,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      animationDuration: const Duration(milliseconds: 120),
    );
  }

  static ButtonStyle dangerSoftStyle({bool compact = false}) {
    return OutlinedButton.styleFrom(
      foregroundColor: AppColors.danger,
      backgroundColor: AppColors.dangerSoft,
      side: BorderSide(color: AppColors.danger.withValues(alpha: 0.2)),
      elevation: 0,
      overlayColor: AppColors.danger.withValues(alpha: 0.08),
      minimumSize: Size(compact ? 0 : 44, compact ? 36 : 44),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 8 : 11,
      ),
      shape: RoundedRectangleBorder(borderRadius: _radiusFor(compact: compact)),
      textStyle: AppFonts.style(
        fontWeight: FontWeight.w600,
        fontSize: compact ? 13 : 16,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      animationDuration: const Duration(milliseconds: 120),
    );
  }

  // ── Widgets ─────────────────────────────────────────────────────────────

  static Widget primary({
    Key? key,
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    bool compact = false,
    bool busy = false,
  }) {
    if (compact && !busy) {
      return SoftPillButton(
        key: key,
        label: label,
        icon: icon,
        filled: true,
        onPressed: onPressed,
        compact: true,
      );
    }
    final style = primaryStyle(compact: compact);
    final child = Text(label);
    if (icon == null) {
      return FilledButton(
        key: key,
        style: style,
        onPressed: busy ? null : onPressed,
        child: busy
            ? const BusySpinner(size: 18, color: Colors.white)
            : child,
      );
    }
    return FilledButton.icon(
      key: key,
      style: style,
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const BusySpinner(size: 16, color: Colors.white)
          : Icon(icon, size: compact ? 16 : 18),
      label: child,
    );
  }

  static Widget secondary({
    Key? key,
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    bool compact = false,
    bool busy = false,
  }) {
    if (compact && !busy) {
      return SoftPillButton(
        key: key,
        label: label,
        icon: icon,
        onPressed: onPressed,
        compact: true,
      );
    }
    final style = secondaryStyle(compact: compact);
    final child = Text(label);
    if (icon == null) {
      return OutlinedButton(
        key: key,
        style: style,
        onPressed: busy ? null : onPressed,
        child: busy ? const BusySpinner(size: 18) : child,
      );
    }
    return OutlinedButton.icon(
      key: key,
      style: style,
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const BusySpinner(size: 16, color: AppColors.navy)
          : Icon(icon, size: compact ? 16 : 18),
      label: child,
    );
  }

  static Widget ghost({
    Key? key,
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    bool compact = false,
  }) {
    if (compact) {
      return SoftPillButton(
        key: key,
        label: label,
        icon: icon,
        onPressed: onPressed,
        compact: true,
      );
    }
    return TextButton(
      key: key,
      style: ghostStyle(compact: compact),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  static Widget danger({
    Key? key,
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    bool compact = false,
    bool soft = false,
    bool busy = false,
  }) {
    if (compact && soft && !busy) {
      return SoftPillButton(
        key: key,
        label: label,
        icon: icon ?? Icons.delete_outline_rounded,
        danger: true,
        onPressed: onPressed,
        compact: true,
      );
    }
    final style =
        soft ? dangerSoftStyle(compact: compact) : dangerStyle(compact: compact);
    if (soft) {
      return OutlinedButton.icon(
        key: key,
        style: style,
        onPressed: busy ? null : onPressed,
        icon: busy
            ? BusySpinner(size: 16, color: AppColors.danger)
            : Icon(icon ?? Icons.delete_outline_rounded, size: 18),
        label: Text(label),
      );
    }
    if (icon == null) {
      return FilledButton(
        key: key,
        style: style,
        onPressed: busy ? null : onPressed,
        child: busy
            ? const BusySpinner(size: 18, color: Colors.white)
            : Text(label),
      );
    }
    return FilledButton.icon(
      key: key,
      style: style,
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const BusySpinner(size: 16, color: Colors.white)
          : Icon(icon, size: 18),
      label: Text(label),
    );
  }

  /// Soft pill sub-button (alias of [SoftPillButton]).
  static Widget pill({
    Key? key,
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    bool selected = false,
    bool danger = false,
    bool filled = false,
  }) {
    return SoftPillButton(
      key: key,
      label: label,
      icon: icon,
      selected: selected,
      danger: danger,
      filled: filled,
      onPressed: onPressed,
    );
  }

  /// Standard header / chrome icon control with press scale.
  static Widget icon({
    Key? key,
    required VoidCallback? onPressed,
    required IconData icon,
    String? tooltip,
    Color? color,
    bool busy = false,
  }) {
    final fg = color ?? AppColors.navy;
    final content = Pressable(
      onTap: busy ? null : onPressed,
      enabled: onPressed != null && !busy,
      scale: 0.9,
      builder: (context, pressed) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 100),
          opacity: pressed ? 0.65 : 1,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: busy
                  ? BusySpinner(size: 18, color: fg)
                  : Icon(icon, size: 20, color: fg),
            ),
          ),
        );
      },
    );
    if (tooltip == null) return KeyedSubtree(key: key, child: content);
    return Tooltip(key: key, message: tooltip, child: content);
  }

  /// Frosted glass icon button for overlays / floating chrome.
  static Widget glassIcon({
    Key? key,
    required VoidCallback? onPressed,
    required IconData icon,
    String? tooltip,
    Color? color,
  }) {
    final btn = Pressable(
      onTap: onPressed,
      enabled: onPressed != null,
      scale: 0.92,
      builder: (context, pressed) {
        return GlassChip(
          padding: const EdgeInsets.all(10),
          borderRadius: BorderRadius.circular(999),
          onTap: null,
          child: Opacity(
            opacity: pressed ? 0.75 : 1,
            child: Icon(icon, size: 20, color: color ?? AppColors.navy),
          ),
        );
      },
    );
    if (tooltip == null) return KeyedSubtree(key: key, child: btn);
    return Tooltip(key: key, message: tooltip, child: btn);
  }

  /// Frosted glass text+icon control (header secondary actions).
  static Widget glass({
    Key? key,
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
  }) {
    return Pressable(
      key: key,
      onTap: onPressed,
      enabled: onPressed != null,
      scale: 0.94,
      builder: (context, pressed) {
        return GlassChip(
          onTap: null,
          borderRadius: BorderRadius.circular(999),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Opacity(
            opacity: pressed ? 0.8 : 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: AppColors.navy),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: AppFonts.style(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.navy,
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

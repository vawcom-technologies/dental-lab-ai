import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'pressable.dart';

/// Compact pill button — standard sub-button look (filters, secondary actions).
class SoftPillButton extends StatelessWidget {
  const SoftPillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.selected = false,
    this.icon,
    this.danger = false,
    this.filled = false,
    this.selectionHaptic = false,
    this.compact = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final IconData? icon;
  final bool danger;
  final bool filled;
  final bool selectionHaptic;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final padH = compact ? 14.0 : 16.0;
    final padV = compact ? 8.0 : 10.0;
    final fontSize = compact ? 13.0 : 14.0;

    return Pressable(
      onTap: onPressed,
      enabled: enabled,
      selectionHaptic: selectionHaptic,
      scale: 0.93,
      builder: (context, pressed) {
        final Color bg;
        final Color fg;
        final Color border;
        final List<BoxShadow>? shadows;

        if (!enabled) {
          bg = AppColors.neo.withValues(alpha: 0.55);
          fg = AppColors.muted.withValues(alpha: 0.55);
          border = AppColors.border.withValues(alpha: 0.35);
          shadows = null;
        } else if (filled) {
          bg = pressed
              ? AppColors.navy.withValues(alpha: 0.88)
              : AppColors.navy;
          fg = Colors.white;
          border = Colors.transparent;
          shadows = pressed ? NeoShadows.pressed() : NeoShadows.soft(depth: 0.4);
        } else if (danger) {
          bg = pressed
              ? AppColors.danger.withValues(alpha: 0.16)
              : AppColors.dangerSoft;
          fg = AppColors.danger;
          border = AppColors.danger.withValues(alpha: 0.22);
          shadows = pressed ? NeoShadows.pressed() : NeoShadows.soft(depth: 0.3);
        } else if (selected) {
          bg = pressed
              ? Colors.white.withValues(alpha: 0.96)
              : Colors.white.withValues(alpha: 0.9);
          fg = AppColors.navy;
          border = AppColors.dentalBlue.withValues(alpha: pressed ? 0.48 : 0.32);
          shadows =
              pressed ? NeoShadows.pressed() : NeoShadows.soft(depth: 0.55);
        } else {
          bg = pressed ? AppColors.inset : AppColors.neo.withValues(alpha: 0.94);
          fg = AppColors.muted;
          border = AppColors.border.withValues(alpha: 0.55);
          shadows =
              pressed ? NeoShadows.pressed() : NeoShadows.soft(depth: 0.35);
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          constraints: BoxConstraints(minHeight: compact ? 34 : 40),
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
            boxShadow: shadows,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: compact ? 15 : 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                softWrap: false,
                style: AppFonts.style(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: fontSize,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

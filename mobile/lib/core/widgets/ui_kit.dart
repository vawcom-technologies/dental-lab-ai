import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'touchable.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.statusKey});

  final String statusKey;

  @override
  Widget build(BuildContext context) {
    final s = StatusStyle.of(statusKey);
    final label = AppLocalizations.of(context).statusLabel(statusKey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: NeoShadows.soft(depth: 0.35),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: s.fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.neo,
        shape: BoxShape.circle,
        boxShadow: NeoShadows.soft(depth: 0.55),
      ),
      child: Text(
        _initials,
        style: TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.32,
        ),
      ),
    );
  }
}

/// Raised neumorphic surface used across the app.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding,
    this.depth = 1,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double depth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Material owns the fill color so nested ListTiles can paint ink /
    // selectedTileColor. A colored DecoratedBox between Material and ListTile
    // asserts in debug and can lock the widget tree.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadii.border,
        boxShadow: NeoShadows.raised(depth: depth),
      ),
      child: Material(
        color: color ?? AppColors.card,
        borderRadius: AppRadii.border,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(18),
          child: child,
        ),
      ),
    );
  }
}

/// Soft inset well (for grouped form fields / search).
class NeoInset extends StatelessWidget {
  const NeoInset({
    super.key,
    required this.child,
    this.padding,
    this.radius,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.inset,
        borderRadius: radius ?? AppRadii.borderSm,
        boxShadow: NeoShadows.pressed(),
      ),
      child: child,
    );
  }
}

class NeoIconBadge extends StatelessWidget {
  const NeoIconBadge({
    super.key,
    required this.icon,
    this.size = 48,
    this.iconSize = 22,
    this.color,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.neo,
        borderRadius: BorderRadius.circular(16),
        boxShadow: NeoShadows.soft(depth: 0.7),
      ),
      child: Icon(icon, size: iconSize, color: color ?? AppColors.dentalBlue),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          NeoIconBadge(icon: icon!, size: 44, iconSize: 20),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                  letterSpacing: -0.4,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty)
          Flexible(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ),
      ],
    );
  }
}

class SoftFilterChip extends StatelessWidget {
  const SoftFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Align widthFactor keeps chips content-sized (not full-width bars).
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: Touchable(
        onTap: onTap,
        selectionHaptic: true,
        borderRadius: BorderRadius.circular(20),
        minHeight: 32,
        scale: 0.98,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.navy : AppColors.neo,
            borderRadius: BorderRadius.circular(20),
            boxShadow: selected ? null : NeoShadows.soft(depth: 0.3),
          ),
          child: Text(
            label,
            softWrap: false,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.muted,
        letterSpacing: 0.8,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../navigation/app_page_routes.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';
import 'soft_pill_button.dart';

export 'app_buttons.dart';
export 'app_dialogs.dart';
export 'app_snackbar.dart';
export 'app_switcher.dart';
export 'busy_action.dart';
export 'dental_date_picker.dart';
export 'glass_surface.dart';
export 'pressable.dart';
export 'password_checklist.dart';
export 'patient_media_dialogs.dart';
export 'phone_field.dart';
export 'soft_pill_button.dart';
export 'tooth_loader.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.statusKey});

  final String statusKey;

  @override
  Widget build(BuildContext context) {
    final key = CaseStatuses.normalize(statusKey);
    return AnimatedSwitcher(
      duration: AppMotion.normal,
      switchInCurve: AppMotion.spring,
      switchOutCurve: AppMotion.easeIn,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.65),
          end: Offset.zero,
        ).animate(animation);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          ),
        );
      },
      child: _StatusChipFace(
        key: ValueKey<String>(key),
        statusKey: key,
      ),
    );
  }
}

class _StatusChipFace extends StatelessWidget {
  const _StatusChipFace({super.key, required this.statusKey});

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
      ),
      child: Text(
        label,
        style: AppFonts.style(
          color: s.fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Tappable status chip with workflow status menu (owner/edit flows).
class PatientStatusMenu extends StatelessWidget {
  const PatientStatusMenu({
    super.key,
    required this.status,
    this.enabled = true,
    this.onSelected,
  });

  final String status;
  final bool enabled;
  final ValueChanged<String>? onSelected;

  Future<void> _pickStatus(BuildContext context) async {
    if (!enabled || onSelected == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + size.height + 6,
        origin.dx + size.width,
        origin.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 8,
      items: [
        for (final key in CaseStatuses.all)
          PopupMenuItem<String>(
            value: key,
            child: Row(
              children: [
                Icon(
                  CaseStatuses.normalize(status) == key
                      ? Icons.check_rounded
                      : Icons.circle,
                  size: CaseStatuses.normalize(status) == key ? 18 : 10,
                  color: StatusStyle.of(key).fg,
                ),
                const SizedBox(width: 10),
                Text(
                  StatusStyle.of(key).label,
                  style: AppFonts.style(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (selected == null) return;
    onSelected!(selected);
  }

  @override
  Widget build(BuildContext context) {
    final chip = StatusChip(statusKey: status);
    if (!enabled || onSelected == null) return chip;

    // GestureDetector avoids PopupMenuButton's rectangular Material/ink chrome.
    return Tooltip(
      message: 'Change status',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _pickStatus(context),
          child: chip,
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
        style: AppFonts.style(
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
    this.boxShadow,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double depth;
  final Color? color;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    // Material owns the fill color so nested ListTiles can paint ink /
    // selectedTileColor. A colored DecoratedBox between Material and ListTile
    // asserts in debug and can lock the widget tree.
    final shadows =
        boxShadow ?? (depth <= 0 ? null : NeoShadows.raised(depth: depth));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadii.border,
        // Custom glows: white rim so dark fills (e.g. photo pane) don't show
        // a grey fringe. Flat depth-0 cards keep the default grey border.
        border: boxShadow != null
            ? Border.all(color: Colors.white)
            : (shadows == null && depth <= 0
                ? Border.all(color: AppColors.border)
                : null),
        boxShadow: shadows,
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
    this.chromeActions = const [],
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Primary / secondary CTAs — never frosted.
  final List<Widget> actions;

  /// Icon / meta chrome — shown in a frosted tray when non-empty.
  final List<Widget> chromeActions;

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
                style: AppFonts.style(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                  letterSpacing: -0.5,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: AppFonts.style(
                    color: AppColors.muted,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (chromeActions.isNotEmpty) ...[
          const SizedBox(width: 10),
          GlassSurface(
            borderRadius: BorderRadius.circular(16),
            blur: 16,
            tint: Colors.white.withValues(alpha: 0.48),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Wrap(
              spacing: 2,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chromeActions,
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ],
    );
  }
}

/// Soft pill filter / sub-control used across list toolbars.
class SoftFilterChip extends StatelessWidget {
  const SoftFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: SoftPillButton(
        label: label,
        selected: selected,
        onPressed: enabled ? onTap : null,
        selectionHaptic: true,
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
      style: AppFonts.style(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.muted,
        letterSpacing: 0.4,
      ),
    );
  }
}

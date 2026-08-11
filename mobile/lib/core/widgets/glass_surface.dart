import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Frosted glass panel for chrome over gradients / media.
///
/// Use for sidebars, floating toolbars, overlays — not for solid primary CTAs.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.blur = 18,
    this.tint,
    this.border,
    this.padding,
    this.width,
    this.height,
    this.showShadow = true,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double blur;
  final Color? tint;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppRadii.border;
    final fill = tint ?? Colors.white.withValues(alpha: 0.55);

    // Shadow must sit outside ClipRRect or it gets clipped away.
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: const Color(0xFF9AADC4).withValues(alpha: 0.2),
                  offset: const Offset(0, 6),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
              border: border ??
                  Border.all(
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Compact frosted chip — icon toolbars and header controls.
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(12);
    return GlassSurface(
      borderRadius: radius,
      blur: 14,
      tint: Colors.white.withValues(alpha: 0.5),
      padding: EdgeInsets.zero,
      showShadow: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppColors.dentalBlue.withValues(alpha: 0.08),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

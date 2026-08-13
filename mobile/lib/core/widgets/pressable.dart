import 'package:flutter/material.dart';

import '../haptics/app_haptics.dart';
import '../navigation/app_page_routes.dart';

/// Press feedback with scale + optional haptic, exposing [pressed] to the child.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.enabled = true,
    this.haptic = true,
    this.selectionHaptic = false,
    this.scale = 0.94,
    this.duration = AppMotion.fast,
  });

  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool pressed) builder;
  final bool enabled;
  final bool haptic;
  final bool selectionHaptic;
  final double scale;
  final Duration duration;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (!widget.enabled || _pressed == v) return;
    setState(() => _pressed = v);
  }

  void _handleTap() {
    if (!widget.enabled || widget.onTap == null) return;
    if (widget.haptic) {
      if (widget.selectionHaptic) {
        AppHaptics.selection();
      } else {
        AppHaptics.light();
      }
    }
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? widget.scale : 1,
      duration: widget.duration,
      curve: AppMotion.spring,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _handleTap : null,
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
        onTapCancel: widget.enabled ? () => _setPressed(false) : null,
        child: widget.builder(context, _pressed),
      ),
    );
  }
}

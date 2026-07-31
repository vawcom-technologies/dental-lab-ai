import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../haptics/app_haptics.dart';

/// iPad-friendly scroll: bounce physics + touch/stylus/trackpad drag.
class EliteScrollBehavior extends MaterialScrollBehavior {
  const EliteScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

/// Soft press scale + optional haptic — for nav rows, chips, custom controls.
class Touchable extends StatefulWidget {
  const Touchable({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius,
    this.enabled = true,
    this.haptic = true,
    this.selectionHaptic = false,
    this.scale = 0.97,
    this.minHeight = 40,
  });

  final VoidCallback? onTap;
  final Widget child;
  final BorderRadius? borderRadius;
  final bool enabled;
  final bool haptic;
  final bool selectionHaptic;
  final double scale;
  final double minHeight;

  @override
  State<Touchable> createState() => _TouchableState();
}

class _TouchableState extends State<Touchable> {
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
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.enabled ? _handleTap : null,
          onHighlightChanged: (v) => _setPressed(v),
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          borderRadius: widget.borderRadius ?? BorderRadius.circular(14),
          splashColor: AppColorsSplash.soft,
          highlightColor: AppColorsSplash.softHighlight,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.minHeight),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Local splash tints (avoids importing full theme cycle issues).
class AppColorsSplash {
  static const soft = Color(0x334A90E2);
  static const softHighlight = Color(0x1A1D3557);
}

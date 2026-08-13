import 'package:flutter/material.dart';

import '../navigation/app_page_routes.dart';

/// Fade / slide the incoming child only. Previous content is removed from
/// the paint tree so frosted glass (BackdropFilter) cannot stack.
class AppSwitcher extends StatelessWidget {
  const AppSwitcher({
    super.key,
    required this.child,
    this.duration = AppMotion.normal,
    this.reverseDuration = AppMotion.fast,
    this.slide = true,
    this.horizontal = false,
  });

  final Widget child;
  final Duration duration;
  final Duration reverseDuration;
  final bool slide;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      switchInCurve: AppMotion.spring,
      switchOutCurve: AppMotion.easeIn,
      layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.12, 1, curve: Curves.easeOut),
        );
        Widget framed = FadeTransition(opacity: fade, child: child);
        if (!slide) return framed;
        final begin = horizontal ? AppMotion.slideIn : AppMotion.slideUp;
        framed = SlideTransition(
          position: Tween<Offset>(
            begin: begin,
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: AppMotion.spring,
          )),
          child: framed,
        );
        return framed;
      },
      child: child,
    );
  }
}

/// Fades the active sidebar pane in after an [IndexedStack] swap.
/// Only one page is painted, so glass layers cannot overlay.
class AppPaneFade extends StatefulWidget {
  const AppPaneFade({
    super.key,
    required this.token,
    required this.child,
  });

  final Object token;
  final Widget child;

  @override
  State<AppPaneFade> createState() => _AppPaneFadeState();
}

class _AppPaneFadeState extends State<AppPaneFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.fast,
    value: 1,
  );

  @override
  void didUpdateWidget(AppPaneFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.2, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: AppMotion.spring),
      ),
      child: widget.child,
    );
  }
}

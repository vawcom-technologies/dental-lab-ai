import 'package:flutter/cupertino.dart';

/// Shared navigation timings + route builders for iPadOS-like motion.
abstract final class AppMotion {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 320);
  static const Duration page = Duration(milliseconds: 380);
  static const Duration pageReverse = Duration(milliseconds: 280);

  /// iOS decelerate — snaps in quickly, eases out softly.
  static const Curve spring = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeIn = Curves.easeInCubic;

  static const Offset slideUp = Offset(0, 0.018);
  static const Offset slideIn = Offset(0.012, 0);
}

abstract final class AppPageRoutes {
  /// Standard iOS push (back-swipe friendly).
  static Route<T> cupertino<T extends Object?>(
    Widget page, {
    String? title,
    bool fullscreenDialog = false,
    RouteSettings? settings,
  }) {
    return CupertinoPageRoute<T>(
      builder: (_) => page,
      title: title,
      fullscreenDialog: fullscreenDialog,
      settings: settings,
    );
  }

  /// Soft fade + slight rise — auth / stack resets.
  static Route<T> fade<T extends Object?>(
    Widget page, {
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: AppMotion.page,
      reverseTransitionDuration: AppMotion.pageReverse,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.easeOut,
          reverseCurve: AppMotion.easeIn,
        );
        final outgoing = CurvedAnimation(
          parent: secondaryAnimation,
          curve: AppMotion.easeOut,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0.88).animate(outgoing),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

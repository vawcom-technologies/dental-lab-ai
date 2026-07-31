import 'package:flutter/services.dart';

/// Soft, intentional haptics for the iPad chairside experience.
class AppHaptics {
  AppHaptics._();

  static Future<void> selection() => HapticFeedback.selectionClick();

  static Future<void> light() => HapticFeedback.lightImpact();

  static Future<void> medium() => HapticFeedback.mediumImpact();

  static Future<void> heavy() => HapticFeedback.heavyImpact();

  static Future<void> success() => HapticFeedback.mediumImpact();

  static Future<void> warn() => HapticFeedback.heavyImpact();

  /// Wrap a tap handler with a light impact (buttons, chips, nav).
  static void Function()? tap(void Function()? onPressed) {
    if (onPressed == null) return null;
    return () {
      light();
      onPressed();
    };
  }

  /// Selection-style haptic for filters / segmented controls.
  static void Function()? select(void Function()? onPressed) {
    if (onPressed == null) return null;
    return () {
      selection();
      onPressed();
    };
  }
}

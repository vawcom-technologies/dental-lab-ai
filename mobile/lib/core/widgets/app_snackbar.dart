import 'package:flutter/material.dart';

import '../errors/user_facing_error.dart';
import '../haptics/app_haptics.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// App-wide floating soft-pill toasts (success / error / info).
///
/// Prefer this over inline banners so feedback stays consistent.
class AppSnackBars {
  AppSnackBars._();

  static const _duration = Duration(seconds: 3);

  /// Successful completion (create, save, grant, approve, sync, etc.).
  static void success(
    BuildContext context,
    String message, {
    bool haptic = true,
  }) {
    _show(
      context,
      message: message,
      background: AppColors.successSoft,
      foreground: AppColors.success,
      border: AppColors.success.withValues(alpha: 0.22),
      icon: Icons.check_circle_rounded,
      haptic: haptic ? AppHaptics.success : null,
    );
  }

  /// Failures, permission denials, rejections, and validation problems.
  static void error(
    BuildContext context,
    String message, {
    bool haptic = true,
  }) {
    final loc = _locOf(context);
    _show(
      context,
      message: friendlyError(message, loc),
      background: AppColors.dangerSoft,
      foreground: AppColors.danger,
      border: AppColors.danger.withValues(alpha: 0.22),
      icon: Icons.error_outline_rounded,
      haptic: haptic ? AppHaptics.warn : null,
    );
  }

  /// Neutral guidance that is neither success nor failure.
  static void info(
    BuildContext context,
    String message, {
    VoidCallback? onTap,
    Duration duration = _duration,
  }) {
    _show(
      context,
      message: message,
      background: const Color(0xFFEAF3FC),
      foreground: AppColors.navy,
      border: AppColors.dentalBlue.withValues(alpha: 0.22),
      icon: Icons.notifications_active_outlined,
      onTap: onTap,
      duration: duration,
    );
  }

  /// Call from `build` so a stored error/success is toasted once, not painted
  /// as permanent on-screen text. Assign the return value back to the field.
  static String? drain(
    BuildContext context,
    String? message, {
    bool error = true,
  }) {
    final text = message?.replaceFirst('Exception: ', '').trim();
    if (text == null || text.isEmpty) return null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (error) {
        AppSnackBars.error(context, text);
      } else {
        AppSnackBars.success(context, text);
      }
    });
    return null;
  }

  static AppLocalizations? _locOf(BuildContext context) {
    try {
      return AppLocalizations.of(context);
    } catch (_) {
      return null;
    }
  }

  static OverlayEntry? _current;

  /// Shown in the root overlay — above dialogs and sheets — so a toast
  /// raised from inside one is never hidden behind it. One at a time.
  static void _show(
    BuildContext context, {
    required String message,
    required Color background,
    required Color foreground,
    required Color border,
    required IconData icon,
    Future<void> Function()? haptic,
    VoidCallback? onTap,
    Duration duration = _duration,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final text = message.replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) return;

    haptic?.call();
    _current?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Toast(
        text: text,
        background: background,
        foreground: foreground,
        border: border,
        icon: icon,
        onTap: onTap,
        duration: duration,
        onDone: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

/// Floating soft pill at the bottom: slides up, waits [duration], fades.
/// Driven by animation controllers (no timers), so tests settle cleanly.
class _Toast extends StatefulWidget {
  const _Toast({
    required this.text,
    required this.background,
    required this.foreground,
    required this.border,
    required this.icon,
    required this.duration,
    required this.onDone,
    this.onTap,
  });

  final String text;
  final Color background, foreground, border;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDone;
  final VoidCallback? onTap;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with TickerProviderStateMixin {
  late final _show = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final _hold = AnimationController(vsync: this, duration: widget.duration);
  late final _curve = CurvedAnimation(parent: _show, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);

  @override
  void initState() {
    super.initState();
    _show.forward().then((_) {
      if (mounted) _hold.forward().then((_) => _dismiss());
    });
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _show.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _show.dispose();
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + MediaQuery.viewInsetsOf(context).bottom;
    return Positioned(
      left: 20,
      right: 20,
      bottom: 20 + bottom,
      child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: FadeTransition(
              opacity: _curve,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(_curve),
                child: Material(
                  type: MaterialType.transparency,
                  child: GestureDetector(
                    onTap: () {
                      widget.onTap?.call();
                      _dismiss();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: widget.background,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: widget.border),
                        boxShadow: NeoShadows.soft(depth: 0.45),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.icon, color: widget.foreground, size: 18),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              widget.text,
                              style: AppFonts.style(
                                color: widget.foreground,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }
}

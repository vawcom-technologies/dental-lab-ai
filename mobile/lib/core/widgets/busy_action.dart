import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'tooth_loader.dart';

/// Mixin for [State] that serializes async work and exposes [busy].
///
/// Use for mutation handlers so a second tap is ignored while the first
/// request is in flight:
///
/// ```dart
/// await runBusy(() async {
///   await api.save(...);
/// });
/// ```
mixin BusyStateMixin<T extends StatefulWidget> on State<T> {
  bool _busy = false;

  bool get busy => _busy;

  /// Runs [action] if not already busy. Returns `null` when skipped.
  Future<R?> runBusy<R>(Future<R> Function() action) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      return await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Soft overlay with a dental tooth loader. Prefer [blockInteraction] only for
/// short form mutations — uploads should use optimistic UI instead.
class BusyBarrier extends StatelessWidget {
  const BusyBarrier({
    super.key,
    required this.busy,
    required this.child,
    this.showSpinner = true,
    this.dim = true,
    this.blockInteraction = true,
    this.message,
  });

  final bool busy;
  final Widget child;
  final bool showSpinner;
  final bool dim;
  final bool blockInteraction;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AbsorbPointer(
          absorbing: busy && blockInteraction,
          child: child,
        ),
        if (busy)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !blockInteraction,
              child: dim
                  ? GlassSurface(
                      borderRadius: BorderRadius.zero,
                      blur: 10,
                      tint: Colors.white.withValues(alpha: 0.28),
                      border: Border.all(color: Colors.transparent),
                      child: showSpinner
                          ? ToothPageLoader(message: message, size: 44)
                          : const SizedBox.shrink(),
                    )
                  : (showSpinner
                      ? ToothPageLoader(message: message, size: 44)
                      : const SizedBox.shrink()),
            ),
          ),
      ],
    );
  }
}

/// Compact inline tooth loader used inside buttons / trailing actions.
/// Prefer [ToothLoadingIndicator] directly at call sites; this alias keeps
/// Async* button helpers concise.
class BusySpinner extends StatelessWidget {
  const BusySpinner({
    super.key,
    this.size = 16,
    this.color,
    this.strokeWidth = 2,
  });

  final double size;
  final Color? color;

  /// Kept for call-site compatibility; unused (tooth loader has no stroke).
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return ToothLoadingIndicator(
      size: size,
      color: color ?? Colors.white,
      compact: true,
    );
  }
}

/// [FilledButton] that disables itself and shows a spinner while [onPressed]
/// is awaiting.
class AsyncFilledButton extends StatefulWidget {
  const AsyncFilledButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  });

  final Future<void> Function()? onPressed;
  final Widget child;
  final ButtonStyle? style;

  @override
  State<AsyncFilledButton> createState() => _AsyncFilledButtonState();
}

class _AsyncFilledButtonState extends State<AsyncFilledButton> {
  bool _busy = false;

  Future<void> _handle() async {
    final fn = widget.onPressed;
    if (fn == null || _busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: widget.style,
      onPressed: widget.onPressed == null || _busy ? null : _handle,
      child: _busy
          ? const BusySpinner(size: 18, color: Colors.white)
          : widget.child,
    );
  }
}

/// [FilledButton.icon] with in-flight spinner + disable.
class AsyncFilledButtonIcon extends StatefulWidget {
  const AsyncFilledButtonIcon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.style,
  });

  final Future<void> Function()? onPressed;
  final Widget icon;
  final Widget label;
  final ButtonStyle? style;

  @override
  State<AsyncFilledButtonIcon> createState() => _AsyncFilledButtonIconState();
}

class _AsyncFilledButtonIconState extends State<AsyncFilledButtonIcon> {
  bool _busy = false;

  Future<void> _handle() async {
    final fn = widget.onPressed;
    if (fn == null || _busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: widget.style,
      onPressed: widget.onPressed == null || _busy ? null : _handle,
      icon: _busy
          ? const BusySpinner(size: 16, color: Colors.white)
          : widget.icon,
      label: widget.label,
    );
  }
}

/// [OutlinedButton.icon] with in-flight spinner + disable.
class AsyncOutlinedButtonIcon extends StatefulWidget {
  const AsyncOutlinedButtonIcon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.style,
  });

  final Future<void> Function()? onPressed;
  final Widget icon;
  final Widget label;
  final ButtonStyle? style;

  @override
  State<AsyncOutlinedButtonIcon> createState() =>
      _AsyncOutlinedButtonIconState();
}

class _AsyncOutlinedButtonIconState extends State<AsyncOutlinedButtonIcon> {
  bool _busy = false;

  Future<void> _handle() async {
    final fn = widget.onPressed;
    if (fn == null || _busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: widget.style,
      onPressed: widget.onPressed == null || _busy ? null : _handle,
      icon: _busy ? const BusySpinner(size: 16) : widget.icon,
      label: widget.label,
    );
  }
}

/// [IconButton] with in-flight spinner + disable.
class AsyncIconButton extends StatefulWidget {
  const AsyncIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.color,
  });

  final Future<void> Function()? onPressed;
  final Widget icon;
  final String? tooltip;
  final Color? color;

  @override
  State<AsyncIconButton> createState() => _AsyncIconButtonState();
}

class _AsyncIconButtonState extends State<AsyncIconButton> {
  bool _busy = false;

  Future<void> _handle() async {
    final fn = widget.onPressed;
    if (fn == null || _busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      color: widget.color,
      onPressed: widget.onPressed == null || _busy ? null : _handle,
      icon: _busy ? BusySpinner(size: 18, color: widget.color) : widget.icon,
    );
  }
}

/// [TextButton] with in-flight spinner + disable.
class AsyncTextButton extends StatefulWidget {
  const AsyncTextButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  });

  final Future<void> Function()? onPressed;
  final Widget child;
  final ButtonStyle? style;

  @override
  State<AsyncTextButton> createState() => _AsyncTextButtonState();
}

class _AsyncTextButtonState extends State<AsyncTextButton> {
  bool _busy = false;

  Future<void> _handle() async {
    final fn = widget.onPressed;
    if (fn == null || _busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: widget.style,
      onPressed: widget.onPressed == null || _busy ? null : _handle,
      child: _busy ? const BusySpinner(size: 16) : widget.child,
    );
  }
}

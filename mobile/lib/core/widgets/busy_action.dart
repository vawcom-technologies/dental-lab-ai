import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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

/// Blocks interaction and optionally shows a centered spinner while [busy].
class BusyBarrier extends StatelessWidget {
  const BusyBarrier({
    super.key,
    required this.busy,
    required this.child,
    this.showSpinner = true,
    this.dim = true,
  });

  final bool busy;
  final Widget child;
  final bool showSpinner;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AbsorbPointer(
          absorbing: busy,
          child: child,
        ),
        if (busy)
          Positioned.fill(
            child: ColoredBox(
              color: dim
                  ? AppColors.navy.withValues(alpha: 0.06)
                  : Colors.transparent,
              child: showSpinner
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}

/// Compact inline spinner used inside buttons / trailing actions.
class BusySpinner extends StatelessWidget {
  const BusySpinner({
    super.key,
    this.size = 16,
    this.color,
    this.strokeWidth = 2,
  });

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: color,
      ),
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

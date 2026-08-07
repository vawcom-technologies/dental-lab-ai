import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Primary dental loader blue (spec `#1E3A8A`), falls back to app navy family.
const Color kToothLoaderBlue = Color(0xFF1E3A8A);

/// Reusable dental-themed loading indicator — pulsing tooth + soft enamel ring.
///
/// Use instead of [CircularProgressIndicator] for page, inline, and bubble states.
class ToothLoadingIndicator extends StatefulWidget {
  const ToothLoadingIndicator({
    super.key,
    this.size = 48,
    this.color,
    this.loadingText,
    this.compact = false,
  });

  final double size;
  final Color? color;
  final String? loadingText;

  /// When true, skips text spacing and uses a tighter layout (buttons / chips).
  final bool compact;

  @override
  State<ToothLoadingIndicator> createState() => _ToothLoadingIndicatorState();
}

class _ToothLoadingIndicatorState extends State<ToothLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  late final Animation<double> _ring;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _scale = Tween<double>(begin: 0.88, end: 1.12).animate(curve);
    _opacity = Tween<double>(begin: 0.55, end: 1.0).animate(curve);
    _ring = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.color ?? kToothLoaderBlue;
    final iconSize = widget.size;

    Widget tooth({double? size}) {
      final s = size ?? iconSize;
      return SizedBox(
        width: s,
        height: s,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: Size.square(s),
                painter: _ToothLoaderPainter(
                  color: themeColor,
                  scale: _scale.value,
                  opacity: _opacity.value,
                  ringProgress: _ring.value,
                ),
              );
            },
          ),
        ),
      );
    }

    // Compact / icon-slot usages are often forced into a tight NxN box
    // (e.g. 18×18). Avoid a Column here — it overflows under tight height.
    if (widget.compact || widget.loadingText == null) {
      return tooth();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final tight = constraints.hasBoundedHeight && maxH.isFinite;

        // Too short for label — tooth only (prevents RenderFlex overflow).
        if (tight && maxH < iconSize + 20) {
          final s = math.min(iconSize, maxH.clamp(12.0, iconSize));
          return tooth(size: s);
        }

        final column = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tooth(),
            const SizedBox(height: 8),
            Text(
              widget.loadingText!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.2,
                color: themeColor.withValues(alpha: 0.85),
              ),
            ),
          ],
        );

        // Scale down when the slot is shorter than the natural column height.
        if (tight) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: column,
            ),
          );
        }

        return column;
      },
    );
  }
}

/// Centered tooth loader for list / page empty-loading states.
class ToothPageLoader extends StatelessWidget {
  const ToothPageLoader({
    super.key,
    this.message = 'Fetching data…',
    this.size = 36,
    this.color,
  });

  final String? message;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ToothLoadingIndicator(
        size: size,
        color: color,
        compact: message == null,
        loadingText: message,
      ),
    );
  }
}

/// Lightweight shimmer skeleton for list placeholders (no extra package).
class ToothListSkeleton extends StatefulWidget {
  const ToothListSkeleton({
    super.key,
    this.rows = 6,
    this.color,
  });

  final int rows;
  final Color? color;

  @override
  State<ToothListSkeleton> createState() => _ToothListSkeletonState();
}

class _ToothListSkeletonState extends State<ToothListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? AppColors.border;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          itemCount: widget.rows,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final phase = (t + i * 0.08) % 1.0;
            final glow = 0.35 + 0.45 * (0.5 - (phase - 0.5).abs()) * 2;
            return Container(
              height: 64,
              decoration: BoxDecoration(
                color: Color.lerp(base.withValues(alpha: 0.35), base, glow),
                borderRadius: BorderRadius.circular(14),
              ),
            );
          },
        );
      },
    );
  }
}

class _ToothLoaderPainter extends CustomPainter {
  _ToothLoaderPainter({
    required this.color,
    required this.scale,
    required this.opacity,
    required this.ringProgress,
  });

  final Color color;
  final double scale;
  final double opacity;
  final double ringProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    // Soft glow halo
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.12 + 0.18 * opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.35);
    canvas.drawCircle(center, radius * 0.72 * scale, glowPaint);

    // Orbiting enamel ring
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.25 + 0.35 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, radius * 0.06)
      ..strokeCap = StrokeCap.round;
    final sweep = 1.4 + ringProgress * 1.2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.82),
      -math.pi / 2 + ringProgress * math.pi * 2,
      sweep,
      false,
      ringPaint,
    );

    // Tooth body
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    final toothPath = _molarPath(center, radius * 0.55);
    final fill = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    canvas.drawPath(toothPath, fill);

    // Shine streak
    final shine = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.55 * opacity),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.55));
    canvas.drawPath(toothPath, shine);
    canvas.restore();
  }

  Path _molarPath(Offset c, double r) {
    // Simplified molar: crown + two roots
    final path = Path();
    final top = c.dy - r * 0.85;
    final mid = c.dy + r * 0.05;
    final bottom = c.dy + r * 0.95;

    path.moveTo(c.dx - r * 0.55, mid);
    path.cubicTo(
      c.dx - r * 0.7,
      top + r * 0.15,
      c.dx - r * 0.35,
      top,
      c.dx - r * 0.18,
      top + r * 0.08,
    );
    path.quadraticBezierTo(c.dx, top - r * 0.05, c.dx + r * 0.18, top + r * 0.08);
    path.cubicTo(
      c.dx + r * 0.35,
      top,
      c.dx + r * 0.7,
      top + r * 0.15,
      c.dx + r * 0.55,
      mid,
    );
    // Right root
    path.quadraticBezierTo(c.dx + r * 0.42, mid + r * 0.35, c.dx + r * 0.28, bottom);
    path.quadraticBezierTo(c.dx + r * 0.12, mid + r * 0.45, c.dx, mid + r * 0.25);
    // Left root
    path.quadraticBezierTo(c.dx - r * 0.12, mid + r * 0.45, c.dx - r * 0.28, bottom);
    path.quadraticBezierTo(c.dx - r * 0.42, mid + r * 0.35, c.dx - r * 0.55, mid);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _ToothLoaderPainter oldDelegate) {
    return oldDelegate.scale != scale ||
        oldDelegate.opacity != opacity ||
        oldDelegate.ringProgress != ringProgress ||
        oldDelegate.color != color;
  }
}

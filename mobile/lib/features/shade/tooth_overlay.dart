import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Maps normalized [0,1] tooth geometry onto a BoxFit.contain image rect.
Rect containRect(Size box, Size image) {
  if (image.width <= 0 || image.height <= 0 || box.width <= 0 || box.height <= 0) {
    return Rect.zero;
  }
  final scale = (box.width / image.width < box.height / image.height)
      ? box.width / image.width
      : box.height / image.height;
  final w = image.width * scale;
  final h = image.height * scale;
  return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
}

Offset normToLocal(List point, Rect dest) {
  final x = (point[0] as num).toDouble();
  final y = (point[1] as num).toDouble();
  return Offset(dest.left + x * dest.width, dest.top + y * dest.height);
}

List<double> localToNorm(Offset local, Rect dest) {
  if (dest.width <= 0 || dest.height <= 0) return [0, 0];
  final x = ((local.dx - dest.left) / dest.width).clamp(0.0, 1.0);
  final y = ((local.dy - dest.top) / dest.height).clamp(0.0, 1.0);
  return [x, y];
}

/// Simplify a dense outline to ~4–6 control points for edge editing.
///
/// Douglas–Peucker style reduction, then midpoints on longest edges if too few.
List<List<double>> simplifyOutlineForEdit(
  List outline, {
  int maxPoints = 6,
  int minPoints = 4,
}) {
  var pts = <List<double>>[];
  for (final p in outline) {
    if (p is List && p.length >= 2) {
      pts.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
    }
  }
  if (pts.length < 3) return pts;
  if (pts.length <= maxPoints && pts.length >= minPoints) return pts;

  // Douglas–Peucker on closed ring (open path with first==last for algorithm)
  double peri = 0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    peri += (Offset(a[0], a[1]) - Offset(b[0], b[1])).distance;
  }
  var simplified = pts;
  for (final frac in [0.01, 0.015, 0.02, 0.03, 0.045, 0.06, 0.08, 0.12]) {
    simplified = _douglasPeuckerClosed(pts, frac * peri);
    if (simplified.length <= maxPoints && simplified.length >= 3) break;
  }

  if (simplified.length > maxPoints) {
    final n = simplified.length;
    final ordered = <List<double>>[];
    final seen = <int>{};
    for (var i = 0; i < maxPoints; i++) {
      final idx = ((i * (n - 1)) / (maxPoints - 1)).round().clamp(0, n - 1);
      if (seen.add(idx)) ordered.add(simplified[idx]);
    }
    if (ordered.length >= 3) simplified = ordered;
  }

  while (simplified.length < minPoints) {
    var bestI = 0;
    var bestLen = -1.0;
    for (var i = 0; i < simplified.length; i++) {
      final a = simplified[i];
      final b = simplified[(i + 1) % simplified.length];
      final d = (Offset(a[0], a[1]) - Offset(b[0], b[1])).distanceSquared;
      if (d > bestLen) {
        bestLen = d;
        bestI = i;
      }
    }
    final a = simplified[bestI];
    final b = simplified[(bestI + 1) % simplified.length];
    simplified = [
      ...simplified.sublist(0, bestI + 1),
      [0.5 * (a[0] + b[0]), 0.5 * (a[1] + b[1])],
      ...simplified.sublist(bestI + 1),
    ];
  }
  return simplified;
}

List<List<double>> _douglasPeuckerClosed(List<List<double>> pts, double epsilon) {
  if (pts.length < 3) return pts;
  // Treat as open path by repeating first at end, then drop last
  final open = [...pts, pts.first];
  final kept = _douglasPeucker(open, epsilon);
  if (kept.length >= 2 &&
      (kept.first[0] - kept.last[0]).abs() < 1e-9 &&
      (kept.first[1] - kept.last[1]).abs() < 1e-9) {
    kept.removeLast();
  }
  return kept.length >= 3 ? kept : pts;
}

List<List<double>> _douglasPeucker(List<List<double>> points, double epsilon) {
  if (points.length < 3) return List<List<double>>.from(points);
  var maxDist = 0.0;
  var index = 0;
  final start = Offset(points.first[0], points.first[1]);
  final end = Offset(points.last[0], points.last[1]);
  for (var i = 1; i < points.length - 1; i++) {
    final d = _perpDistance(Offset(points[i][0], points[i][1]), start, end);
    if (d > maxDist) {
      maxDist = d;
      index = i;
    }
  }
  if (maxDist > epsilon) {
    final left = _douglasPeucker(points.sublist(0, index + 1), epsilon);
    final right = _douglasPeucker(points.sublist(index), epsilon);
    return [...left.sublist(0, left.length - 1), ...right];
  }
  return [points.first, points.last];
}

double _perpDistance(Offset p, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  if (dx == 0 && dy == 0) return (p - a).distance;
  final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / (dx * dx + dy * dy);
  final proj = Offset(a.dx + t * dx, a.dy + t * dy);
  return (p - proj).distance;
}

int? hitTestTooth({
  required Offset local,
  required Size box,
  required Size imageSize,
  required List<Map<String, dynamic>> teeth,
}) {
  final dest = containRect(box, imageSize);
  if (!dest.contains(local)) return null;
  final nx = ((local.dx - dest.left) / dest.width).clamp(0.0, 1.0);
  final ny = ((local.dy - dest.top) / dest.height).clamp(0.0, 1.0);

  int? best;
  var bestArea = double.infinity;
  for (final t in teeth) {
    final geo = t['geometry'];
    if (geo is! Map) continue;
    final bbox = geo['bbox'];
    if (bbox is! Map) continue;
    final x = (bbox['x'] as num).toDouble();
    final y = (bbox['y'] as num).toDouble();
    final w = (bbox['w'] as num).toDouble();
    final h = (bbox['h'] as num).toDouble();
    if (nx >= x && nx <= x + w && ny >= y && ny <= y + h) {
      final area = w * h;
      if (area < bestArea) {
        bestArea = area;
        best = (t['tooth_index'] as num).toInt();
      }
    }
  }
  return best;
}

/// Hit-test a vertex handle while editing. Returns outline index or null.
int? hitTestOutlineHandle({
  required Offset local,
  required Size box,
  required Size imageSize,
  required List<List<double>> outline,
  // ~44pt Apple min touch target; generous so iPad fingers pick handles easily.
  double radius = 32,
}) {
  final dest = containRect(box, imageSize);
  int? best;
  var bestDist = radius;
  for (var i = 0; i < outline.length; i++) {
    final o = normToLocal(outline[i], dest);
    final d = (o - local).distance;
    if (d <= bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

class ToothOverlayPainter extends CustomPainter {
  ToothOverlayPainter({
    required this.teeth,
    required this.selectedToothIndex,
    required this.imageSize,
    required this.focusZone,
    this.editMode = false,
    this.editOutline,
    this.activeHandleIndex,
  });

  final List<Map<String, dynamic>> teeth;
  final int? selectedToothIndex;
  final Size imageSize;
  final String focusZone;
  final bool editMode;
  final List<List<double>>? editOutline;
  final int? activeHandleIndex;

  static const _zoneColors = {
    'cervical': Color(0xFFE09B2D),
    'middle': Color(0xFF4A90E2),
    'incisal': Color(0xFF1F9D63),
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (teeth.isEmpty || imageSize.width <= 0) return;
    final dest = containRect(size, imageSize);

    for (final t in teeth) {
      final idx = (t['tooth_index'] as num?)?.toInt();
      if (idx == null) continue;
      final selected = idx == selectedToothIndex;
      final rejected = t['rejected'] == true;
      final geo = t['geometry'];
      if (geo is! Map) continue;

      // While editing the selected tooth, draw the live outline instead.
      final outline = (editMode && selected && editOutline != null)
          ? editOutline!
          : geo['outline'];
      if (outline is List && outline.length >= 3) {
        final path = Path();
        for (var i = 0; i < outline.length; i++) {
          final p = outline[i];
          if (p is! List || p.length < 2) continue;
          final o = normToLocal(p, dest);
          if (i == 0) {
            path.moveTo(o.dx, o.dy);
          } else {
            path.lineTo(o.dx, o.dy);
          }
        }
        path.close();

        final fill = Paint()
          ..style = PaintingStyle.fill
          ..color = selected
              ? AppColors.dentalBlue.withValues(alpha: editMode ? 0.28 : 0.22)
              : (rejected
                  ? AppColors.danger.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.06));
        canvas.drawPath(path, fill);

        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.6 : 1.6
          ..color = selected
              ? AppColors.dentalBlue
              : (rejected ? AppColors.danger : Colors.white70);
        canvas.drawPath(path, stroke);
      }

      if (!(editMode && selected)) {
        final zoneOutlines = geo['zone_outlines'];
        if (zoneOutlines is Map && selected) {
          for (final entry in zoneOutlines.entries) {
            final name = entry.key.toString();
            final pts = entry.value;
            if (pts is! List || pts.length < 3) continue;
            final path = Path();
            for (var i = 0; i < pts.length; i++) {
              final p = pts[i];
              if (p is! List || p.length < 2) continue;
              final o = normToLocal(p, dest);
              if (i == 0) {
                path.moveTo(o.dx, o.dy);
              } else {
                path.lineTo(o.dx, o.dy);
              }
            }
            path.close();
            final c = _zoneColors[name] ?? Colors.white;
            canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = name == focusZone ? 2.0 : 1.0
                ..color = c.withValues(alpha: name == focusZone ? 0.95 : 0.55),
            );
          }
        }

        final lines = geo['zone_lines'];
        if (lines is List) {
          for (final line in lines) {
            if (line is! List || line.length < 2) continue;
            final a = line[0];
            final b = line[1];
            if (a is! List || b is! List) continue;
            final p0 = normToLocal(a, dest);
            final p1 = normToLocal(b, dest);
            canvas.drawLine(
              p0,
              p1,
              Paint()
                ..color = selected ? Colors.white : Colors.white54
                ..strokeWidth = selected ? 1.8 : 1.2,
            );
          }
        }
      }

      final label = geo['label'];
      if (label is Map && !(editMode && selected)) {
        final lp = normToLocal([label['x'], label['y']], dest);
        final text = 'T${idx + 1}';
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: Colors.white,
              fontSize: selected ? 13 : 11,
              fontWeight: FontWeight.w800,
              shadows: const [
                Shadow(blurRadius: 4, color: Colors.black54),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final bg = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: lp.translate(0, -2),
            width: tp.width + 10,
            height: tp.height + 4,
          ),
          const Radius.circular(6),
        );
        canvas.drawRRect(
          bg,
          Paint()
            ..color = selected
                ? AppColors.dentalBlue
                : AppColors.navy.withValues(alpha: 0.85),
        );
        tp.paint(canvas, Offset(lp.dx - tp.width / 2, lp.dy - tp.height / 2 - 2));
      }
    }

    // Drag handles for the tooth being edited (sized for finger, not mouse).
    if (editMode && editOutline != null) {
      for (var i = 0; i < editOutline!.length; i++) {
        final o = normToLocal(editOutline![i], dest);
        final active = i == activeHandleIndex;
        // Soft outer ring = larger visible/affordance target on iPad
        canvas.drawCircle(
          o,
          active ? 18 : 15,
          Paint()..color = Colors.white.withValues(alpha: 0.35),
        );
        canvas.drawCircle(
          o,
          active ? 11 : 9,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          o,
          active ? 8 : 6,
          Paint()..color = AppColors.dentalBlue,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ToothOverlayPainter oldDelegate) {
    return oldDelegate.selectedToothIndex != selectedToothIndex ||
        oldDelegate.focusZone != focusZone ||
        oldDelegate.teeth != teeth ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.editMode != editMode ||
        oldDelegate.editOutline != editOutline ||
        oldDelegate.activeHandleIndex != activeHandleIndex;
  }
}

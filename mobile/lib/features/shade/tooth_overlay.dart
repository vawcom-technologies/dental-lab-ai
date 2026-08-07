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

typedef OutlineSnap = ({List<List<double>> verts, List<double> bulges});

/// Undo/redo stack for tooth-outline handle + curve edits.
class OutlineEditHistory {
  final List<OutlineSnap> _undo = [];
  final List<OutlineSnap> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  static List<List<double>> cloneVerts(List<List<double>> outline) =>
      outline.map((p) => [p[0], p[1]]).toList();

  static List<double> cloneBulges(List<double> bulges) =>
      List<double>.from(bulges);

  static OutlineSnap snapOf(List<List<double>> verts, List<double> bulges) => (
        verts: cloneVerts(verts),
        bulges: cloneBulges(bulges),
      );

  static bool same(OutlineSnap a, OutlineSnap b) {
    if (a.verts.length != b.verts.length ||
        a.bulges.length != b.bulges.length) {
      return false;
    }
    for (var i = 0; i < a.verts.length; i++) {
      if (a.verts[i][0] != b.verts[i][0] || a.verts[i][1] != b.verts[i][1]) {
        return false;
      }
    }
    for (var i = 0; i < a.bulges.length; i++) {
      if ((a.bulges[i] - b.bulges[i]).abs() > 1e-9) return false;
    }
    return true;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  void record(OutlineSnap before) {
    _undo.add(before);
    _redo.clear();
  }

  OutlineSnap? undo(OutlineSnap current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  OutlineSnap? redo(OutlineSnap current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    return _redo.removeLast();
  }
}

/// Neutral bulges (one per edge) matching [vertCount].
List<double> zeroBulges(int vertCount) =>
    List<double>.filled(vertCount < 0 ? 0 : vertCount, 0.0);

Offset closestPointOnSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-9) return a;
  final t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
  final u = t.clamp(0.0, 1.0);
  return Offset(a.dx + ab.dx * u, a.dy + ab.dy * u);
}

double _distToSegment(Offset p, Offset a, Offset b) =>
    (p - closestPointOnSegment(p, a, b)).distance;

/// Soft-corner / edge-bent closed path. [bulges[i]] bends edge i→i+1
/// (fraction of image shortest side; + = left of directed edge).
Path curvedPathFromNorm(
  List outline,
  Rect dest, {
  List<double>? bulges,
}) {
  final pts = <Offset>[];
  for (final p in outline) {
    if (p is! List || p.length < 2) continue;
    pts.add(normToLocal(p, dest));
  }
  final n = pts.length;
  final path = Path();
  if (n < 3) return path;

  final scale = dest.shortestSide.clamp(1.0, 10000.0);
  path.moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < n; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % n];
    final ctrl = _edgeCtrl(a, b, bulges, i, unit: scale);
    if (ctrl == null) {
      path.lineTo(b.dx, b.dy);
    } else {
      path.quadraticBezierTo(ctrl.dx, ctrl.dy, b.dx, b.dy);
    }
  }
  path.close();
  return path;
}

/// Sample curved outline to a polyline for backend fillPoly.
List<List<double>> sampleCurvedOutline(
  List<List<double>> verts,
  List<double> bulges, {
  int samplesPerEdge = 5,
}) {
  final n = verts.length;
  if (n < 3) return OutlineEditHistory.cloneVerts(verts);
  final out = <List<double>>[];
  final sp = samplesPerEdge.clamp(2, 12);
  for (var i = 0; i < n; i++) {
    final a = Offset(verts[i][0], verts[i][1]);
    final b = Offset(verts[(i + 1) % n][0], verts[(i + 1) % n][1]);
    // Norm space: treat unit length as 1 (square image).
    final ctrl = _edgeCtrl(a, b, bulges, i, unit: 1.0) ?? a;
    for (var s = 0; s < sp; s++) {
      final o = _quadBezier(a, ctrl, b, s / sp);
      out.add([
        (o.dx * 1e5).round() / 1e5,
        (o.dy * 1e5).round() / 1e5,
      ]);
    }
  }
  return out;
}

/// Control point for edge a→b, or null if edge is degenerate.
Offset? _edgeCtrl(
  Offset a,
  Offset b,
  List<double>? bulges,
  int i, {
  required double unit,
}) {
  final ab = b - a;
  final len = ab.distance;
  if (len < 1e-9) return null;
  final user = (bulges != null && i < bulges.length) ? bulges[i] : 0.0;
  final auto = 0.012 * (len / unit);
  final bulge = (user + auto).clamp(-0.09, 0.09);
  final perp = Offset(-ab.dy / len, ab.dx / len);
  final mid = Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5);
  return mid + perp * (bulge * unit);
}

Offset _quadBezier(Offset a, Offset c, Offset b, double t) {
  final u = 1 - t;
  return Offset(
    u * u * a.dx + 2 * u * t * c.dx + t * t * b.dx,
    u * u * a.dy + 2 * u * t * c.dy + t * t * b.dy,
  );
}

/// Hit-test closest outline edge. Returns edge index (vertex i → i+1) or null.
int? hitTestOutlineEdge({
  required Offset local,
  required Size box,
  required Size imageSize,
  required List<List<double>> outline,
  double maxDist = 22,
}) {
  final dest = containRect(box, imageSize);
  final n = outline.length;
  if (n < 2) return null;
  int? best;
  var bestDist = maxDist;
  for (var i = 0; i < n; i++) {
    final a = normToLocal(outline[i], dest);
    final b = normToLocal(outline[(i + 1) % n], dest);
    final d = _distToSegment(local, a, b);
    if (d <= bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
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
  int? preferIndex,
}) {
  final dest = containRect(box, imageSize);
  if (!dest.contains(local)) return null;
  final nx = ((local.dx - dest.left) / dest.width).clamp(0.0, 1.0);
  final ny = ((local.dy - dest.top) / dest.height).clamp(0.0, 1.0);
  final point = Offset(local.dx, local.dy);

  int? bestOutline;
  var bestOutlineArea = double.infinity;
  int? bestBBox;
  var bestBBoxArea = double.infinity;

  for (final t in teeth) {
    final idx = (t['tooth_index'] as num?)?.toInt();
    if (idx == null) continue;
    final geo = t['geometry'];
    if (geo is! Map) continue;

    final bbox = geo['bbox'];
    double? area;
    if (bbox is Map) {
      final x = (bbox['x'] as num).toDouble();
      final y = (bbox['y'] as num).toDouble();
      final w = (bbox['w'] as num).toDouble();
      final h = (bbox['h'] as num).toDouble();
      area = w * h;
      if (nx >= x && nx <= x + w && ny >= y && ny <= y + h) {
        if (area < bestBBoxArea ||
            (area == bestBBoxArea && preferIndex != null && idx == preferIndex)) {
          bestBBoxArea = area;
          bestBBox = idx;
        }
      }
    }

    final raw = geo['outline'];
    if (raw is List && raw.length >= 3) {
      final verts = [
        for (final p in raw)
          if (p is List && p.length >= 2)
            [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
      ];
      if (verts.length >= 3) {
        final path = curvedPathFromNorm(verts, dest);
        if (path.contains(point)) {
          final a = area ?? 1.0;
          // Prefer outline hits; among those, smallest tooth. On a tie,
          // prefer a tooth that isn't already selected so taps can switch.
          final better = bestOutline == null ||
              a < bestOutlineArea ||
              (a == bestOutlineArea &&
                  preferIndex != null &&
                  idx != preferIndex);
          if (better) {
            bestOutlineArea = a;
            bestOutline = idx;
          }
        }
      }
    }
  }

  return bestOutline ?? bestBBox;
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
  /// [repaint] drives handle drags: the outline list is mutated in place, so
  /// there is no new painter to compare against while a handle moves.
  ToothOverlayPainter({
    super.repaint,
    required this.teeth,
    required this.selectedToothIndex,
    required this.imageSize,
    required this.focusZone,
    this.isolatedToothIndex,
    this.editMode = false,
    this.editOutline,
    this.editBulges,
    this.activeHandleIndex,
    this.activeEdgeIndex,
    this.transformationController,
  });

  final List<Map<String, dynamic>> teeth;
  final int? selectedToothIndex;
  /// When set, non-focused teeth are drawn dimmer (still tappable).
  final int? isolatedToothIndex;
  final Size imageSize;
  final String focusZone;
  final bool editMode;
  final List<List<double>>? editOutline;
  final List<double>? editBulges;
  final int? activeHandleIndex;
  final int? activeEdgeIndex;
  final TransformationController? transformationController;

  static const _zoneColors = {
    'cervical': Color(0xFFE09B2D),
    'middle': Color(0xFF4A90E2),
    'incisal': Color(0xFF1F9D63),
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (teeth.isEmpty || imageSize.width <= 0) return;
    final dest = containRect(size, imageSize);

    // After upload: draw all. After triple-tap isolate: draw only that tooth.
    final isolateIdx = isolatedToothIndex;

    for (final t in teeth) {
      final idx = (t['tooth_index'] as num?)?.toInt();
      if (idx == null) continue;
      if (isolateIdx != null && idx != isolateIdx) continue;
      final selected = idx == selectedToothIndex;
      final rejected = t['rejected'] == true;
      final geo = t['geometry'];
      if (geo is! Map) continue;

      final List<List<double>> verts;
      final List<double>? bulges;
      if (editMode && selected && editOutline != null) {
        verts = editOutline!;
        bulges = editBulges;
      } else {
        final raw = geo['outline'];
        if (raw is! List || raw.length < 3) continue;
        verts = [
          for (final p in raw)
            if (p is List && p.length >= 2)
              [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
        ];
        bulges = null;
      }
      if (verts.length >= 3) {
        final path = curvedPathFromNorm(verts, dest, bulges: bulges);

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
            final zVerts = [
              for (final p in pts)
                if (p is List && p.length >= 2)
                  [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
            ];
            final path = curvedPathFromNorm(zVerts, dest);
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

    if (editMode && editOutline != null) {
      final scale =
          transformationController?.value.getMaxScaleOnAxis().clamp(1.0, 4.0) ??
              1.0;
      for (var i = 0; i < editOutline!.length; i++) {
        final a = normToLocal(editOutline![i], dest);
        final b = normToLocal(editOutline![(i + 1) % editOutline!.length], dest);
        final mid = Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5);
        final active = i == activeEdgeIndex;
        canvas.drawCircle(
          mid,
          (active ? 5.5 : 4.0) / scale,
          Paint()
            ..color = active
                ? AppColors.dentalBlue.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.55),
        );
      }
      for (var i = 0; i < editOutline!.length; i++) {
        final o = normToLocal(editOutline![i], dest);
        final active = i == activeHandleIndex;
        canvas.drawCircle(
          o,
          (active ? 8 : 7) / scale,
          Paint()..color = Colors.white.withValues(alpha: 0.35),
        );
        canvas.drawCircle(
          o,
          (active ? 5 : 4.5) / scale,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          o,
          (active ? 3 : 2.5) / scale,
          Paint()..color = AppColors.dentalBlue,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ToothOverlayPainter oldDelegate) {
    if (editMode || oldDelegate.editMode) return true;
    return oldDelegate.selectedToothIndex != selectedToothIndex ||
        oldDelegate.isolatedToothIndex != isolatedToothIndex ||
        oldDelegate.focusZone != focusZone ||
        oldDelegate.teeth != teeth ||
        oldDelegate.imageSize != imageSize;
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'shade_shared.dart';

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

/// Backend `lines` → {"upper_incisal": [[x, y], ...], "lower_incisal": ...}.
Map<String, List<List<double>>> parseGuideLines(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, List<List<double>>>{};
  for (final e in raw.entries) {
    final pts = e.value;
    if (pts is! List) continue;
    final line = [
      for (final p in pts)
        if (p is List && p.length >= 2)
          [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
    ];
    if (line.length >= 2) out['${e.key}'] = line;
  }
  return out;
}

/// Symmetry-view lip lines from the lip outline: [top] runs across the lips
/// (4% past each corner) at the upper lip's highest point; [bottomY] is the
/// lower lip's lowest point (drawn full width). Null when that lip is absent.
({List<List<double>>? top, double? bottomY}) lipSymmetryLines(
  Map<String, List<List<double>>> guides,
) {
  final upper = guides['upper_lip'] ?? const <List<double>>[];
  final lower = guides['lower_lip'] ?? const <List<double>>[];
  final lips = [...upper, ...lower];
  if (lips.isEmpty) return (top: null, bottomY: null);
  final xs = [for (final p in lips) p[0]];
  final x0 = xs.reduce((a, b) => a < b ? a : b);
  final x1 = xs.reduce((a, b) => a > b ? a : b);
  final pad = 0.04 * (x1 - x0);
  final topY = upper.isEmpty
      ? null
      : upper.map((p) => p[1]).reduce((a, b) => a < b ? a : b);
  return (
    top: topY == null
        ? null
        : [
            [x0 - pad, topY],
            [x1 + pad, topY],
          ],
    bottomY: lower.isEmpty
        ? null
        : lower.map((p) => p[1]).reduce((a, b) => a > b ? a : b),
  );
}

/// Guides the user can drag in Adjust edges.
const kEditableGuides = {'midline', 'upper_lip', 'lower_lip'};

/// Guide point under [local] — (key, point index), or null.
/// Index -1 = the midline's body (drag slides the whole line).
({String key, int index})? hitTestGuideHandle({
  required Offset local,
  required Size box,
  required Size imageSize,
  required Map<String, List<List<double>>> guides,
  double radius = 28,
}) {
  final dest = containRect(box, imageSize);
  ({String key, int index})? best;
  var bestDist = radius;
  for (final e in guides.entries) {
    if (!kEditableGuides.contains(e.key)) continue;
    for (var i = 0; i < e.value.length; i++) {
      final d = (normToLocal(e.value[i], dest) - local).distance;
      if (d <= bestDist) {
        bestDist = d;
        best = (key: e.key, index: i);
      }
    }
  }
  final mid = guides['midline'];
  if (best == null && mid != null && mid.length >= 2) {
    final a = normToLocal(mid.first, dest);
    final b = normToLocal(mid.last, dest);
    if (_distToSegment(local, a, b) <= radius * 0.6) {
      return (key: 'midline', index: -1);
    }
  }
  return best;
}

/// Smooth open curve through [pts] (Catmull–Rom as cubic Béziers).
Path smoothOpenPath(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  for (var i = 0; i + 1 < pts.length; i++) {
    final p0 = pts[i == 0 ? 0 : i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = pts[i + 2 < pts.length ? i + 2 : i + 1];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
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

/// Soft-corner closed path. User [bulges] still bend individual edges.
/// Dense display rings (no bulges) use a Catmull–Rom spline so the stroke
/// follows the crown instead of showing polygon corners.
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

  var hasBulge = false;
  if (bulges != null) {
    for (final b in bulges) {
      if (b.abs() > 1e-9) {
        hasBulge = true;
        break;
      }
    }
  }
  if (!hasBulge && n >= 16) {
    return _catmullRomClosed(pts);
  }

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

Path _catmullRomClosed(List<Offset> pts) {
  final n = pts.length;
  final path = Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = pts[(i - 1) % n];
    final p1 = pts[i];
    final p2 = pts[(i + 1) % n];
    final p3 = pts[(i + 2) % n];
    final c1 = Offset(
      p1.dx + (p2.dx - p0.dx) / 6,
      p1.dy + (p2.dy - p0.dy) / 6,
    );
    final c2 = Offset(
      p2.dx - (p3.dx - p1.dx) / 6,
      p2.dy - (p3.dy - p1.dy) / 6,
    );
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
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
    final ctrl = _edgeCtrl(a, b, bulges, i, unit: 1.0);
    for (var s = 0; s < sp; s++) {
      final t = s / sp;
      final o = ctrl == null
          ? Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t)
          : _quadBezier(a, ctrl, b, t);
      out.add([
        (o.dx * 1e5).round() / 1e5,
        (o.dy * 1e5).round() / 1e5,
      ]);
    }
  }
  return out;
}

/// Control point for edge a→b, or null for a straight edge / degenerate.
/// Only user-set [bulges] bend the edge — no automatic puff.
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
  if (user.abs() < 1e-9) return null;
  final bulge = user.clamp(-0.09, 0.09);
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

/// Edit target under [local]: the nearest visible dot wins — a corner ('v')
/// or an edge-curve dot ('e') — so dense outlines don't steal the grab.
/// Inside the outline with no dot nearby drags the whole outline ('b').
({String kind, int index})? hitTestOutlineEditTarget({
  required Offset local,
  required Size box,
  required Size imageSize,
  required List<List<double>> outline,
  List<double>? bulges,
  double radius = 28,
}) {
  final dest = containRect(box, imageSize);
  final n = outline.length;
  ({String kind, int index})? best;
  var bestDist = radius;
  for (var i = 0; i < n; i++) {
    final a = normToLocal(outline[i], dest);
    final b = normToLocal(outline[(i + 1) % n], dest);
    final dv = (a - local).distance;
    if (dv <= bestDist) {
      bestDist = dv;
      best = (kind: 'v', index: i);
    }
    // Edge dots are drawn smaller; a slight handicap lets corners win ties.
    final mid = Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5);
    final de = (mid - local).distance * 1.15;
    if (de < bestDist) {
      bestDist = de;
      best = (kind: 'e', index: i);
    }
  }
  if (best != null) return best;
  if (n >= 3 &&
      curvedPathFromNorm(outline, dest, bulges: bulges).contains(local)) {
    return (kind: 'b', index: 0);
  }
  return null;
}

/// Simplify a dense outline to ~6–8 control points for edge editing.
///
/// Keep in sync with backend `EDIT_HANDLES_MAX` / `EDIT_HANDLES_MIN`.
/// Douglas–Peucker style reduction, then midpoints on longest edges if too few.
List<List<double>> simplifyOutlineForEdit(
  List outline, {
  int maxPoints = 12,
  int minPoints = 8,
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

/// Axis-aligned bounds of a normalized outline.
Rect outlineBBox(List<List<double>> pts) {
  if (pts.isEmpty) return Rect.zero;
  var left = pts[0][0], top = pts[0][1], right = pts[0][0], bottom = pts[0][1];
  for (final p in pts) {
    if (p[0] < left) left = p[0];
    if (p[0] > right) right = p[0];
    if (p[1] < top) top = p[1];
    if (p[1] > bottom) bottom = p[1];
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

Rect? toothGeometryBBox(Map<dynamic, dynamic> tooth) {
  final geo = tooth['geometry'];
  if (geo is Map) {
    final bbox = geo['bbox'];
    if (bbox is Map) {
      final w = (bbox['w'] as num?)?.toDouble() ?? 0;
      final h = (bbox['h'] as num?)?.toDouble() ?? 0;
      if (w > 0.012 && h > 0.02) {
        return Rect.fromLTWH(
          (bbox['x'] as num?)?.toDouble() ?? 0,
          (bbox['y'] as num?)?.toDouble() ?? 0,
          w,
          h,
        );
      }
    }
  }
  final pts = toothEditHandles(tooth);
  if (pts == null || pts.length < 3) return null;
  return outlineBBox(pts);
}

/// Sparse handles used in Adjust edges (prefers stored skeleton).
List<List<double>>? toothEditHandles(Map<dynamic, dynamic> tooth) {
  final geo = tooth['geometry'];
  if (geo is! Map) return null;
  final handles = geo['edit_handles'];
  if (handles is List && handles.length >= 3) {
    final pts = <List<double>>[
      for (final p in handles)
        if (p is List && p.length >= 2)
          [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
    ];
    if (pts.length >= 3) return pts;
  }
  final raw = geo['outline'];
  if (raw is! List || raw.length < 3) return null;
  final simplified = simplifyOutlineForEdit(raw, maxPoints: 8, minPoints: 6);
  return simplified.length >= 3 ? simplified : null;
}

List<double>? toothEdgeBulges(Map<dynamic, dynamic> tooth, int vertCount) {
  final geo = tooth['geometry'];
  if (geo is! Map) return null;
  final stored = geo['edge_bulges'];
  if (stored is! List || stored.length != vertCount) return null;
  return [for (final b in stored) (b as num).toDouble()];
}

/// Incisor-like 8-handle crown, mapped into [box] (normalized image space).
List<List<double>> crownOutlineForBBox(Rect box) {
  const unit = <List<double>>[
    [0.30, 0.07],
    [0.50, 0.03],
    [0.70, 0.07],
    [0.93, 0.38],
    [0.88, 0.80],
    [0.50, 0.97],
    [0.12, 0.80],
    [0.07, 0.38],
  ];
  return [
    for (final p in unit)
      [box.left + p[0] * box.width, box.top + p[1] * box.height],
  ];
}

List<List<double>> translateOutline(
  List<List<double>> pts,
  double dx,
  double dy,
) =>
    [
      for (final p in pts) [p[0] + dx, p[1] + dy],
    ];

/// Keep the whole polygon on the photo. Scales about center if it still overflows.
List<List<double>> clampOutlineToImage(
  List<List<double>> pts, {
  double pad = 0.02,
}) {
  if (pts.length < 3) return pts;
  var next = OutlineEditHistory.cloneVerts(pts);
  var box = outlineBBox(next);
  var dx = 0.0;
  var dy = 0.0;
  if (box.left < pad) dx = pad - box.left;
  if (box.right > 1 - pad) dx = (1 - pad) - box.right;
  if (box.top < pad) dy = pad - box.top;
  if (box.bottom > 1 - pad) dy = (1 - pad) - box.bottom;
  if (dx != 0 || dy != 0) {
    next = translateOutline(next, dx, dy);
    box = outlineBBox(next);
  }
  final maxW = 1 - 2 * pad;
  final maxH = 1 - 2 * pad;
  if (box.width <= maxW && box.height <= maxH) return next;
  final scale = [
    maxW / box.width,
    maxH / box.height,
    1.0,
  ].reduce((a, b) => a < b ? a : b);
  final cx = box.center.dx;
  final cy = box.center.dy;
  return [
    for (final p in next)
      [
        cx + (p[0] - cx) * scale,
        cy + (p[1] - cy) * scale,
      ],
  ];
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
    this.editMode = false,
    this.editOutline,
    this.editBulges,
    this.activeHandleIndex,
    this.activeEdgeIndex,
    this.transformationController,
    this.paintSelectedOnlyWhileDragging = false,
    this.guideLines = const {},
    this.symmetryView = false,
    this.focusSelected = false,
  });

  final List<Map<String, dynamic>> teeth;
  final int? selectedToothIndex;
  final Size imageSize;
  final String focusZone;
  final bool editMode;
  final List<List<double>>? editOutline;
  final List<double>? editBulges;
  final int? activeHandleIndex;
  final int? activeEdgeIndex;
  final TransformationController? transformationController;
  /// Loupe: skip other teeth while a handle/edge is active (cheaper frames).
  final bool paintSelectedOnlyWhileDragging;
  /// Guides from [parseGuideLines]: bite line(s) (`upper_incisal` +
  /// `lower_incisal`, or one `occlusal`), `midline`, and user-placed
  /// `upper_lip` / `lower_lip`.
  final Map<String, List<List<double>>> guideLines;
  /// Symmetry view: only the midline + the lip top / bottom lines.
  final bool symmetryView;
  /// Focus view: only the selected tooth's mapping, nothing else.
  final bool focusSelected;

  /// Clinical overlay — matches aesthetic analysis plates (box / axis / ticks).
  static const _boxColor = Color(0xFFA48CC8);
  static const _axisColor = Color(0xFFE6C34A);
  static const _tickColor = Color(0xFF6DB56A);
  static const _contourColor = Color(0xFFE8F4F8);
  static const _midlineColor = Color(0xFFF0F0F0);
  static const _upperIncisalColor = Color(0xFFFF8A65);
  static const _lowerIncisalColor = Color(0xFF64B5F6);
  /// Closed bite: one shared line where the arches meet.
  static const _occlusalColor = Color(0xFF4DB6AC);
  static const _lipColor = Color(0xFFF06292);

  /// Cached paths for teeth that don't move during a drag.
  Size? _staticCacheSize;
  List<_CachedToothStroke>? _staticCache;

  @override
  void paint(Canvas canvas, Size size) {
    if (teeth.isEmpty || imageSize.width <= 0) return;
    final dest = containRect(size, imageSize);
    final dragging = editMode &&
        (activeHandleIndex != null || activeEdgeIndex != null);

    if (paintSelectedOnlyWhileDragging && dragging) {
      _paintSelectedEdit(canvas, dest);
      return;
    }

    if (dragging) {
      _ensureStaticCache(size, dest);
      for (final c in _staticCache!) {
        if (c.selected) continue;
        _paintCachedTooth(canvas, c);
      }
      _paintGuideLines(canvas, dest);
      _paintSelectedEdit(canvas, dest);
      return;
    }

    _staticCache = null;
    _staticCacheSize = null;
    if (symmetryView && !editMode) {
      _paintSymmetry(canvas, dest);
      return;
    }
    final focusOnly = focusSelected && !editMode;
    for (final t in teeth) {
      final idx = (t['tooth_index'] as num?)?.toInt();
      if (idx == null) continue;
      final selected = idx == selectedToothIndex;
      if (focusOnly && !selected) continue;
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
        final editing = editMode && selected;
        final fill = Paint()
          ..style = PaintingStyle.fill
          ..color = editing
              ? AppColors.dentalBlue.withValues(alpha: 0.28)
              : (rejected
                  ? AppColors.danger.withValues(alpha: 0.08)
                  : (selected
                      ? AppColors.dentalBlue.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.02)));
        canvas.drawPath(path, fill);
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 1.7 : 1.15
          ..color = rejected
              ? AppColors.danger
              : (editing ? AppColors.dentalBlue : _contourColor);
        canvas.drawPath(path, stroke);
      }

      if (selected && !editMode) {
        _paintClinicalMarks(
          canvas,
          dest,
          geo,
          selected: true,
          rejected: rejected,
        );
      }

      final label = geo['label'];
      if (label is Map && !(editMode && selected)) {
        _paintLabel(
          canvas,
          _LabelPaint(
            at: normToLocal([label['x'], label['y']], dest),
            text: toothDisplayLabel(t),
            selected: selected,
          ),
        );
      }
    }

    if (!focusOnly) _paintGuideLines(canvas, dest);

    if (editMode && editOutline != null) {
      _paintEditHandles(canvas, dest);
    }
    if (editMode) _paintGuideHandles(canvas, dest);
  }

  void _paintGuideLines(Canvas canvas, Rect dest) {
    for (final e in guideLines.entries) {
      final color = switch (e.key) {
        'lower_incisal' => _lowerIncisalColor,
        'occlusal' => _occlusalColor,
        'midline' => _midlineColor,
        'upper_lip' || 'lower_lip' => _lipColor,
        _ => _upperIncisalColor,
      };
      final pts = [for (final p in e.value) normToLocal(p, dest)];
      final lip = e.key.endsWith('_lip');
      canvas.drawPath(
        lip ? smoothOpenPath(pts) : (Path()..addPolygon(pts, false)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = e.key == 'midline' ? 1.2 : (lip ? 2.0 : 1.6)
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.9),
      );
    }
  }

  /// Midline, lip outline, and horizontal lines at the top of the upper lip
  /// (arrowed, across the lips) and the bottom of the lower lip (full width).
  void _paintSymmetry(Canvas canvas, Rect dest) {
    for (final key in ['upper_lip', 'lower_lip']) {
      final lip = guideLines[key];
      if (lip == null || lip.length < 2) continue;
      canvas.drawPath(
        smoothOpenPath([for (final p in lip) normToLocal(p, dest)]),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..color = _lipColor.withValues(alpha: 0.9),
      );
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = _midlineColor.withValues(alpha: 0.9);
    final mid = guideLines['midline'];
    if (mid != null && mid.length >= 2) {
      canvas.drawLine(
        normToLocal(mid.first, dest),
        normToLocal(mid.last, dest),
        paint,
      );
    }
    final lines = lipSymmetryLines(guideLines);
    final top = lines.top;
    if (top != null) {
      final a = normToLocal(top.first, dest);
      final b = normToLocal(top.last, dest);
      canvas.drawLine(a, b, paint);
      const head = 7.0;
      for (final (tip, dir) in [(a, 1.0), (b, -1.0)]) {
        canvas.drawLine(tip, tip + Offset(dir * head, -head * 0.6), paint);
        canvas.drawLine(tip, tip + Offset(dir * head, head * 0.6), paint);
      }
    }
    final bottom = lines.bottomY;
    if (bottom != null) {
      final y = normToLocal([0, bottom], dest).dy;
      canvas.drawLine(Offset(dest.left, y), Offset(dest.right, y), paint);
    }
  }

  /// Adjust edges: drag dots on the midline ends and lip points.
  void _paintGuideHandles(Canvas canvas, Rect dest) {
    final scale =
        transformationController?.value.getMaxScaleOnAxis().clamp(1.0, 4.0) ??
            1.0;
    for (final e in guideLines.entries) {
      if (!kEditableGuides.contains(e.key)) continue;
      final color = e.key == 'midline' ? _midlineColor : _lipColor;
      for (final p in e.value) {
        final o = normToLocal(p, dest);
        canvas.drawCircle(o, 6.5 / scale, Paint()..color = Colors.black38);
        canvas.drawCircle(o, 5 / scale, Paint()..color = color);
      }
    }
  }

  void _ensureStaticCache(Size size, Rect dest) {
    if (_staticCache != null && _staticCacheSize == size) return;
    _staticCacheSize = size;
    final out = <_CachedToothStroke>[];
    for (final t in teeth) {
      final idx = (t['tooth_index'] as num?)?.toInt();
      if (idx == null) continue;
      final selected = idx == selectedToothIndex;
      if (selected) continue;
      final rejected = t['rejected'] == true;
      final geo = t['geometry'];
      if (geo is! Map) continue;
      final raw = geo['outline'];
      if (raw is! List || raw.length < 3) continue;
      final verts = [
        for (final p in raw)
          if (p is List && p.length >= 2)
            [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
      ];
      if (verts.length < 3) continue;
      final path = curvedPathFromNorm(verts, dest);
      _LabelPaint? labelPaint;
      final label = geo['label'];
      if (label is Map) {
        labelPaint = _LabelPaint(
          at: normToLocal([label['x'], label['y']], dest),
          text: toothDisplayLabel(t),
          selected: false,
        );
      }
      out.add(
        _CachedToothStroke(
          path: path,
          selected: false,
          fill: Paint()
            ..style = PaintingStyle.fill
            ..color = rejected
                ? AppColors.danger.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.02),
          stroke: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.15
            ..color = rejected ? AppColors.danger : _contourColor,
          label: labelPaint,
        ),
      );
    }
    _staticCache = out;
  }

  void _paintCachedTooth(Canvas canvas, _CachedToothStroke c) {
    canvas.drawPath(c.path, c.fill);
    canvas.drawPath(c.path, c.stroke);
    if (c.label != null) {
      _paintLabel(canvas, c.label!);
    }
  }

  void _paintClinicalMarks(
    Canvas canvas,
    Rect dest,
    Map geo, {
    required bool selected,
    required bool rejected,
  }) {
    final marks = _clinicalMarks(geo, dest);
    _strokeClinical(
      canvas,
      box: marks.box,
      axisFrom: marks.axis?.$1,
      axisTo: marks.axis?.$2,
      ticks: marks.ticks,
      selected: selected,
      rejected: rejected,
    );
  }

  ({Rect? box, (Offset, Offset)? axis, List<(Offset, Offset)> ticks})
      _clinicalMarks(Map geo, Rect dest) {
    var box = _bboxRect(geo['bbox'], dest);
    var axis = _normLine(geo['axis'], dest);
    final ticks = <(Offset, Offset)>[];
    final rawTicks = geo['width_ticks'];
    if (rawTicks is List) {
      for (final line in rawTicks) {
        final t = _normLine(line, dest);
        if (t != null) ticks.add(t);
      }
    }
    if (box == null) {
      final raw = geo['outline'];
      if (raw is List && raw.length >= 3) {
        final verts = [
          for (final p in raw)
            if (p is List && p.length >= 2)
              [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
        ];
        if (verts.length >= 3) {
          final nb = outlineBBox(verts);
          box = Rect.fromLTWH(
            dest.left + nb.left * dest.width,
            dest.top + nb.top * dest.height,
            nb.width * dest.width,
            nb.height * dest.height,
          );
        }
      }
    }
    if (axis == null && box != null) {
      axis = (Offset(box.center.dx, box.top), Offset(box.center.dx, box.bottom));
    }
    if (ticks.isEmpty && box != null) {
      for (final frac in [0.18, 0.50, 0.82]) {
        final y = box.top + box.height * frac;
        ticks.add((Offset(box.left, y), Offset(box.right, y)));
      }
    }
    return (box: box, axis: axis, ticks: ticks);
  }

  void _strokeClinical(
    Canvas canvas, {
    required Rect? box,
    required Offset? axisFrom,
    required Offset? axisTo,
    required List<(Offset, Offset)> ticks,
    required bool selected,
    required bool rejected,
  }) {
    if (box != null) {
      canvas.drawRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.15 : 1.35
          ..color = rejected
              ? AppColors.danger.withValues(alpha: 0.9)
              : _boxColor.withValues(alpha: selected ? 1 : 0.9),
      );
    }
    if (axisFrom != null && axisTo != null) {
      canvas.drawLine(
        axisFrom,
        axisTo,
        Paint()
          ..color = _axisColor.withValues(alpha: selected ? 1 : 0.92)
          ..strokeWidth = selected ? 2.05 : 1.35
          ..strokeCap = StrokeCap.round,
      );
    }
    final focusIdx = switch (focusZone) {
      'cervical' => 0,
      'middle' => 1,
      'incisal' => 2,
      _ => -1,
    };
    for (var i = 0; i < ticks.length; i++) {
      final tick = ticks[i];
      final hot = selected && i == focusIdx;
      canvas.drawLine(
        tick.$1,
        tick.$2,
        Paint()
          ..color = _tickColor.withValues(alpha: hot ? 1 : (selected ? 0.95 : 0.85))
          ..strokeWidth = hot ? 2.0 : (selected ? 1.55 : 1.2)
          ..strokeCap = StrokeCap.square,
      );
    }
  }

  Rect? _bboxRect(dynamic bbox, Rect dest) {
    if (bbox is! Map) return null;
    final w = (bbox['w'] as num?)?.toDouble() ?? 0;
    final h = (bbox['h'] as num?)?.toDouble() ?? 0;
    if (w <= 0.004 || h <= 0.004) return null;
    return Rect.fromLTWH(
      dest.left + ((bbox['x'] as num?)?.toDouble() ?? 0) * dest.width,
      dest.top + ((bbox['y'] as num?)?.toDouble() ?? 0) * dest.height,
      w * dest.width,
      h * dest.height,
    );
  }

  (Offset, Offset)? _normLine(dynamic line, Rect dest) {
    if (line is! List || line.length < 2) return null;
    final a = line[0];
    final b = line[1];
    if (a is! List || b is! List || a.length < 2 || b.length < 2) return null;
    return (normToLocal(a, dest), normToLocal(b, dest));
  }

  void _paintSelectedEdit(Canvas canvas, Rect dest) {
    if (editOutline == null || editOutline!.length < 3) return;
    final path =
        curvedPathFromNorm(editOutline!, dest, bulges: editBulges);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = AppColors.dentalBlue.withValues(alpha: 0.28),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..color = AppColors.dentalBlue,
    );
    _paintEditHandles(canvas, dest);
  }

  void _paintEditHandles(Canvas canvas, Rect dest) {
    if (editOutline == null) return;
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

  void _paintLabel(Canvas canvas, _LabelPaint label) {
    final tp = TextPainter(
      text: TextSpan(
        text: label.text,
        style: TextStyle(
          color: Colors.white,
          fontSize: label.selected ? 13 : 11,
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
        center: label.at.translate(0, -2),
        width: tp.width + 10,
        height: tp.height + 4,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      bg,
      Paint()
        ..color = label.selected
            ? AppColors.dentalBlue
            : AppColors.navy.withValues(alpha: 0.85),
    );
    tp.paint(
      canvas,
      Offset(label.at.dx - tp.width / 2, label.at.dy - tp.height / 2 - 2),
    );
  }

  @override
  bool shouldRepaint(covariant ToothOverlayPainter oldDelegate) {
    if (editMode || oldDelegate.editMode) return true;
    return oldDelegate.selectedToothIndex != selectedToothIndex ||
        oldDelegate.focusZone != focusZone ||
        oldDelegate.teeth != teeth ||
        oldDelegate.guideLines != guideLines ||
        oldDelegate.symmetryView != symmetryView ||
        oldDelegate.focusSelected != focusSelected ||
        oldDelegate.imageSize != imageSize;
  }
}

class _CachedToothStroke {
  const _CachedToothStroke({
    required this.path,
    required this.selected,
    required this.fill,
    required this.stroke,
    this.label,
  });

  final Path path;
  final bool selected;
  final Paint fill;
  final Paint stroke;
  final _LabelPaint? label;
}

class _LabelPaint {
  const _LabelPaint({
    required this.at,
    required this.text,
    required this.selected,
  });

  final Offset at;
  final String text;
  final bool selected;
}

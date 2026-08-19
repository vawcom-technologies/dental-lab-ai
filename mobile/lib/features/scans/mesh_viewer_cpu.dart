import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'mesh_sample.dart';
import 'mesh_viewer_chrome.dart';

/// CPU / CustomPaint preview — **web only** via [MeshViewer] on `dart.library.html`.
/// Native iPad must not use this: Impeller often fails to fill `drawVertices`,
/// which looks exactly like a point cloud while the HUD still says "N tris".
class CpuMeshViewer extends StatefulWidget {
  const CpuMeshViewer({
    super.key,
    this.bytes,
    this.filename,
    this.previewVertices = const [],
    this.loading = false,
    this.error,
    this.vertexCount,
  });

  final Uint8List? bytes;
  final String? filename;
  final List<List<double>> previewVertices;
  final bool loading;
  final String? error;
  final int? vertexCount;

  @override
  State<CpuMeshViewer> createState() => _CpuMeshViewerState();
}

class _CpuMeshViewerState extends State<CpuMeshViewer> {
  List<List<double>> _vertices = const [];
  Float32List? _triangles;
  String? _sampleError;
  bool _sampling = false;
  bool _solid = true;
  double _yaw = 0.55;
  double _pitch = -0.35;
  double _zoom = 1.0;
  double _baseZoom = 1.0;
  Object? _token;

  bool get _canSolid => _triangles != null && _triangles!.length >= 18;

  @override
  void initState() {
    super.initState();
    _resync();
  }

  @override
  void didUpdateWidget(covariant CpuMeshViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.filename != widget.filename ||
        !identical(oldWidget.previewVertices, widget.previewVertices)) {
      _resync();
    }
  }

  void _resync() {
    final token = Object();
    _token = token;
    if (widget.bytes != null && widget.bytes!.isNotEmpty) {
      setState(() {
        _sampling = true;
        _sampleError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!identical(_token, token) || !mounted) return;
        try {
          final local = sampleMeshBytes(
            widget.bytes!,
            widget.filename ?? 'scan.ply',
          );
          if (!identical(_token, token) || !mounted) return;
          setState(() {
            _vertices = local.vertices;
            _triangles = local.triangles;
            _sampleError = local.error;
            _sampling = false;
            if (!_canSolid) _solid = false;
          });
        } catch (e) {
          if (!identical(_token, token) || !mounted) return;
          setState(() {
            _vertices = const [];
            _triangles = null;
            _sampleError = e.toString().replaceFirst('Exception: ', '');
            _sampling = false;
            _solid = false;
          });
        }
      });
      return;
    }
    setState(() {
      _vertices = widget.previewVertices;
      _triangles = null;
      _sampleError = null;
      _sampling = false;
      _solid = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    _sampleError = AppSnackBars.drain(context, _sampleError);
    final empty = _vertices.isEmpty && !_canSolid;
    final busy = widget.loading || _sampling;

    return ClipRRect(
      borderRadius: AppRadii.border,
      child: ColoredBox(
        color: const Color(0xFF15283F),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (busy)
              const Center(
                child: ToothLoadingIndicator(
                  size: 44,
                  color: Colors.white70,
                  loadingText: 'Loading mesh…',
                ),
              )
            else if (empty)
              const MeshViewerHint('Upload a PLY / STL / OBJ to preview')
            else
              GestureDetector(
                onScaleStart: (_) => _baseZoom = _zoom,
                onScaleUpdate: (d) {
                  setState(() {
                    _zoom = (_baseZoom * d.scale).clamp(0.35, 4.0);
                    _yaw += d.focalPointDelta.dx * 0.008;
                    _pitch = (_pitch + d.focalPointDelta.dy * 0.008)
                        .clamp(-1.2, 1.2);
                  });
                },
                child: CustomPaint(
                  painter: _CpuMeshPainter(
                    vertices: _vertices,
                    triangles: _triangles,
                    yaw: _yaw,
                    pitch: _pitch,
                    zoom: _zoom,
                    solid: _solid && _canSolid,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            if (!busy && !empty) ...[
              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MeshViewerChip(
                        'Dots',
                        selected: !_solid,
                        onTap: () => setState(() => _solid = false),
                      ),
                      MeshViewerChip(
                        'Solid',
                        selected: _solid,
                        enabled: _canSolid,
                        onTap: _canSolid
                            ? () => setState(() => _solid = true)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 10,
                child: Text(
                  _solid && _canSolid
                      ? 'web · ${_triangles!.length ~/ 18} tris · drag/pinch'
                      : 'web · ${widget.vertexCount ?? _vertices.length}'
                          '${_canSolid ? '' : ' · no faces'} · drag/pinch',
                  style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CpuMeshPainter extends CustomPainter {
  _CpuMeshPainter({
    required this.vertices,
    required this.triangles,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.solid,
  });

  final List<List<double>> vertices;
  final Float32List? triangles;
  final double yaw;
  final double pitch;
  final double zoom;
  final bool solid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF15283F),
    );
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final scale = math.min(size.width, size.height) * 0.42 * zoom;
    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);

    double camZ(double x, double y, double z) {
      final z1 = -x * sinY + z * cosY;
      return y * sinP + z1 * cosP;
    }

    Offset project(double x, double y, double z) {
      final x1 = x * cosY + z * sinY;
      final z1 = -x * sinY + z * cosY;
      final y2 = y * cosP - z1 * sinP;
      return Offset(cx + x1 * scale, cy - y2 * scale);
    }

    if (solid && triangles != null && triangles!.length >= 18) {
      final t = triangles!;
      final n = t.length ~/ 18;
      final depth = Float32List(n);
      final order = List<int>.generate(n, (i) => i);
      for (var i = 0; i < n; i++) {
        final o = i * 18;
        depth[i] = (camZ(t[o], t[o + 1], t[o + 2]) +
                camZ(t[o + 6], t[o + 7], t[o + 8]) +
                camZ(t[o + 12], t[o + 13], t[o + 14])) /
            3;
      }
      order.sort((a, b) => depth[b].compareTo(depth[a]));

      // Impeller: drawVertices + vertex colors + srcOver often fails to fill
      // (looks like a point cloud). Use opaque Path fills — reliable on iOS.
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = false;
      for (final i in order) {
        final o = i * 18;
        final ax = t[o], ay = t[o + 1], az = t[o + 2];
        final bx = t[o + 6], by = t[o + 7], bz = t[o + 8];
        final dx = t[o + 12], dy = t[o + 13], dz = t[o + 14];
        var nx = (by - ay) * (dz - az) - (bz - az) * (dy - ay);
        var ny = (bz - az) * (dx - ax) - (bx - ax) * (dz - az);
        var nz = (bx - ax) * (dy - ay) - (by - ay) * (dx - ax);
        final nz1 = -nx * sinY + nz * cosY;
        final nCamZ = ny * sinP + nz1 * cosP;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        final facing = len < 1e-9 ? 0.5 : (nCamZ / len);
        final lum = (0.42 + 0.58 * facing.abs()).clamp(0.28, 1.0);

        // Flat shade from first corner color (web preview — not App Store path).
        final r = (t[o + 3] * lum * 255).round().clamp(0, 255);
        final g = (t[o + 4] * lum * 255).round().clamp(0, 255);
        final b = (t[o + 5] * lum * 255).round().clamp(0, 255);
        fill.color = Color.fromARGB(255, r, g, b);

        final p0 = project(ax, ay, az);
        final p1 = project(bx, by, bz);
        final p2 = project(dx, dy, dz);
        canvas.drawPath(
          Path()
            ..moveTo(p0.dx, p0.dy)
            ..lineTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..close(),
          fill,
        );
      }
    } else if (vertices.isNotEmpty) {
      final pts = Float32List(vertices.length * 2);
      for (var i = 0; i < vertices.length; i++) {
        final v = vertices[i];
        final p = project(v[0], v[1], v[2]);
        pts[i * 2] = p.dx;
        pts[i * 2 + 1] = p.dy;
      }
      canvas.drawRawPoints(
        ui.PointMode.points,
        pts,
        Paint()
          ..color = const Color(0xFFC5D9F0)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CpuMeshPainter old) =>
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.solid != solid ||
      !identical(old.vertices, vertices) ||
      !identical(old.triangles, triangles);
}

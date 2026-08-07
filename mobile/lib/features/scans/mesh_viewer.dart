/// Chairside mesh preview entry.
///
/// - **Native (App Store iPad):** [mesh_viewer_io.dart] → three_js GPU Mesh/Points
/// - **Web:** [mesh_viewer_html.dart] → CustomPaint [CpuMeshViewer]
library;

export 'mesh_viewer_cpu.dart' show CpuMeshViewer;
export 'mesh_viewer_io.dart'
    if (dart.library.html) 'mesh_viewer_html.dart'
    show MeshViewer;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/tooth_loader.dart';

/// Rotatable point-cloud preview for dental mesh scans.
///
/// Packed XYZ + a single batched [drawRawPoints] call keep drag rotation smooth.
class MeshViewer extends StatefulWidget {
  const MeshViewer({
    super.key,
    required this.vertices,
    this.loading = false,
    this.error,
    this.vertexCount,
    this.sampled,
  });

  /// Normalized XYZ points (already centered / scaled by the API).
  final List<List<double>> vertices;
  final bool loading;
  final String? error;
  final int? vertexCount;
  final int? sampled;

  @override
  State<MeshViewer> createState() => _MeshViewerState();
}

class _MeshViewerState extends State<MeshViewer> {
  /// Cap displayed points so web canvas stays interactive.
  static const int _displayCap = 8000;

  final ValueNotifier<double> _yaw = ValueNotifier(0.55);
  final ValueNotifier<double> _pitch = ValueNotifier(-0.35);

  Float32List _xyz = Float32List(0);
  Float32List _xy = Float32List(0);
  int _pointCount = 0;
  late final Listenable _camera;

  @override
  void initState() {
    super.initState();
    _camera = Listenable.merge([_yaw, _pitch]);
    _packVertices(widget.vertices);
  }

  @override
  void didUpdateWidget(covariant MeshViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.vertices, widget.vertices)) {
      _packVertices(widget.vertices);
    }
  }

  @override
  void dispose() {
    _yaw.dispose();
    _pitch.dispose();
    super.dispose();
  }

  void _packVertices(List<List<double>> vertices) {
    final total = vertices.length;
    final step = total > _displayCap ? (total / _displayCap).ceil() : 1;
    final capacity =
        step == 1 ? total : (total / step).ceil().clamp(0, _displayCap);
    final packed = Float32List(capacity * 3);
    var w = 0;
    for (var i = 0; i < total && w < capacity; i += step) {
      final v = vertices[i];
      if (v.length < 3) continue;
      packed[w * 3] = v[0].toDouble();
      packed[w * 3 + 1] = v[1].toDouble();
      packed[w * 3 + 2] = v[2].toDouble();
      w++;
    }
    _xyz = packed;
    _pointCount = w;
    _xy = Float32List(w * 2);
  }

  void _onDrag(DragUpdateDetails d) {
    _yaw.value += d.delta.dx * 0.008;
    _pitch.value = (_pitch.value + d.delta.dy * 0.008).clamp(-1.2, 1.2);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadii.border,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF15283F),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.loading)
              const Center(
                child: ToothLoadingIndicator(size: 28, compact: true, color: Colors.white70),
              )
            else if (widget.error != null)
              _EmptyState(
                icon: Icons.warning_amber_rounded,
                title: 'Could not load 3D preview',
                subtitle: widget.error!,
              )
            else if (_pointCount == 0)
              const _EmptyState(
                icon: Icons.view_in_ar_outlined,
                title: 'No mesh to display',
                subtitle: 'Upload a PLY / STL / OBJ scan to preview the 3D model',
              )
            else
              GestureDetector(
                onPanUpdate: _onDrag,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _camera,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _PointCloudPainter(
                          xyz: _xyz,
                          count: _pointCount,
                          yaw: _yaw.value,
                          pitch: _pitch.value,
                          xy: _xy,
                        ),
                        isComplex: true,
                        willChange: true,
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ),
            if (!widget.loading && _pointCount > 0)
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: IgnorePointer(
                  child: Row(
                    children: [
                      const Icon(Icons.open_with, size: 14, color: Colors.white54),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Drag to rotate',
                          style: TextStyle(color: Colors.white54, fontSize: 11.5),
                        ),
                      ),
                      Text(
                        '${widget.sampled ?? _pointCount}'
                        '${widget.vertexCount != null ? ' / ${widget.vertexCount}' : ''} pts',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white70, size: 36),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

class _PointCloudPainter extends CustomPainter {
  _PointCloudPainter({
    required this.xyz,
    required this.count,
    required this.yaw,
    required this.pitch,
    required this.xy,
  });

  final Float32List xyz;
  final int count;
  final double yaw;
  final double pitch;
  final Float32List xy;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0) return;

    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final scale = math.min(size.width, size.height) * 0.42;

    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);

    for (var i = 0; i < count; i++) {
      final x = xyz[i * 3];
      final y = xyz[i * 3 + 1];
      final z = xyz[i * 3 + 2];

      // Yaw around Y, then pitch around X.
      final x1 = x * cosY + z * sinY;
      final z1 = -x * sinY + z * cosY;
      final y2 = y * cosP - z1 * sinP;

      xy[i * 2] = cx + x1 * scale;
      xy[i * 2 + 1] = cy - y2 * scale;
    }

    final paint = Paint()
      ..color = const Color(0xFFC5D9F0)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = count > 6000 ? 1.2 : 1.5;

    canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.sublistView(xy, 0, count * 2),
      paint,
    );

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
        const Radius.circular(16),
      ),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant _PointCloudPainter oldDelegate) {
    return oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        !identical(oldDelegate.xyz, xyz) ||
        oldDelegate.count != count;
  }
}

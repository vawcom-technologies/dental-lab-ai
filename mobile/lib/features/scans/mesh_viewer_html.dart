import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'mesh_viewer_cpu.dart';

/// Web [MeshViewer] — CustomPaint only (no three_js ANGLE).
class MeshViewer extends StatelessWidget {
  const MeshViewer({
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
  Widget build(BuildContext context) {
    return CpuMeshViewer(
      bytes: bytes,
      filename: filename,
      previewVertices: previewVertices,
      loading: loading,
      error: error,
      vertexCount: vertexCount,
    );
  }
}

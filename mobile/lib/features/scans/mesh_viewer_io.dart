import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'mesh_viewer_gpu.dart';

/// Native iOS/Android [MeshViewer] — three_js GPU only (App Store path).
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
    return GpuMeshViewerHost(
      bytes: bytes,
      filename: filename,
      previewVertices: previewVertices,
      loading: loading,
      error: error,
      vertexCount: vertexCount,
    );
  }
}

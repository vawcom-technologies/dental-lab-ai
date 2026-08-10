/// Chairside mesh preview entry.
///
/// - **Native (App Store iPad):** [mesh_viewer_io.dart] → three_js GPU Mesh/Points
/// - **Web:** [mesh_viewer_html.dart] → CustomPaint [CpuMeshViewer]
///
/// Supports PLY / STL / OBJ with **Dots** and **Solid** modes.
library;

export 'mesh_viewer_cpu.dart' show CpuMeshViewer;
export 'mesh_viewer_io.dart'
    if (dart.library.html) 'mesh_viewer_html.dart'
    show MeshViewer;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'mesh_sample.dart';
import 'mesh_viewer_chrome.dart';

/// Native three_js host. Booted only after [LayoutBuilder] size is known.
///
/// Dots = [three.Points] + [three.PointsMaterial].
/// Solid = [three.Mesh] + opaque [three.MeshPhongMaterial] (indexed triangles).
/// Tab toggles only flip scene-graph membership — geometry is parsed once.
class GpuMeshViewerHost extends StatefulWidget {
  const GpuMeshViewerHost({
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
  State<GpuMeshViewerHost> createState() => _GpuMeshViewerHostState();
}

class _GpuMeshViewerHostState extends State<GpuMeshViewerHost>
    with WidgetsBindingObserver {
  three.ThreeJS? _three;
  three.OrbitControls? _controls;
  three.DirectionalLight? _keyLight;
  three.BufferGeometry? _geometry;
  three.Mesh? _mesh;
  three.Points? _points;
  bool _hasVertexColors = false;
  int _loadedTris = 0;

  bool _solid = true;
  bool _canSolid = false;
  bool _sceneReady = false;
  bool _meshLoading = false;
  String? _meshError;
  int? _loadedVerts;
  Object? _loadToken;
  Size? _viewSize;

  bool get _hasSource =>
      (widget.bytes != null && widget.bytes!.isNotEmpty) ||
      widget.previewVertices.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _applyViewSize(Size size) {
    final tj = _three;
    if (tj == null) return;
    _viewSize = size;
    tj.screenSize = size;
    if (!_sceneReady) return;
    try {
      tj.camera.aspect = size.width / math.max(size.height, 1.0);
      tj.camera.updateProjectionMatrix();
      tj.renderer?.setSize(size.width, size.height, false);
    } catch (_) {}
  }

  void _boot(Size size) {
    if (_three != null) return;
    _viewSize = size;
    try {
      _three = three.ThreeJS(
        size: size,
        settings: three.Settings(
          clearColor: 0x15283F,
          antialias: true,
          animate: true,
        ),
        onSetupComplete: () {
          if (!mounted) return;
          setState(() {});
          _loadCurrent();
        },
        setup: _setupScene,
        loadingWidget: const ColoredBox(
          color: Color(0xFF15283F),
          child: Center(
            child: ToothLoadingIndicator(
              size: 44,
              color: Colors.white70,
              loadingText: 'Loading mesh…',
            ),
          ),
        ),
      );
    } catch (e) {
      _meshError = '3D viewer failed to start: $e';
    }
  }

  Future<void> _setupScene() async {
    final tj = _three!;
    final aspect =
        (tj.height == 0) ? 1.0 : tj.width / math.max(tj.height, 1.0);
    tj.scene = three.Scene();
    tj.camera = three.PerspectiveCamera(45, aspect, 0.01, 5000);
    tj.camera.position.setValues(0, 0.6, 2.2);

    // Studio lighting — ambient fill + sky/ground + headlamp on the camera.
    tj.scene.add(three.AmbientLight(0xffffff, 0.4));
    tj.scene.add(three.HemisphereLight(0xf0f4ff, 0x2a3544, 0.65));
    _keyLight = three.DirectionalLight(0xffffff, 1.05);
    _keyLight!.position.setValues(2.5, 4.0, 3.0);
    tj.scene.add(_keyLight!);

    _controls = three.OrbitControls(tj.camera, tj.globalKey);
    _controls!.enableDamping = true;
    _controls!.dampingFactor = 0.08;
    _controls!.enablePan = true;

    tj.addAnimationEvent((dt) {
      _controls?.update();
      final light = _keyLight;
      if (light == null) return;
      // Key light rides with the camera so Solid never goes flat/black on orbit.
      final cam = tj.camera.position;
      light.position.setValues(cam.x, cam.y, cam.z);
    });
    tj.toDispose(() {
      try {
        _controls?.dispose();
      } catch (_) {}
      _controls = null;
      _keyLight = null;
      _disposeMeshObjects(disposeGeometry: true);
    });

    _sceneReady = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_sceneReady) return;
    _three?.pause = state != AppLifecycleState.resumed;
  }

  @override
  void activate() {
    super.activate();
    if (_sceneReady) _three?.pause = false;
  }

  @override
  void deactivate() {
    if (_sceneReady) _three?.pause = true;
    super.deactivate();
  }

  @override
  void didUpdateWidget(covariant GpuMeshViewerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bytesChanged = !identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.filename != widget.filename;
    final vertsChanged =
        !identical(oldWidget.previewVertices, widget.previewVertices);
    if (_sceneReady && (bytesChanged || vertsChanged)) {
      _loadCurrent();
    }
  }

  Future<void> _loadCurrent() async {
    if (!_sceneReady || _three == null) return;
    final token = Object();
    _loadToken = token;

    if (!_hasSource) {
      _disposeMeshObjects(disposeGeometry: true);
      if (mounted) {
        setState(() {
          _canSolid = false;
          _meshError = null;
          _loadedVerts = null;
          _loadedTris = 0;
          _meshLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _meshLoading = true;
        _meshError = null;
      });
    }

    try {
      three.BufferGeometry geometry;
      if (widget.bytes != null && widget.bytes!.isNotEmpty) {
        final loaded = await _loadFromBytes(
          widget.bytes!,
          widget.filename ?? 'scan.ply',
        );
        if (!identical(_loadToken, token) || !mounted) {
          loaded.dispose();
          return;
        }
        geometry = loaded;
      } else {
        geometry = _geometryFromPreview(widget.previewVertices);
      }

      final hasFaces = _geometryHasFaces(geometry);
      final idx = geometry.getIndex();
      final triCount = idx != null ? idx.count ~/ 3 : 0;
      if (hasFaces && geometry.getAttribute(three.Attribute.normal) == null) {
        geometry.computeVertexNormals();
      }

      _disposeMeshObjects(disposeGeometry: true);
      _geometry = geometry;
      _loadedTris = triCount;
      _installObjects(geometry, hasFaces: hasFaces);

      final pos = geometry.getAttribute(three.Attribute.position);
      final nVerts = pos is three.BufferAttribute ? pos.count : null;
      _frameCamera(geometry);

      if (!identical(_loadToken, token) || !mounted) return;
      setState(() {
        _canSolid = hasFaces;
        if (!hasFaces) _solid = false;
        _loadedVerts = nVerts;
        _meshLoading = false;
        _meshError = null;
      });
      _applyMode();
    } catch (e) {
      if (!identical(_loadToken, token) || !mounted) return;
      setState(() {
        _meshLoading = false;
        _meshError = e.toString().replaceFirst('Exception: ', '');
        _canSolid = false;
        _loadedVerts = null;
      });
    }
  }

  Future<three.BufferGeometry> _loadFromBytes(
    Uint8List bytes,
    String filename,
  ) async {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.stl')) {
      final mesh = await three.STLLoader().fromBytes(bytes);
      final g = mesh.geometry;
      if (g == null) throw Exception('STL has no geometry');
      mesh.material?.dispose();
      return _weldFaceSoup(g);
    }
    if (lower.endsWith('.obj')) {
      final group = await three.OBJLoader().fromBytes(bytes);
      three.BufferGeometry? found;
      group.traverse((child) {
        if (child is three.Mesh) {
          if (found == null && child.geometry != null) {
            found = child.geometry;
          }
          child.material?.dispose();
        }
      });
      if (found == null) throw Exception('OBJ has no mesh geometry');
      final g = found!;
      return g.getIndex() == null ? _weldFaceSoup(g) : g;
    }

    // Indexed PLY: segregate position / color / face index, then smooth normals.
    final parsed = parsePlyGeometry(bytes);
    if (parsed.error != null) throw Exception(parsed.error);
    if (parsed.positions.isEmpty) {
      throw Exception('PLY has no vertices');
    }
    final g = three.BufferGeometry();
    g.setAttribute(
      three.Attribute.position,
      three.Float32BufferAttribute(parsed.positions, 3),
    );
    if (parsed.colors != null && parsed.colors!.isNotEmpty) {
      g.setAttribute(
        three.Attribute.color,
        three.Float32BufferAttribute(parsed.colors!, 3),
      );
    }
    final idx = parsed.indices;
    if (idx != null && idx.isNotEmpty) {
      // List path picks Uint32 when max index > 65535 (dental arches).
      g.setIndex(idx);
      g.computeVertexNormals();
    }

    assert(
      parsed.indices == null ||
          (g.getIndex()?.count ?? 0) == parsed.indices!.length,
      'Index buffer lost after setIndex',
    );

    return g;
  }

  /// Triangle-soup → welded shared index buffer + smooth normals.
  three.BufferGeometry _weldFaceSoup(three.BufferGeometry source) {
    final posAttr = source.getAttribute(three.Attribute.position);
    if (posAttr is! three.BufferAttribute || posAttr.count < 3) {
      return source;
    }
    final raw = posAttr.array;
    final positions = raw is Float32List
        ? raw
        : Float32List.fromList(
            List<double>.generate(raw.length, (i) => (raw[i] as num).toDouble()),
          );
    final n = positions.length ~/ 3;
    final identity = Uint32List(n);
    for (var i = 0; i < n; i++) {
      identity[i] = i;
    }

    Float32List? colors;
    final colAttr = source.getAttribute(three.Attribute.color);
    if (colAttr is three.BufferAttribute) {
      final c = colAttr.array;
      colors = c is Float32List
          ? c
          : Float32List.fromList(
              List<double>.generate(c.length, (i) => (c[i] as num).toDouble()),
            );
    }

    final welded = weldSharedVertices(positions, colors, identity);
    source.dispose();
    final g = three.BufferGeometry();
    g.setAttribute(
      three.Attribute.position,
      three.Float32BufferAttribute(welded.positions, 3),
    );
    if (welded.colors != null) {
      g.setAttribute(
        three.Attribute.color,
        three.Float32BufferAttribute(welded.colors!, 3),
      );
    }
    g.setIndex(welded.indices);
    g.computeVertexNormals();
    return g;
  }

  three.BufferGeometry _geometryFromPreview(List<List<double>> verts) {
    final positions = Float32List(verts.length * 3);
    for (var i = 0; i < verts.length; i++) {
      final v = verts[i];
      positions[i * 3] = v[0];
      positions[i * 3 + 1] = v[1];
      positions[i * 3 + 2] = v[2];
    }
    final g = three.BufferGeometry();
    g.setAttribute(
      three.Attribute.position,
      three.Float32BufferAttribute(positions, 3),
    );
    return g;
  }

  bool _geometryHasFaces(three.BufferGeometry g) =>
      (g.getIndex()?.count ?? 0) >= 3;

  /// Mesh for Solid, Points only when Dots is selected — never both in scene.
  void _installObjects(
    three.BufferGeometry geometry, {
    required bool hasFaces,
  }) {
    final hasColor = geometry.getAttribute(three.Attribute.color) != null;
    _hasVertexColors = hasColor;

    if (hasFaces) {
      final mat = three.MeshPhongMaterial({
        three.MaterialProperty.color: hasColor ? 0xffffff : 0xe8ddd4,
        three.MaterialProperty.vertexColors: hasColor,
        three.MaterialProperty.side: three.DoubleSide,
        three.MaterialProperty.shininess: 30,
        three.MaterialProperty.specular: 0x444444,
        three.MaterialProperty.flatShading: false,
        three.MaterialProperty.wireframe: false,
        three.MaterialProperty.transparent: false,
        three.MaterialProperty.opacity: 1.0,
        three.MaterialProperty.depthTest: true,
        three.MaterialProperty.depthWrite: true,
      });
      _mesh = three.Mesh(geometry, mat);
    } else {
      _mesh = null;
    }
    // Points created lazily in [_applyMode] so Solid never shares the scene
    // with a Points draw call (same geometry + Points looks like a cloud).
    _points = null;
  }

  void _ensurePoints() {
    if (_points != null || _geometry == null) return;
    // Fixed screen-space dots (no perspective attenuation) so density reads
    // straight from the input: dots bunch where the scan sampled denser
    // (cavities/fissures) instead of ballooning with the model's mm scale.
    final ptsMat = three.PointsMaterial({
      three.MaterialProperty.color: _hasVertexColors ? 0xffffff : 0xc5d9f0,
      three.MaterialProperty.vertexColors: _hasVertexColors,
      three.MaterialProperty.size: 1.6,
      three.MaterialProperty.sizeAttenuation: false,
    });
    _points = three.Points(_geometry!, ptsMat);
  }

  /// Tab switch: scene-graph swap only. Geometry stays put.
  void _applyMode() {
    final scene = _three?.scene;
    if (scene == null) return;

    final useSolid = _solid && _canSolid && _mesh != null;

    if (useSolid) {
      // Solid: Mesh only — tear down Points so ANGLE cannot draw gl.POINTS.
      if (_points != null) {
        try {
          scene.remove(_points!);
        } catch (_) {}
        try {
          _points!.material?.dispose();
        } catch (_) {}
        _points = null;
      }
      if (_mesh!.parent == null) {
        scene.add(_mesh!);
      }
      _mesh!.visible = true;
      return;
    }

    // Dots: Points only.
    if (_mesh != null) {
      if (_mesh!.parent != null) {
        try {
          scene.remove(_mesh!);
        } catch (_) {}
      }
      _mesh!.visible = false;
    }
    _ensurePoints();
    if (_points != null) {
      if (_points!.parent == null) {
        scene.add(_points!);
      }
      _points!.visible = true;
    }
  }

  void _frameCamera(three.BufferGeometry geometry) {
    final tj = _three;
    final controls = _controls;
    if (tj == null || controls == null || !_sceneReady) return;

    geometry.computeBoundingBox();
    final box = geometry.boundingBox;
    if (box == null) return;

    final center = three.Vector3();
    box.getCenter(center);
    final size = three.Vector3();
    size.sub2(box.max, box.min);
    final radius = size.length * 0.5;
    if (radius < 1e-9) return;

    controls.target.setFrom(center);
    final dist = radius / math.tan((45 * math.pi / 180) * 0.5) * 1.35;
    tj.camera.position.setValues(
      center.x + dist * 0.35,
      center.y + dist * 0.45,
      center.z + dist,
    );
    tj.camera.near = math.max(0.001, dist / 200);
    tj.camera.far = dist * 40;
    tj.camera.updateProjectionMatrix();
    controls.update();

    _keyLight?.position.setValues(
      tj.camera.position.x,
      tj.camera.position.y,
      tj.camera.position.z,
    );
  }

  void _disposeMeshObjects({required bool disposeGeometry}) {
    final tj = _three;
    if (_mesh != null) {
      try {
        tj?.scene.remove(_mesh!);
      } catch (_) {}
      try {
        _mesh!.material?.dispose();
      } catch (_) {}
      _mesh = null;
    }
    if (_points != null) {
      try {
        tj?.scene.remove(_points!);
      } catch (_) {}
      try {
        _points!.material?.dispose();
      } catch (_) {}
      _points = null;
    }
    if (disposeGeometry) {
      try {
        _geometry?.dispose();
      } catch (_) {}
      _geometry = null;
    }
  }

  void _safeDisposeThree() {
    final tj = _three;
    _three = null;
    if (tj == null) return;
    if (!_sceneReady) {
      try {
        tj.pause = true;
      } catch (_) {}
      return;
    }
    try {
      tj.dispose();
    } catch (_) {}
    _sceneReady = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeMeshObjects(disposeGeometry: true);
    _safeDisposeThree();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _meshError = AppSnackBars.drain(context, _meshError);
    final empty = !_hasSource && !widget.loading;

    return ClipRRect(
      borderRadius: AppRadii.border,
      clipBehavior: Clip.hardEdge,
      child: ColoredBox(
        color: const Color(0xFF15283F),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final bounded = w.isFinite && h.isFinite && w > 2 && h > 2;
            if (bounded) {
              final next = Size(w, h);
              if (_three == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _three != null) return;
                  _boot(next);
                  setState(() {});
                });
              } else if (_viewSize == null ||
                  (_viewSize!.width - w).abs() > 2 ||
                  (_viewSize!.height - h).abs() > 2) {
                _applyViewSize(next);
              }
            }

            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                if (_three != null)
                  Positioned.fill(
                    child: FittedBox(
                      fit: BoxFit.fill,
                      clipBehavior: Clip.hardEdge,
                      child: _three!.build(),
                    ),
                  ),
                if (widget.loading || _meshLoading)
                  const ColoredBox(
                    color: Color(0x8815283F),
                    child: Center(
                      child: ToothLoadingIndicator(
                        size: 44,
                        color: Colors.white70,
                        loadingText: 'Loading mesh…',
                      ),
                    ),
                  )
                else if (empty)
                  const ColoredBox(
                    color: Color(0xFF15283F),
                    child: MeshViewerHint(
                      'Upload a PLY / STL / OBJ to preview',
                    ),
                  ),
                if (!widget.loading && !_meshLoading && !empty) ...[
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
                            onTap: () => setState(() {
                              _solid = false;
                              _applyMode();
                            }),
                          ),
                          MeshViewerChip(
                            'Solid',
                            selected: _solid,
                            enabled: _canSolid,
                            onTap: _canSolid
                                ? () => setState(() {
                                      _solid = true;
                                      _applyMode();
                                    })
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
                      _hudLabel,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  String get _hudLabel {
    final n = widget.vertexCount ?? _loadedVerts;
    if (_solid && _canSolid) {
      // Must NOT look like CpuMeshViewer ("web · N tris · drag/pinch").
      return 'ipad-gpu · ${n ?? '—'} verts · $_loadedTris tris';
    }
    if (!_canSolid && _hasSource) {
      return 'ipad-gpu · ${n ?? '—'} pts · no faces';
    }
    return 'ipad-gpu · ${n ?? '—'} pts';
  }
}

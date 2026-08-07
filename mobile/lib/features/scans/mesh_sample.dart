import 'dart:math' as math;
import 'dart:typed_data';

/// Weld geometrically coincident vertices so faces share an index buffer.
/// Required for smooth [computeVertexNormals] on triangle *soups* (STL-style
/// duplicated corners). Already-indexed dental PLYs must NOT be welded —
/// [Object.hash] collisions on large arches corrupt topology.
({
  Float32List positions,
  Float32List? colors,
  Uint32List indices,
}) weldSharedVertices(
  Float32List positions,
  Float32List? colors,
  Uint32List indices,
) {
  final vertCount = positions.length ~/ 3;
  if (vertCount == 0 || indices.isEmpty) {
    return (positions: positions, colors: colors, indices: indices);
  }

  var minX = positions[0], maxX = positions[0];
  var minY = positions[1], maxY = positions[1];
  var minZ = positions[2], maxZ = positions[2];
  for (var i = 1; i < vertCount; i++) {
    final o = i * 3;
    final x = positions[o], y = positions[o + 1], z = positions[o + 2];
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
    if (z < minZ) minZ = z;
    if (z > maxZ) maxZ = z;
  }
  final dx = maxX - minX, dy = maxY - minY, dz = maxZ - minZ;
  final diag = math.sqrt(dx * dx + dy * dy + dz * dz);
  // Relative grid — weld scanner float noise without collapsing real edges.
  final invEps = 1.0 / math.max(diag * 1e-6, 1e-9);

  // String keys — never Object.hash (collisions merge unrelated verts).
  final keyToNew = <String, int>{};
  final outPos = <double>[];
  final outCol = colors != null ? <double>[] : null;
  final outIdx = Uint32List(indices.length);

  for (var i = 0; i < indices.length; i++) {
    final vi = indices[i];
    if (vi < 0 || vi >= vertCount) {
      outIdx[i] = 0;
      continue;
    }
    final o = vi * 3;
    final x = positions[o];
    final y = positions[o + 1];
    final z = positions[o + 2];
    final key =
        '${(x * invEps).round()}_${(y * invEps).round()}_${(z * invEps).round()}';
    var ni = keyToNew[key];
    if (ni == null) {
      ni = outPos.length ~/ 3;
      keyToNew[key] = ni;
      outPos.add(x);
      outPos.add(y);
      outPos.add(z);
      if (outCol != null && colors != null) {
        outCol.add(colors[o]);
        outCol.add(colors[o + 1]);
        outCol.add(colors[o + 2]);
      }
    }
    outIdx[i] = ni;
  }

  return (
    positions: Float32List.fromList(outPos),
    colors: outCol != null ? Float32List.fromList(outCol) : null,
    indices: outIdx,
  );
}

/// True when [indices] already share vertices (dental PLY). False for identity
/// triangle soups where every corner is its own vertex (needs weld).
bool meshAlreadyIndexed(int vertCount, Uint32List indices) =>
    indices.length > vertCount;

/// Decide soup-vs-shared, then weld only when corners are duplicated.
({
  Float32List positions,
  Float32List? colors,
  Uint32List? indices,
  int vertexCount,
  String? error,
}) _finishPlyMesh({
  required Float32List positions,
  Float32List? colors,
  Uint32List? indices,
  required int vertexCount,
  String? error,
}) {
  if (error != null || indices == null || indices.length < 3) {
    return (
      positions: positions,
      colors: colors,
      indices: indices,
      vertexCount: vertexCount,
      error: error,
    );
  }
  // Shared-index dental mesh (indices >> verts): keep topology intact.
  if (meshAlreadyIndexed(vertexCount, indices)) {
    return (
      positions: positions,
      colors: colors,
      indices: indices,
      vertexCount: vertexCount,
      error: null,
    );
  }
  // Triangle soup / identity indices: weld coincident corners for smooth normals.
  final welded = weldSharedVertices(positions, colors, indices);
  return (
    positions: welded.positions,
    colors: welded.colors,
    indices: welded.indices,
    vertexCount: welded.positions.length ~/ 3,
    error: null,
  );
}

class _PlyFaceListProp {
  const _PlyFaceListProp(this.countType, this.itemType, this.name);
  final String countType;
  final String itemType;
  final String name;
}

class _PlyElement {
  _PlyElement(this.name, this.count);
  final String name;
  final int count;
  final scalars = <({String type, String name})>[];
  _PlyFaceListProp? list;
}

/// Full-resolution PLY for the native GPU viewer.
/// Handles: ascii/binary LE|BE, CRLF, RGB (uchar/float), normals/extra props,
/// face-before-vertex element order, n-gons, face trailing scalars, point-only
/// clouds, shared-index meshes, and STL-style triangle soups.
({
  Float32List positions,
  Float32List? colors,
  Uint32List? indices,
  int vertexCount,
  String? error,
}) parsePlyGeometry(Uint8List data) {
  final headerEnd = _plyHeaderEnd(data);
  if (headerEnd < 0) {
    return (
      positions: Float32List(0),
      colors: null,
      indices: null,
      vertexCount: 0,
      error: 'PLY header missing',
    );
  }
  final headerRaw = String.fromCharCodes(data.sublist(0, headerEnd));
  final header = headerRaw
      .toLowerCase()
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final isBinary = header.contains('format binary');
  final little = !header.contains('binary_big_endian');

  final elements = <_PlyElement>[];
  _PlyElement? current;
  for (final line in header.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) continue;
    if (parts[0] == 'element' && parts.length >= 3) {
      current = _PlyElement(parts[1], int.tryParse(parts[2]) ?? 0);
      elements.add(current);
      continue;
    }
    if (current == null || parts[0] != 'property' || parts.length < 3) continue;
    if (parts[1] == 'list' && parts.length >= 5) {
      current.list = _PlyFaceListProp(parts[2], parts[3], parts.last);
    } else if (parts[1] != 'list') {
      current.scalars.add((type: parts[1], name: parts.last));
    }
  }

  _PlyElement? vertexEl;
  for (final e in elements) {
    if (e.name == 'vertex') {
      vertexEl = e;
      break;
    }
  }
  if (vertexEl == null || vertexEl.count <= 0) {
    return (
      positions: Float32List(0),
      colors: null,
      indices: null,
      vertexCount: 0,
      error: 'PLY has no vertices',
    );
  }

  if (!isBinary) {
    return _parsePlyGeometryAscii(data, elements);
  }
  return _parsePlyGeometryBinary(
    data.sublist(headerEnd),
    elements,
    little ? Endian.little : Endian.big,
  );
}

({
  Float32List positions,
  Float32List? colors,
  Uint32List? indices,
  int vertexCount,
  String? error,
}) _parsePlyGeometryBinary(
  Uint8List body,
  List<_PlyElement> elements,
  Endian endian,
) {
  final vertexEl = elements.firstWhere((e) => e.name == 'vertex');
  final vProps = vertexEl.scalars;
  final vertexCount = vertexEl.count;

  var stride = 0;
  final xyzOff = <String, int?>{'x': null, 'y': null, 'z': null};
  final xyzType = <String, String>{'x': 'float', 'y': 'float', 'z': 'float'};
  final rgbOff = <String, int?>{'red': null, 'green': null, 'blue': null};
  final rgbType = <String, String>{
    'red': 'uchar',
    'green': 'uchar',
    'blue': 'uchar',
  };
  var layoutOk = true;
  for (final p in vProps) {
    final size = _plyPropSize(p.type);
    if (size == null) {
      layoutOk = false;
      break;
    }
    if (xyzOff.containsKey(p.name) && xyzOff[p.name] == null) {
      xyzOff[p.name] = stride;
      xyzType[p.name] = p.type;
    }
    final rgb = _plyRgbKey(p.name);
    if (rgb != null && rgbOff[rgb] == null) {
      rgbOff[rgb] = stride;
      rgbType[rgb] = p.type;
    }
    stride += size;
  }
  if (!layoutOk ||
      stride <= 0 ||
      xyzOff['x'] == null ||
      xyzOff['y'] == null ||
      xyzOff['z'] == null) {
    stride = 12;
    xyzOff['x'] = 0;
    xyzOff['y'] = 4;
    xyzOff['z'] = 8;
    xyzType['x'] = 'float';
    xyzType['y'] = 'float';
    xyzType['z'] = 'float';
  }

  final hasRgb = rgbOff['red'] != null &&
      rgbOff['green'] != null &&
      rgbOff['blue'] != null;
  final bd = ByteData.sublistView(body);
  final ox = xyzOff['x']!, oy = xyzOff['y']!, oz = xyzOff['z']!;

  double rgb01(int base, String channel) {
    final t = rgbType[channel]!;
    final v = _plyRead(bd, base + rgbOff[channel]!, t, endian);
    if (t == 'float' || t == 'float32' || t == 'double' || t == 'float64') {
      return v.clamp(0.0, 1.0);
    }
    return (v / 255.0).clamp(0.0, 1.0);
  }

  Float32List? positions;
  Float32List? colors;
  final idx = <int>[];
  var cursor = 0;
  var knownVerts = 0;

  void readVertices(_PlyElement el) {
    final need = el.count * stride;
    if (cursor + need > body.length) {
      throw StateError('Truncated binary PLY vertices');
    }
    positions = Float32List(el.count * 3);
    colors = hasRgb ? Float32List(el.count * 3) : null;
    for (var i = 0; i < el.count; i++) {
      final base = cursor + i * stride;
      final x = _plyRead(bd, base + ox, xyzType['x']!, endian);
      final y = _plyRead(bd, base + oy, xyzType['y']!, endian);
      final z = _plyRead(bd, base + oz, xyzType['z']!, endian);
      final o = i * 3;
      if (x.isFinite && y.isFinite && z.isFinite) {
        positions![o] = x;
        positions![o + 1] = y;
        positions![o + 2] = z;
      }
      if (colors != null) {
        colors![o] = rgb01(base, 'red');
        colors![o + 1] = rgb01(base, 'green');
        colors![o + 2] = rgb01(base, 'blue');
      }
    }
    cursor += need;
    knownVerts = el.count;
  }

  void readFaces(_PlyElement el) {
    final list = el.list;
    final countType = list?.countType ?? 'uchar';
    final indexType = list?.itemType ?? 'int';
    final countSize = _plyPropSize(countType) ?? 1;
    final indexSize = _plyPropSize(indexType) ?? 4;
    var trailing = 0;
    for (final s in el.scalars) {
      trailing += _plyPropSize(s.type) ?? 0;
    }
    final vertLimit = knownVerts > 0 ? knownVerts : vertexCount;
    for (var fi = 0; fi < el.count; fi++) {
      if (cursor + countSize > body.length) break;
      final nIdx = _plyRead(bd, cursor, countType, endian).round();
      cursor += countSize;
      if (nIdx < 0 || nIdx > 16) {
        break;
      }
      if (nIdx < 3) {
        if (cursor + nIdx * indexSize + trailing > body.length) break;
        cursor += nIdx * indexSize + trailing;
        continue;
      }
      if (cursor + nIdx * indexSize + trailing > body.length) break;
      final face = <int>[
        for (var k = 0; k < nIdx; k++)
          _plyRead(bd, cursor + k * indexSize, indexType, endian).round(),
      ];
      cursor += nIdx * indexSize + trailing;
      for (var t = 2; t < face.length; t++) {
        final a = face[0], b = face[t - 1], c = face[t];
        if (a < 0 ||
            b < 0 ||
            c < 0 ||
            a >= vertLimit ||
            b >= vertLimit ||
            c >= vertLimit) {
          continue;
        }
        idx.add(a);
        idx.add(b);
        idx.add(c);
      }
    }
  }

  void skipElement(_PlyElement el) {
    // Best-effort skip for unknown fixed-stride elements (e.g. edge).
    var row = 0;
    for (final s in el.scalars) {
      row += _plyPropSize(s.type) ?? 0;
    }
    if (el.list != null) {
      // Variable — cannot safely skip; abort remaining.
      cursor = body.length;
      return;
    }
    cursor += el.count * row;
  }

  try {
    for (final el in elements) {
      if (el.name == 'vertex') {
        readVertices(el);
      } else if (el.name == 'face') {
        readFaces(el);
      } else {
        skipElement(el);
      }
    }
  } catch (e) {
    return (
      positions: Float32List(0),
      colors: null,
      indices: null,
      vertexCount: vertexCount,
      error: e.toString(),
    );
  }

  if (positions == null || positions!.isEmpty) {
    return (
      positions: Float32List(0),
      colors: null,
      indices: null,
      vertexCount: vertexCount,
      error: 'No valid PLY vertices',
    );
  }

  return _finishPlyMesh(
    positions: positions!,
    colors: colors,
    indices: idx.isEmpty ? null : Uint32List.fromList(idx),
    vertexCount: knownVerts,
  );
}

({
  Float32List positions,
  Float32List? colors,
  Uint32List? indices,
  int vertexCount,
  String? error,
}) _parsePlyGeometryAscii(
  Uint8List data,
  List<_PlyElement> elements,
) {
  final text = String.fromCharCodes(data)
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final lines = text.split('\n');
  var lineIdx = 0;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() == 'end_header') {
      lineIdx = i + 1;
      break;
    }
  }

  final vertexEl = elements.firstWhere((e) => e.name == 'vertex');
  final vProps = vertexEl.scalars;
  var xi = 0, yi = 1, zi = 2;
  int? ri, gi, bi;
  for (var i = 0; i < vProps.length; i++) {
    final n = vProps[i].name;
    if (n == 'x' || n == 'px' || n == 'posx') xi = i;
    if (n == 'y' || n == 'py' || n == 'posy') yi = i;
    if (n == 'z' || n == 'pz' || n == 'posz') zi = i;
    final rgb = _plyRgbKey(n);
    if (rgb == 'red') ri = i;
    if (rgb == 'green') gi = i;
    if (rgb == 'blue') bi = i;
  }
  final hasColor = ri != null && gi != null && bi != null;

  final positions = <double>[];
  final colors = <double>[];
  final indices = <int>[];
  final pendingFaces = <List<int>>[];
  var filled = 0;

  List<String> nextNonEmpty() {
    while (lineIdx < lines.length) {
      final clean = lines[lineIdx++].trim();
      if (clean.isEmpty) continue;
      return clean.split(RegExp(r'\s+'));
    }
    return const [];
  }

  void readVertices(int count) {
    for (var i = 0; i < count; i++) {
      final parts = nextNonEmpty();
      if (parts.length <= zi) continue;
      final x = double.tryParse(parts[xi]);
      final y = double.tryParse(parts[yi]);
      final z = double.tryParse(parts[zi]);
      if (x == null ||
          y == null ||
          z == null ||
          !x.isFinite ||
          !y.isFinite ||
          !z.isFinite) {
        continue;
      }
      positions.add(x);
      positions.add(y);
      positions.add(z);
      if (hasColor) {
        final rIdx = ri!;
        final gIdx = gi!;
        final bIdx = bi!;
        if (parts.length > bIdx &&
            parts.length > rIdx &&
            parts.length > gIdx) {
          double chan(int idx, String type) {
            final v = double.tryParse(parts[idx]) ?? 0;
            if (type == 'float' ||
                type == 'float32' ||
                type == 'double' ||
                type == 'float64') {
              return v.clamp(0.0, 1.0);
            }
            return (v / 255.0).clamp(0.0, 1.0);
          }

          colors.add(chan(rIdx, vProps[rIdx].type));
          colors.add(chan(gIdx, vProps[gIdx].type));
          colors.add(chan(bIdx, vProps[bIdx].type));
        }
      }
      filled++;
    }
  }

  void readFaces(int count) {
    for (var i = 0; i < count; i++) {
      final parts = nextNonEmpty();
      if (parts.isEmpty) continue;
      final n = int.tryParse(parts[0]) ?? 0;
      if (n < 3 || parts.length < n + 1) continue;
      final face = <int>[
        for (var k = 1; k <= n; k++) int.tryParse(parts[k]) ?? -1,
      ];
      if (filled == 0) {
        pendingFaces.add(face);
      } else {
        for (var t = 2; t < face.length; t++) {
          final a = face[0], b = face[t - 1], c = face[t];
          if (a < 0 ||
              b < 0 ||
              c < 0 ||
              a >= filled ||
              b >= filled ||
              c >= filled) {
            continue;
          }
          indices.add(a);
          indices.add(b);
          indices.add(c);
        }
      }
    }
  }

  for (final el in elements) {
    if (el.name == 'vertex') {
      readVertices(el.count);
      // Flush faces that arrived before vertices.
      for (final face in pendingFaces) {
        for (var t = 2; t < face.length; t++) {
          final a = face[0], b = face[t - 1], c = face[t];
          if (a < 0 ||
              b < 0 ||
              c < 0 ||
              a >= filled ||
              b >= filled ||
              c >= filled) {
            continue;
          }
          indices.add(a);
          indices.add(b);
          indices.add(c);
        }
      }
      pendingFaces.clear();
    } else if (el.name == 'face') {
      readFaces(el.count);
    } else {
      for (var i = 0; i < el.count; i++) {
        nextNonEmpty();
      }
    }
  }

  if (filled == 0) {
    return (
      positions: Float32List(0),
      colors: null,
      indices: null,
      vertexCount: vertexEl.count,
      error: 'No valid PLY vertices',
    );
  }

  return _finishPlyMesh(
    positions: Float32List.fromList(positions),
    colors: colors.isEmpty ? null : Float32List.fromList(colors),
    indices: indices.isEmpty ? null : Uint32List.fromList(indices),
    vertexCount: filled,
  );
}

/// Downsample PLY / STL / OBJ into a point cloud + optional solid triangles.
/// Chairside preview only — server validation still owns quality scores.
({
  List<List<double>> vertices,
  Float32List? triangles,
  int vertexCount,
  int sampled,
  String? error,
}) sampleMeshBytes(Uint8List data, String filename, {int maxPoints = 8000}) {
  maxPoints = maxPoints.clamp(500, 20000);
  const maxTris = 60000;
  final kind = _detect(data, filename);
  final parsed = switch (kind) {
    'stl' => _stl(data, maxPoints, maxTris),
    'obj' => _obj(data, maxPoints, maxTris),
    'ply' => _ply(data, maxPoints, maxTris),
    _ => (
        verts: <List<double>>[],
        tris: <List<double>>[],
        total: 0,
        error: 'Unsupported mesh format',
      ),
  };
  final verts = parsed.verts;
  if (verts.isEmpty) {
    return (
      vertices: const [],
      triangles: null,
      vertexCount: parsed.total,
      sampled: 0,
      error: parsed.error ?? 'No valid vertices found',
    );
  }

  // Fit points + triangle corners in one frame so modes share scale.
  var cx = 0.0, cy = 0.0, cz = 0.0;
  var n = 0;
  void acc(List<double> v) {
    cx += v[0];
    cy += v[1];
    cz += v[2];
    n++;
  }

  for (final v in verts) {
    acc(v);
  }
  for (final v in parsed.tris) {
    acc(v);
  }
  if (n == 0) {
    return (
      vertices: const [],
      triangles: null,
      vertexCount: parsed.total,
      sampled: 0,
      error: 'No valid vertices found',
    );
  }
  cx /= n;
  cy /= n;
  cz /= n;

  var span = 0.0;
  void spanOf(List<double> v) {
    final dx = v[0] - cx, dy = v[1] - cy, dz = v[2] - cz;
    final r = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (r > span) span = r;
  }

  for (final v in verts) {
    spanOf(v);
  }
  for (final v in parsed.tris) {
    spanOf(v);
  }
  if (span < 1e-12) span = 1.0;

  // Solid buffer: xyzrgb per corner (18 floats / triangle).
  List<double> normXyz(List<double> v) =>
      [(v[0] - cx) / span, (v[1] - cy) / span, (v[2] - cz) / span];

  final out = <List<double>>[for (final v in verts) normXyz(v)];
  Float32List? triOut;
  if (parsed.tris.length >= 3) {
    final t = Float32List(parsed.tris.length * 6);
    var w = 0;
    for (final v in parsed.tris) {
      final nrm = normXyz(v);
      t[w++] = nrm[0];
      t[w++] = nrm[1];
      t[w++] = nrm[2];
      if (v.length >= 6) {
        t[w++] = v[3];
        t[w++] = v[4];
        t[w++] = v[5];
      } else {
        t[w++] = 0.88;
        t[w++] = 0.84;
        t[w++] = 0.80;
      }
    }
    triOut = t;
  }

  return (
    vertices: out,
    triangles: triOut,
    vertexCount: parsed.total,
    sampled: out.length,
    error: null,
  );
}

String _detect(Uint8List data, String filename) {
  final name = filename.toLowerCase();
  if (name.endsWith('.ply')) return 'ply';
  if (name.endsWith('.stl')) return 'stl';
  if (name.endsWith('.obj')) return 'obj';

  final head = String.fromCharCodes(data.take(math.min(data.length, 256)));
  final lower = head.trimLeft().toLowerCase();
  if (lower.startsWith('ply')) return 'ply';
  if (lower.startsWith('solid')) return 'stl';
  if (lower.startsWith('v ') || lower.contains('\nv ')) return 'obj';
  if (data.length >= 84) {
    final tri = ByteData.sublistView(data).getUint32(80, Endian.little);
    final expected = 84 + tri * 50;
    if (tri > 0 && (expected - data.length).abs() <= 2) return 'stl';
  }
  return 'unknown';
}

typedef _Parsed = ({
  List<List<double>> verts,
  List<List<double>> tris,
  int total,
  String? error,
});

_Parsed _stl(Uint8List data, int maxPoints, int maxTris) {
  final head = String.fromCharCodes(data.take(math.min(data.length, 80)))
      .trimLeft()
      .toLowerCase();
  final sniff = String.fromCharCodes(data.take(math.min(data.length, 4096)));
  if (head.startsWith('solid') && sniff.contains('facet')) {
    return _stlAscii(data, maxPoints, maxTris);
  }
  return _stlBinary(data, maxPoints, maxTris);
}

_Parsed _stlBinary(Uint8List data, int maxPoints, int maxTris) {
  if (data.length < 84) {
    return (verts: const [], tris: const [], total: 0, error: 'Truncated STL');
  }
  final bd = ByteData.sublistView(data);
  final triCount = bd.getUint32(80, Endian.little);
  final need = 84 + triCount * 50;
  if (triCount <= 0 || data.length < need - 2) {
    return (
      verts: const [],
      tris: const [],
      total: 0,
      error: 'Invalid binary STL',
    );
  }
  final total = triCount * 3;
  final stepPts = total > maxPoints ? math.max(1, total ~/ maxPoints) : 1;
  final stepTri = triCount > maxTris ? math.max(1, triCount ~/ maxTris) : 1;
  final verts = <List<double>>[];
  final tris = <List<double>>[];
  var ptBucket = 0;
  for (var i = 0; i < triCount; i++) {
    final off = 84 + i * 50 + 12;
    final a = [
      bd.getFloat32(off, Endian.little),
      bd.getFloat32(off + 4, Endian.little),
      bd.getFloat32(off + 8, Endian.little),
    ];
    final b = [
      bd.getFloat32(off + 12, Endian.little),
      bd.getFloat32(off + 16, Endian.little),
      bd.getFloat32(off + 20, Endian.little),
    ];
    final c = [
      bd.getFloat32(off + 24, Endian.little),
      bd.getFloat32(off + 28, Endian.little),
      bd.getFloat32(off + 32, Endian.little),
    ];
    if (i % stepTri == 0 && tris.length < maxTris * 3) {
      tris.addAll([a, b, c]);
    }
    for (final v in [a, b, c]) {
      if (ptBucket % stepPts == 0 && verts.length < maxPoints) verts.add(v);
      ptBucket++;
    }
  }
  return (verts: verts, tris: tris, total: total, error: null);
}

_Parsed _stlAscii(Uint8List data, int maxPoints, int maxTris) {
  final text = String.fromCharCodes(data);
  final corner = <List<double>>[];
  for (final line in text.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 4 || parts[0].toLowerCase() != 'vertex') continue;
    final x = double.tryParse(parts[1]);
    final y = double.tryParse(parts[2]);
    final z = double.tryParse(parts[3]);
    if (x != null && y != null && z != null) corner.add([x, y, z]);
  }
  final tris = <List<double>>[];
  final triCount = corner.length ~/ 3;
  final stepTri = triCount > maxTris ? math.max(1, triCount ~/ maxTris) : 1;
  for (var i = 0; i < triCount; i += stepTri) {
    final o = i * 3;
    tris.addAll([corner[o], corner[o + 1], corner[o + 2]]);
    if (tris.length >= maxTris * 3) break;
  }
  return (
    verts: _thin(corner, maxPoints),
    tris: tris,
    total: corner.length,
    error: null,
  );
}

_Parsed _obj(Uint8List data, int maxPoints, int maxTris) {
  // Dental OBJ exports are often CRLF; stray \r breaks tryParse on the last token.
  var text = String.fromCharCodes(data);
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xfeff) {
    text = text.substring(1);
  }
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  final all = <List<double>>[];
  final faces = <List<int>>[];
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    if (line.startsWith('v ')) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;
      final x = double.tryParse(parts[1]);
      final y = double.tryParse(parts[2]);
      final z = double.tryParse(parts[3]);
      if (x != null && y != null && z != null) all.add([x, y, z]);
      continue;
    }
    if (!line.startsWith('f ')) continue;

    final parts = line.split(RegExp(r'\s+')).skip(1);
    final idx = <int>[];
    for (final p in parts) {
      if (p.isEmpty) continue;
      // f v / f v/vt / f v/vt/vn / f v//vn
      final raw = p.split('/')[0];
      final i = int.tryParse(raw);
      if (i == null) continue;
      // OBJ is 1-based; negative = relative to current vertex count
      final resolved = i > 0 ? i - 1 : all.length + i;
      idx.add(resolved);
    }
    // Fan triangulate quads/ngons
    for (var i = 2; i < idx.length; i++) {
      faces.add([idx[0], idx[i - 1], idx[i]]);
    }
  }

  if (all.isEmpty) {
    return (
      verts: const [],
      tris: const [],
      total: 0,
      error: 'OBJ has no vertices',
    );
  }

  final tris = <List<double>>[];
  final step = faces.length > maxTris ? math.max(1, faces.length ~/ maxTris) : 1;
  for (var i = 0; i < faces.length && tris.length < maxTris * 3; i += step) {
    final f = faces[i];
    if (f[0] < 0 ||
        f[1] < 0 ||
        f[2] < 0 ||
        f[0] >= all.length ||
        f[1] >= all.length ||
        f[2] >= all.length) {
      continue;
    }
    tris.addAll([all[f[0]], all[f[1]], all[f[2]]]);
  }
  return (
    verts: _thin(all, maxPoints),
    tris: tris,
    total: all.length,
    error: null,
  );
}

_Parsed _ply(Uint8List data, int maxPoints, int maxTris) {
  final headerEnd = _plyHeaderEnd(data);
  if (headerEnd < 0) {
    return (
      verts: const [],
      tris: const [],
      total: 0,
      error: 'PLY header missing',
    );
  }
  final headerRaw = String.fromCharCodes(data.sublist(0, headerEnd));
  // Dental exports often use CRLF — strip before tokenizing.
  final header = headerRaw
      .toLowerCase()
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final isBinary = header.contains('format binary');
  final little = !header.contains('binary_big_endian');

  var vertexCount = 0;
  var faceCount = 0;
  final vProps = <({String type, String name})>[];
  var faceIndexType = 'int';
  var faceCountType = 'uchar';
  var inVertex = false;
  var inFace = false;
  for (final line in header.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) continue;
    if (parts[0] == 'element') {
      inVertex = parts.length >= 3 && parts[1] == 'vertex';
      inFace = parts.length >= 3 && parts[1] == 'face';
      if (inVertex) vertexCount = int.tryParse(parts[2]) ?? 0;
      if (inFace) faceCount = int.tryParse(parts[2]) ?? 0;
      continue;
    }
    if (inVertex && parts[0] == 'property' && parts.length >= 3) {
      if (parts[1] == 'list') continue;
      vProps.add((type: parts[1], name: parts.last));
    }
    if (inFace &&
        parts[0] == 'property' &&
        parts.length >= 5 &&
        parts[1] == 'list') {
      faceCountType = parts[2];
      faceIndexType = parts[3];
    }
  }
  if (vertexCount <= 0) {
    return (
      verts: const [],
      tris: const [],
      total: 0,
      error: 'PLY has no vertices',
    );
  }

  if (!isBinary) {
    return _plyAscii(data, headerRaw, vertexCount, faceCount, maxPoints, maxTris);
  }

  var stride = 0;
  final xyzOff = <String, int?>{'x': null, 'y': null, 'z': null};
  final xyzType = <String, String>{'x': 'float', 'y': 'float', 'z': 'float'};
  var layoutOk = true;
  for (final p in vProps) {
    final size = _plyPropSize(p.type);
    if (size == null) {
      layoutOk = false;
      break;
    }
    if (xyzOff.containsKey(p.name) && xyzOff[p.name] == null) {
      xyzOff[p.name] = stride;
      xyzType[p.name] = p.type;
    }
    stride += size;
  }
  if (!layoutOk ||
      stride <= 0 ||
      xyzOff['x'] == null ||
      xyzOff['y'] == null ||
      xyzOff['z'] == null) {
    stride = 12;
    xyzOff['x'] = 0;
    xyzOff['y'] = 4;
    xyzOff['z'] = 8;
    xyzType['x'] = 'float';
    xyzType['y'] = 'float';
    xyzType['z'] = 'float';
  }

  final body = data.sublist(headerEnd);
  if (body.length < vertexCount * stride) {
    return (
      verts: const [],
      tris: const [],
      total: vertexCount,
      error: 'Truncated binary PLY',
    );
  }

  final endian = little ? Endian.little : Endian.big;
  final bd = ByteData.sublistView(body);
  final ox = xyzOff['x']!, oy = xyzOff['y']!, oz = xyzOff['z']!;

  // Keep full verts when faces exist so indices stay valid.
  final needFaces = faceCount > 0;
  // Dental PLYs often carry gum/tooth vertex colors.
  final rgbOff = <String, int?>{'red': null, 'green': null, 'blue': null};
  final rgbType = <String, String>{
    'red': 'uchar',
    'green': 'uchar',
    'blue': 'uchar',
  };
  var walk = 0;
  for (final p in vProps) {
    final size = _plyPropSize(p.type);
    if (size == null) break;
    final key = _plyRgbKey(p.name);
    if (key != null && rgbOff[key] == null) {
      rgbOff[key] = walk;
      rgbType[key] = p.type;
    }
    walk += size;
  }
  final hasRgb = rgbOff['red'] != null &&
      rgbOff['green'] != null &&
      rgbOff['blue'] != null;

  double rgb01(int base, String channel) {
    final t = rgbType[channel]!;
    final v = _plyRead(bd, base + rgbOff[channel]!, t, endian);
    if (t == 'float' || t == 'float32' || t == 'double' || t == 'float64') {
      return v.clamp(0.0, 1.0);
    }
    return (v / 255.0).clamp(0.0, 1.0);
  }

  final all = <List<double>>[];
  final step =
      (!needFaces && vertexCount > maxPoints)
          ? math.max(1, vertexCount ~/ maxPoints)
          : 1;
  for (var i = 0; i < vertexCount; i += step) {
    final base = i * stride;
    final x = _plyRead(bd, base + ox, xyzType['x']!, endian);
    final y = _plyRead(bd, base + oy, xyzType['y']!, endian);
    final z = _plyRead(bd, base + oz, xyzType['z']!, endian);
    if (x.isFinite && y.isFinite && z.isFinite) {
      if (hasRgb) {
        all.add([x, y, z, rgb01(base, 'red'), rgb01(base, 'green'), rgb01(base, 'blue')]);
      } else {
        all.add([x, y, z]);
      }
    } else if (needFaces) {
      all.add(hasRgb ? [0.0, 0.0, 0.0, 0.8, 0.8, 0.8] : [0.0, 0.0, 0.0]);
    }
  }

  final tris = <List<double>>[];
  if (needFaces && step == 1) {
    var cursor = vertexCount * stride;
    final stepFace =
        faceCount > maxTris ? math.max(1, faceCount ~/ maxTris) : 1;
    final countSize = _plyPropSize(faceCountType) ?? 1;
    final indexSize = _plyPropSize(faceIndexType) ?? 4;
    for (var fi = 0; fi < faceCount; fi++) {
      if (cursor + countSize > body.length) break;
      final nIdx = _plyRead(bd, cursor, faceCountType, endian).round();
      cursor += countSize;
      // Skip corrupt / non-triangle polygons without aborting the whole file.
      if (nIdx < 3 || nIdx > 16) {
        if (nIdx > 0 && cursor + nIdx * indexSize <= body.length) {
          cursor += nIdx * indexSize;
          continue;
        }
        break;
      }
      if (cursor + nIdx * indexSize > body.length) break;
      final idx = <int>[
        for (var k = 0; k < nIdx; k++)
          _plyRead(bd, cursor + k * indexSize, faceIndexType, endian).round(),
      ];
      cursor += nIdx * indexSize;
      if (fi % stepFace != 0) continue;
      for (var t = 2; t < idx.length && tris.length < maxTris * 3; t++) {
        final a = idx[0], b = idx[t - 1], c = idx[t];
        if (a < 0 ||
            b < 0 ||
            c < 0 ||
            a >= all.length ||
            b >= all.length ||
            c >= all.length) {
          continue;
        }
        tris.addAll([all[a], all[b], all[c]]);
      }
    }
  }

  if (all.isEmpty) {
    return (
      verts: const [],
      tris: const [],
      total: vertexCount,
      error: 'No valid PLY vertices',
    );
  }
  return (
    verts: _thin(all, maxPoints),
    tris: tris,
    total: vertexCount,
    error: null,
  );
}

_Parsed _plyAscii(
  Uint8List data,
  String headerRaw,
  int vertexCount,
  int faceCount,
  int maxPoints,
  int maxTris,
) {
  final lines = headerRaw.contains('\r\n')
      ? String.fromCharCodes(data).split('\r\n')
      : String.fromCharCodes(data).split('\n');
  var start = 0;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() == 'end_header') {
      start = i + 1;
      break;
    }
  }
  final all = <List<double>>[];
  for (var i = start; i < start + vertexCount && i < lines.length; i++) {
    final parts = lines[i].trim().split(RegExp(r'\s+'));
    if (parts.length < 3) continue;
    final x = double.tryParse(parts[0]);
    final y = double.tryParse(parts[1]);
    final z = double.tryParse(parts[2]);
    if (x != null && y != null && z != null &&
        x.isFinite &&
        y.isFinite &&
        z.isFinite) {
      all.add([x, y, z]);
    }
  }
  final tris = <List<double>>[];
  if (faceCount > 0) {
    final faceStart = start + vertexCount;
    final step = faceCount > maxTris ? math.max(1, faceCount ~/ maxTris) : 1;
    for (var fi = 0; fi < faceCount; fi++) {
      final li = faceStart + fi;
      if (li >= lines.length) break;
      if (fi % step != 0) continue;
      final parts = lines[li].trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) continue;
      final n = int.tryParse(parts[0]) ?? 0;
      if (n < 3 || parts.length < n + 1) continue;
      final idx = <int>[
        for (var k = 1; k <= n; k++) int.tryParse(parts[k]) ?? -1,
      ];
      for (var t = 2; t < idx.length && tris.length < maxTris * 3; t++) {
        final a = idx[0], b = idx[t - 1], c = idx[t];
        if (a < 0 ||
            b < 0 ||
            c < 0 ||
            a >= all.length ||
            b >= all.length ||
            c >= all.length) {
          continue;
        }
        tris.addAll([all[a], all[b], all[c]]);
      }
    }
  }
  return (
    verts: _thin(all, maxPoints),
    tris: tris,
    total: vertexCount,
    error: null,
  );
}

const _plySizes = <String, int>{
  'char': 1,
  'uchar': 1,
  'int8': 1,
  'uint8': 1,
  'short': 2,
  'ushort': 2,
  'int16': 2,
  'uint16': 2,
  'int': 4,
  'uint': 4,
  'int32': 4,
  'uint32': 4,
  'float': 4,
  'float32': 4,
  'double': 8,
  'float64': 8,
};

int? _plyPropSize(String type) => _plySizes[type];

String? _plyRgbKey(String name) {
  switch (name) {
    case 'red':
    case 'r':
    case 'diffuse_red':
      return 'red';
    case 'green':
    case 'g':
    case 'diffuse_green':
      return 'green';
    case 'blue':
    case 'b':
    case 'diffuse_blue':
      return 'blue';
    default:
      return null;
  }
}

double _plyRead(ByteData bd, int off, String type, Endian endian) {
  switch (type) {
    case 'double':
    case 'float64':
      return bd.getFloat64(off, endian);
    case 'float':
    case 'float32':
      return bd.getFloat32(off, endian);
    case 'int':
    case 'int32':
      return bd.getInt32(off, endian).toDouble();
    case 'uint':
    case 'uint32':
      return bd.getUint32(off, endian).toDouble();
    case 'short':
    case 'int16':
      return bd.getInt16(off, endian).toDouble();
    case 'ushort':
    case 'uint16':
      return bd.getUint16(off, endian).toDouble();
    case 'char':
    case 'int8':
      return bd.getInt8(off).toDouble();
    case 'uchar':
    case 'uint8':
      return bd.getUint8(off).toDouble();
    default:
      return bd.getFloat32(off, endian);
  }
}

int _plyHeaderEnd(Uint8List data) {
  final n = data.length < 65536 ? data.length : 65536;
  for (var i = 0; i + 11 <= n; i++) {
    if (data[i] == 0x65 &&
        data[i + 1] == 0x6e &&
        data[i + 2] == 0x64 &&
        data[i + 3] == 0x5f &&
        data[i + 4] == 0x68 &&
        data[i + 5] == 0x65 &&
        data[i + 6] == 0x61 &&
        data[i + 7] == 0x64 &&
        data[i + 8] == 0x65 &&
        data[i + 9] == 0x72) {
      var end = i + 10;
      if (end < data.length && data[end] == 0x0d) end++;
      if (end < data.length && data[end] == 0x0a) end++;
      return end;
    }
  }
  return -1;
}

List<List<double>> _thin(List<List<double>> all, int maxPoints) {
  if (all.length <= maxPoints) return all;
  final step = math.max(1, all.length ~/ maxPoints);
  final out = <List<double>>[];
  for (var i = 0; i < all.length && out.length < maxPoints; i += step) {
    out.add(all[i]);
  }
  return out;
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dental_lab_ai/features/scans/mesh_sample.dart';

Uint8List _binaryPlyWithNormals() {
  final header = [
    'ply',
    'format binary_little_endian 1.0',
    'element vertex 3',
    'property float x',
    'property float y',
    'property float z',
    'property float nx',
    'property float ny',
    'property float nz',
    'element face 1',
    'property list uchar int vertex_indices',
    'end_header\n',
  ].join('\n');
  final head = Uint8List.fromList(header.codeUnits);
  final body = ByteData(3 * 24 + 1 + 12);
  body.setFloat32(0, 1, Endian.little);
  body.setFloat32(4, 0, Endian.little);
  body.setFloat32(8, 0, Endian.little);
  body.setFloat32(24, 0, Endian.little);
  body.setFloat32(28, 1, Endian.little);
  body.setFloat32(32, 0, Endian.little);
  body.setFloat32(48, 0, Endian.little);
  body.setFloat32(52, 0, Endian.little);
  body.setFloat32(56, 1, Endian.little);
  final faceOff = 3 * 24;
  body.setUint8(faceOff, 3);
  body.setInt32(faceOff + 1, 0, Endian.little);
  body.setInt32(faceOff + 5, 1, Endian.little);
  body.setInt32(faceOff + 9, 2, Endian.little);
  return Uint8List.fromList([...head, ...body.buffer.asUint8List()]);
}

Uint8List _crlfRgbPly() {
  final header = [
    'ply',
    'format binary_little_endian 1.0',
    'element vertex 3',
    'property float x',
    'property float y',
    'property float z',
    'property uchar red',
    'property uchar green',
    'property uchar blue',
    'element face 1',
    'property list uchar int vertex_indices',
    'end_header',
  ].join('\r\n');
  final head = Uint8List.fromList('$header\r\n'.codeUnits);
  final body = ByteData(3 * 15 + 1 + 12);
  void vert(int i, double x, double y, double z, int r, int g, int b) {
    final o = i * 15;
    body.setFloat32(o, x, Endian.little);
    body.setFloat32(o + 4, y, Endian.little);
    body.setFloat32(o + 8, z, Endian.little);
    body.setUint8(o + 12, r);
    body.setUint8(o + 13, g);
    body.setUint8(o + 14, b);
  }

  vert(0, 1, 0, 0, 255, 200, 200);
  vert(1, 0, 1, 0, 200, 100, 100);
  vert(2, 0, 0, 1, 255, 255, 255);
  final faceOff = 3 * 15;
  body.setUint8(faceOff, 3);
  body.setInt32(faceOff + 1, 0, Endian.little);
  body.setInt32(faceOff + 5, 1, Endian.little);
  body.setInt32(faceOff + 9, 2, Endian.little);
  return Uint8List.fromList([...head, ...body.buffer.asUint8List()]);
}

Uint8List _indexedAsciiPly() {
  return Uint8List.fromList(
    'ply\n'
            'format ascii 1.0\n'
            'element vertex 4\n'
            'property float x\n'
            'property float y\n'
            'property float z\n'
            'element face 2\n'
            'property list uchar int vertex_indices\n'
            'end_header\n'
            '0 0 0\n'
            '1 0 0\n'
            '0 1 0\n'
            '1 1 0\n'
            '3 0 1 2\n'
            '3 1 3 2\n'
        .codeUnits,
  );
}

void main() {
  test('samples ascii OBJ vertices and refuses empty input', () {
    final obj = Uint8List.fromList(
      'v 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 2 3\n'.codeUnits,
    );
    final ok = sampleMeshBytes(obj, 'tooth.obj');
    expect(ok.vertices.length, 3);
    expect(ok.triangles, isNotNull);
    expect(ok.triangles!.length, 18);
    expect(ok.error, isNull);

    final bad = sampleMeshBytes(Uint8List(0), 'empty.ply');
    expect(bad.vertices, isEmpty);
    expect(bad.error, isNotNull);
  });

  test('binary PLY with normals + face yields solid triangles', () {
    final ply = _binaryPlyWithNormals();
    final ok = sampleMeshBytes(ply, 'jaw.ply');
    expect(ok.error, isNull, reason: '${ok.error}');
    expect(ok.vertices.length, 3);
    expect(ok.triangles, isNotNull);
    expect(ok.triangles!.length, 18);
  });

  test('binary PLY with CRLF header + rgb still builds solid tris', () {
    final ok = sampleMeshBytes(_crlfRgbPly(), 'colored.ply');
    expect(ok.error, isNull, reason: '${ok.error}');
    expect(ok.triangles, isNotNull);
    expect(ok.triangles!.length, 18);
    expect(ok.triangles![3], greaterThan(0.9));
    expect(ok.triangles![4], lessThan(0.85));
  });

  test('OBJ with CRLF + v/vt/vn faces still builds solid tris', () {
    final obj = Uint8List.fromList(
      'v 1 0 0\r\nv 0 1 0\r\nv 0 0 1\r\nv 1 1 0\r\n'
              'f 1/1/1 2/2/2 3/3/3\r\nf 1//1 3//3 4//4\r\n'
          .codeUnits,
    );
    final ok = sampleMeshBytes(obj, 'jaw.obj');
    expect(ok.error, isNull, reason: '${ok.error}');
    expect(ok.vertices.length, greaterThanOrEqualTo(3));
    expect(ok.triangles, isNotNull);
    expect(ok.triangles!.length, greaterThanOrEqualTo(18));
  });

  test('weldSharedVertices merges duplicated triangle corners', () {
    // Two tris sharing an edge, but with 6 unique corner slots (STL-style).
    final positions = Float32List.fromList([
      0, 0, 0, // 0
      1, 0, 0, // 1
      0, 1, 0, // 2
      1, 0, 0, // 3 == 1
      1, 1, 0, // 4
      0, 1, 0, // 5 == 2
    ]);
    final indices = Uint32List.fromList([0, 1, 2, 3, 4, 5]);
    final welded = weldSharedVertices(positions, null, indices);
    expect(welded.positions.length ~/ 3, 4);
    expect(welded.indices.length, 6);
    expect(welded.indices[1], welded.indices[3]); // shared (1,0,0)
    expect(welded.indices[2], welded.indices[5]); // shared (0,1,0)
  });

  test('already-indexed dental mesh is not welded (preserves topology)', () {
    // 4 shared verts, 2 tris — like a tiny Medit PLY (indices.length > verts).
    final indices = Uint32List.fromList([0, 1, 2, 1, 3, 2]);
    expect(meshAlreadyIndexed(4, indices), isTrue);
    final done = parsePlyGeometry(_indexedAsciiPly());
    expect(done.error, isNull);
    expect(done.vertexCount, 4);
    expect(done.indices!.length, 6);
    // Positions unchanged (no weld collapse).
    expect(done.positions.length, 12);
  });

  test('parsePlyGeometry keeps faces + rgb on CRLF dental PLY', () {
    final g = parsePlyGeometry(_crlfRgbPly());
    expect(g.error, isNull, reason: '${g.error}');
    expect(g.vertexCount, 3);
    expect(g.positions.length, 9);
    expect(g.colors, isNotNull);
    expect(g.colors!.length, 9);
    expect(g.indices, isNotNull);
    expect(g.indices!.toList(), [0, 1, 2]);
    expect(g.colors![0], greaterThan(0.9));
  });

  test('parsePlyGeometry ascii CRLF + rgb faces maps index*3', () {
    final ply = Uint8List.fromList(
      'ply\r\n'
              'format ascii 1.0\r\n'
              'element vertex 3\r\n'
              'property float x\r\n'
              'property float y\r\n'
              'property float z\r\n'
              'property uchar red\r\n'
              'property uchar green\r\n'
              'property uchar blue\r\n'
              'element face 1\r\n'
              'property list uchar int vertex_indices\r\n'
              'end_header\r\n'
              '1 0 0 255 200 200\r\n'
              '0 1 0 200 100 100\r\n'
              '0 0 1 255 255 255\r\n'
              '3 0 1 2\r\n'
          .codeUnits,
    );
    final g = parsePlyGeometry(ply);
    expect(g.error, isNull, reason: '${g.error}');
    expect(g.vertexCount, 3);
    expect(g.indices, isNotNull);
    expect(g.indices!.length, 3); // 1 face * 3
    expect(g.colors, isNotNull);
    expect(g.colors![0], closeTo(1.0, 1e-6));
    expect(g.colors![1], closeTo(200 / 255.0, 1e-6));
  });

  test('binary PLY with face colors still keeps triangle indices', () {
    final header = [
      'ply',
      'format binary_little_endian 1.0',
      'element vertex 3',
      'property float x',
      'property float y',
      'property float z',
      'element face 1',
      'property list uchar int vertex_indices',
      'property uchar red',
      'property uchar green',
      'property uchar blue',
      'end_header\n',
    ].join('\n');
    final head = Uint8List.fromList(header.codeUnits);
    final body = ByteData(3 * 12 + 1 + 12 + 3);
    body.setFloat32(0, 1, Endian.little);
    body.setFloat32(12, 0, Endian.little);
    body.setFloat32(16, 1, Endian.little);
    body.setFloat32(24, 0, Endian.little);
    body.setFloat32(28, 0, Endian.little);
    body.setFloat32(32, 1, Endian.little);
    final fo = 36;
    body.setUint8(fo, 3);
    body.setInt32(fo + 1, 0, Endian.little);
    body.setInt32(fo + 5, 1, Endian.little);
    body.setInt32(fo + 9, 2, Endian.little);
    body.setUint8(fo + 13, 10);
    body.setUint8(fo + 14, 20);
    body.setUint8(fo + 15, 30);
    final g = parsePlyGeometry(
      Uint8List.fromList([...head, ...body.buffer.asUint8List()]),
    );
    expect(g.error, isNull, reason: '${g.error}');
    expect(g.indices!.toList(), [0, 1, 2]);
  });

  test('ascii face-before-vertex element order still builds solid', () {
    final ply = Uint8List.fromList(
      'ply\nformat ascii 1.0\n'
              'element face 1\n'
              'property list uchar int vertex_indices\n'
              'element vertex 3\n'
              'property float x\nproperty float y\nproperty float z\n'
              'end_header\n'
              '3 0 1 2\n'
              '1 0 0\n0 1 0\n0 0 1\n'
          .codeUnits,
    );
    final g = parsePlyGeometry(ply);
    expect(g.error, isNull, reason: '${g.error}');
    expect(g.vertexCount, 3);
    expect(g.indices!.toList(), [0, 1, 2]);
  });

  test('triangle-soup identity indices are welded for smooth shading', () {
    // 2 tris, 6 unique corner slots (same as STL dump into PLY).
    final header = [
      'ply',
      'format ascii 1.0',
      'element vertex 6',
      'property float x',
      'property float y',
      'property float z',
      'element face 2',
      'property list uchar int vertex_indices',
      'end_header',
    ].join('\n');
    final body = [
      '0 0 0',
      '1 0 0',
      '0 1 0',
      '1 0 0',
      '1 1 0',
      '0 1 0',
      '3 0 1 2',
      '3 3 4 5',
    ].join('\n');
    final g = parsePlyGeometry(Uint8List.fromList('$header\n$body\n'.codeUnits));
    expect(g.error, isNull);
    expect(g.vertexCount, 4); // welded
    expect(g.indices!.length, 6);
  });

  test('parsePlyGeometry returns no indices for point-only PLY', () {
    final ply = Uint8List.fromList(
      'ply\nformat ascii 1.0\nelement vertex 3\n'
              'property float x\nproperty float y\nproperty float z\n'
              'end_header\n0 0 0\n1 0 0\n0 1 0\n'
          .codeUnits,
    );
    final g = parsePlyGeometry(ply);
    expect(g.error, isNull);
    expect(g.positions.length, 9);
    expect(g.indices, isNull);
  });
}

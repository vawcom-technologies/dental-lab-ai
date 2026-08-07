import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;

import 'package:dental_lab_ai/features/scans/mesh_sample.dart';

/// Minimal binary PLY: 3 verts + 1 face (CRLF header — dental export style).
Uint8List _tinyPly() {
  final header = [
    'ply',
    'format binary_little_endian 1.0',
    'element vertex 3',
    'property float x',
    'property float y',
    'property float z',
    'element face 1',
    'property list uchar int vertex_indices',
    'end_header',
  ].join('\r\n');
  final head = Uint8List.fromList('$header\r\n'.codeUnits);
  final body = ByteData(3 * 12 + 1 + 12);
  body.setFloat32(0, 1, Endian.little);
  body.setFloat32(4, 0, Endian.little);
  body.setFloat32(8, 0, Endian.little);
  body.setFloat32(12, 0, Endian.little);
  body.setFloat32(16, 1, Endian.little);
  body.setFloat32(20, 0, Endian.little);
  body.setFloat32(24, 0, Endian.little);
  body.setFloat32(28, 0, Endian.little);
  body.setFloat32(32, 1, Endian.little);
  final faceOff = 36;
  body.setUint8(faceOff, 3);
  body.setInt32(faceOff + 1, 0, Endian.little);
  body.setInt32(faceOff + 5, 1, Endian.little);
  body.setInt32(faceOff + 9, 2, Endian.little);
  return Uint8List.fromList([...head, ...body.buffer.asUint8List()]);
}

void main() {
  test('parsePlyGeometry → BufferGeometry is indexed for Solid path', () {
    final parsed = parsePlyGeometry(_tinyPly());
    expect(parsed.error, isNull);
    expect(parsed.indices, isNotNull);

    final geom = three.BufferGeometry();
    geom.setAttribute(
      three.Attribute.position,
      three.Float32BufferAttribute(parsed.positions, 3),
    );
    geom.setIndex(parsed.indices!);
    geom.computeVertexNormals();
    final pos = geom.getAttribute(three.Attribute.position);
    expect(pos, isNotNull);
    expect((pos as three.BufferAttribute).count, 3);
    final idx = geom.getIndex();
    expect(idx, isNotNull);
    expect(idx!.count, 3);
    expect(geom.getAttribute(three.Attribute.normal), isNotNull);
  });

  test('Solid MeshPhongMaterial is opaque filled triangles with vertexColors', () {
    final mat = three.MeshPhongMaterial({
      three.MaterialProperty.color: 0xffffff,
      three.MaterialProperty.vertexColors: true,
      three.MaterialProperty.side: three.DoubleSide,
      three.MaterialProperty.shininess: 30,
      three.MaterialProperty.flatShading: false,
      three.MaterialProperty.wireframe: false,
      three.MaterialProperty.transparent: false,
      three.MaterialProperty.opacity: 1.0,
      three.MaterialProperty.depthWrite: true,
    });
    expect(mat.vertexColors, isTrue);
    expect(mat.flatShading, isFalse);
    expect(mat.shininess, 30);
    expect(mat.wireframe, isFalse);
    expect(mat.transparent, isFalse);
    expect(mat.opacity, 1.0);
    expect(mat.depthWrite, isTrue);
    mat.dispose();
  });
}

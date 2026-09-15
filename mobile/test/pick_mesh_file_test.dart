import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dental_lab_ai/features/scans/pick_mesh_host_io.dart';

void main() {
  test('listHostMeshFiles finds ply/stl/obj and ignores other types', () async {
    final dir = await Directory.systemTemp.createTemp('mesh-pick-');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/Jaguar ring.ply').writeAsString('ply');
    await File('${dir.path}/model.STL').writeAsString('solid');
    await File('${dir.path}/notes.txt').writeAsString('nope');

    final found = await listHostMeshFiles([dir.path, '${dir.path}/missing']);
    expect(found.map((e) => e.name), ['Jaguar ring.ply', 'model.STL']);
  });

  test('listHostMeshFiles skips unreadable dirs and de-dupes by name', () async {
    final a = await Directory.systemTemp.createTemp('mesh-a-');
    final b = await Directory.systemTemp.createTemp('mesh-b-');
    addTearDown(() => a.delete(recursive: true));
    addTearDown(() => b.delete(recursive: true));
    await File('${a.path}/Dente.obj').writeAsString('o');
    await File('${b.path}/Dente.obj').writeAsString('o2');

    final found = await listHostMeshFiles([
      a.path,
      '/this/path/does/not/exist',
      b.path,
    ]);
    expect(found.map((e) => e.name), ['Dente.obj']);
    expect(found.single.path, '${a.path}/Dente.obj');
  });

  test('isMeshFilename accepts ply/stl/obj only', () {
    expect(isMeshFilename('Jaguar ring.ply'), isTrue);
    expect(isMeshFilename('Dente.OBJ'), isTrue);
    expect(isMeshFilename('model.stl'), isTrue);
    expect(isMeshFilename('photo.jpg'), isFalse);
    expect(isMeshFilename('scan'), isFalse);
  });

  test('useIosFilesPicker is off in unit tests', () {
    expect(useIosFilesPicker, isFalse);
  });
}

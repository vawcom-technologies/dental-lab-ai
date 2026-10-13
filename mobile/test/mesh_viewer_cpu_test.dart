import 'dart:typed_data';

import 'package:dental_lab_ai/features/scans/mesh_viewer.dart';
import 'package:dental_lab_ai/features/scans/mesh_viewer_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CpuMeshViewer samples OBJ bytes without crashing', (tester) async {
    final obj = Uint8List.fromList(
      'v 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 2 3\n'.codeUnits,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: CpuMeshViewer(bytes: obj, filename: 't.obj'),
          ),
        ),
      ),
    );
    await tester.pump(); // post-frame sample
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CpuMeshViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CpuMeshViewer paints rough patches given in file coordinates', (tester) async {
    // Two far-apart triangles; only the one near (10, 0, 0) is rough. File
    // coords differ from the viewer's normalised frame, so this checks the map.
    final obj = Uint8List.fromList(
      ('v 10 0 0\nv 11 0 0\nv 10 1 0\n'
              'v -10 0 0\nv -11 0 0\nv -10 1 0\n'
              'f 1 2 3\nf 4 5 6\n')
          .codeUnits,
    );
    Widget viewer(List<List<double>> pts) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: CpuMeshViewer(
                bytes: obj,
                filename: 't.obj',
                roughPoints: pts,
                roughRadius: 0.3,
              ),
            ),
          ),
        );
    await tester.pumpWidget(viewer(const []));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(MeshViewerRoughLegend), findsNothing);

    await tester.pumpWidget(viewer(const [
      [10.1, 0.1, 0],
    ]));
    await tester.pump();
    expect(find.byType(MeshViewerRoughLegend), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

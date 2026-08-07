import 'dart:typed_data';

import 'package:dental_lab_ai/features/scans/mesh_viewer.dart';
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
}

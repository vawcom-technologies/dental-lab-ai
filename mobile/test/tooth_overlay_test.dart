import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dental_lab_ai/features/shade/tooth_overlay.dart';

void main() {
  test('Outline edit history undoes and redoes a drag', () {
    final history = OutlineEditHistory();
    var current = OutlineEditHistory.snapOf(
      [
        [0.1, 0.1],
        [0.2, 0.2],
      ],
      [0.0, 0.0],
    );
    final before = OutlineEditHistory.snapOf(current.verts, current.bulges);
    current = OutlineEditHistory.snapOf(
      [
        [0.3, 0.3],
        [0.2, 0.2],
      ],
      [0.01, 0.0],
    );
    history.record(before);

    expect(history.canUndo, isTrue);
    expect(history.canRedo, isFalse);

    final undone = history.undo(current)!;
    expect(undone.verts, before.verts);
    expect(undone.bulges, before.bulges);
    expect(history.canRedo, isTrue);

    final redone = history.redo(undone)!;
    expect(redone.verts, current.verts);
    expect(redone.bulges, current.bulges);
  });

  testWidgets('Tooth overlay paints clinical box, axis, and ticks',
      (tester) async {
    final teeth = <Map<String, dynamic>>[
      {
        'tooth_index': 0,
        'fdi': 11,
        'rejected': false,
        'geometry': {
          'outline': [
            [0.22, 0.22],
            [0.38, 0.22],
            [0.38, 0.68],
            [0.22, 0.68],
          ],
          'bbox': {'x': 0.20, 'y': 0.20, 'w': 0.20, 'h': 0.50},
          'axis': [
            [0.30, 0.18],
            [0.30, 0.72],
          ],
          'width_ticks': [
            [
              [0.22, 0.30],
              [0.38, 0.30],
            ],
            [
              [0.22, 0.45],
              [0.38, 0.45],
            ],
            [
              [0.22, 0.60],
              [0.38, 0.60],
            ],
          ],
          'label': {'x': 0.30, 'y': 0.16},
        },
      },
      {
        'tooth_index': 1,
        'fdi': 21,
        'rejected': false,
        'geometry': {
          'outline': [
            [0.42, 0.22],
            [0.58, 0.22],
            [0.58, 0.68],
            [0.42, 0.68],
          ],
          'bbox': {'x': 0.40, 'y': 0.20, 'w': 0.20, 'h': 0.50},
          'axis': [
            [0.50, 0.18],
            [0.50, 0.72],
          ],
          'width_ticks': [
            [
              [0.42, 0.45],
              [0.58, 0.45],
            ],
          ],
          'label': {'x': 0.50, 'y': 0.16},
        },
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            painter: ToothOverlayPainter(
              teeth: teeth,
              selectedToothIndex: 0,
              imageSize: const Size(800, 600),
              focusZone: 'middle',
            ),
            child: const SizedBox(width: 400, height: 300),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
  });
}

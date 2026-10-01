import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:dental_lab_ai/features/shade/shade_shared.dart';
import 'package:dental_lab_ai/features/shade/tooth_overlay.dart';

void main() {
  // 100×100 image in a 100×100 box → normalized coords map 1:1 to pixels/100.
  const box = Size(100, 100);
  final square = [
    [0.2, 0.2],
    [0.8, 0.2],
    [0.8, 0.8],
    [0.2, 0.8],
  ];

  ({String kind, int index})? hit(Offset p) => hitTestOutlineEditTarget(
        local: p,
        box: box,
        imageSize: box,
        outline: square,
        radius: 12,
      );

  test('nearest dot wins: corner vs edge-curve dot', () {
    expect(hit(const Offset(22, 21)), (kind: 'v', index: 0));
    // Right on the top edge's midpoint dot, inside the corner radius of none.
    expect(hit(const Offset(50, 21)), (kind: 'e', index: 0));
  });

  test('inside with no dot nearby drags the outline; outside is nothing', () {
    expect(hit(const Offset(50, 50)), (kind: 'b', index: 0));
    expect(hit(const Offset(95, 50)), isNull);
  });

  test('guide handles: points, then midline body slides the line', () {
    final guides = {
      'midline': [
        [0.5, 0.1],
        [0.5, 0.9],
      ],
      'upper_lip': [
        [0.3, 0.15],
        [0.7, 0.15],
      ],
      'occlusal': [
        [0.1, 0.5],
        [0.9, 0.5],
      ],
    };
    ({String key, int index})? g(Offset p) => hitTestGuideHandle(
          local: p,
          box: box,
          imageSize: box,
          guides: guides,
          radius: 10,
        );
    expect(g(const Offset(50, 11)), (key: 'midline', index: 0));
    expect(g(const Offset(31, 15)), (key: 'upper_lip', index: 0));
    expect(g(const Offset(51, 50)), (key: 'midline', index: -1));
    expect(g(const Offset(10, 50)), isNull); // bite line is not draggable
  });

  test('moving the midline one tooth renumbers both arches', () {
    Map<String, dynamic> t(double x, String arch) => {
          'arch': arch,
          'geometry': {
            'bbox': {'x': x, 'y': arch == 'upper' ? 0.2 : 0.6, 'w': 0.1, 'h': 0.2},
          },
        };
    final teeth = [
      for (final x in [0.2, 0.3, 0.4, 0.5]) t(x, 'upper'),
      for (final x in [0.26, 0.36, 0.46]) t(x, 'lower'),
    ];
    renumberTeethFromMidline(teeth, [
      [0.4, 0.0],
      [0.4, 1.0],
    ]);
    int fdiAt(double x, String arch) => teeth.firstWhere((e) =>
        e['arch'] == arch &&
        ((e['geometry'] as Map)['bbox'] as Map)['x'] == x)['fdi'] as int;
    expect(fdiAt(0.3, 'upper'), 11);
    expect(fdiAt(0.2, 'upper'), 12);
    expect(fdiAt(0.4, 'upper'), 21);
    expect(fdiAt(0.36, 'lower'), 31); // centre 0.41, just right of the line
    expect(fdiAt(0.26, 'lower'), 41);
    expect([for (final e in teeth) e['tooth_index']], [0, 1, 2, 3, 4, 5, 6]);
  });

  test('symmetry lip lines: top of upper lip, bottom of lower lip', () {
    final lines = lipSymmetryLines({
      'upper_lip': [
        [0.2, 0.40],
        [0.5, 0.30],
        [0.8, 0.42],
      ],
      'lower_lip': [
        [0.2, 0.40],
        [0.5, 0.75],
        [0.8, 0.42],
      ],
    });
    expect(lines.top!.first[1], 0.30);
    expect(lines.top!.first[0], closeTo(0.2 - 0.024, 1e-9));
    expect(lines.top!.last[0], closeTo(0.8 + 0.024, 1e-9));
    expect(lines.bottomY, 0.75);
    final none = lipSymmetryLines({});
    expect(none.top, isNull);
    expect(none.bottomY, isNull);
  });
}

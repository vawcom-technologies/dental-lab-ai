import 'package:flutter_test/flutter_test.dart';

import 'package:dental_lab_ai/features/shade/fdi_tooth_chart.dart';
import 'package:dental_lab_ai/features/shade/shade_shared.dart';

void main() {
  test('centeredFdiWindow picks anteriors for 6 teeth', () {
    expect(
      centeredFdiWindow(kUpperFdiSelectableLtr, 6),
      [13, 12, 11, 21, 22, 23],
    );
  });

  test('mapFdiToToothIndex uses stored FDI from analyze', () {
    final teeth = [
      {'tooth_index': 0, 'arch': 'upper', 'fdi': 11},
      {'tooth_index': 1, 'arch': 'upper', 'fdi': 12},
      {'tooth_index': 2, 'arch': 'upper', 'fdi': 13},
      {'tooth_index': 3, 'arch': 'upper', 'fdi': 21},
      {'tooth_index': 4, 'arch': 'upper', 'fdi': 22},
      {'tooth_index': 5, 'arch': 'upper', 'fdi': 23},
      {'tooth_index': 6, 'arch': 'lower', 'fdi': 41},
      {'tooth_index': 7, 'arch': 'lower', 'fdi': 31},
    ];
    final map = mapFdiToToothIndex(teeth);
    expect(map[11], 0);
    expect(map[13], 2);
    expect(map[21], 3);
    expect(map[23], 5);
    expect(map.containsKey(15), isFalse);
    expect(map[41], 6);
    expect(map[31], 7);
  });

  test('mapFdiToToothIndex falls back to LTR window without fdi', () {
    final teeth = [
      {'tooth_index': 0, 'arch': 'upper', 'arch_index': 0},
      {'tooth_index': 1, 'arch': 'upper', 'arch_index': 1},
      {'tooth_index': 2, 'arch': 'upper', 'arch_index': 2},
      {'tooth_index': 3, 'arch': 'upper', 'arch_index': 3},
      {'tooth_index': 4, 'arch': 'upper', 'arch_index': 4},
      {'tooth_index': 5, 'arch': 'upper', 'arch_index': 5},
      {'tooth_index': 6, 'arch': 'lower', 'arch_index': 0},
      {'tooth_index': 7, 'arch': 'lower', 'arch_index': 1},
    ];
    final map = mapFdiToToothIndex(teeth);
    expect(map[13], 0);
    expect(map[11], 2);
    expect(map[21], 3);
    expect(map[23], 5);
    expect(map.containsKey(15), isFalse);
    expect(map[41], 6);
    expect(map[31], 7);
  });

  test('toothDisplayLabel prefers FDI over T-index', () {
    expect(toothDisplayLabel({'tooth_index': 0, 'fdi': 11}), '11');
    expect(toothDisplayLabel({'tooth_index': 4, 'label': 'Upper 5'}), 'Upper 5');
    expect(fdiSortKey({'fdi': 21}), greaterThan(fdiSortKey({'fdi': 13})));
    expect(fdiSortKey({'fdi': 41}), greaterThan(fdiSortKey({'fdi': 23})));
    expect(fdiSortKey({'fdi': 31}), greaterThan(fdiSortKey({'fdi': 42})));
  });
}

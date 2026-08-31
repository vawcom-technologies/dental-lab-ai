import 'package:flutter_test/flutter_test.dart';

import 'package:dental_lab_ai/features/shade/fdi_tooth_chart.dart';

void main() {
  test('centeredFdiWindow picks anteriors for 6 teeth', () {
    expect(
      centeredFdiWindow(kUpperFdiSelectableLtr, 6),
      [13, 12, 11, 21, 22, 23],
    );
  });

  test('mapFdiToToothIndex uses arch rows', () {
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
}

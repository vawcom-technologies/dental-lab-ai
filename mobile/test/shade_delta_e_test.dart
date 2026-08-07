import 'package:dental_lab_ai/features/shade/shade_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ΔE vs self is ~0; far shade lowers confidence', () {
    final b1Lab = rgbToLab(kShadeRgb['B1']!);
    expect(deltaEVsShade(b1Lab, 'B1')!, lessThan(0.05));
    final near = confidenceFromDeltaE(deltaEVsShade(b1Lab, 'B1')!);
    final far = confidenceFromDeltaE(deltaEVsShade(b1Lab, 'A4')!);
    expect(near, greaterThan(0.9));
    expect(far, lessThan(near));
  });
}

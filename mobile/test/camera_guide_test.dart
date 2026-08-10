import 'dart:typed_data';

import 'package:dental_lab_ai/features/camera/camera_guide.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('jaw crop bands stay inside angle guide', () {
    for (final angle in ['frontal', 'left', 'right']) {
      final guide = guideRectForAngle(angle);
      final top = cropRectFor(angle, JawFocus.top);
      final bottom = cropRectFor(angle, JawFocus.bottom);
      final both = cropRectFor(angle, JawFocus.both);
      expect(both, guide);
      expect(top.top, greaterThanOrEqualTo(guide.top));
      expect(top.bottom, lessThanOrEqualTo(guide.bottom));
      expect(bottom.top, greaterThanOrEqualTo(guide.top));
      expect(bottom.bottom, lessThanOrEqualTo(guide.bottom));
      expect(top.height, lessThan(guide.height));
      expect(bottom.height, lessThan(guide.height));
    }
  });

  test('cropCaptureToGuide returns smaller upper band for top focus', () {
    final src = img.Image(width: 200, height: 200);
    img.fill(src, color: img.ColorRgb8(40, 40, 40));
    final jpeg = Uint8List.fromList(img.encodeJpg(src));
    final both = cropCaptureToGuide(
      jpeg,
      angle: 'frontal',
      focus: JawFocus.both,
    );
    final top = cropCaptureToGuide(
      jpeg,
      angle: 'frontal',
      focus: JawFocus.top,
    );
    final bothImg = img.decodeImage(both)!;
    final topImg = img.decodeImage(top)!;
    expect(topImg.height, lessThan(bothImg.height));
    expect(topImg.width, bothImg.width);
  });
}

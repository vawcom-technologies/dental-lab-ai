import 'dart:typed_data';

import 'package:dental_lab_ai/core/images/orient_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('bakeExifOrientation returns a decodable upright JPEG', () {
    final image = img.Image(width: 32, height: 24);
    img.fill(image, color: img.ColorRgb8(200, 180, 160));
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
    final out = bakeExifOrientation(bytes);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 32);
    expect(decoded.height, 24);
  });

  test('bakeExifOrientation applies 90° CW bake from oriented buffer', () {
    // Simulate what camera JPEGs look like after decode+bakeOrientation.
    final landscape = img.Image(width: 40, height: 20);
    img.fill(landscape, color: img.ColorRgb8(10, 20, 30));
    landscape.setPixelRgb(0, 0, 255, 255, 255);
    final rotated = img.copyRotate(landscape, angle: 90);
    expect(rotated.width, 20);
    expect(rotated.height, 40);
    final bytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 90));
    final out = bakeExifOrientation(bytes);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 20);
    expect(decoded.height, 40);
  });
}

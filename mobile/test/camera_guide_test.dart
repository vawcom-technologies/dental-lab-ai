import 'dart:typed_data';
import 'dart:ui';

import 'package:dental_lab_ai/features/camera/camera_guide.dart';
import 'package:dental_lab_ai/features/camera/camera_preview_fit.dart';
import 'package:flutter/services.dart';
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

  test('portrait preview swaps sensor axes to avoid landscape stretch', () {
    const sensor = Size(1920, 1080);
    final portrait = displayedPreviewSize(sensor, landscape: false);
    final landscape = displayedPreviewSize(sensor, landscape: true);
    expect(landscape, sensor);
    expect(portrait, const Size(1080, 1920));
    expect(portrait.aspectRatio, closeTo(1 / sensor.aspectRatio, 0.0001));
  });

  test('cover-fit keeps source aspect on every iPad size', () {
    const sensorPortrait = Size(1080, 1920);
    const ipads = <String, Size>{
      'mini portrait': Size(744, 1133),
      '11" portrait': Size(834, 1194),
      '13" portrait': Size(1024, 1366),
      'mini landscape': Size(1133, 744),
      '11" landscape': Size(1194, 834),
      '13" landscape': Size(1366, 1024),
    };
    ipads.forEach((name, viewport) {
      final dest = coverDestinationSize(sensorPortrait, viewport);
      expect(
        dest.aspectRatio,
        closeTo(sensorPortrait.aspectRatio, 0.001),
        reason: name,
      );
      expect(dest.width + 0.01, greaterThanOrEqualTo(viewport.width), reason: name);
      expect(dest.height + 0.01, greaterThanOrEqualTo(viewport.height), reason: name);
      final visible = coverVisibleFraction(sensorPortrait, viewport);
      expect(visible.left, greaterThanOrEqualTo(0), reason: name);
      expect(visible.top, greaterThanOrEqualTo(0), reason: name);
      expect(visible.right, lessThanOrEqualTo(1.001), reason: name);
      expect(visible.bottom, lessThanOrEqualTo(1.001), reason: name);
    });
  });

  test('4:3 iPad portrait nearly fills a 4:3 camera still', () {
    const stillPortrait = Size(3024, 4032);
    const ipad11 = Size(834, 1194);
    final dest = coverDestinationSize(stillPortrait, ipad11);
    expect(dest.aspectRatio, closeTo(stillPortrait.aspectRatio, 0.001));
    final visible = coverVisibleFraction(stillPortrait, ipad11);
    expect(visible.width * visible.height, greaterThan(0.85));
  });

  test('guide on a cover-cropped viewport maps inside the image', () {
    const source = Size(1080, 1920);
    const ipad11 = Size(834, 1194);
    final visible = coverVisibleFraction(source, ipad11);
    final mapped = mapGuideToImage(
      guide: cropRectFor('frontal', JawFocus.both),
      visible: visible,
    );
    expect(mapped.left, greaterThanOrEqualTo(visible.left));
    expect(mapped.right, lessThanOrEqualTo(visible.right));
    expect(mapped.top, greaterThanOrEqualTo(visible.top));
    expect(mapped.bottom, lessThanOrEqualTo(visible.bottom));
  });

  test('centerCropToAspect turns 4:3 still into 9:16 preview strip', () {
    final crop = centerCropToAspect(const Size(3024, 4032), 9 / 16);
    expect(crop.width / crop.height, closeTo(9 / 16, 0.01));
    expect(crop.height, 4032);
    expect(crop.top, 0);
  });

  test('cropCaptureToGuide matching portrait preview crops a 4:3 still', () {
    final src = img.Image(width: 400, height: 300);
    img.fill(src, color: img.ColorRgb8(40, 40, 40));
    final jpeg = Uint8List.fromList(img.encodeJpg(src));
    final out = cropCaptureToGuide(
      jpeg,
      angle: 'frontal',
      focus: JawFocus.both,
      previewAspect: 3 / 4,
    );
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, lessThan(400));
    expect(decoded.height, lessThanOrEqualTo(300));
  });

  test('portrait iPad guides stay a landscape mouth band', () {
    const ipads = <Size>[
      Size(744, 1133),
      Size(834, 1194),
      Size(1024, 1366),
    ];
    for (final viewport in ipads) {
      for (final angle in ['frontal', 'left', 'right']) {
        final guide = guideRectForAngle(angle, viewport: viewport);
        final pixelW = guide.width * viewport.width;
        final pixelH = guide.height * viewport.height;
        expect(pixelW, greaterThan(pixelH), reason: '$angle $viewport');
        expect(guide.left, greaterThanOrEqualTo(0));
        expect(guide.right, lessThanOrEqualTo(1));
        expect(guide.top, greaterThan(0.2));
        expect(guide.bottom, lessThan(0.8));
      }
    }
  });

  test('landscape camera orientations match CameraPreview', () {
    expect(isLandscapeDeviceOrientation(DeviceOrientation.landscapeLeft), isTrue);
    expect(isLandscapeDeviceOrientation(DeviceOrientation.landscapeRight), isTrue);
    expect(isLandscapeDeviceOrientation(DeviceOrientation.portraitUp), isFalse);
    expect(
      applicableCameraOrientation(
        deviceOrientation: DeviceOrientation.portraitUp,
        isRecordingVideo: false,
        lockedCaptureOrientation: DeviceOrientation.landscapeLeft,
      ),
      DeviceOrientation.landscapeLeft,
    );
  });
}

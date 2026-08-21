import 'dart:io';

import 'package:image/image.dart' as img;

/// Builds opaque iOS app icons from the Elite Dent wordmark.
/// Run from `mobile/`: `dart run tool/generate_app_icons.dart`
void main() {
  final logoFile = File('assets/brand/logo.png');
  if (!logoFile.existsSync()) {
    stderr.writeln('Missing ${logoFile.path}');
    exit(1);
  }
  final logo = img.decodeImage(logoFile.readAsBytesSync());
  if (logo == null) {
    stderr.writeln('Could not decode logo.png');
    exit(1);
  }

  const sizes = <(String, int)>[
    ('Icon-App-20x20@1x.png', 20),
    ('Icon-App-20x20@2x.png', 40),
    ('Icon-App-20x20@3x.png', 60),
    ('Icon-App-29x29@1x.png', 29),
    ('Icon-App-29x29@2x.png', 58),
    ('Icon-App-29x29@3x.png', 87),
    ('Icon-App-40x40@1x.png', 40),
    ('Icon-App-40x40@2x.png', 80),
    ('Icon-App-40x40@3x.png', 120),
    ('Icon-App-60x60@2x.png', 120),
    ('Icon-App-60x60@3x.png', 180),
    ('Icon-App-76x76@1x.png', 76),
    ('Icon-App-76x76@2x.png', 152),
    ('Icon-App-83.5x83.5@2x.png', 167),
    ('Icon-App-1024x1024@1x.png', 1024),
  ];

  final dir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  for (final (name, size) in sizes) {
    // RGB only — App Store 1024px marketing icon cannot have alpha.
    final canvas = img.Image(width: size, height: size, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(0x1D, 0x35, 0x57));
    final targetW = (size * 0.82).round().clamp(1, size);
    final scaled = img.copyResize(
      logo,
      width: targetW,
      interpolation: img.Interpolation.cubic,
    );
    img.compositeImage(
      canvas,
      scaled,
      dstX: ((size - scaled.width) / 2).round(),
      dstY: ((size - scaled.height) / 2).round(),
    );
    File('${dir.path}/$name').writeAsBytesSync(img.encodePng(canvas));
  }

  // Launch images: wordmark on the clinical canvas color.
  const launch = <(String, int)>[
    ('LaunchImage.png', 168),
    ('LaunchImage@2x.png', 336),
    ('LaunchImage@3x.png', 504),
  ];
  final launchDir = Directory('ios/Runner/Assets.xcassets/LaunchImage.imageset');
  for (final (name, size) in launch) {
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0xE4, 0xEB, 0xF4, 0xFF));
    final scaled = img.copyResize(
      logo,
      width: (size * 0.86).round(),
      interpolation: img.Interpolation.cubic,
    );
    img.compositeImage(
      canvas,
      scaled,
      dstX: ((size - scaled.width) / 2).round(),
      dstY: ((size - scaled.height) / 2).round(),
    );
    File('${launchDir.path}/$name').writeAsBytesSync(img.encodePng(canvas));
  }

  stdout.writeln('Wrote ${sizes.length} app icons and ${launch.length} launch images.');
}

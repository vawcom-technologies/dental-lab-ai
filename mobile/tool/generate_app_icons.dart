import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Builds opaque iOS app icons from [assets/brand/appicon.png] and launch
/// images from [assets/brand/logo.png] (wordmark stays for splash / in-app).
///
/// Run from `mobile/`: `dart run tool/generate_app_icons.dart`
void main() {
  final appIcon = _decode('assets/brand/appicon.png');
  final logo = _decode('assets/brand/logo.png');

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
  // Trim transparent padding so the mark fills the icon.
  final mark = img.trim(
    appIcon,
    mode: img.TrimMode.transparent,
  );
  for (final (name, size) in sizes) {
    // RGB only — App Store 1024px marketing icon cannot have alpha.
    final canvas = img.Image(width: size, height: size, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(0xFF, 0xFF, 0xFF));
    // ~70% of the canvas so the tooth has even top/bottom padding.
    final inset = (size * 0.70).round().clamp(1, size);
    final scale = math.min(inset / mark.width, inset / mark.height);
    final scaled = img.copyResize(
      mark,
      width: math.max(1, (mark.width * scale).round()),
      height: math.max(1, (mark.height * scale).round()),
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
    ('LaunchImage.png', 260),
    ('LaunchImage@2x.png', 520),
    ('LaunchImage@3x.png', 780),
  ];
  final launchDir = Directory('ios/Runner/Assets.xcassets/LaunchImage.imageset');
  for (final (name, size) in launch) {
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0xE4, 0xEB, 0xF4, 0xFF));
    final scaled = img.copyResize(
      logo,
      width: (size * 0.94).round(),
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

  stdout.writeln(
    'Wrote ${sizes.length} app icons (appicon.png) and '
    '${launch.length} launch images (logo.png).',
  );
}

img.Image _decode(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Missing $path');
    exit(1);
  }
  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode $path');
    exit(1);
  }
  return decoded;
}

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Builds opaque iOS app icons and launch images from the EliteDent wordmark.
///
/// Run from `mobile/`: `dart run tool/generate_app_icons.dart`
void main() {
  final logo = _decode('assets/brand/logo.png');
  final mark = img.trim(logo, mode: img.TrimMode.transparent);

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

  // Master 1024 is RGB (App Store forbids alpha). Smaller sizes downsample it.
  final icon1024 = _wordmarkOnWhite(mark, 1024);
  final dir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  for (final (name, size) in sizes) {
    final canvas = size == 1024
        ? icon1024
        : img.copyResize(
            icon1024,
            width: size,
            height: size,
            interpolation: img.Interpolation.cubic,
          );
    File('${dir.path}/$name').writeAsBytesSync(img.encodePng(canvas));
  }

  File('assets/brand/appicon.png').writeAsBytesSync(img.encodePng(icon1024));
  _writeRoundedPreview(icon1024);

  const launch = <(String, int)>[
    ('LaunchImage.png', 340),
    ('LaunchImage@2x.png', 680),
    ('LaunchImage@3x.png', 1020),
  ];
  final launchDir = Directory('ios/Runner/Assets.xcassets/LaunchImage.imageset');
  for (final (name, size) in launch) {
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0xE4, 0xEB, 0xF4, 0xFF));
    final scaled = img.copyResize(
      mark,
      width: (size * 0.92).round(),
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
    'Wrote ${sizes.length} app icons and ${launch.length} launch images '
    'from the EliteDent wordmark.',
  );
}

/// Full original wordmark on white, filling the square like the home-screen icon.
img.Image _wordmarkOnWhite(img.Image mark, int size) {
  final canvas = img.Image(width: size, height: size, numChannels: 3);
  img.fill(canvas, color: img.ColorRgb8(0xFF, 0xFF, 0xFF));
  final inset = (size * 0.90).round().clamp(1, size);
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
  return canvas;
}

/// Home-screen style preview (rounded) for review — not used as the App Store icon.
void _writeRoundedPreview(img.Image square) {
  const preview = 512;
  const radius = 114; // ~22.4% of 512, iOS squircle-ish
  final scaled = img.copyResize(
    square,
    width: preview,
    height: preview,
    interpolation: img.Interpolation.cubic,
  );
  final out = img.Image(width: preview, height: preview, numChannels: 4);
  img.fill(out, color: img.ColorRgba8(0, 0, 0, 0));
  for (var y = 0; y < preview; y++) {
    for (var x = 0; x < preview; x++) {
      if (_inRoundedRect(x, y, preview, radius)) {
        final p = scaled.getPixel(x, y);
        out.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
      }
    }
  }
  File('/tmp/elite-dent-app-icon-preview.png').writeAsBytesSync(img.encodePng(out));
}

bool _inRoundedRect(int x, int y, int size, int r) {
  final cx = x < r
      ? r - x
      : x >= size - r
          ? x - (size - r - 1)
          : 0;
  final cy = y < r
      ? r - y
      : y >= size - r
          ? y - (size - r - 1)
          : 0;
  if (cx == 0 || cy == 0) return true;
  return cx * cx + cy * cy <= r * r;
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

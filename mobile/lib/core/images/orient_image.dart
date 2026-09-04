import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Longest side sent to shade upload / detect. iPad camera-roll photos are
/// often 12MP HEIC; the backend segments at ≤1280px and times out at 90s.
const int kShadeUploadMaxSide = 1600;

/// Bake EXIF orientation into pixels and re-encode as JPEG.
///
/// [Image.memory] ignores EXIF orientation tags. The shade backend applies
/// `exif_transpose` before segmentation — without baking here, overlays are
/// drawn against a differently-oriented preview (common for iPad camera roll).
Uint8List bakeExifOrientation(Uint8List bytes, {int quality = 92}) {
  return bakeExifOrientationSized(bytes, quality: quality).bytes;
}

/// Bake EXIF and return pixel size of the JPEG used on screen.
({Uint8List bytes, int width, int height}) bakeExifOrientationSized(
  Uint8List bytes, {
  int quality = 92,
}) {
  if (bytes.isEmpty) {
    return (bytes: bytes, width: 0, height: 0);
  }
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null || decoded.width < 2 || decoded.height < 2) {
    return (bytes: bytes, width: 0, height: 0);
  }
  final oriented = img.bakeOrientation(decoded);
  return (
    bytes: Uint8List.fromList(img.encodeJpg(oriented, quality: quality)),
    width: oriented.width,
    height: oriented.height,
  );
}

/// Decode with the native iOS/Android codec (HEIC, wide-gamut JPEG, …),
/// bake orientation, downscale, and re-encode as JPEG.
///
/// The Dart `image` package cannot decode HEIC. iPad Photos defaults to HEIC,
/// so [bakeExifOrientationSized] would pass the original bytes through and
/// Pillow on the server would fail — upload looks fine, teeth never appear.
Future<({Uint8List bytes, int width, int height})> prepareShadeJpeg(
  Uint8List bytes, {
  int quality = 90,
  int maxSide = kShadeUploadMaxSide,
}) async {
  if (bytes.isEmpty) {
    throw StateError('Could not read this photo. Try another image.');
  }

  final native = await _prepareWithUi(bytes, quality: quality, maxSide: maxSide);
  if (native != null) {
    return native;
  }

  final baked = bakeExifOrientationSized(bytes, quality: quality);
  if (baked.width < 2 || baked.height < 2) {
    throw StateError(
      'Could not read this photo. Export it as JPEG from Photos and try again.',
    );
  }
  return _downscaleJpeg(baked, quality: quality, maxSide: maxSide);
}

String shadeJpegFilename(String originalName) {
  final trimmed = originalName.trim();
  final dot = trimmed.lastIndexOf('.');
  final stem = (dot > 0 ? trimmed.substring(0, dot) : trimmed).trim();
  final safe = stem.isEmpty ? 'tooth' : stem;
  return '$safe.jpg';
}

Future<({Uint8List bytes, int width, int height})?> _prepareWithUi(
  Uint8List bytes, {
  required int quality,
  required int maxSide,
}) async {
  ui.Image? image;
  try {
    final probed = await ui.instantiateImageCodec(bytes);
    final probeFrame = await probed.getNextFrame();
    final pw = probeFrame.image.width;
    final ph = probeFrame.image.height;
    probeFrame.image.dispose();
    if (pw < 2 || ph < 2) {
      return null;
    }

    final longSide = pw > ph ? pw : ph;
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: longSide > maxSide && pw >= ph ? maxSide : null,
      targetHeight: longSide > maxSide && ph > pw ? maxSide : null,
    );
    final frame = await codec.getNextFrame();
    image = frame.image;

    final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) {
      return null;
    }
    final raster = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: bd.buffer,
      bytesOffset: bd.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return (
      bytes: Uint8List.fromList(img.encodeJpg(raster, quality: quality)),
      width: raster.width,
      height: raster.height,
    );
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
  }
}

({Uint8List bytes, int width, int height}) _downscaleJpeg(
  ({Uint8List bytes, int width, int height}) baked, {
  required int quality,
  required int maxSide,
}) {
  final longSide = baked.width > baked.height ? baked.width : baked.height;
  if (longSide <= maxSide || baked.width < 2) {
    return baked;
  }
  img.Image? decoded;
  try {
    decoded = img.decodeImage(baked.bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    return baked;
  }
  final scale = maxSide / longSide;
  final resized = img.copyResize(
    decoded,
    width: (decoded.width * scale).round().clamp(1, maxSide),
    height: (decoded.height * scale).round().clamp(1, maxSide),
    interpolation: img.Interpolation.linear,
  );
  return (
    bytes: Uint8List.fromList(img.encodeJpg(resized, quality: quality)),
    width: resized.width,
    height: resized.height,
  );
}

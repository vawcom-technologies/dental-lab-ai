import 'dart:typed_data';

import 'package:image/image.dart' as img;

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
  final decoded = img.decodeImage(bytes);
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

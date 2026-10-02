import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Lets the user adjust a crop rectangle over [bytes]; pops cropped JPEG bytes
/// (or null when cancelled).
class CropPhotoPage extends StatefulWidget {
  const CropPhotoPage({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<CropPhotoPage> createState() => _CropPhotoPageState();
}

class _CropPhotoPageState extends State<CropPhotoPage> {
  static const _minFrac = 0.1;
  static const _handle = 28.0;

  Size? _imageSize;
  // Crop rect in 0..1 image coordinates.
  Rect _crop = const Rect.fromLTWH(0.05, 0.05, 0.9, 0.9);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ui.decodeImageFromList(widget.bytes, (image) {
      if (!mounted) return;
      setState(() => _imageSize = Size(
            image.width.toDouble(),
            image.height.toDouble(),
          ));
    });
  }

  /// Applies [delta] (in image fractions) to the sides flagged by [l]/[t]/[r]/[b].
  void _drag(Offset delta, {bool l = false, bool t = false, bool r = false, bool b = false}) {
    var rect = _crop;
    if (l && t && r && b) {
      rect = rect.shift(delta);
      final dx = rect.left < 0 ? -rect.left : (rect.right > 1 ? 1 - rect.right : 0.0);
      final dy = rect.top < 0 ? -rect.top : (rect.bottom > 1 ? 1 - rect.bottom : 0.0);
      rect = rect.shift(Offset(dx, dy));
    } else {
      rect = Rect.fromLTRB(
        l ? (rect.left + delta.dx).clamp(0.0, rect.right - _minFrac) : rect.left,
        t ? (rect.top + delta.dy).clamp(0.0, rect.bottom - _minFrac) : rect.top,
        r ? (rect.right + delta.dx).clamp(rect.left + _minFrac, 1.0) : rect.right,
        b ? (rect.bottom + delta.dy).clamp(rect.top + _minFrac, 1.0) : rect.bottom,
      );
    }
    setState(() => _crop = rect);
  }

  Future<void> _done() async {
    setState(() => _saving = true);
    final out = await compute(_cropJpeg, (widget.bytes, _crop));
    if (mounted) Navigator.of(context).pop<Uint8List>(out);
  }

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Crop photo'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: size == null || _saving ? null : _done,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Use photo'),
          ),
        ],
      ),
      body: size == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, c) {
              final fit = applyBoxFit(BoxFit.contain, size, c.biggest).destination;
              final img0 = Alignment.center.inscribe(fit, Offset.zero & c.biggest);
              final r = Rect.fromLTRB(
                img0.left + _crop.left * img0.width,
                img0.top + _crop.top * img0.height,
                img0.left + _crop.right * img0.width,
                img0.top + _crop.bottom * img0.height,
              );
              Offset frac(Offset d) => Offset(d.dx / img0.width, d.dy / img0.height);
              Widget corner(Offset at, {bool l = false, bool t = false, bool r = false, bool b = false}) =>
                  Positioned(
                    left: at.dx - _handle / 2,
                    top: at.dy - _handle / 2,
                    width: _handle,
                    height: _handle,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) => _drag(frac(d.delta), l: l, t: t, r: r, b: b),
                      child: Center(
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  );
              return Stack(children: [
                Positioned.fromRect(
                  rect: img0,
                  child: Image.memory(widget.bytes, fit: BoxFit.fill),
                ),
                // Dim everything outside the crop rect.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _DimPainter(r)),
                  ),
                ),
                Positioned.fromRect(
                  rect: r,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) =>
                        _drag(frac(d.delta), l: true, t: true, r: true, b: true),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ),
                corner(r.topLeft, l: true, t: true),
                corner(r.topRight, r: true, t: true),
                corner(r.bottomLeft, l: true, b: true),
                corner(r.bottomRight, r: true, b: true),
              ]);
            }),
    );
  }
}

class _DimPainter extends CustomPainter {
  _DimPainter(this.hole);
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(hole),
      Paint()..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}

Uint8List _cropJpeg((Uint8List, Rect) args) {
  final (bytes, f) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final src = img.bakeOrientation(decoded);
  final x = (f.left * src.width).round().clamp(0, src.width - 1);
  final y = (f.top * src.height).round().clamp(0, src.height - 1);
  final w = (f.width * src.width).round().clamp(1, src.width - x);
  final h = (f.height * src.height).round().clamp(1, src.height - y);
  return Uint8List.fromList(
    img.encodeJpg(img.copyCrop(src, x: x, y: y, width: w, height: h), quality: 96),
  );
}

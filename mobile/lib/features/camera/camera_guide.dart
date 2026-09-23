import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'camera_preview_fit.dart';

/// Which dental arch the dentist wants in frame.
enum JawFocus { both, top, bottom }

extension JawFocusLabel on JawFocus {
  String get label => switch (this) {
        JawFocus.both => 'Both jaws',
        JawFocus.top => 'Upper teeth',
        JawFocus.bottom => 'Lower teeth',
      };
}

/// Capture frame (includes cheeks / sides of mouth). Teeth art sits smaller inside.
///
/// [viewport] is the on-screen preview. In portrait the mouth window stays a
/// landscape band (the smile is wider than it is tall) so 11" / 13" iPads
/// don't get a stretched tall frame.
Rect guideRectForAngle(String angle, {Size viewport = Size.zero}) {
  final Rect base;
  switch (angle) {
    case 'left':
      base = const Rect.fromLTRB(0.06, 0.22, 0.70, 0.78);
    case 'right':
      base = const Rect.fromLTRB(0.30, 0.22, 0.94, 0.78);
    default: // frontal — room around the smile for lips/cheeks
      base = const Rect.fromLTRB(0.10, 0.22, 0.90, 0.78);
  }
  if (viewport.height <= viewport.width || viewport.height <= 0) {
    return base;
  }
  const frameAspect = 1.55;
  final widthFrac = base.width;
  final heightFrac = (widthFrac / frameAspect * (viewport.width / viewport.height))
      .clamp(0.28, 0.48);
  final top = ((1 - heightFrac) / 2).clamp(0.0, 1.0);
  return Rect.fromLTRB(base.left, top, base.right, top + heightFrac);
}

/// Crop window for the selected jaw within the angle guide.
Rect cropRectFor(String angle, JawFocus focus, {Size viewport = Size.zero}) {
  final g = guideRectForAngle(angle, viewport: viewport);
  switch (focus) {
    case JawFocus.top:
      return Rect.fromLTRB(g.left, g.top, g.right, g.top + g.height * 0.62);
    case JawFocus.bottom:
      return Rect.fromLTRB(g.left, g.bottom - g.height * 0.62, g.right, g.bottom);
    case JawFocus.both:
      return g;
  }
}

/// Crop captured JPEG to the on-screen guide / jaw band.
///
/// [previewAspect] is the live feed's displayed width/height (after portrait
/// swap). iOS stills are often 4:3 while preview is 16:9 — matching first
/// keeps the crop aligned with what the dentist framed.
///
/// [visible] is the BoxFit.cover window inside that preview (0–1).
Uint8List cropCaptureToGuide(
  Uint8List jpeg, {
  required String angle,
  required JawFocus focus,
  Rect visible = const Rect.fromLTWH(0, 0, 1, 1),
  double? previewAspect,
  Size viewport = Size.zero,
}) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null || decoded.width < 8 || decoded.height < 8) return jpeg;

  var oriented = img.bakeOrientation(decoded);
  if (previewAspect != null && previewAspect > 0) {
    final crop = centerCropToAspect(
      Size(oriented.width.toDouble(), oriented.height.toDouble()),
      previewAspect,
    );
    final x = crop.left.round().clamp(0, oriented.width - 1);
    final y = crop.top.round().clamp(0, oriented.height - 1);
    oriented = img.copyCrop(
      oriented,
      x: x,
      y: y,
      width: crop.width.round().clamp(1, oriented.width - x),
      height: crop.height.round().clamp(1, oriented.height - y),
    );
  }
  final frac = mapGuideToImage(
    guide: cropRectFor(angle, focus, viewport: viewport),
    visible: visible,
  );
  final x = (frac.left * oriented.width).round().clamp(0, oriented.width - 1);
  final y = (frac.top * oriented.height).round().clamp(0, oriented.height - 1);
  final w = (frac.width * oriented.width).round().clamp(1, oriented.width - x);
  final h =
      (frac.height * oriented.height).round().clamp(1, oriented.height - y);
  final cropped = img.copyCrop(oriented, x: x, y: y, width: w, height: h);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 96));
}

/// Dim mask + realistic tooth guide (reference art for frontal).
class CameraGuideOverlay extends StatelessWidget {
  const CameraGuideOverlay({
    super.key,
    required this.angle,
    required this.focus,
    this.scale = 0.88,
    this.offset = Offset.zero,
  });

  final String angle;
  final JawFocus focus;

  /// Overlay size as a fraction of the capture frame (clamped to stay inside).
  final double scale;

  /// Pan from the capture-frame center, in preview pixels (clamped so art stays inside).
  final Offset offset;

  static const bothAsset = 'assets/camera/both_teeth_overlay.png';
  static const minScale = 0.50;
  static const maxScale = 1.0;
  static const defaultScale = 0.88;

  /// Max pan from center so a [scale]-sized overlay stays inside [guide].
  static Offset clampOffset(Offset offset, {required Rect guide, required double scale}) {
    final s = scale.clamp(minScale, maxScale);
    final maxDx = guide.width * (1 - s) / 2;
    final maxDy = guide.height * (1 - s) / 2;
    return Offset(
      offset.dx.clamp(-maxDx, maxDx),
      offset.dy.clamp(-maxDy, maxDy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clampedScale = scale.clamp(minScale, maxScale);
    final showTeeth = angle == 'frontal';
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final guide = guideRectForAngle(angle, viewport: size);
        final focusRect = cropRectFor(angle, focus, viewport: size);
        final guidePx = Rect.fromLTRB(
          guide.left * size.width,
          guide.top * size.height,
          guide.right * size.width,
          guide.bottom * size.height,
        );
        final focusPx = Rect.fromLTRB(
          focusRect.left * size.width,
          focusRect.top * size.height,
          focusRect.right * size.width,
          focusRect.bottom * size.height,
        );
        final pan = clampOffset(offset, guide: guidePx, scale: clampedScale);

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _DimAndBracketsPainter(focusPx: focusPx),
            ),
            if (showTeeth) _frontalGuide(guidePx, clampedScale, pan),
          ],
        );
      },
    );
  }

  /// Solidified bite outline, sized/panned within the capture frame.
  Widget _frontalGuide(Rect guidePx, double scale, Offset pan) {
    final w = guidePx.width * scale;
    final h = guidePx.height * scale;
    final full = SizedBox(
      width: w,
      height: h,
      child: const _TeethGuideImage(asset: bothAsset),
    );

    Widget child = full;
    if (focus == JawFocus.top) {
      child = ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 0.55,
          child: full,
        ),
      );
    } else if (focus == JawFocus.bottom) {
      child = ClipRect(
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 0.55,
          child: full,
        ),
      );
    }

    return Positioned(
      left: guidePx.center.dx - w / 2 + pan.dx,
      top: guidePx.center.dy - h / 2 + pan.dy,
      width: w,
      height: h,
      child: Center(child: child),
    );
  }
}

class _TeethGuideImage extends StatelessWidget {
  const _TeethGuideImage({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.92,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _DimAndBracketsPainter extends CustomPainter {
  _DimAndBracketsPainter({required this.focusPx});

  final Rect focusPx;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(focusPx, const Radius.circular(18)),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = const Color(0x99000000));

    final stroke = Paint()
      ..color = const Color(0xE6FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    const len = 22.0;
    final r = focusPx;
    final brackets = Path()
      ..moveTo(r.left, r.top + len)
      ..lineTo(r.left, r.top)
      ..lineTo(r.left + len, r.top)
      ..moveTo(r.right - len, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.top + len)
      ..moveTo(r.right, r.bottom - len)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right - len, r.bottom)
      ..moveTo(r.left + len, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left, r.bottom - len);
    canvas.drawPath(brackets, stroke);
  }

  @override
  bool shouldRepaint(covariant _DimAndBracketsPainter oldDelegate) {
    return oldDelegate.focusPx != focusPx;
  }
}

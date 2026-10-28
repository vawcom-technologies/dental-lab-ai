import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// The app's [ApiClient], so avatars anywhere can resolve protected photo
/// URLs without threading the client through every widget. Set by the
/// client itself.
abstract final class AvatarSource {
  static ApiClient? api;

  /// Bumped when a photo is replaced, so widgets showing it can redraw.
  static final changed = ValueNotifier<int>(0);
}

/// A person's profile photo, or tinted initials when there is none (or it
/// fails to load). Colour comes from the name, so it is stable.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.url, this.size = 42});

  final String name;
  final String? url;
  final double size;

  static const _palette = [
    AppColors.dentalBlue,
    AppColors.review,
    AppColors.success,
    AppColors.warning,
    Color(0xFF3AA5B8),
  ];

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.first[0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();
    final color = _palette[name.hashCode.abs() % _palette.length];
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Text(
        initials,
        style: AppFonts.style(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.34),
      ),
    );
    final raw = url?.trim() ?? '';
    final api = AvatarSource.api;
    if (raw.isEmpty || api == null) return fallback;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipOval(
      child: Image.network(
        api.resolveMediaUrl(raw),
        headers: api.mediaHeaders,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Decode at display size, not the upload's full resolution.
        cacheWidth: (size * dpr).round(),
        gaplessPlayback: true,
        frameBuilder: (_, child, frame, sync) => sync
            ? child
            : AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: child,
              ),
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// Asks "Take photo / Choose from library" and returns a small square-ish
/// JPEG, or null if cancelled.
Future<({Uint8List bytes, String contentType})?> pickProfilePhoto(BuildContext context) async {
  final loc = AppLocalizations.of(context);
  final source = await showCupertinoModalPopup<ImageSource>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: Text(loc.tr('avatar.pickTitle')),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx, ImageSource.camera),
          child: Text(loc.tr('avatar.takePhoto')),
        ),
        CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
          child: Text(loc.tr('avatar.chooseLibrary')),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(ctx),
        child: Text(loc.cancel),
      ),
    ),
  );
  if (source == null) return null;
  // Larger than the final 600px so zooming in while cropping stays sharp.
  final shot = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 90,
    preferredCameraDevice: CameraDevice.front,
  );
  if (shot == null) return null;
  final raw = await shot.readAsBytes();
  if (!context.mounted) return null;
  final cropped = await cropProfilePhoto(context, raw);
  return cropped == null ? null : (bytes: cropped, contentType: 'image/jpeg');
}

/// Opens the circle cropper on [bytes]; returns the square JPEG or null.
Future<Uint8List?> cropProfilePhoto(BuildContext context, Uint8List bytes) =>
    Navigator.of(context).push<Uint8List>(
      CupertinoPageRoute(fullscreenDialog: true, builder: (_) => _PhotoCropper(bytes: bytes)),
    );

/// Pinch and drag the photo inside a circle (with a thirds grid); returns
/// the square under the circle as a 600px JPEG.
class _PhotoCropper extends StatefulWidget {
  const _PhotoCropper({required this.bytes});

  final Uint8List bytes;

  @override
  State<_PhotoCropper> createState() => _PhotoCropperState();
}

class _PhotoCropperState extends State<_PhotoCropper> {
  final _matrix = TransformationController();
  // Decoded once; bakeOrientation so camera shots aren't sideways.
  late final img.Image? _image = () {
    final d = img.decodeImage(widget.bytes);
    return d == null ? null : img.bakeOrientation(d);
  }();
  late final Uint8List _display = _image == null ? widget.bytes : img.encodeJpg(_image, quality: 90);
  double? _side;
  bool _busy = false;

  @override
  void dispose() {
    _matrix.dispose();
    super.dispose();
  }

  /// Scale that makes the image's short side fill the [side] square.
  double _fit(double side) => side / math.min(_image!.width, _image.height);

  void _center(double side) {
    final f = _fit(side);
    _matrix.value = Matrix4.identity()
      ..translateByDouble(-(_image!.width * f - side) / 2, -(_image.height * f - side) / 2, 0, 1);
  }

  Future<void> _done() async {
    final side = _side;
    final image = _image;
    if (side == null || image == null) return;
    setState(() => _busy = true);
    final m = _matrix.value;
    final k = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    final f = _fit(side);
    // Viewport square, in image pixels.
    final int x = (-t.x / k / f).round().clamp(0, image.width - 1).toInt();
    final int y = (-t.y / k / f).round().clamp(0, image.height - 1).toInt();
    final int w = (side / k / f).round().clamp(1, math.min(image.width - x, image.height - y)).toInt();
    final square = img.copyCrop(image, x: x, y: y, width: w, height: w);
    final out = img.encodeJpg(w > 600 ? img.copyResize(square, width: 600, height: 600) : square, quality: 88);
    if (mounted) Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(loc.cancel, style: const TextStyle(color: Colors.white)),
                  ),
                  Expanded(
                    child: Text(
                      loc.tr('avatar.cropTitle'),
                      textAlign: TextAlign.center,
                      style: AppFonts.style(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  CupertinoButton(
                    onPressed: _image == null || _busy ? null : _done,
                    child: Text(
                      loc.tr('avatar.cropDone'),
                      style: AppFonts.style(fontWeight: FontWeight.w700, color: AppColors.dentalBlue),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _image == null
                  ? Center(child: Text(loc.tr('avatar.cropFailed'), style: const TextStyle(color: Colors.white70)))
                  : LayoutBuilder(
                      builder: (context, c) {
                        final side = math.min(c.maxWidth, c.maxHeight) - 48;
                        if (_side != side) {
                          _side = side;
                          _center(side);
                        }
                        final f = _fit(side);
                        return Center(
                          child: SizedBox.square(
                            dimension: side,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                InteractiveViewer(
                                  transformationController: _matrix,
                                  constrained: false,
                                  minScale: 1,
                                  maxScale: 6,
                                  clipBehavior: Clip.none,
                                  child: Image.memory(
                                    _display,
                                    width: _image.width * f,
                                    height: _image.height * f,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                const IgnorePointer(child: CustomPaint(painter: _CropOverlay())),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Text(
                loc.tr('avatar.cropHint'),
                textAlign: TextAlign.center,
                style: AppFonts.style(fontSize: 13, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims outside the circle and draws a rule-of-thirds grid.
class _CropOverlay extends CustomPainter {
  const _CropOverlay();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Path()..addOval(rect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(rect.inflate(400)), circle),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (final f in const [1 / 3, 2 / 3]) {
      canvas.drawLine(Offset(size.width * f, 0), Offset(size.width * f, size.height), line);
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), line);
    }
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CropOverlay old) => false;
}

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/tooth_loader.dart';
import 'camera_guide.dart';

/// Full-screen live camera with angle guide + jaw focus. Pops JPEG bytes.
class LiveCameraCapturePage extends StatefulWidget {
  const LiveCameraCapturePage({
    super.key,
    this.hint = 'Align the tooth / arch, then capture',
    this.angle = 'frontal',
  });

  final String hint;
  final String angle;

  @override
  State<LiveCameraCapturePage> createState() => _LiveCameraCapturePageState();
}

class _LiveCameraCapturePageState extends State<LiveCameraCapturePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _ready = false;
  bool _capturing = false;
  String? _error;
  JawFocus _focus = JawFocus.both;
  double _overlayScale = CameraGuideOverlay.defaultScale;
  double _scaleAtStart = CameraGuideOverlay.defaultScale;
  Offset _overlayOffset = Offset.zero;
  final _previewKey = GlobalKey();

  Offset _clampedOffset(Offset offset, double scale) {
    final box = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return offset;
    final size = box.size;
    final g = guideRectForAngle(widget.angle);
    final guidePx = Rect.fromLTRB(
      g.left * size.width,
      g.top * size.height,
      g.right * size.width,
      g.bottom * size.height,
    );
    return CameraGuideOverlay.clampOffset(
      offset,
      guide: guidePx,
      scale: scale,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _controller = null;
      _ready = false;
    } else if (state == AppLifecycleState.resumed) {
      _start(preferredIndex: _cameraIndex);
    }
  }

  Future<void> _start({int preferredIndex = 0}) async {
    setState(() {
      _error = null;
      _ready = false;
    });
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      _cameras = cameras;
      var index = preferredIndex.clamp(0, cameras.length - 1);
      final back = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (preferredIndex == 0 && back >= 0) index = back;
      await _openCamera(index);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openCamera(int index) async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    final description = _cameras[index];
    final controller = CameraController(
      description,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    _cameraIndex = index;
    await controller.initialize();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _flip() async {
    if (_cameras.length < 2 || _capturing) return;
    AppHaptics.selection();
    final next = (_cameraIndex + 1) % _cameras.length;
    setState(() => _ready = false);
    await _openCamera(next);
  }

  void _resetOverlay() {
    if (_capturing) return;
    AppHaptics.selection();
    setState(() {
      _overlayScale = CameraGuideOverlay.defaultScale;
      _scaleAtStart = CameraGuideOverlay.defaultScale;
      _overlayOffset = Offset.zero;
    });
  }

  Future<void> _pickJawFocus() async {
    if (_capturing) return;
    AppHaptics.selection();
    final picked = await showModalBottomSheet<JawFocus>(
      context: context,
      backgroundColor: const Color(0xFF1A1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Capture focus',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Hold the preview to change. Default is both jaws.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              for (final f in JawFocus.values)
                ListTile(
                  leading: Icon(
                    f == JawFocus.both
                        ? Icons.horizontal_split
                        : f == JawFocus.top
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                    color: Colors.white70,
                  ),
                  title: Text(
                    f.label,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight:
                          f == _focus ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: f == _focus
                      ? const Icon(Icons.check, color: AppColors.dentalBlue)
                      : null,
                  onTap: () => Navigator.pop(ctx, f),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _focus = picked);
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    AppHaptics.medium();
    try {
      final file = await c.takePicture();
      final raw = await file.readAsBytes();
      // Crop to the on-screen guide / jaw band before returning.
      final bytes = cropCaptureToGuide(
        Uint8List.fromList(raw),
        angle: widget.angle,
        focus: _focus,
      );
      AppHaptics.success();
      if (!mounted) return;
      Navigator.of(context).pop<Uint8List>(bytes);
    } catch (e) {
      AppHaptics.warn();
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _capturing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final showTeeth = widget.angle == 'frontal';
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && c != null && c.value.isInitialized)
              Center(
                child: AspectRatio(
                  key: _previewKey,
                  aspectRatio: c.value.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(c),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: _pickJawFocus,
                        onScaleStart: showTeeth
                            ? (_) {
                                _scaleAtStart = _overlayScale;
                              }
                            : null,
                        onScaleUpdate: showTeeth
                            ? (details) {
                                setState(() {
                                  var scale = _overlayScale;
                                  if (details.pointerCount >= 2) {
                                    scale = (_scaleAtStart * details.scale)
                                        .clamp(
                                      CameraGuideOverlay.minScale,
                                      CameraGuideOverlay.maxScale,
                                    );
                                    _overlayScale = scale;
                                  }
                                  _overlayOffset = _clampedOffset(
                                    _overlayOffset + details.focalPointDelta,
                                    scale,
                                  );
                                });
                              }
                            : null,
                        child: CameraGuideOverlay(
                          angle: widget.angle,
                          focus: _focus,
                          scale: _overlayScale,
                          offset: _overlayOffset,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_error == null)
              const Center(
                child: ToothLoadingIndicator(
                  size: 28,
                  compact: true,
                  color: Colors.white,
                ),
              ),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam_off_outlined,
                        color: Colors.white70,
                        size: 36,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, height: 1.35),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => _start(preferredIndex: _cameraIndex),
                        child: const Text('Retry camera'),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                ),
              ),
            ),
            if (_cameras.length > 1 || showTeeth)
              Positioned(
                top: 8,
                right: 8,
                child: Column(
                  children: [
                    if (_cameras.length > 1)
                      IconButton(
                        onPressed: _capturing ? null : _flip,
                        tooltip: 'Switch camera',
                        icon: const Icon(
                          Icons.cameraswitch_outlined,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                        ),
                      ),
                    if (showTeeth) ...[
                      if (_cameras.length > 1) const SizedBox(height: 4),
                      IconButton(
                        onPressed: _capturing ? null : _resetOverlay,
                        tooltip: 'Reset overlay',
                        icon: const Icon(
                          Icons.filter_center_focus,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _pickJawFocus,
                  onLongPress: _pickJawFocus,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      '${widget.angle.toUpperCase()} · ${_focus.label} · hold to change',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 28,
              child: Column(
                children: [
                  Text(
                    widget.hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (showTeeth)
                    Row(
                      children: [
                        const Icon(
                          Icons.photo_size_select_small,
                          color: Colors.white54,
                          size: 18,
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                              overlayColor: Colors.white24,
                            ),
                            child: Slider(
                              value: _overlayScale,
                              min: CameraGuideOverlay.minScale,
                              max: CameraGuideOverlay.maxScale,
                              onChanged: (v) {
                                setState(() {
                                  _overlayScale = v;
                                  _overlayOffset =
                                      _clampedOffset(_overlayOffset, v);
                                });
                              },
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.photo_size_select_large,
                          color: Colors.white54,
                          size: 18,
                        ),
                      ],
                    ),
                  if (showTeeth) const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _ready && !_capturing ? _capture : null,
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: _capturing
                            ? AppColors.dentalBlue.withValues(alpha: 0.5)
                            : Colors.white24,
                      ),
                      child: Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _capturing
                                ? AppColors.dentalBlue
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the live camera UI and returns cropped JPEG bytes.
Future<Uint8List?> captureWithLiveCamera(
  BuildContext context, {
  String hint = 'Align the tooth / arch, then capture',
  String angle = 'frontal',
}) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LiveCameraCapturePage(hint: hint, angle: angle),
    ),
  );
}

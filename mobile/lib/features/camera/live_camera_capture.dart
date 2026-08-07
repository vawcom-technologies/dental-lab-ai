import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/tooth_loader.dart';

/// Full-screen live camera. Pops with JPEG bytes, or null if cancelled.
class LiveCameraCapturePage extends StatefulWidget {
  const LiveCameraCapturePage({
    super.key,
    this.hint = 'Align the tooth / arch, then capture',
  });

  final String hint;

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
      // Prefer back camera for clinical photos when available.
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

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    AppHaptics.medium();
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      AppHaptics.success();
      if (!mounted) return;
      Navigator.of(context).pop<Uint8List>(Uint8List.fromList(bytes));
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_ready && c != null && c.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio,
                  child: CameraPreview(c),
                ),
              )
            else if (_error == null)
              const Center(
                child: ToothLoadingIndicator(size: 28, compact: true, color: Colors.white),
              ),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_outlined,
                          color: Colors.white70, size: 36),
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
            if (_cameras.length > 1)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: _capturing ? null : _flip,
                  icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
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
                  const SizedBox(height: 16),
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

/// Opens the live camera UI and returns captured JPEG bytes.
Future<Uint8List?> captureWithLiveCamera(
  BuildContext context, {
  String hint = 'Align the tooth / arch, then capture',
}) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LiveCameraCapturePage(hint: hint),
    ),
  );
}

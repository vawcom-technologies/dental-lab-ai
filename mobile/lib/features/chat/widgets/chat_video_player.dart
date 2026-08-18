import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/tooth_loader.dart';

String _formatTime(Duration duration) {
  final total = duration.inSeconds.clamp(0, 36000);
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Fullscreen chat video player with scrubbing and skip controls.
/// Playback happens only here — never in the thread preview or inbox.
class ChatVideoPlayerPage extends StatefulWidget {
  const ChatVideoPlayerPage({
    super.key,
    required this.url,
    this.durationSeconds,
  });

  final String url;
  final double? durationSeconds;

  @override
  State<ChatVideoPlayerPage> createState() => _ChatVideoPlayerPageState();
}

class _ChatVideoPlayerPageState extends State<ChatVideoPlayerPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;
  bool _controlsVisible = true;
  Timer? _hideControls;
  double _scrubProgress = 0;

  bool get _ready =>
      _controller != null && _controller!.value.isInitialized;

  Duration get _duration {
    if (_ready && _controller!.value.duration > Duration.zero) {
      return _controller!.value.duration;
    }
    final fallbackMs =
        ((widget.durationSeconds ?? 0) * 1000).round().clamp(0, 36000000);
    return Duration(milliseconds: fallbackMs);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_controller?.pause());
    }
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
    );
    try {
      await controller.initialize();
      await controller.setVolume(1);
      await controller.setLooping(false);
      controller.addListener(() {
        if (!mounted || _scrubbing) return;
        setState(() {});
        final value = controller.value;
        if (value.isInitialized &&
            value.duration > Duration.zero &&
            value.position >= value.duration &&
            !value.isPlaying) {
          _showControls(sticky: true);
        }
      });
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
      if (mounted) _scheduleHideControls();
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _hideControls?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  void _showControls({bool sticky = false}) {
    _hideControls?.cancel();
    setState(() => _controlsVisible = true);
    if (!sticky) _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideControls?.cancel();
    final playing = _controller?.value.isPlaying == true;
    if (!playing) return;
    _hideControls = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_controller?.value.isPlaying == true) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideControls?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      _showControls(sticky: true);
    } else {
      final remaining = controller.value.duration - controller.value.position;
      if (remaining <= const Duration(milliseconds: 400)) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      _showControls();
    }
  }

  Future<void> _skip(Duration delta) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final total = _duration;
    var target = controller.value.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (total > Duration.zero && target > total) target = total;
    await controller.seekTo(target);
    _showControls();
  }

  void _beginScrub(double fraction) {
    if (!_ready || _duration.inMilliseconds <= 0) return;
    _resumeAfterScrub = _controller!.value.isPlaying;
    if (_resumeAfterScrub) unawaited(_controller!.pause());
    setState(() {
      _scrubbing = true;
      _scrubProgress = fraction.clamp(0.0, 1.0);
      _controlsVisible = true;
    });
    _hideControls?.cancel();
  }

  void _updateScrub(double fraction) {
    if (!_scrubbing) return;
    setState(() => _scrubProgress = fraction.clamp(0.0, 1.0));
  }

  Future<void> _endScrub([double? fraction]) async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    final targetFrac = (fraction ?? _scrubProgress).clamp(0.0, 1.0);
    final shouldResume = _resumeAfterScrub;
    final total = _duration;
    setState(() {
      _scrubbing = false;
      _resumeAfterScrub = false;
      _scrubProgress = targetFrac;
    });
    if (total.inMilliseconds > 0) {
      await controller.seekTo(
        Duration(milliseconds: (total.inMilliseconds * targetFrac).round()),
      );
    }
    if (shouldResume && mounted) {
      await controller.play();
      _showControls();
    } else {
      _showControls(sticky: true);
    }
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _failed
              ? _FailedBody(
                  onClose: () => Navigator.of(context).pop(),
                  onOpen: _openExternal,
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _ready ? _toggleControls : null,
                      child: Center(child: _buildStage()),
                    ),
                    if (_controlsVisible || _loading) _buildTopBar(),
                    if (_ready && _controlsVisible) _buildBottomBar(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    if (_loading) {
      return const ToothLoadingIndicator(
        size: 36,
        compact: true,
        color: Colors.white,
      );
    }
    final controller = _controller!;
    final aspect =
        controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9;
    return AspectRatio(
      aspectRatio: aspect,
      child: VideoPlayer(controller),
    );
  }

  Widget _buildTopBar() {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 28),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Open / download',
              onPressed: _openExternal,
              icon: const Icon(Icons.download_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final controller = _controller!;
    final total = _duration;
    final position = _scrubbing
        ? Duration(
            milliseconds:
                (total.inMilliseconds * _scrubProgress).round().clamp(0, 1 << 30),
          )
        : controller.value.position;
    final maxMs = total.inMilliseconds <= 0 ? 1.0 : total.inMilliseconds.toDouble();
    final progress = _scrubbing
        ? _scrubProgress
        : (position.inMilliseconds / maxMs).clamp(0.0, 1.0);
    final playing = controller.value.isPlaying && !_scrubbing;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xE6000000), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 36, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundControl(
                  icon: CupertinoIcons.gobackward_10,
                  onPressed: () => unawaited(_skip(const Duration(seconds: -10))),
                ),
                const SizedBox(width: 28),
                _RoundControl(
                  icon: playing
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  large: true,
                  onPressed: () => unawaited(_togglePlay()),
                ),
                const SizedBox(width: 28),
                _RoundControl(
                  icon: CupertinoIcons.goforward_10,
                  onPressed: () => unawaited(_skip(const Duration(seconds: 10))),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    _formatTime(position),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor: AppColors.dentalBlue,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: AppColors.dentalBlue.withValues(alpha: 0.24),
                    ),
                    child: Slider(
                      value: progress,
                      onChangeStart: _beginScrub,
                      onChanged: _updateScrub,
                      onChangeEnd: (value) => unawaited(_endScrub(value)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    _formatTime(total),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.onPressed,
    this.large = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 44.0;
    return Material(
      color: Colors.white.withValues(alpha: large ? 0.16 : 0.10),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: large ? 30 : 22),
        ),
      ),
    );
  }
}

class _FailedBody extends StatelessWidget {
  const _FailedBody({required this.onClose, required this.onOpen});

  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: IconButton(
            onPressed: onClose,
            icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
          ),
        ),
        const Spacer(),
        const Icon(CupertinoIcons.exclamationmark_circle, color: Colors.white70, size: 40),
        const SizedBox(height: 12),
        const Text(
          'Could not load video',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        TextButton(
          onPressed: onOpen,
          child: const Text('Open / download'),
        ),
        const Spacer(),
      ],
    );
  }
}

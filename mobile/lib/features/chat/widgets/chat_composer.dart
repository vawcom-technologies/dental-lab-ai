import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../../../core/theme/app_theme.dart';
import '../utils/voice_record_path.dart';
import '../widgets/chat_bubble.dart';

typedef SendMediaFn = Future<void> Function({
  required Uint8List fileBytes,
  required String fileName,
  required String mediaType,
  double? durationSeconds,
  String? content,
});

/// Composer with attach sheet + cross-platform voice notes (`record` package).
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onSendMedia,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final SendMediaFn onSendMedia;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _tick;
  bool _recording = false;
  double _elapsedSeconds = 0;
  double _amplitudeNorm = 0;
  DateTime? _recordStartedAt;
  AudioEncoder _activeEncoder = AudioEncoder.aacLc;

  @override
  void dispose() {
    _ampSub?.cancel();
    _tick?.cancel();
    if (_recording) {
      unawaited(_audioRecorder.stop());
    }
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  Future<void> _showAttachSheet() async {
    if (widget.sending) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Attach',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined,
                      color: AppColors.dentalBlue),
                  title: const Text('Photo library'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined,
                      color: AppColors.dentalBlue),
                  title: const Text('Camera'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.attach_file_rounded,
                      color: AppColors.dentalBlue),
                  title: const Text('Document'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickDocument();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2048,
      );
      if (shot == null) return;
      final bytes = await shot.readAsBytes();
      if (bytes.isEmpty) {
        _toast('Could not read the selected image.');
        return;
      }
      final name = shot.name.trim().isNotEmpty
          ? shot.name
          : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await widget.onSendMedia(
        fileBytes: bytes,
        fileName: name,
        mediaType: 'image',
      );
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      Uint8List? bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        final path = picked.path;
        if (path == null || path.isEmpty) {
          _toast('Could not read the selected file.');
          return;
        }
        bytes = await XFile(path).readAsBytes();
      }
      if (bytes.isEmpty) {
        _toast('Could not read the selected file.');
        return;
      }
      final name = picked.name.trim().isNotEmpty
          ? picked.name
          : 'document_${DateTime.now().millisecondsSinceEpoch}.bin';
      await widget.onSendMedia(
        fileBytes: bytes,
        fileName: name,
        mediaType: 'document',
      );
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<AudioEncoder> _resolveEncoder() async {
    final preferred = kIsWeb
        ? const [
            AudioEncoder.wav,
            AudioEncoder.opus,
            AudioEncoder.aacLc,
          ]
        : const [
            AudioEncoder.aacLc,
            AudioEncoder.wav,
          ];
    for (final encoder in preferred) {
      if (await _audioRecorder.isEncoderSupported(encoder)) {
        return encoder;
      }
    }
    return preferred.first;
  }

  String _extensionFor(AudioEncoder encoder) {
    switch (encoder) {
      case AudioEncoder.wav:
        return 'wav';
      case AudioEncoder.opus:
        return 'opus';
      case AudioEncoder.aacLc:
      case AudioEncoder.aacEld:
      case AudioEncoder.aacHe:
        return 'm4a';
      default:
        return 'm4a';
    }
  }

  Future<void> _startRecording() async {
    if (widget.sending || _recording) return;
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _toast('Microphone permission is required for voice notes.');
        return;
      }
      _activeEncoder = await _resolveEncoder();
      final path = await resolveVoiceRecordPath();
      await _audioRecorder.start(
        RecordConfig(encoder: _activeEncoder),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _elapsedSeconds = 0;
        _amplitudeNorm = 0;
        _recordStartedAt = DateTime.now();
      });
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted || _recordStartedAt == null) return;
        setState(() {
          _elapsedSeconds =
              DateTime.now().difference(_recordStartedAt!).inMilliseconds /
                  1000.0;
        });
      });
      await _ampSub?.cancel();
      _ampSub = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
        if (!mounted) return;
        final norm = ((amp.current + 50) / 50).clamp(0.05, 1.0);
        setState(() => _amplitudeNorm = norm);
      });
    } catch (e) {
      _toast('Could not start recording: $e');
    }
  }

  Future<void> _stopRecordingAndSend({bool cancel = false}) async {
    if (!_recording) return;
    _tick?.cancel();
    _tick = null;
    await _ampSub?.cancel();
    _ampSub = null;

    try {
      final path = await _audioRecorder.stop();
      final started = _recordStartedAt;
      final duration = started == null
          ? _elapsedSeconds
          : DateTime.now().difference(started).inMilliseconds / 1000.0;
      if (!mounted) return;
      setState(() {
        _recording = false;
        _elapsedSeconds = 0;
        _amplitudeNorm = 0;
        _recordStartedAt = null;
      });
      if (cancel) return;
      if (path == null || path.isEmpty) {
        _toast('Recording failed — no audio captured.');
        return;
      }
      if (duration < 0.4) {
        _toast('Hold a bit longer to record a voice note.');
        return;
      }
      final bytes = await XFile(path).readAsBytes();
      if (bytes.isEmpty) {
        _toast('Could not read the recorded audio.');
        return;
      }
      final ext = _extensionFor(_activeEncoder);
      await widget.onSendMedia(
        fileBytes: bytes,
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext',
        mediaType: 'voice',
        durationSeconds: duration,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _recording = false;
          _elapsedSeconds = 0;
          _amplitudeNorm = 0;
          _recordStartedAt = null;
        });
      }
      _toast('Could not send voice note: $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceFirst('Exception: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Attach',
            onPressed: widget.sending || _recording ? null : _showAttachSheet,
            icon: const Icon(Icons.attach_file_rounded),
            color: AppColors.navy,
          ),
          Expanded(
            child: _recording
                ? Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.mic, color: AppColors.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _LiveAmplitudeBars(level: _amplitudeNorm),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatVoiceDuration(_elapsedSeconds),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => widget.onSend(),
                    decoration: InputDecoration(
                      hintText: 'Type a message…',
                      filled: true,
                      fillColor: AppColors.neo,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 4),
          if (_recording)
            IconButton(
              tooltip: 'Cancel',
              onPressed: () => _stopRecordingAndSend(cancel: true),
              icon: const Icon(Icons.close_rounded),
              color: AppColors.muted,
            ),
          GestureDetector(
            onLongPressStart: (_) => _startRecording(),
            onLongPressEnd: (_) => _stopRecordingAndSend(),
            onLongPressCancel: () => _stopRecordingAndSend(cancel: true),
            child: IconButton(
              tooltip: _recording ? 'Release to send' : 'Hold to record',
              onPressed: _recording ? () => _stopRecordingAndSend() : () {},
              icon: Icon(
                _recording ? Icons.send_rounded : Icons.mic_none_rounded,
                color: _recording ? AppColors.dentalBlue : AppColors.navy,
              ),
            ),
          ),
          FilledButton(
            onPressed: widget.sending || _recording ? null : widget.onSend,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(14),
            ),
            child: widget.sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _LiveAmplitudeBars extends StatelessWidget {
  const _LiveAmplitudeBars({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const count = 28;
        final w = constraints.maxWidth;
        final barW = (w / (count * 1.6)).clamp(2.0, 4.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(count, (i) {
            final wave = (1 +
                    (i.isEven ? 1 : -1) *
                        0.35 *
                        (1 - (i - count / 2).abs() / (count / 2)))
                .clamp(0.2, 1.0);
            final h = (10 + 22 * level * wave).clamp(4.0, 32.0);
            return Container(
              width: barW,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1.2),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

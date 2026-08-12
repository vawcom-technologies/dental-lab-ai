import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/tooth_loader.dart';
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
    if (_recording) return;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Attach'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.gallery);
            },
            child: const Text('Photo Library'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.camera);
            },
            child: const Text('Camera'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickDocument();
            },
            child: const Text('Document'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
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
    if (_recording) return;
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
    AppSnackBars.error(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE5E5EA)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.sending)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  ToothLoadingIndicator(
                    size: 14,
                    compact: true,
                    color: kToothLoaderBlue,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Uploading…',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.all(6),
                  onPressed: _recording ? null : _showAttachSheet,
                  child: const Icon(
                    CupertinoIcons.add_circled,
                    size: 30,
                    color: AppColors.dentalBlue,
                  ),
                ),
                Expanded(
                  child: _recording
                      ? Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.dangerSoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.mic_fill,
                                color: AppColors.danger,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child:
                                    _LiveAmplitudeBars(level: _amplitudeNorm),
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
                      : ListenableBuilder(
                          listenable: widget.controller,
                          builder: (context, _) {
                            return CupertinoTextField(
                              controller: widget.controller,
                              minLines: 1,
                              maxLines: 5,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              placeholder: 'Message',
                              placeholderStyle: const TextStyle(
                                color: Color(0xFF8E8E93),
                                fontSize: 16,
                              ),
                              style: const TextStyle(
                                fontSize: 16,
                                color: AppColors.navy,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F2F7),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFD1D1D6),
                                ),
                              ),
                              onSubmitted: (_) => widget.onSend(),
                            );
                          },
                        ),
                ),
                const SizedBox(width: 2),
                if (_recording)
                  CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    onPressed: () => _stopRecordingAndSend(cancel: true),
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      size: 28,
                      color: Color(0xFFC7C7CC),
                    ),
                  ),
                GestureDetector(
                  onLongPressStart: (_) => _startRecording(),
                  onLongPressEnd: (_) => _stopRecordingAndSend(),
                  onLongPressCancel: () =>
                      _stopRecordingAndSend(cancel: true),
                  onTap: _recording ? () => _stopRecordingAndSend() : null,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      _recording
                          ? CupertinoIcons.paperplane_fill
                          : CupertinoIcons.mic,
                      size: 26,
                      color: _recording
                          ? AppColors.dentalBlue
                          : AppColors.navy,
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    final canSend =
                        !_recording && widget.controller.text.trim().isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2, left: 2),
                      child: AnimatedOpacity(
                        opacity: canSend ? 1 : 0.35,
                        duration: const Duration(milliseconds: 120),
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: canSend ? widget.onSend : null,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: canSend
                                  ? AppColors.dentalBlue
                                  : const Color(0xFFC7C7CC),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              CupertinoIcons.arrow_up,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
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

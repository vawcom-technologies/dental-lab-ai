import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/tooth_loader.dart';
import '../models/chat_models.dart';
import '../utils/patient_mentions.dart';
import '../utils/voice_gain.dart';
import '../utils/voice_record_path.dart';
import '../utils/video_duration.dart';
import '../widgets/chat_bubble.dart';

typedef SendTextFn = void Function(List<PatientMention> mentions);

typedef SendMediaFn = Future<void> Function({
  Uint8List? fileBytes,
  String? filePath,
  required String fileName,
  required String mediaType,
  double? durationSeconds,
  String? content,
});

const int kChatVideoMaxBytes = 200 * 1024 * 1024;

/// Composer with attach sheet + cross-platform voice notes (`record` package).
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onSendMedia,
    this.patientSession,
  });

  final TextEditingController controller;
  final bool sending;
  final SendTextFn onSend;
  final SendMediaFn onSendMedia;
  final PatientSession? patientSession;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _tick;
  Timer? _holdArm;
  bool _recording = false;
  bool _holdActive = false;
  double _elapsedSeconds = 0;
  double _amplitudeNorm = 0;
  DateTime? _recordStartedAt;
  AudioEncoder _activeEncoder = AudioEncoder.aacLc;
  final List<PatientMention> _pendingMentions = [];
  MentionDraft? _mentionDraft;
  List<Map<String, dynamic>> _mentionHits = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onComposeChanged);
    widget.patientSession?.addListener(_onComposeChanged);
  }

  @override
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onComposeChanged);
      widget.controller.addListener(_onComposeChanged);
    }
    if (oldWidget.patientSession != widget.patientSession) {
      oldWidget.patientSession?.removeListener(_onComposeChanged);
      widget.patientSession?.addListener(_onComposeChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onComposeChanged);
    widget.patientSession?.removeListener(_onComposeChanged);
    _ampSub?.cancel();
    _tick?.cancel();
    _holdArm?.cancel();
    if (_recording) {
      unawaited(_audioRecorder.stop());
    }
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  Future<void> _showAttachSheet() async {
    if (_recording) return;
    final loc = AppLocalizations.of(context);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(loc.messagesAttach),
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
              _pickVideoFromLibrary();
            },
            child: const Text('Video Library'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _recordVideo();
            },
            child: const Text('Record Video'),
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
          child: Text(loc.cancel),
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

  Future<void> _pickVideoFromLibrary() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.video,
        withData: kIsWeb,
        compressionQuality: 0,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      await _sendPickedVideo(
        fileName: picked.name,
        path: picked.path,
        bytes: picked.bytes,
        sizeBytes: picked.size,
      );
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _recordVideo() async {
    try {
      final picker = ImagePicker();
      final shot = await picker.pickVideo(source: ImageSource.camera);
      if (shot == null) return;
      final length = await shot.length();
      await _sendPickedVideo(
        fileName: shot.name.trim().isNotEmpty
            ? shot.name
            : 'video_${DateTime.now().millisecondsSinceEpoch}.mp4',
        path: shot.path,
        sizeBytes: length,
      );
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _sendPickedVideo({
    required String fileName,
    String? path,
    Uint8List? bytes,
    int? sizeBytes,
  }) async {
    final size = sizeBytes ?? bytes?.length ?? 0;
    if (size <= 0) {
      _toast('Could not read the selected video.');
      return;
    }
    if (size > kChatVideoMaxBytes) {
      _toast('Videos must be 200 MB or smaller.');
      return;
    }
    var name = fileName.trim();
    if (name.isEmpty) {
      name = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
    }
    final usePath = path != null && path.isNotEmpty && !kIsWeb;
    Uint8List? payload = bytes;
    if (!usePath && (payload == null || payload.isEmpty)) {
      if (path == null || path.isEmpty) {
        _toast('Could not read the selected video.');
        return;
      }
      payload = await XFile(path).readAsBytes();
      if (payload.isEmpty) {
        _toast('Could not read the selected video.');
        return;
      }
    }
    double? durationSeconds;
    if (usePath) {
      durationSeconds = await probeLocalVideoDuration(path);
    }
    await widget.onSendMedia(
      fileBytes: usePath ? null : payload,
      filePath: usePath ? path : null,
      fileName: name,
      mediaType: 'video',
      durationSeconds: durationSeconds,
    );
  }

  Future<AudioEncoder> _resolveEncoder() async {
    // Prefer WAV so we can peak-normalize quiet mic input before upload.
    const preferred = [
      AudioEncoder.wav,
      AudioEncoder.aacLc,
      AudioEncoder.opus,
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

  Future<void>? _startInFlight;

  Future<void> _startRecording() async {
    if (_recording) return;
    final op = _doStartRecording();
    _startInFlight = op;
    try {
      await op;
    } finally {
      if (identical(_startInFlight, op)) _startInFlight = null;
    }
  }

  Future<void> _doStartRecording() async {
    if (_recording) return;
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _toast('Microphone permission is required for voice notes.');
        return;
      }
      _activeEncoder = await _resolveEncoder();
      final path = await resolveVoiceRecordPath(
        extension: _extensionFor(_activeEncoder),
      );
      await _audioRecorder.start(
        RecordConfig(
          encoder: _activeEncoder,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
          // Helps Android (and iOS stream path). Keep echo/noise off —
          // those processors often attenuate quiet speech.
          autoGain: true,
          echoCancel: false,
          noiseSuppress: false,
          androidConfig: const AndroidRecordConfig(
            audioSource: AndroidAudioSource.mic,
          ),
        ),
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
    final pendingStart = _startInFlight;
    if (pendingStart != null) await pendingStart;
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
      final raw = await XFile(path).readAsBytes();
      if (raw.isEmpty) {
        _toast('Could not read the recorded audio.');
        return;
      }
      final bytes = amplifyVoiceWav(raw);
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

  void _onMicPointerDown() {
    if (widget.sending) return;
    _holdArm?.cancel();
    _holdActive = false;
    // Already recording from a previous tap — wait for pointer up to send.
    if (_recording) return;
    _holdArm = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _holdActive = true;
      unawaited(_startRecording());
    });
  }

  Future<void> _onMicPointerUp() async {
    _holdArm?.cancel();
    _holdArm = null;
    if (widget.sending) return;

    if (_holdActive) {
      _holdActive = false;
      await _stopRecordingAndSend();
      return;
    }

    // Short tap while recording → send. Short tap idle → start (tap mode).
    if (_recording) {
      await _stopRecordingAndSend();
      return;
    }
    await _startRecording();
  }

  Future<void> _onMicPointerCancel() async {
    _holdArm?.cancel();
    _holdArm = null;
    if (_holdActive) {
      _holdActive = false;
      await _stopRecordingAndSend(cancel: true);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    AppSnackBars.error(context, message);
  }

  void _onComposeChanged() {
    if (!mounted || _recording) return;
    final draft = mentionDraftAt(
      widget.controller.text,
      widget.controller.selection.baseOffset,
    );
    List<Map<String, dynamic>> hits = const [];
    if (draft != null) {
      final session = widget.patientSession;
      if (session != null && !session.isLoaded) {
        unawaited(session.ensureLoaded());
      }
      hits = filterPatientsForMention(
        session?.patients ?? const [],
        draft.query,
      );
    }
    final sameDraft = _mentionDraft?.atIndex == draft?.atIndex &&
        _mentionDraft?.query == draft?.query &&
        hits.length == _mentionHits.length;
    if (sameDraft) return;
    setState(() {
      _mentionDraft = draft;
      _mentionHits = hits;
    });
  }

  void _insertMention(Map<String, dynamic> row) {
    final draft = _mentionDraft;
    if (draft == null) return;
    final mention = PatientMention(
      id: '${row['id'] ?? ''}',
      label: patientRowLabel(row),
    );
    if (mention.id.isEmpty) return;
    final next = insertMention(
      text: widget.controller.text,
      cursor: widget.controller.selection.baseOffset,
      draft: draft,
      mention: mention,
    );
    _pendingMentions.removeWhere((m) => m.id == mention.id);
    _pendingMentions.add(mention);
    widget.controller.value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.cursor),
    );
    setState(() {
      _mentionDraft = null;
      _mentionHits = const [];
    });
  }

  void _submitText() {
    if (widget.sending) return;
    final mentions = mentionsPresentIn(
      widget.controller.text,
      _pendingMentions,
    );
    widget.onSend(mentions);
    _pendingMentions.clear();
    setState(() {
      _mentionDraft = null;
      _mentionHits = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
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
          if (!_recording && _mentionDraft != null)
            _PatientMentionPicker(
              query: _mentionDraft!.query,
              hits: _mentionHits,
              loading: widget.patientSession?.loading == true,
              onSelect: _insertMention,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ComposerCircleButton(
                  icon: CupertinoIcons.add,
                  color: AppColors.dentalBlue,
                  background: AppColors.dentalBlue.withValues(alpha: 0.12),
                  onPressed: _recording ? null : _showAttachSheet,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _recording
                      ? Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.dangerSoft,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.2),
                            ),
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
                              placeholder:
                                  AppLocalizations.of(context).messagesPlaceholder,
                              placeholderStyle: const TextStyle(
                                color: Color(0xFF8E8E93),
                                fontSize: 16,
                              ),
                              style: const TextStyle(
                                fontSize: 16,
                                color: AppColors.navy,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                              ),
                              onSubmitted: (_) => _submitText(),
                            );
                          },
                        ),
                ),
                const SizedBox(width: 6),
                if (_recording) ...[
                  _ComposerCircleButton(
                    icon: CupertinoIcons.xmark,
                    color: const Color(0xFF636366),
                    background: const Color(0xFFE5E5EA),
                    onPressed: () => _stopRecordingAndSend(cancel: true),
                  ),
                  const SizedBox(width: 6),
                  _ComposerCircleButton(
                    icon: CupertinoIcons.paperplane_fill,
                    color: Colors.white,
                    background: AppColors.dentalBlue,
                    onPressed: () => _stopRecordingAndSend(),
                  ),
                ] else ...[
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => _onMicPointerDown(),
                    onPointerUp: (_) => unawaited(_onMicPointerUp()),
                    onPointerCancel: (_) => unawaited(_onMicPointerCancel()),
                    child: const _ComposerCircleButton(
                      icon: CupertinoIcons.mic_fill,
                      color: AppColors.navy,
                      background: Color(0xFFE8EDF4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) {
                      final canSend =
                          widget.controller.text.trim().isNotEmpty &&
                              !widget.sending;
                      return _ComposerCircleButton(
                        icon: CupertinoIcons.arrow_up,
                        color: Colors.white,
                        background: canSend
                            ? AppColors.dentalBlue
                            : const Color(0xFFC7C7CC),
                        onPressed: canSend ? _submitText : null,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerCircleButton extends StatelessWidget {
  const _ComposerCircleButton({
    required this.icon,
    required this.color,
    required this.background,
    this.onPressed,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          splashFactory: NoSplash.splashFactory,
          child: Ink(
            decoration: BoxDecoration(
              color: enabled
                  ? background
                  : Color.alphaBlend(
                      background.withValues(alpha: 0.45),
                      Colors.white,
                    ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                icon,
                size: 20,
                color: enabled ? color : color.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
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

class _PatientMentionPicker extends StatelessWidget {
  const _PatientMentionPicker({
    required this.query,
    required this.hits,
    required this.loading,
    required this.onSelect,
  });

  final String query;
  final List<Map<String, dynamic>> hits;
  final bool loading;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Text(
                  query.isEmpty ? 'Tag a patient' : 'Patients matching “$query”',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ),
              if (loading && hits.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: ToothLoadingIndicator(
                      size: 18,
                      compact: true,
                      color: kToothLoaderBlue,
                    ),
                  ),
                )
              else if (hits.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 14),
                  child: Text(
                    'No matching patients',
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 6),
                  itemCount: hits.length,
                  itemBuilder: (context, index) {
                    final row = hits[index];
                    final name = patientRowLabel(row);
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        CupertinoIcons.person_crop_circle,
                        color: AppColors.dentalBlue,
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                      onTap: () => onSelect(row),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

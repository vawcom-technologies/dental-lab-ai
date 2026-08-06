import 'dart:async';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../models/chat_models.dart';
import '../state/chat_controller.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.onBack,
    this.showBack = false,
  });

  final VoidCallback? onBack;
  final bool showBack;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _compose = TextEditingController();
  final _scroll = ScrollController();
  ChatController? _chat;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chat = context.read<ChatController>();
      _chat?.setViewingThread(true);
    });
  }

  @override
  void dispose() {
    _chat?.setViewingThread(false);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _compose.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 80) {
      context.read<ChatController>().loadOlderMessages();
    }
  }

  void _send() {
    final text = _compose.text;
    if (text.trim().isEmpty) return;
    context.read<ChatController>().sendText(text);
    _compose.clear();
  }

  Future<void> _sendMedia({
    required Uint8List fileBytes,
    required String fileName,
    required String mediaType,
    double? durationSeconds,
    String? content,
  }) async {
    await context.read<ChatController>().sendMedia(
          fileBytes: fileBytes,
          fileName: fileName,
          mediaType: mediaType,
          durationSeconds: durationSeconds,
          content: content,
        );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    final active = controller.activeConversation;

    if (active == null) {
      return SectionCard(
        child: Center(
          child: Text(
            'Select a conversation to start messaging',
            style: TextStyle(color: AppColors.muted.withValues(alpha: 0.9)),
          ),
        ),
      );
    }

    final partner = active.partner;
    final messages = controller.messages;

    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _ChatHeader(
            partner: partner,
            connected: controller.socketConnected,
            showBack: widget.showBack,
            onBack: widget.onBack,
          ),
          Divider(height: 1, color: AppColors.border.withValues(alpha: 0.7)),
          if (controller.threadError != null)
            Container(
              width: double.infinity,
              color: AppColors.dangerSoft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                controller.threadError!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
          Expanded(
            child: controller.loadingMessages && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet — say hello.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          final me = controller.currentUserId;
                          String? lastSeenMineId;
                          if (me != null) {
                            for (var i = messages.length - 1; i >= 0; i--) {
                              final m = messages[i];
                              if (m.senderId == me && m.isRead) {
                                lastSeenMineId = m.id;
                                break;
                              }
                            }
                          }
                          return ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                            itemCount: messages.length +
                                (controller.loadingOlder ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (controller.loadingOlder &&
                                  index == messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final message =
                                  messages[messages.length - 1 - index];
                              final mine =
                                  me != null && message.senderId == me;
                              return ChatMessageBubble(
                                message: message,
                                mine: mine,
                                showSeenEye: mine &&
                                    lastSeenMineId != null &&
                                    message.id == lastSeenMineId,
                                onReply: () =>
                                    controller.setReplyTo(message),
                              );
                            },
                          );
                        },
                      ),
          ),
          if (controller.replyTo != null)
            _ReplyPreviewBar(
              message: controller.replyTo!,
              onClear: controller.clearReply,
            ),
          _Composer(
            controller: _compose,
            sending: controller.sending,
            onSend: _send,
            onSendMedia: _sendMedia,
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.partner,
    required this.connected,
    required this.showBack,
    this.onBack,
  });

  final UserProfile partner;
  final bool connected;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          CircleAvatar(
            backgroundColor: AppColors.dentalBlue.withValues(alpha: 0.15),
            child: Text(
              partner.displayName.isNotEmpty
                  ? partner.displayName.characters.first.toUpperCase()
                  : '?',
              style: const TextStyle(
                color: AppColors.dentalBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partner.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: connected
                            ? AppColors.success
                            : AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        connected
                            ? (partner.subtitle.isEmpty
                                ? 'Connected'
                                : partner.subtitle)
                            : 'Reconnecting…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyPreviewBar extends StatelessWidget {
  const _ReplyPreviewBar({
    required this.message,
    required this.onClear,
  });

  final Message message;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.dentalBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Replying to…',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dentalBlue,
                  ),
                ),
                Text(
                  message.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}

typedef _SendMediaFn = Future<void> Function({
  required Uint8List fileBytes,
  required String fileName,
  required String mediaType,
  double? durationSeconds,
  String? content,
});

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onSendMedia,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final _SendMediaFn onSendMedia;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  late final RecorderController _recorder;
  StreamSubscription<Duration>? _durationSub;
  bool _recording = false;
  double _elapsedSeconds = 0;
  DateTime? _recordStartedAt;

  bool get _voiceSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    _recorder = RecorderController();
    _durationSub = _recorder.onCurrentDuration.listen((d) {
      if (mounted) setState(() => _elapsedSeconds = d.inMilliseconds / 1000.0);
    });
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    if (_recording) {
      unawaited(_recorder.stop());
    }
    _recorder.dispose();
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
        // Native platforms may omit in-memory bytes; XFile works without dart:io.
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

  Future<void> _startRecording() async {
    if (widget.sending || _recording) return;
    if (!_voiceSupported) {
      _toast('Voice notes are supported on iOS and Android.');
      return;
    }
    try {
      final hasPermission = await _recorder.checkPermission();
      if (!hasPermission) {
        _toast('Microphone permission is required for voice notes.');
        return;
      }
      // Let the plugin choose a temp path — avoid dart:io / path_provider.
      await _recorder.record(recorderSettings: const RecorderSettings());
      if (!mounted) return;
      setState(() {
        _recording = true;
        _elapsedSeconds = 0;
        _recordStartedAt = DateTime.now();
      });
    } catch (e) {
      _toast('Could not start recording: $e');
    }
  }

  Future<void> _stopRecordingAndSend({bool cancel = false}) async {
    if (!_recording) return;
    try {
      final path = await _recorder.stop();
      final started = _recordStartedAt;
      final duration = started == null
          ? _elapsedSeconds
          : DateTime.now().difference(started).inMilliseconds / 1000.0;
      if (!mounted) return;
      setState(() {
        _recording = false;
        _elapsedSeconds = 0;
        _recordStartedAt = null;
      });
      if (cancel || path == null || path.isEmpty) return;
      if (duration < 0.4) {
        _toast('Hold a bit longer to record a voice note.');
        return;
      }
      final bytes = await XFile(path).readAsBytes();
      if (bytes.isEmpty) {
        _toast('Could not read the recorded audio.');
        return;
      }
      final lower = path.toLowerCase();
      final ext = lower.endsWith('.wav')
          ? 'wav'
          : lower.endsWith('.aac')
              ? 'aac'
              : 'm4a';
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
                          child: AudioWaveforms(
                            size: const Size(double.infinity, 36),
                            recorderController: _recorder,
                            waveStyle: const WaveStyle(
                              waveColor: AppColors.danger,
                              extendWaveform: true,
                              showMiddleLine: false,
                              spacing: 4,
                            ),
                          ),
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
              onPressed: _recording
                  ? () => _stopRecordingAndSend()
                  : () {
                      if (!_voiceSupported) {
                        _toast(
                          'Voice notes are supported on iOS and Android.',
                        );
                      }
                    },
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

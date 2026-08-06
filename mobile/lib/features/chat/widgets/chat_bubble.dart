import 'dart:async';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../models/chat_models.dart';

/// Formats voice duration as `m:ss`.
String formatVoiceDuration(double? seconds) {
  final total = (seconds ?? 0).clamp(0, 36000).round();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _fileExtension(String? url) {
  if (url == null || url.isEmpty) return 'FILE';
  final name = p.basename(Uri.tryParse(url)?.path ?? url);
  final ext = p.extension(name).replaceFirst('.', '').toUpperCase();
  return ext.isEmpty ? 'FILE' : (ext.length > 5 ? ext.substring(0, 5) : ext);
}

String _fileName(String? url) {
  if (url == null || url.isEmpty) return 'Document';
  final name = p.basename(Uri.tryParse(url)?.path ?? url);
  return name.isEmpty ? 'Document' : name;
}

/// Chat bubble that renders text and/or media (voice / image / document).
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.onReply,
    this.showSeenEye = false,
  });

  final Message message;
  final bool mine;
  final VoidCallback onReply;
  final bool showSeenEye;

  @override
  Widget build(BuildContext context) {
    final time = message.createdAt != null
        ? DateFormat.Hm().format(message.createdAt!.toLocal())
        : '';
    final fg = mine ? Colors.white : AppColors.navy;
    final muted = mine ? Colors.white70 : AppColors.muted;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onReply,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity!.abs() > 200) {
            onReply();
          }
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.72,
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                margin: EdgeInsets.only(bottom: showSeenEye ? 2 : 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                decoration: BoxDecoration(
                  color: mine ? AppColors.dentalBlue : AppColors.neo,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 16),
                  ),
                  boxShadow: NeoShadows.soft(depth: 0.35),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.replyTo != null) ...[
                      _ReplyQuote(
                        label: message.replyTo!.previewLabel,
                        mine: mine,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (message.isVoice && message.hasMedia)
                      VoiceNoteBubble(
                        url: message.mediaUrl!,
                        durationSeconds: message.durationSeconds,
                        mine: mine,
                      )
                    else if (message.isImage && message.hasMedia)
                      ImageMessageBubble(
                        url: message.mediaUrl!,
                        mine: mine,
                      )
                    else if (message.isDocument && message.hasMedia)
                      DocumentMessageBubble(
                        url: message.mediaUrl!,
                        mine: mine,
                      )
                    else if (message.hasMedia && !message.isVoice)
                      DocumentMessageBubble(
                        url: message.mediaUrl!,
                        mine: mine,
                      ),
                    if (message.content.trim().isNotEmpty) ...[
                      if (message.hasMedia) const SizedBox(height: 8),
                      Text(
                        message.content,
                        style: TextStyle(color: fg, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      time,
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ),
              if (showSeenEye)
                const Padding(
                  padding: EdgeInsets.only(right: 4, bottom: 8),
                  child: Icon(
                    Icons.remove_red_eye_outlined,
                    size: 14,
                    color: AppColors.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.label, required this.mine});

  final String label;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: (mine ? Colors.white : AppColors.navy).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: mine ? Colors.white70 : AppColors.dentalBlue,
            width: 3,
          ),
        ),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: mine ? Colors.white70 : AppColors.muted,
        ),
      ),
    );
  }
}

/// Playable voice note with waveform bars.
class VoiceNoteBubble extends StatefulWidget {
  const VoiceNoteBubble({
    super.key,
    required this.url,
    required this.mine,
    this.durationSeconds,
  });

  final String url;
  final bool mine;
  final double? durationSeconds;

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  late final PlayerController _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<int>? _posSub;
  bool _ready = false;
  bool _failed = false;
  int _positionMs = 0;
  int _maxMs = 0;

  @override
  void initState() {
    super.initState();
    _player = PlayerController();
    _stateSub = _player.onPlayerStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _posSub = _player.onCurrentDurationChanged.listen((ms) {
      if (mounted) setState(() => _positionMs = ms);
    });
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await _player.preparePlayer(
        path: widget.url,
        shouldExtractWaveform: true,
        noOfSamples: 48,
      );
      await _player.setFinishMode(finishMode: FinishMode.stop);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _maxMs = _player.maxDuration;
        if (_maxMs <= 0 && widget.durationSeconds != null) {
          _maxMs = (widget.durationSeconds! * 1000).round();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_player.playerState.isPlaying) {
      await _player.pausePlayer();
    } else {
      await _player.startPlayer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.mine ? Colors.white : AppColors.dentalBlue;
    final waveFixed = widget.mine ? Colors.white38 : AppColors.border;
    final waveLive = widget.mine ? Colors.white : AppColors.dentalBlue;
    final labelSeconds = _maxMs > 0
        ? _maxMs / 1000.0
        : widget.durationSeconds;
    final progressLabel = _player.playerState.isPlaying
        ? formatVoiceDuration(_positionMs / 1000.0)
        : formatVoiceDuration(labelSeconds);

    if (_failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_off_rounded, color: accent, size: 20),
          const SizedBox(width: 8),
          Text(
            'Voice note · ${formatVoiceDuration(widget.durationSeconds)}',
            style: TextStyle(
              color: widget.mine ? Colors.white : AppColors.navy,
              fontSize: 13,
            ),
          ),
        ],
      );
    }

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          IconButton(
            onPressed: _ready ? _toggle : null,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              _player.playerState.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: accent,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_ready)
                  AudioFileWaveforms(
                    size: const Size(160, 36),
                    playerController: _player,
                    waveformType: WaveformType.fitWidth,
                    continuousWaveform: true,
                    playerWaveStyle: PlayerWaveStyle(
                      fixedWaveColor: waveFixed,
                      liveWaveColor: waveLive,
                      spacing: 4,
                      waveThickness: 2.5,
                      showSeekLine: false,
                    ),
                  )
                else
                  SizedBox(
                    height: 36,
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  progressLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.mine ? Colors.white70 : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ImageMessageBubble extends StatelessWidget {
  const ImageMessageBubble({
    super.key,
    required this.url,
    required this.mine,
  });

  final String url;
  final bool mine;

  void _openLightbox(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => _ImageLightbox(url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openLightbox(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 260,
            maxHeight: 280,
            minWidth: 140,
            minHeight: 100,
          ),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(
              height: 160,
              color: (mine ? Colors.white : AppColors.navy)
                  .withValues(alpha: 0.08),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: mine ? Colors.white70 : AppColors.dentalBlue,
                  ),
                ),
              ),
            ),
            errorWidget: (_, _, _) => Container(
              height: 100,
              alignment: Alignment.center,
              child: Icon(
                Icons.broken_image_outlined,
                color: mine ? Colors.white70 : AppColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageLightbox extends StatelessWidget {
  const _ImageLightbox({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(color: Colors.black54),
          ),
          Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, _) => const CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DocumentMessageBubble extends StatelessWidget {
  const DocumentMessageBubble({
    super.key,
    required this.url,
    required this.mine,
  });

  final String url;
  final bool mine;

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final fg = mine ? Colors.white : AppColors.navy;
    final badge = _fileExtension(url);
    final name = _fileName(url);

    return Material(
      color: (mine ? Colors.white : AppColors.navy).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: mine
                      ? Colors.white.withValues(alpha: 0.18)
                      : AppColors.dentalBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.insert_drive_file_rounded,
                      size: 16,
                      color: mine ? Colors.white : AppColors.dentalBlue,
                    ),
                    Text(
                      badge,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: mine ? Colors.white70 : AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: mine ? Colors.white70 : AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

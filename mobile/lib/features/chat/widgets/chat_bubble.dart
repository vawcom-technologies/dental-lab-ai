import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
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

Future<void> _openMediaUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
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

/// Cross-platform voice playback via [just_audio] (Web / Android / iOS).
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
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  bool _ready = false;
  bool _failed = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _stateSub = _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _posSub = _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _durSub = _player.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final d = await _player.setUrl(widget.url);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _duration = d ??
            Duration(
              milliseconds:
                  ((widget.durationSeconds ?? 0) * 1000).round().clamp(0, 36000000),
            );
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_duration.inMilliseconds > 0 &&
          _position >= _duration - const Duration(milliseconds: 200)) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.mine ? Colors.white : AppColors.dentalBlue;
    final track = widget.mine ? Colors.white38 : AppColors.border;
    final labelSeconds = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds / 1000.0
        : widget.durationSeconds;
    final progressLabel = _player.playing
        ? formatVoiceDuration(_position.inMilliseconds / 1000.0)
        : formatVoiceDuration(labelSeconds);

    if (_failed) {
      return Row(
        children: [
          IconButton(
            onPressed: () => _openMediaUrl(widget.url),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Open audio',
            icon: Icon(Icons.open_in_new_rounded, color: accent, size: 20),
          ),
          Expanded(
            child: Text(
              'Voice note · ${formatVoiceDuration(widget.durationSeconds)}',
              style: TextStyle(
                color: widget.mine ? Colors.white : AppColors.navy,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    }

    final maxMs = _duration.inMilliseconds <= 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final value = (_position.inMilliseconds.toDouble()).clamp(0.0, maxMs);

    return SizedBox(
      width: 240,
      child: Row(
        children: [
          IconButton(
            onPressed: _ready ? _toggle : null,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              _player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: accent,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_ready)
                  SizedBox(
                    height: 28,
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
                  )
                else
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: accent,
                      inactiveTrackColor: track,
                      thumbColor: accent,
                    ),
                    child: Slider(
                      min: 0,
                      max: maxMs,
                      value: value,
                      onChanged: (v) {
                        setState(
                          () => _position = Duration(milliseconds: v.round()),
                        );
                      },
                      onChangeEnd: (v) async {
                        await _player.seek(Duration(milliseconds: v.round()));
                      },
                    ),
                  ),
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

/// Image bubble: web uses HTML `<img>` to avoid CanvasKit EncodingError;
/// tap opens lightbox with download/open actions.
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
    final placeholderColor =
        (mine ? Colors.white : AppColors.navy).withValues(alpha: 0.08);
    final iconColor = mine ? Colors.white70 : AppColors.muted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
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
              child: _ChatNetworkImage(
                url: url,
                fit: BoxFit.cover,
                placeholderColor: placeholderColor,
                iconColor: iconColor,
                height: 160,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _openLightbox(context),
              icon: Icon(
                Icons.fullscreen_rounded,
                size: 16,
                color: mine ? Colors.white70 : AppColors.dentalBlue,
              ),
              label: Text(
                'View',
                style: TextStyle(
                  fontSize: 12,
                  color: mine ? Colors.white70 : AppColors.dentalBlue,
                ),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => _openMediaUrl(url),
              icon: Icon(
                Icons.download_rounded,
                size: 16,
                color: mine ? Colors.white70 : AppColors.dentalBlue,
              ),
              label: Text(
                'Download',
                style: TextStyle(
                  fontSize: 12,
                  color: mine ? Colors.white70 : AppColors.dentalBlue,
                ),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChatNetworkImage extends StatelessWidget {
  const _ChatNetworkImage({
    required this.url,
    required this.fit,
    required this.placeholderColor,
    required this.iconColor,
    this.height,
  });

  final String url;
  final BoxFit fit;
  final Color placeholderColor;
  final Color iconColor;
  final double? height;

  @override
  Widget build(BuildContext context) {
    // On web, prefer HTML <img> so browsers can paint cross-origin images
    // without CanvasKit decode (avoids EncodingError).
    return Image.network(
      url,
      fit: fit,
      height: height,
      width: double.infinity,
      webHtmlElementStrategy: kIsWeb
          ? WebHtmlElementStrategy.prefer
          : WebHtmlElementStrategy.never,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          height: height ?? 160,
          color: placeholderColor,
          alignment: Alignment.center,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: iconColor,
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) {
        return Container(
          height: height ?? 120,
          color: placeholderColor,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: iconColor, size: 28),
              const SizedBox(height: 8),
              Text(
                'Could not preview',
                style: TextStyle(color: iconColor, fontSize: 12),
              ),
              TextButton(
                onPressed: () => _openMediaUrl(url),
                child: Text(
                  'Open / download',
                  style: TextStyle(color: iconColor, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
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
              child: _ChatNetworkImage(
                url: url,
                fit: BoxFit.contain,
                placeholderColor: Colors.black26,
                iconColor: Colors.white70,
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Download / open',
                    onPressed: () => _openMediaUrl(url),
                    icon: const Icon(Icons.download_rounded, color: Colors.white),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
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

  @override
  Widget build(BuildContext context) {
    final fg = mine ? Colors.white : AppColors.navy;
    final badge = _fileExtension(url);
    final name = _fileName(url);

    return Material(
      color: (mine ? Colors.white : AppColors.navy).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _openMediaUrl(url),
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
                Icons.download_rounded,
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

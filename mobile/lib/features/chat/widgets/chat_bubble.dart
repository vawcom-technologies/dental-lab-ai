import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/tooth_loader.dart';
import '../models/chat_models.dart';
import '../utils/patient_mentions.dart';
import 'chat_video_player.dart';

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

/// iMessage-like bubble colors (kept on-brand with dental blue for sent).
abstract final class _BubbleColors {
  static const mine = Color(0xFF4A90E2);
  static const theirs = Color(0xFFE9E9EB);
  static const theirsFg = Color(0xFF1C1C1E);
}

/// Chat bubble that renders text and/or media (voice / image / document).
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.onReply,
    this.onPatientMention,
    this.showSeenEye = false,
  });

  final Message message;
  final bool mine;
  final VoidCallback onReply;
  final ValueChanged<String>? onPatientMention;
  final bool showSeenEye;

  bool get _mediaOnly =>
      message.hasMedia &&
      !message.isPending &&
      message.content.trim().isEmpty &&
      message.replyTo == null;

  @override
  Widget build(BuildContext context) {
    final time = message.createdAt != null
        ? DateFormat.jm().format(message.createdAt!.toLocal())
        : '';
    final fg = mine ? Colors.white : _BubbleColors.theirsFg;
    final muted = mine ? Colors.white.withValues(alpha: 0.72) : AppColors.muted;
    final bubbleMax = math.min(340.0, MediaQuery.sizeOf(context).width * 0.55);

    final hasText =
        !message.isPending && message.content.trim().isNotEmpty;
    final hasMediaBody = !message.isPending && message.hasMedia &&
        (message.isVoice ||
            message.isImage ||
            message.isDocument ||
            message.hasMedia);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Align(
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
            constraints: BoxConstraints(maxWidth: bubbleMax),
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: _mediaOnly && (message.isImage || message.isVideo)
                          ? EdgeInsets.zero
                          : EdgeInsets.fromLTRB(
                              hasMediaBody && !hasText ? 10 : 14,
                              hasMediaBody && !hasText ? 10 : 10,
                              hasMediaBody && !hasText ? 10 : 14,
                              8,
                            ),
                      decoration: BoxDecoration(
                        color: _mediaOnly && (message.isImage || message.isVideo)
                            ? Colors.transparent
                            : (mine
                                ? _BubbleColors.mine
                                : _BubbleColors.theirs),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(mine ? 18 : 5),
                          bottomRight: Radius.circular(mine ? 5 : 18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.replyTo != null) ...[
                            _ReplyQuote(
                              label: message.replyTo!.previewLabel,
                              mine: mine,
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (message.isPending)
                            Padding(
                              padding: const EdgeInsets.only(right: 22, bottom: 2),
                              child: Text(
                                message.previewText,
                                style: TextStyle(
                                  color: muted,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 16,
                                  height: 1.3,
                                ),
                              ),
                            )
                          else if (message.isVoice && message.hasMedia)
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
                          else if (message.isVideo && message.hasMedia)
                            VideoMessageBubble(
                              url: message.mediaUrl!,
                              mine: mine,
                              durationSeconds: message.durationSeconds,
                            )
                          else if (message.hasMedia)
                            DocumentMessageBubble(
                              url: message.mediaUrl!,
                              mine: mine,
                            ),
                          if (hasText) ...[
                            if (hasMediaBody) const SizedBox(height: 6),
                            _MentionRichText(
                              text: message.content,
                              mentions: message.mentionedPatients,
                              style: TextStyle(
                                color: fg,
                                fontSize: 16,
                                height: 1.28,
                              ),
                              mentionColor: mine
                                  ? Colors.white
                                  : AppColors.dentalBlue,
                              onMentionTap: onPatientMention,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (message.isPending)
                      Positioned(
                        top: 8,
                        right: mine ? 10 : null,
                        left: mine ? null : 10,
                        child: ToothLoadingIndicator(
                          size: 16,
                          compact: true,
                          color: mine ? Colors.white : kToothLoaderBlue,
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(
                    top: 3,
                    bottom: showSeenEye ? 2 : 8,
                    left: mine ? 0 : 4,
                    right: mine ? 4 : 0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (showSeenEye) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          CupertinoIcons.eye,
                          size: 12,
                          color: AppColors.muted,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _MentionRichText extends StatefulWidget {
  const _MentionRichText({
    required this.text,
    required this.mentions,
    required this.style,
    required this.mentionColor,
    this.onMentionTap,
  });

  final String text;
  final List<PatientMention> mentions;
  final TextStyle style;
  final Color mentionColor;
  final ValueChanged<String>? onMentionTap;

  @override
  State<_MentionRichText> createState() => _MentionRichTextState();
}

class _MentionRichTextState extends State<_MentionRichText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final spans = mentionSpansIn(widget.text, widget.mentions);
    if (spans.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    final children = <InlineSpan>[];
    var cursor = 0;
    for (final span in spans) {
      if (span.start > cursor) {
        children.add(TextSpan(text: widget.text.substring(cursor, span.start)));
      }
      final id = span.mention.id;
      final recognizer = TapGestureRecognizer()
        ..onTap = widget.onMentionTap == null
            ? null
            : () => widget.onMentionTap!(id);
      _recognizers.add(recognizer);
      children.add(
        TextSpan(
          text: widget.text.substring(span.start, span.end),
          style: widget.style.copyWith(
            color: widget.mentionColor,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: widget.mentionColor.withValues(alpha: 0.7),
          ),
          recognizer: recognizer,
        ),
      );
      cursor = span.end;
    }
    if (cursor < widget.text.length) {
      children.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: widget.style, children: children),
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
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: (mine ? Colors.white : AppColors.navy).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
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
          fontSize: 13,
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
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;
  double _scrubProgress = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  Duration get _effectiveDuration {
    if (_duration.inMilliseconds > 0) return _duration;
    final fallbackMs =
        ((widget.durationSeconds ?? 0) * 1000).round().clamp(0, 36000000);
    return Duration(milliseconds: fallbackMs);
  }

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    // Slight boost for older quiet notes; new recordings are peak-normalized.
    unawaited(_player.setVolume(1.6));
    _stateSub = _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _posSub = _player.positionStream.listen((pos) {
      if (!mounted || _scrubbing) return;
      setState(() => _position = pos);
    });
    _durSub = _player.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await _player.setVolume(1.6);
      final d = await _player.setUrl(widget.url);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _duration = d ??
            Duration(
              milliseconds: ((widget.durationSeconds ?? 0) * 1000)
                  .round()
                  .clamp(0, 36000000),
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

  Future<void> _seekToFraction(double fraction) async {
    if (!_ready) return;
    final total = _effectiveDuration;
    if (total.inMilliseconds <= 0) return;
    final clamped = fraction.clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (total.inMilliseconds * clamped).round(),
    );
    setState(() {
      _position = target;
      _scrubProgress = clamped;
    });
    await _player.seek(target);
  }

  void _beginScrub(double fraction) {
    if (!_ready || _effectiveDuration.inMilliseconds <= 0) return;
    _resumeAfterScrub = _player.playing;
    if (_resumeAfterScrub) unawaited(_player.pause());
    setState(() {
      _scrubbing = true;
      _scrubProgress = fraction.clamp(0.0, 1.0);
      _position = Duration(
        milliseconds:
            (_effectiveDuration.inMilliseconds * _scrubProgress).round(),
      );
    });
  }

  void _updateScrub(double fraction) {
    if (!_scrubbing) return;
    setState(() {
      _scrubProgress = fraction.clamp(0.0, 1.0);
      _position = Duration(
        milliseconds:
            (_effectiveDuration.inMilliseconds * _scrubProgress).round(),
      );
    });
  }

  Future<void> _endScrub([double? fraction]) async {
    if (!_scrubbing && fraction == null) return;
    final target = (fraction ?? _scrubProgress).clamp(0.0, 1.0);
    final shouldResume = _resumeAfterScrub;
    setState(() {
      _scrubbing = false;
      _resumeAfterScrub = false;
      _scrubProgress = target;
      _position = Duration(
        milliseconds: (_effectiveDuration.inMilliseconds * target).round(),
      );
    });
    await _seekToFraction(target);
    if (shouldResume && mounted) await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.mine ? Colors.white : AppColors.dentalBlue;
    final totalSeconds = _effectiveDuration.inMilliseconds / 1000.0;
    final displaySeconds = _scrubbing || _player.playing || _position > Duration.zero
        ? _position.inMilliseconds / 1000.0
        : totalSeconds;
    final progressLabel = formatVoiceDuration(displaySeconds);

    if (_failed) {
      return SizedBox(
        width: 200,
        child: Row(
          children: [
            Icon(CupertinoIcons.exclamationmark_circle, color: accent, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => _openMediaUrl(widget.url),
                child: Text(
                  'Voice · ${formatVoiceDuration(widget.durationSeconds)}',
                  style: TextStyle(
                    color: widget.mine ? Colors.white : _BubbleColors.theirsFg,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final maxMs = _effectiveDuration.inMilliseconds <= 0
        ? 1.0
        : _effectiveDuration.inMilliseconds.toDouble();
    final progress = _scrubbing
        ? _scrubProgress
        : (_position.inMilliseconds / maxMs).clamp(0.0, 1.0);

    return SizedBox(
      width: 210,
      child: Row(
        children: [
          GestureDetector(
            onTap: _ready ? _toggle : null,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: widget.mine
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: !_ready
                  ? ToothLoadingIndicator(
                      size: 14,
                      compact: true,
                      color: accent,
                    )
                  : Icon(
                      _player.playing
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      size: 16,
                      color: accent,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _VoiceWaveform(
                  progress: progress,
                  mine: widget.mine,
                  playing: _player.playing && !_scrubbing,
                  enabled: _ready && _effectiveDuration.inMilliseconds > 0,
                  onScrubStart: _beginScrub,
                  onScrubUpdate: _updateScrub,
                  onScrubEnd: (fraction) => unawaited(_endScrub(fraction)),
                ),
                const SizedBox(height: 4),
                Text(
                  progressLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: widget.mine
                        ? Colors.white.withValues(alpha: 0.75)
                        : AppColors.muted,
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

class _VoiceWaveform extends StatelessWidget {
  const _VoiceWaveform({
    required this.progress,
    required this.mine,
    required this.playing,
    required this.enabled,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  final double progress;
  final bool mine;
  final bool playing;
  final bool enabled;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;

  double _fractionFor(Offset local, double width) {
    if (width <= 0) return 0;
    return (local.dx / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    const count = 24;
    final active = mine ? Colors.white : AppColors.dentalBlue;
    final idle = mine
        ? Colors.white.withValues(alpha: 0.35)
        : const Color(0xFFC7C7CC);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled
              ? (details) {
                  final f = _fractionFor(details.localPosition, width);
                  onScrubStart(f);
                  onScrubEnd(f);
                }
              : null,
          onHorizontalDragStart: enabled
              ? (details) =>
                  onScrubStart(_fractionFor(details.localPosition, width))
              : null,
          onHorizontalDragUpdate: enabled
              ? (details) =>
                  onScrubUpdate(_fractionFor(details.localPosition, width))
              : null,
          onHorizontalDragEnd: enabled
              ? (_) => onScrubEnd(progress)
              : null,
          onHorizontalDragCancel: enabled ? () => onScrubEnd(progress) : null,
          child: SizedBox(
            height: 28,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(count, (i) {
                final t = i / (count - 1);
                final wave = 0.35 +
                    0.65 *
                        (0.55 +
                            0.45 *
                                math.sin(i * 0.9) *
                                math.cos(i * 0.35));
                final h = (22 * wave).clamp(4.0, 22.0);
                final filled = t <= progress;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.8),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: playing ? 120 : 0),
                      height: playing && filled ? h * 1.05 : h,
                      decoration: BoxDecoration(
                        color: filled ? active : idle,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

/// Image bubble: tap opens lightbox. No inline action buttons (iMessage-like).
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

    return GestureDetector(
      onTap: () => _openLightbox(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 220,
          height: 200,
          child: _ChatNetworkImage(
            url: url,
            fit: BoxFit.cover,
            placeholderColor: placeholderColor,
            iconColor: iconColor,
            height: 200,
          ),
        ),
      ),
    );
  }
}

/// Static video preview in the thread. Playback only happens in [ChatVideoPlayerPage].
class VideoMessageBubble extends StatelessWidget {
  const VideoMessageBubble({
    super.key,
    required this.url,
    required this.mine,
    this.durationSeconds,
  });

  final String url;
  final bool mine;
  final double? durationSeconds;

  void _openPlayer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChatVideoPlayerPage(
          url: url,
          durationSeconds: durationSeconds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholderColor =
        (mine ? Colors.white : AppColors.navy).withValues(alpha: 0.10);
    final durationLabel = (durationSeconds ?? 0) > 0.4
        ? formatVoiceDuration(durationSeconds)
        : null;

    return GestureDetector(
      onTap: () => _openPlayer(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 220,
          height: 148,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1C1C1E),
                      Color.alphaBlend(
                        placeholderColor,
                        const Color(0xFF2C2C2E),
                      ),
                    ],
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    CupertinoIcons.play_fill,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              Positioned(
                left: 10,
                bottom: 8,
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.videocam_fill,
                      color: Colors.white,
                      size: 14,
                    ),
                    if (durationLabel != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        durationLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
          child: ToothLoadingIndicator(
            size: 24,
            compact: true,
            color: iconColor,
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
    final fg = mine ? Colors.white : _BubbleColors.theirsFg;
    final badge = _fileExtension(url);
    final name = _fileName(url);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openMediaUrl(url),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 240,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: mine
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.doc_fill,
                      size: 15,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.arrow_down_circle,
                size: 20,
                color: mine ? Colors.white70 : AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

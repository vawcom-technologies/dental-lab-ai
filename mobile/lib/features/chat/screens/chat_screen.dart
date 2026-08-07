import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../models/chat_models.dart';
import '../state/chat_controller.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_composer.dart';

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
                ? const ToothPageLoader(message: 'Loading chat…')
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
                                    child: ToothLoadingIndicator(size: 28),
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
          ChatComposer(
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

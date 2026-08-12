import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../models/chat_models.dart';
import '../state/chat_controller.dart';

/// Soft list selection (iPadOS Messages-style).
const _kSelectedRow = Color(0xFFE8F1FB);
const _kSeparator = Color(0xFFC6C6C8);
const _kSearchFill = Color(0xFFE5E5EA);

class InboxScreen extends StatelessWidget {
  const InboxScreen({
    super.key,
    this.onConversationSelected,
    this.onNewChat,
    this.embedded = false,
  });

  /// Called after a conversation is opened (useful when not embedded).
  final ValueChanged<Conversation>? onConversationSelected;
  final VoidCallback? onNewChat;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final controller = context.watch<ChatController>();
    final rows = controller.visibleConversations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!embedded)
          PageHeader(
            icon: Icons.chat_bubble_outline,
            title: loc.messagesTitle,
            subtitle: controller.socketConnected
                ? 'Live · ${controller.totalUnread} unread'
                : 'Reconnecting…',
            chromeActions: [
              AppButtons.icon(
                tooltip: loc.refresh,
                onPressed:
                    controller.loadingInbox ? null : controller.loadInbox,
                icon: Icons.refresh_rounded,
              ),
              if (onNewChat != null)
                AppButtons.icon(
                  tooltip: 'New chat',
                  onPressed: onNewChat,
                  icon: Icons.edit_square,
                ),
            ],
          ),
        if (!embedded) const SizedBox(height: 12),
        Expanded(
          child: SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoSearchTextField(
                          placeholder: 'Search',
                          backgroundColor: _kSearchFill,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.navy,
                          ),
                          onChanged: controller.setInboxQuery,
                        ),
                      ),
                      if (onNewChat != null)
                        CupertinoButton(
                          padding: const EdgeInsets.only(left: 4),
                          onPressed: onNewChat,
                          child: const Icon(
                            CupertinoIcons.square_pencil,
                            size: 24,
                            color: AppColors.dentalBlue,
                          ),
                        ),
                    ],
                  ),
                ),
                if (controller.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      controller.error!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ),
                Expanded(
                  child: controller.loadingInbox && rows.isEmpty
                      ? const ToothPageLoader(message: 'Loading conversations…')
                      : rows.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      CupertinoIcons.bubble_left_bubble_right,
                                      size: 40,
                                      color: Color(0xFFC7C7CC),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      controller.inboxQuery.isEmpty
                                          ? 'No conversations yet.'
                                          : 'No conversations match your search.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (onNewChat != null &&
                                        controller.inboxQuery.isEmpty) ...[
                                      const SizedBox(height: 16),
                                      CupertinoButton.filled(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 10,
                                        ),
                                        onPressed: onNewChat,
                                        child: const Text('Start a chat'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              color: AppColors.dentalBlue,
                              onRefresh: controller.loadInbox,
                              child: ListView.builder(
                                itemCount: rows.length,
                                itemBuilder: (context, i) {
                                  final c = rows[i];
                                  final selected =
                                      controller.activeConversation?.id ==
                                          c.id;
                                  return _ConversationTile(
                                    conversation: c,
                                    selected: selected,
                                    showDivider: i < rows.length - 1,
                                    enabled: !controller.loadingMessages,
                                    onTap: () async {
                                      await controller.openConversation(c);
                                      onConversationSelected?.call(c);
                                    },
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
    required this.showDivider,
    this.enabled = true,
  });

  final Conversation conversation;
  final bool selected;
  final VoidCallback onTap;
  final bool showDivider;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final partner = conversation.partner;
    final preview = conversation.lastMessage?.previewText.isNotEmpty == true
        ? conversation.lastMessage!.previewText
        : 'No messages yet';
    final time = conversation.lastMessage?.createdAt ??
        conversation.updatedAt ??
        conversation.createdAt;
    final unread = conversation.unreadCount;
    final subtitle = partner.subtitle.trim();
    final previewLine = subtitle.isEmpty ? preview : '$subtitle · $preview';

    return Material(
      color: selected ? _kSelectedRow : Colors.white,
      child: InkWell(
        onTap: enabled ? onTap : null,
        splashColor: AppColors.dentalBlue.withValues(alpha: 0.08),
        highlightColor: AppColors.dentalBlue.withValues(alpha: 0.04),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor:
                        AppColors.dentalBlue.withValues(alpha: 0.14),
                    child: Text(
                      partner.displayName.isNotEmpty
                          ? partner.displayName.characters.first.toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: AppColors.dentalBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                partner.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: unread > 0
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: AppColors.navy,
                                  fontSize: 17,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (time != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                _formatInboxTime(time),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: unread > 0
                                      ? AppColors.dentalBlue
                                      : const Color(0xFF8E8E93),
                                  fontWeight: unread > 0
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                CupertinoIcons.chevron_forward,
                                size: 14,
                                color: Color(0xFFC7C7CC),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                previewLine,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.25,
                                  color: unread > 0
                                      ? const Color(0xFF3A3A3C)
                                      : const Color(0xFF8E8E93),
                                  fontWeight: unread > 0
                                      ? FontWeight.w500
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.dentalBlue,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  unread > 99 ? '99+' : '$unread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              const Padding(
                padding: EdgeInsets.only(left: 66),
                child: Divider(height: 0.5, thickness: 0.5, color: _kSeparator),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatInboxTime(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) return DateFormat.jm().format(local);
  final yesterday = now.subtract(const Duration(days: 1));
  if (local.year == yesterday.year &&
      local.month == yesterday.month &&
      local.day == yesterday.day) {
    return 'Yesterday';
  }
  return DateFormat.MMMd().format(local);
}

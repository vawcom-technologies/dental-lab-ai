import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../models/chat_models.dart';
import '../state/chat_controller.dart';

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

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!embedded)
              PageHeader(
                icon: Icons.chat_bubble_outline,
                title: loc.messagesTitle,
                subtitle: controller.socketConnected
                    ? 'Live · ${controller.totalUnread} unread'
                    : 'Reconnecting…',
                actions: [
                  IconButton(
                    tooltip: loc.refresh,
                    onPressed:
                        controller.loadingInbox ? null : controller.loadInbox,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                  if (onNewChat != null)
                    IconButton(
                      tooltip: 'New chat',
                      onPressed: onNewChat,
                      icon: const Icon(Icons.edit_square, size: 20),
                    ),
                ],
              ),
            if (!embedded) const SizedBox(height: 12),
            SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              depth: 0.7,
              child: TextField(
                onChanged: controller.setInboxQuery,
                decoration: const InputDecoration(
                  hintText: 'Search conversations…',
                  prefixIcon: Icon(Icons.search, color: AppColors.muted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 10),
              Text(
                controller.error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: SectionCard(
                padding: EdgeInsets.zero,
                child: controller.loadingInbox && rows.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : rows.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    controller.inboxQuery.isEmpty
                                        ? 'No conversations yet.'
                                        : 'No conversations match your search.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: AppColors.muted),
                                  ),
                                  if (onNewChat != null &&
                                      controller.inboxQuery.isEmpty) ...[
                                    const SizedBox(height: 14),
                                    FilledButton.icon(
                                      onPressed: onNewChat,
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('Start a chat'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: controller.loadInbox,
                            child: ListView.separated(
                              itemCount: rows.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color:
                                    AppColors.border.withValues(alpha: 0.7),
                              ),
                              itemBuilder: (context, i) {
                                final c = rows[i];
                                final selected =
                                    controller.activeConversation?.id == c.id;
                                return _ConversationTile(
                                  conversation: c,
                                  selected: selected,
                                  onTap: () async {
                                    await controller.openConversation(c);
                                    onConversationSelected?.call(c);
                                  },
                                );
                              },
                            ),
                          ),
              ),
            ),
          ],
        ),
        if (onNewChat != null)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'inbox_new_chat',
              tooltip: 'New chat',
              backgroundColor: AppColors.dentalBlue,
              onPressed: onNewChat,
              child: const Icon(Icons.add_comment_rounded, color: Colors.white),
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
  });

  final Conversation conversation;
  final bool selected;
  final VoidCallback onTap;

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

    return Material(
      color: selected
          ? AppColors.sidebarActive.withValues(alpha: 0.65)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            partner.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  unread > 0 ? FontWeight.w800 : FontWeight.w600,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                        if (time != null)
                          Text(
                            _formatInboxTime(time),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                      ],
                    ),
                    if (partner.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        partner.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: unread > 0 ? AppColors.navy : AppColors.muted,
                        fontWeight:
                            unread > 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread > 0) ...[
                const SizedBox(width: 8),
                Container(
                  constraints:
                      const BoxConstraints(minWidth: 22, minHeight: 22),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
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
  if (sameDay) return DateFormat.Hm().format(local);
  final yesterday = now.subtract(const Duration(days: 1));
  if (local.year == yesterday.year &&
      local.month == yesterday.month &&
      local.day == yesterday.day) {
    return 'Yesterday';
  }
  return DateFormat.MMMd().format(local);
}

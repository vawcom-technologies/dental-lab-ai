import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../models/chat_models.dart';
import '../state/chat_controller.dart';

/// Soft glass selection (iPadOS Messages / liquid glass).
const _kSelectedGlass = Color(0x66FFFFFF);
const _kHairline = Color(0x33FFFFFF);

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
                onPressed: controller.loadingInbox
                    ? null
                    : () => controller.loadInbox(forceRefresh: true),
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
          child: GlassSurface(
            borderRadius: BorderRadius.circular(28),
            blur: 28,
            tint: Colors.white.withValues(alpha: 0.42),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.72),
              width: 1.1,
            ),
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _GlassSearchField(
                          onChanged: controller.setInboxQuery,
                        ),
                      ),
                      if (onNewChat != null) ...[
                        const SizedBox(width: 6),
                        _GlassIconButton(
                          tooltip: 'New chat',
                          icon: CupertinoIcons.square_pencil,
                          onPressed: onNewChat,
                        ),
                      ],
                    ],
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
                                    Container(
                                      width: 72,
                                      height: 72,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withValues(
                                          alpha: 0.45,
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.7,
                                          ),
                                        ),
                                      ),
                                      child: const Icon(
                                        CupertinoIcons
                                            .bubble_left_bubble_right,
                                        size: 34,
                                        color: Color(0xFF8E8E93),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      controller.inboxQuery.isEmpty
                                          ? 'No conversations yet.'
                                          : 'No conversations match your search.',
                                      textAlign: TextAlign.center,
                                      style: AppFonts.style(
                                        color: AppColors.muted,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (onNewChat != null &&
                                        controller.inboxQuery.isEmpty) ...[
                                      const SizedBox(height: 16),
                                      AppButtons.primary(
                                        onPressed: onNewChat,
                                        icon: Icons.edit_square,
                                        label: 'Start a chat',
                                        compact: true,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              color: AppColors.dentalBlue,
                              onRefresh: () =>
                                  controller.loadInbox(forceRefresh: true),
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  0,
                                  10,
                                  12,
                                ),
                                itemCount: rows.length,
                                itemBuilder: (context, i) {
                                  final c = rows[i];
                                  final selected =
                                      controller.activeConversation?.id ==
                                          c.id;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: _ConversationTile(
                                      conversation: c,
                                      selected: selected,
                                      enabled: !controller.loadingMessages,
                                      onTap: () async {
                                        await controller.openConversation(c);
                                        onConversationSelected?.call(c);
                                      },
                                    ),
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

class _GlassSearchField extends StatelessWidget {
  const _GlassSearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.68),
        ),
      ),
      child: CupertinoSearchTextField(
        placeholder: 'Search',
        backgroundColor: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        prefixIcon: const Icon(
          CupertinoIcons.search,
          color: Color(0xFF8E8E93),
        ),
        style: AppFonts.style(
          fontSize: 16,
          color: AppColors.navy,
          fontWeight: FontWeight.w500,
        ),
        placeholderStyle: AppFonts.style(
          fontSize: 16,
          color: const Color(0xFF8E8E93),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        splashFactory: NoSplash.splashFactory,
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          child: Icon(icon, size: 22, color: AppColors.dentalBlue),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final Conversation conversation;
  final bool selected;
  final VoidCallback onTap;
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
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppColors.dentalBlue.withValues(alpha: 0.06),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: selected
                ? _kSelectedGlass
                : Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.85)
                  : _kHairline,
              width: selected ? 1.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.dentalBlue.withValues(alpha: 0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _GlassAvatar(name: partner.displayName),
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
                            style: AppFonts.style(
                              fontWeight: unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: AppColors.navy,
                              fontSize: 17,
                              letterSpacing: -0.25,
                            ),
                          ),
                        ),
                        if (time != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatInboxTime(time),
                            style: AppFonts.style(
                              fontSize: 13,
                              color: unread > 0
                                  ? AppColors.dentalBlue
                                  : const Color(0xFF8E8E93),
                              fontWeight: unread > 0
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            CupertinoIcons.chevron_forward,
                            size: 13,
                            color: Colors.black.withValues(alpha: 0.22),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            previewLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.style(
                              fontSize: 14.5,
                              height: 1.28,
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
                              minWidth: 22,
                              minHeight: 22,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.dentalBlue,
                                  AppColors.dentalBlue.withValues(alpha: 0.85),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(11),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.dentalBlue.withValues(
                                    alpha: 0.28,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: AppFonts.style(
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
      ),
    );
  }
}

class _GlassAvatar extends StatelessWidget {
  const _GlassAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty
        ? name.trim().characters.first.toUpperCase()
        : '?';
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.dentalBlue.withValues(alpha: 0.28),
            AppColors.navy.withValues(alpha: 0.18),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.75),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.dentalBlue.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        initial,
        style: AppFonts.style(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
          fontSize: 18,
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

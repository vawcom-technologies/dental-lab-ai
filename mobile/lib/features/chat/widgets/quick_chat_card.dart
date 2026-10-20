import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/auth/app_roles.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/date_formats.dart';
import '../../../core/navigation/app_page_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/page_kit.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shell/app_sidebar.dart';
import '../../admin/admin_top_bar.dart';
import '../models/chat_models.dart';
import 'user_profile_sheet.dart';

/// Latest conversations. Tapping one opens the thread right here in the
/// card (iOS push from the right); "Open" goes to the Messages page.
class QuickChatCard extends StatefulWidget {
  const QuickChatCard({this.fill = true, this.active = true});

  final bool fill;

  /// Dashboard visible; read receipts are only sent while it is.
  final bool active;

  @override
  State<QuickChatCard> createState() => _QuickChatState();
}

class _QuickChatState extends State<QuickChatCard> {
  Conversation? _open;
  AdminChrome? _chrome;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chrome = AdminChrome.maybeOf(context);
  }

  @override
  void didUpdateWidget(QuickChatCard old) {
    super.didUpdateWidget(old);
    if (_open == null || old.active == widget.active) return;
    final chat = _chrome!.chat;
    if (widget.active) {
      // Messages may have switched the active thread meanwhile.
      chat.openConversation(_open!);
      chat.setViewingThread(true);
    } else {
      chat.setViewingThread(false);
    }
  }

  @override
  void dispose() {
    if (_open != null) _chrome?.chat.setViewingThread(false);
    super.dispose();
  }

  void _show(Conversation c) {
    final chat = _chrome!.chat;
    setState(() => _open = c);
    chat.openConversation(c);
    chat.setViewingThread(true);
  }

  void _back() {
    _chrome!.chat.setViewingThread(false);
    setState(() => _open = null);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final chrome = _chrome;
    if (chrome == null) return const SizedBox.shrink();
    final fill = widget.fill;
    return ListenableBuilder(
      listenable: chrome.chat,
      builder: (context, _) {
        final convs = [...chrome.chat.conversations]
          ..sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
        final open = _open;
        final Widget body;
        if (open != null) {
          body = KeyedSubtree(
            key: const ValueKey('thread'),
            child: _InlineThread(
              conv: open,
              onBack: _back,
              // Single column: give the thread a fixed body height.
              height: fill ? null : 360,
            ),
          );
        } else if (convs.isEmpty) {
          body = KeyedSubtree(
            key: const ValueKey('list'),
            child: PanelEmpty(icon: Icons.chat_bubble_outline_rounded, color: AppColors.dentalBlue, text: loc.tr('admin.noChats')),
          );
        } else {
          body = ListView(
            key: const ValueKey('list'),
            shrinkWrap: !fill,
            physics: fill ? null : const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              for (final (i, c) in convs.take(5).indexed)
                AdminAppear(index: i, child: _ChatRow(conv: c, onTap: () => _show(c))),
            ],
          );
        }
        return PanelCard(
          fill: fill,
          title: loc.tr('admin.quickChat'),
          subtitle: chrome.chat.totalUnread > 0 ? plural(loc, 'admin.unreadCount', chrome.chat.totalUnread) : loc.tr('admin.quickChatSub'),
          // Open: the Messages page, on this thread if one is showing.
          action: (
            loc.tr('admin.openMessages'),
            () => open == null ? chrome.onOpen(AppNavItem.messages, 0) : chrome.openChat(open),
          ),
          child: ClipRect(
            child: AnimatedSize(
              duration: AppMotion.normal,
              curve: AppMotion.spring,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: AppMotion.page,
                reverseDuration: AppMotion.page,
                switchInCurve: AppMotion.spring,
                switchOutCurve: AppMotion.spring,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  fit: fill ? StackFit.expand : StackFit.loose,
                  children: [...previous, ?current],
                ),
                transitionBuilder: (child, a) {
                  // Thread pushes in from the right; the list sits slightly left
                  // underneath, like a navigation stack.
                  final thread = child.key == const ValueKey('thread');
                  return SlideTransition(
                    position: Tween(
                      begin: thread ? const Offset(1, 0) : const Offset(-0.3, 0),
                      end: Offset.zero,
                    ).animate(a),
                    child: FadeTransition(opacity: thread ? const AlwaysStoppedAnimation(1) : a, child: child),
                  );
                },
                child: body,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Chat with [userId] in a sheet over the current page (lab Review, My lab),
/// so nobody has to find the person again on Messages.
Future<void> messageUser(BuildContext context, String userId) async {
  final chrome = AdminChrome.maybeOf(context);
  if (chrome == null || userId.isEmpty) return;
  final Conversation conv;
  try {
    conv = await AppDialogs.runWithLoading(context, action: () => chrome.chat.openOrCreateWith(userId));
  } catch (e) {
    if (context.mounted) AppSnackBars.error(context, friendlyError(e));
    return;
  }
  if (!context.mounted) return;
  chrome.chat.setViewingThread(true);
  await AppDialogs.sheet<void>(
    context: context,
    maxWidth: 520,
    // Routes sit above the shell: hand the thread the shell's chrome again.
    builder: (ctx) => AdminChrome(
      api: chrome.api,
      inbox: chrome.inbox,
      chat: chrome.chat,
      onOpen: chrome.onOpen,
      openChat: chrome.openChat,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 14, 14),
        child: ListenableBuilder(
          listenable: chrome.chat,
          builder: (ctx, _) => _InlineThread(conv: conv, onBack: () => Navigator.pop(ctx), height: 380),
        ),
      ),
    ),
  );
  chrome.chat.setViewingThread(false);
}

/// One conversation inside the quick chat card: header with back, messages,
/// and a composer.
class _InlineThread extends StatefulWidget {
  const _InlineThread({required this.conv, required this.onBack, this.height});

  final Conversation conv;
  final VoidCallback onBack;
  final double? height;

  @override
  State<_InlineThread> createState() => _InlineThreadState();
}

class _InlineThreadState extends State<_InlineThread> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send(AdminChrome chrome) {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    chrome.chat.sendText(t);
    _text.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final chrome = AdminChrome.maybeOf(context)!;
    final chat = chrome.chat;
    final c = widget.conv;
    final name = (c.partner.name ?? '').trim().isEmpty ? (c.partner.email ?? '—') : c.partner.name!.trim();
    final showing = chat.activeConversation?.id == c.id;
    final messages = showing ? chat.messages : const <Message>[];
    final me = chat.currentUserId;

    final list = !showing || (chat.loadingMessages && messages.isEmpty)
        ? const Center(child: CupertinoActivityIndicator())
        : messages.isEmpty
            ? Center(
                child: Text(loc.tr('admin.chatEmpty'), style: AppFonts.style(fontSize: 13, color: AppColors.muted)),
              )
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: messages.length,
                itemBuilder: (context, i) {
                  final m = messages[messages.length - 1 - i];
                  return _Bubble(message: m, mine: m.senderId == me);
                },
              );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppButtons.icon(onPressed: widget.onBack, icon: Icons.arrow_back_ios_new_rounded, tooltip: loc.tr('admin.back')),
            Expanded(
              child: Pressable(
                onTap: () => showUserProfileSheet(context, c.partner),
                scale: 0.98,
                builder: (_, _) => Row(
                  children: [
                    UserAvatar(name: name, url: c.partner.avatarUrl, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navy)),
                          if (c.partner.role != null)
                            Text(AppRoles.label(c.partner.role, loc),
                                style: AppFonts.style(fontSize: 11.5, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Divider(height: 12, color: AppColors.border.withValues(alpha: 0.5)),
        if (widget.height == null) Expanded(child: list) else SizedBox(height: widget.height, child: list),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _text,
                placeholder: loc.tr('admin.chatPlaceholder'),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(chrome),
                onChanged: (_) => setState(() {}),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                style: AppFonts.style(fontSize: 14.5, color: AppColors.navy),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedScale(
              scale: _text.text.trim().isEmpty ? 0.85 : 1,
              duration: AppMotion.fast,
              curve: AppMotion.spring,
              child: Pressable(
                onTap: _text.text.trim().isEmpty ? null : () => _send(chrome),
                enabled: _text.text.trim().isNotEmpty,
                scale: 0.9,
                builder: (_, _) => AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _text.text.trim().isEmpty ? AppColors.border : AppColors.navy,
                    shape: BoxShape.circle,
                  ),
                  child: Tooltip(
                    message: loc.tr('admin.send'),
                    child: const Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    return column;
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final m = message;
    final media = m.isImage
        ? (Icons.photo_outlined, loc.tr('admin.chatPhoto'))
        : m.isVoice
            ? (Icons.mic_none_rounded, loc.tr('admin.chatVoice'))
            : m.isVideo
                ? (Icons.videocam_outlined, loc.tr('admin.chatVideo'))
                : m.hasMedia
                    ? (Icons.description_outlined, loc.tr('admin.chatDocument'))
                    : null;
    final fg = mine ? Colors.white : AppColors.navy;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: mine ? AppColors.navy : AppColors.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (media != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(media.$1, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(media.$2, style: AppFonts.style(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
                  ],
                ),
              if (m.content.trim().isNotEmpty)
                Text(m.content, style: AppFonts.style(fontSize: 13.5, height: 1.3, color: fg)),
              if (m.createdAt != null)
                Text(
                  formatAppTime(context, m.createdAt!.toLocal()),
                  style: AppFonts.style(fontSize: 10.5, color: fg.withValues(alpha: 0.6)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.conv, required this.onTap});

  final Conversation conv;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (conv.partner.name ?? '').trim().isEmpty ? (conv.partner.email ?? '—') : conv.partner.name!.trim();
    final unread = conv.unreadCount > 0;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      builder: (_, pressed) => AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: pressed ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            UserAvatar(name: name, url: conv.partner.avatarUrl, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(fontSize: 14, fontWeight: unread ? FontWeight.w700 : FontWeight.w600, color: AppColors.navy)),
                  Text(conv.lastMessage?.content ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(fontSize: 12.5, color: unread ? AppColors.navy : AppColors.muted)),
                ],
              ),
            ),
            if (unread)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: AppColors.dentalBlue, borderRadius: BorderRadius.circular(999)),
                child: Text('${conv.unreadCount}', style: AppFonts.style(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}

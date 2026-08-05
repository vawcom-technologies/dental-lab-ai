import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/layout/adaptive.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'screens/chat_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/select_contact_screen.dart';
import 'services/chat_api_service.dart';
import 'state/chat_controller.dart';

/// Messages hub: real-time inbox + 1-to-1 chat (`/api/conversations` + `/ws/chat`).
class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    required this.api,
    this.onUnreadChanged,
  });

  final ApiClient api;
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  late final ChatController _controller;
  bool _showThread = false;

  @override
  void initState() {
    super.initState();
    _controller = ChatController(api: widget.api);
    _controller.addListener(_onControllerChanged);
    _controller.start();
  }

  void _onControllerChanged() {
    widget.onUnreadChanged?.call(_controller.totalUnread);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openNewChat() async {
    final conversation = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<ChatController>.value(
          value: _controller,
          child: SelectContactScreen(
            onConversationOpened: (_) {
              if (MediaQuery.sizeOf(context).width < 900) {
                setState(() => _showThread = true);
              }
            },
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (conversation != null && MediaQuery.sizeOf(context).width < 900) {
      setState(() => _showThread = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 900;

    return ChangeNotifierProvider<ChatController>.value(
      value: _controller,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                return PageHeader(
                  icon: Icons.chat_bubble_outline,
                  title: loc.messagesTitle,
                  subtitle: _controller.socketConnected
                      ? 'Live · ${_controller.totalUnread} unread'
                      : 'Connecting to live chat…',
                  actions: [
                    IconButton(
                      tooltip: 'New chat',
                      onPressed: _openNewChat,
                      icon: const Icon(Icons.edit_square, size: 20),
                      color: AppColors.dentalBlue,
                    ),
                    IconButton(
                      tooltip: loc.refresh,
                      onPressed: _controller.loadingInbox
                          ? null
                          : _controller.loadInbox,
                      icon: const Icon(Icons.refresh, size: 20),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: narrow
                  ? (_showThread
                      ? ChatScreen(
                          showBack: true,
                          onBack: () => setState(() => _showThread = false),
                        )
                      : InboxScreen(
                          embedded: true,
                          onNewChat: _openNewChat,
                          onConversationSelected: (_) {
                            setState(() => _showThread = true);
                          },
                        ))
                  : AdaptiveSplit(
                      panel: InboxScreen(
                        embedded: true,
                        onNewChat: _openNewChat,
                        onConversationSelected: (_) {},
                      ),
                      content: const ChatScreen(),
                      panelFraction: 0.36,
                      minPanelWidth: 280,
                      maxPanelWidth: 420,
                      narrowPanelHeight: 320,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience for shell badge without opening Messages.
Future<int> fetchChatUnreadTotal(ApiClient api) async {
  try {
    final list = await ChatApiService(api).fetchConversations();
    return list.fold<int>(0, (sum, c) => sum + c.unreadCount);
  } catch (_) {
    return 0;
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/layout/adaptive.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/session/patient_session.dart';
import '../../core/widgets/ui_kit.dart';
import 'screens/chat_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/select_contact_screen.dart';
import 'state/chat_controller.dart';

/// Messages hub: real-time inbox + 1-to-1 chat (`/api/conversations` + `/ws/chat`).
///
/// Pass [chatController] from [AppShell] so inbox/WS stay warm after login.
class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    required this.api,
    this.chatController,
    this.patientSession,
    this.onUnreadChanged,
  });

  final ApiClient api;
  final ChatController? chatController;
  final PatientSession? patientSession;
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  late final ChatController _controller;
  late final bool _ownsController;
  bool _showThread = false;

  @override
  void initState() {
    super.initState();
    if (widget.chatController != null) {
      _controller = widget.chatController!;
      _ownsController = false;
    } else {
      _controller = ChatController(api: widget.api);
      _ownsController = true;
      _controller.start();
    }
    _controller.addListener(_onControllerChanged);
    // Ensure latest inbox when opening the page.
    _controller.loadInbox();
  }

  void _onControllerChanged() {
    widget.onUnreadChanged?.call(_controller.totalUnread);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    final controller = _controller;
    final owns = _ownsController;
    super.dispose();
    if (owns) {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
  }

  Future<void> _openNewChat() async {
    final conversation = await Navigator.of(context).push(
      AppPageRoutes.cupertino(
        ChangeNotifierProvider<ChatController>.value(
          value: _controller,
          child: SelectContactScreen(
            onConversationOpened: (_) {
              if (MediaQuery.sizeOf(context).width < 900) {
                setState(() => _showThread = true);
              }
            },
          ),
        ),
        title: 'New Message',
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
    // Prefer screen width (stable when keyboard opens) so we don't swap
    // AnimatedSwitcher ↔ AdaptiveSplit and drop composer focus.
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
                  icon: Icons.chat_bubble_outline_rounded,
                  title: loc.messagesTitle,
                  subtitle: loc.messagesSubtitle,
                );
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: narrow
                  ? AnimatedSwitcher(
                      duration: AppMotion.normal,
                      switchInCurve: AppMotion.easeOut,
                      switchOutCurve: AppMotion.easeIn,
                      // One pane only — no stacked overlay (iPadOS drill-in style).
                      layoutBuilder: (currentChild, previousChildren) {
                        return currentChild ?? const SizedBox.shrink();
                      },
                      transitionBuilder: (child, animation) {
                        final slide = Tween<Offset>(
                          begin: Offset(_showThread ? 0.06 : -0.06, 0),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: slide,
                            child: child,
                          ),
                        );
                      },
                      child: _showThread
                          ? KeyedSubtree(
                              key: const ValueKey('thread'),
                              child: ChatScreen(
                                showBack: true,
                                patientSession: widget.patientSession,
                                onBack: () {
                                  _controller.setViewingThread(false);
                                  setState(() => _showThread = false);
                                },
                              ),
                            )
                          : KeyedSubtree(
                              key: const ValueKey('inbox'),
                              child: InboxScreen(
                                embedded: true,
                                onNewChat: _openNewChat,
                                onConversationSelected: (_) {
                                  setState(() => _showThread = true);
                                },
                              ),
                            ),
                    )
                  : AdaptiveSplit(
                      panel: InboxScreen(
                        embedded: true,
                        onNewChat: _openNewChat,
                        onConversationSelected: (_) {},
                        onSwipeCloseChat: () {
                          if (_controller.activeConversation != null) {
                            _controller.clearActiveConversation();
                          }
                        },
                      ),
                      content: ChatScreen(
                        patientSession: widget.patientSession,
                        onClose: () => _controller.clearActiveConversation(),
                      ),
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

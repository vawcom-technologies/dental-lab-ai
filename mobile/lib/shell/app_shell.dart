import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/theme/app_theme.dart';
import '../features/camera/camera_page.dart';
import '../features/chat/messages_page.dart';
import '../features/chat/state/chat_controller.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/laboratories/laboratories_page.dart';
import '../features/notifications/notifications_page.dart';
import '../features/patients/new_patient_page.dart';
import '../features/patients/patients_page.dart';
import '../features/reports/reports_page.dart';
import '../features/scan_body/scan_body_page.dart';
import '../features/scans/scans_page.dart';
import '../features/settings/settings_page.dart';
import '../features/shade/shade_page.dart';
import '../features/shapes/shape_overlay_page.dart';
import 'app_sidebar.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.api,
    required this.dentistName,
  });

  final ApiClient api;
  final String dentistName;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _pageIn = Duration(milliseconds: 320);
  static const _pageOut = Duration(milliseconds: 220);

  AppNavItem _active = AppNavItem.dashboard;
  int _patientRefresh = 0;
  late String _dentistName;
  int _notificationBadge = 0;
  int _messageBadge = 0;
  bool _sidebarCollapsed = false;
  late final ChatController _chat;

  @override
  void initState() {
    super.initState();
    _dentistName = widget.dentistName;
    _chat = ChatController(api: widget.api);
    _chat.addListener(_onChatChanged);
    // Load conversations + open WebSocket immediately after login.
    _chat.start();
    _refreshNotificationBadge();
  }

  void _onChatChanged() {
    final unread = _chat.totalUnread;
    if (_messageBadge != unread && mounted) {
      setState(() => _messageBadge = unread);
    }
  }

  @override
  void dispose() {
    _chat.removeListener(_onChatChanged);
    _chat.dispose();
    super.dispose();
  }

  Future<void> _refreshNotificationBadge() async {
    try {
      final unreadNotifs = await widget.api.notificationsUnreadCount();
      if (!mounted) return;
      setState(() => _notificationBadge = unreadNotifs);
    } catch (_) {
      // Badge is non-critical
    }
  }

  void _go(AppNavItem item) {
    if (item == _active) return;
    setState(() => _active = item);
    if (item == AppNavItem.notifications) {
      _refreshNotificationBadge();
    }
    if (item == AppNavItem.messages) {
      // Refresh inbox when opening Messages (WS already running).
      _chat.loadInbox();
    }
  }

  Widget _transition(Widget child, Animation<double> animation) {
    final fade = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0.014, 0.008),
      end: Offset.zero,
    ).animate(fade);

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFEAF1F8),
              AppColors.surface,
              Color(0xFFDCE6F2),
            ],
          ),
        ),
        child: Row(
          children: [
            AppSidebar(
              active: _active,
              onSelect: _go,
              collapsed: _sidebarCollapsed,
              onToggle: () {
                setState(() => _sidebarCollapsed = !_sidebarCollapsed);
              },
              messageBadge: _messageBadge,
              notificationBadge: _notificationBadge,
              showLaboratories: widget.api.isDentist,
            ),
            Expanded(
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: _pageIn,
                  reverseDuration: _pageOut,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ...previousChildren,
                        ?currentChild,
                      ],
                    );
                  },
                  transitionBuilder: _transition,
                  child: KeyedSubtree(
                    key: ValueKey<AppNavItem>(_active),
                    child: RepaintBoundary(child: _page()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page() {
    switch (_active) {
      case AppNavItem.dashboard:
        return DashboardPage(
          dentistName: _dentistName,
          api: widget.api,
          onNavigate: _go,
          unreadMessages: _messageBadge,
        );
      case AppNavItem.patients:
        return PatientsPage(
          key: ValueKey(_patientRefresh),
          api: widget.api,
          dentistName: _dentistName,
          onNewPatient: () => _go(AppNavItem.newPatient),
        );
      case AppNavItem.newPatient:
        return NewPatientPage(
          api: widget.api,
          onCreated: () {
            _patientRefresh++;
            _go(AppNavItem.patients);
            _refreshNotificationBadge();
          },
        );
      case AppNavItem.camera:
        return CameraPage(api: widget.api, dentistName: _dentistName);
      case AppNavItem.scans:
        return ScansPage(api: widget.api);
      case AppNavItem.shade:
        return ShadePage(api: widget.api);
      case AppNavItem.smilePreview:
        return ShapeOverlayPage(api: widget.api);
      case AppNavItem.scanBody:
        return ScanBodyPage(api: widget.api);
      case AppNavItem.messages:
        return MessagesPage(
          api: widget.api,
          chatController: _chat,
        );
      case AppNavItem.laboratories:
        return LaboratoriesPage(api: widget.api);
      case AppNavItem.notifications:
        return NotificationsPage(
          api: widget.api,
          onNavigate: _go,
          onUnreadChanged: (n) {
            if (_notificationBadge != n) {
              setState(() => _notificationBadge = n);
            }
          },
        );
      case AppNavItem.reports:
        return ReportsPage(
          api: widget.api,
          onNavigate: _go,
        );
      case AppNavItem.settings:
        return SettingsPage(api: widget.api);
    }
  }
}

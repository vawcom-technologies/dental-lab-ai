import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/session/patient_session.dart';
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
  static const _navOrder = AppNavItem.values;

  AppNavItem _active = AppNavItem.dashboard;
  int _patientRefresh = 0;
  late String _dentistName;
  int _notificationBadge = 0;
  int _messageBadge = 0;
  bool _sidebarCollapsed = false;
  late final ChatController _chat;
  late final PatientSession _patients;

  /// Lazily mount pages on first visit, then keep their State alive.
  final Set<AppNavItem> _mountedPages = {AppNavItem.dashboard};

  @override
  void initState() {
    super.initState();
    _dentistName = widget.dentistName;
    _chat = ChatController(api: widget.api);
    _chat.addListener(_onChatChanged);
    _patients = PatientSession(widget.api);
    // Warm patient list + chat so the first workflow page opens faster.
    _patients.ensureLoaded();
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
    _patients.dispose();
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
    setState(() {
      _active = item;
      _mountedPages.add(item);
    });
    if (item == AppNavItem.notifications) {
      _refreshNotificationBadge();
    }
    if (item == AppNavItem.messages) {
      _chat.loadInbox();
    }
  }

  Future<void> _onPatientCreated() async {
    await _patients.refresh(keepSelection: true);
    if (!mounted) return;
    setState(() {
      _patientRefresh++;
      // Drop new-patient form so the next visit starts clean.
      _mountedPages.remove(AppNavItem.newPatient);
      _active = AppNavItem.patients;
      _mountedPages.add(AppNavItem.patients);
    });
    _refreshNotificationBadge();
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = _navOrder.indexOf(_active);

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
              child: SafeArea(
                left: false,
                child: ClipRect(
                  child: IndexedStack(
                    index: activeIndex < 0 ? 0 : activeIndex,
                    sizing: StackFit.expand,
                    children: [
                      for (final item in _navOrder)
                        _mountedPages.contains(item)
                            ? KeyedSubtree(
                                key: _pageKey(item),
                                child: RepaintBoundary(
                                  child: _createPage(item),
                                ),
                              )
                            : const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Key _pageKey(AppNavItem item) {
    if (item == AppNavItem.patients) {
      return ValueKey<String>('patients-$_patientRefresh');
    }
    return ValueKey<AppNavItem>(item);
  }

  Widget _createPage(AppNavItem item) {
    final active = item == _active;
    switch (item) {
      case AppNavItem.dashboard:
        return DashboardPage(
          dentistName: _dentistName,
          api: widget.api,
          onNavigate: _go,
          unreadMessages: _messageBadge,
        );
      case AppNavItem.patients:
        return PatientsPage(
          api: widget.api,
          dentistName: _dentistName,
          onNewPatient: () => _go(AppNavItem.newPatient),
        );
      case AppNavItem.newPatient:
        return NewPatientPage(
          api: widget.api,
          onCreated: _onPatientCreated,
        );
      case AppNavItem.camera:
        return CameraPage(
          api: widget.api,
          patientSession: _patients,
          active: active,
        );
      case AppNavItem.scans:
        return ScansPage(
          api: widget.api,
          patientSession: _patients,
          active: active,
        );
      case AppNavItem.shade:
        return ShadePage(
          api: widget.api,
          patientSession: _patients,
          active: active,
        );
      case AppNavItem.smilePreview:
        return ShapeOverlayPage(
          api: widget.api,
          patientSession: _patients,
          active: active,
        );
      case AppNavItem.scanBody:
        return ScanBodyPage(
          api: widget.api,
          patientSession: _patients,
          active: active,
        );
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

import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/navigation/app_page_routes.dart';
import '../core/session/patient_session.dart';
import '../core/theme/app_theme.dart';
import '../features/appointments/screens/appointments_screen.dart';
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
  bool _contentVisible = true;
  bool _navAnimating = false;
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
    _patients.addListener(_onPatientSessionChanged);
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

  void _onPatientSessionChanged() {
    if (!mounted) return;
    final toShade = _patients.consumeNavigateToShade();
    final toNewPatient = _patients.consumeNavigateToNewPatient();
    if (!toShade && !toNewPatient) return;
    // Wait a frame so menus/dialogs can finish disposing (avoids
    // `_dependents.isEmpty` crashes when navigating from pickers).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (toShade) _go(AppNavItem.shade);
      if (toNewPatient) _go(AppNavItem.newPatient);
    });
  }

  @override
  void dispose() {
    _chat.removeListener(_onChatChanged);
    _chat.dispose();
    _patients.removeListener(_onPatientSessionChanged);
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
    if (item == _active || _navAnimating) return;

    void apply() {
      _active = item;
      _mountedPages.add(item);
      if (item == AppNavItem.notifications) {
        _refreshNotificationBadge();
      }
      if (item == AppNavItem.messages) {
        _chat.loadInbox();
      }
    }

    // iPadOS sidebar style: one content pane at a time (fade out → swap → fade in).
    _navAnimating = true;
    setState(() => _contentVisible = false);
    Future<void>.delayed(const Duration(milliseconds: 110), () {
      if (!mounted) return;
      setState(() {
        apply();
        _contentVisible = true;
      });
      Future<void>.delayed(AppMotion.fast, () {
        if (mounted) _navAnimating = false;
      });
    });
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
      _contentVisible = true;
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
                  child: AnimatedOpacity(
                    opacity: _contentVisible ? 1 : 0,
                    duration: AppMotion.fast,
                    curve: AppMotion.easeOut,
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
          active: active,
        );
      case AppNavItem.patients:
        return PatientsPage(
          api: widget.api,
          dentistName: _dentistName,
          patientSession: _patients,
          onNewPatient: () => _go(AppNavItem.newPatient),
        );
      case AppNavItem.newPatient:
        return NewPatientPage(
          api: widget.api,
          patientSession: _patients,
          onCreated: _onPatientCreated,
        );
      case AppNavItem.appointments:
        return AppointmentsScreen(
          api: widget.api,
          patientSession: _patients,
          active: active,
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
        return LaboratoriesPage(
          api: widget.api,
          onMessageLab: (lab) async {
            await _chat.openOrCreateWith(lab.id);
            if (!mounted) return;
            _go(AppNavItem.messages);
          },
        );
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

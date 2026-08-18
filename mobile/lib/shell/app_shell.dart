import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/layout/adaptive.dart';
import '../core/widgets/app_switcher.dart';
import '../core/widgets/app_snackbar.dart';
import '../core/session/patient_session.dart';
import '../core/theme/app_theme.dart';
import '../features/appointments/screens/appointments_screen.dart';
import '../features/camera/camera_page.dart';
import '../features/chat/messages_page.dart';
import '../features/chat/state/chat_controller.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/laboratories/laboratories_page.dart';
import '../features/notifications/notification_inbox_controller.dart';
import '../features/notifications/notifications_page.dart';
import '../features/patients/new_patient_page.dart';
import '../features/patients/patients_page.dart';
import '../features/reports/reports_page.dart';
// Scan body parked — restore when needed.
// import '../features/scan_body/scan_body_page.dart';
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
  /// When the window is narrow (iPad portrait), expand overrides auto-collapse.
  bool _narrowSidebarOpen = false;
  late final ChatController _chat;
  late final PatientSession _patients;
  late final NotificationInboxController _inbox;

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
    _inbox = NotificationInboxController(widget.api);
    _inbox.addListener(_onInboxChanged);
    // Warm patient list + chat so the first workflow page opens faster.
    _patients.ensureLoaded();
    _chat.start();
    _inbox.start();
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
    final toSmile = _patients.consumeNavigateToSmilePreview();
    final toNewPatient = _patients.consumeNavigateToNewPatient();
    if (!toShade && !toSmile && !toNewPatient) return;
    // Wait a frame so menus/dialogs can finish disposing (avoids
    // `_dependents.isEmpty` crashes when navigating from pickers).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (toShade) _go(AppNavItem.shade);
      if (toSmile) _go(AppNavItem.smilePreview);
      if (toNewPatient) _go(AppNavItem.newPatient);
    });
  }

  @override
  void dispose() {
    _chat.removeListener(_onChatChanged);
    _chat.dispose();
    _patients.removeListener(_onPatientSessionChanged);
    _patients.dispose();
    _inbox.removeListener(_onInboxChanged);
    _inbox.dispose();
    super.dispose();
  }

  void _onInboxChanged() {
    if (!mounted) return;
    final unread = _inbox.unreadCount;
    if (_notificationBadge != unread) {
      setState(() => _notificationBadge = unread);
    }
    final toasts = _inbox.takePendingToasts();
    if (toasts.isEmpty) return;
    if (_active == AppNavItem.notifications) return;
    final allowed = toasts.where((n) {
      return _inbox.allowedBySettings('${n['type'] ?? ''}');
    }).toList();
    if (allowed.isEmpty) return;
    final first = allowed.first;
    var text = '${first['message'] ?? ''}'.trim();
    if (text.isEmpty) return;
    if (allowed.length > 1) {
      text = '$text  (+${allowed.length - 1} more)';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppSnackBars.info(
        context,
        text,
        duration: const Duration(seconds: 5),
        onTap: () => _go(AppNavItem.notifications),
      );
    });
  }

  void _pingInbox() {
    _inbox.refresh(announce: false);
  }

  void _go(AppNavItem item) {
    // Scan body parked — restore when needed.
    if (item == AppNavItem.scanBody) return;
    if (item == _active) return;
    setState(() {
      _active = item;
      _mountedPages.add(item);
    });
    if (item == AppNavItem.notifications) {
      _pingInbox();
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
    _pingInbox();
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxHeight > constraints.maxWidth ||
                constraints.maxWidth < AppBreakpoints.collapseSidebar;
            final sidebarCollapsed =
                narrow ? !_narrowSidebarOpen : _sidebarCollapsed;
            return Row(
              children: [
                AppSidebar(
                  active: _active,
                  onSelect: (item) {
                    if (narrow && _narrowSidebarOpen) {
                      setState(() => _narrowSidebarOpen = false);
                    }
                    _go(item);
                  },
                  collapsed: sidebarCollapsed,
                  onToggle: () {
                    setState(() {
                      if (narrow) {
                        _narrowSidebarOpen = !_narrowSidebarOpen;
                      } else {
                        _sidebarCollapsed = !_sidebarCollapsed;
                      }
                    });
                  },
                  messageBadge: _messageBadge,
                  notificationBadge: _notificationBadge,
                  showLaboratories: widget.api.isDentist,
                ),
                Expanded(
                  child: SafeArea(
                    left: false,
                    child: ClipRect(
                      child: AppPaneFade(
                        token: _active,
                        child: IndexedStack(
                          index: activeIndex < 0 ? 0 : activeIndex,
                          sizing: StackFit.expand,
                          children: [
                            for (final item in _navOrder)
                              _mountedPages.contains(item)
                                  ? KeyedSubtree(
                                      key: _pageKey(item),
                                      child: TickerMode(
                                        enabled: item == _active,
                                        child: RepaintBoundary(
                                          child: _createPage(item),
                                        ),
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
            );
          },
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
          onInboxChanged: _pingInbox,
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
          onInboxChanged: _pingInbox,
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
        // Scan body parked — restore ScanBodyPage when needed.
        return const SizedBox.shrink();
        // return ScanBodyPage(
        //   api: widget.api,
        //   patientSession: _patients,
        //   active: active,
        // );
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
          inbox: _inbox,
          onNavigate: _go,
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

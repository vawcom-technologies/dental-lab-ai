import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/layout/adaptive.dart';
import '../core/widgets/app_switcher.dart';
import '../core/widgets/app_snackbar.dart';
import '../core/widgets/busy_action.dart';
import '../core/widgets/tooth_loader.dart';
import '../core/session/patient_session.dart';
import '../core/theme/app_theme.dart';
import '../features/admin/admin_dashboard_page.dart';
import '../features/admin/admin_patients_page.dart';
import '../features/admin/admin_signups_page.dart';
import '../features/admin/admin_top_bar.dart';
import '../features/appointments/screens/appointments_screen.dart';
import '../features/cases/review_page.dart';
import '../features/lab/join_lab_page.dart';
import '../features/lab/lab_dashboard_page.dart';
import '../features/lab/lab_page.dart';
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
import '../features/interpreter/interpreter_page.dart';
import '../features/shade/shade_page.dart';
import '../features/shapes/shape_overlay_page.dart';
import 'app_sidebar.dart';
import '../core/l10n/app_localizations.dart';

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
  int _messageBadge = 0;
  int _labBadge = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final ChatController _chat;
  late final PatientSession _patients;
  late final NotificationInboxController _inbox;

  /// Selected tab on each admin page, so the dashboard can deep-link.
  final _adminTabs = {
    for (final item in const [
      AppNavItem.settings,
      AppNavItem.laboratories,
      AppNavItem.patients,
      AppNavItem.lab,
    ])
      item: ValueNotifier<int>(0),
  };

  /// Admin Patients status filter ('' = all); the dashboard can preset it.
  final _patientStatus = ValueNotifier<String>('');

  /// Lazily mount pages on first visit, then keep their State alive.
  final Set<AppNavItem> _mountedPages = {AppNavItem.dashboard};

  @override
  void initState() {
    super.initState();
    _dentistName = widget.dentistName;
    _chat = ChatController(api: widget.api);
    _chat.onError = (msg) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppSnackBars.error(context, msg);
      });
    };
    _chat.addListener(_onChatChanged);
    _patients = PatientSession(widget.api);
    _patients.addListener(_onPatientSessionChanged);
    // Labs review inside a pushed page (no Scans/Shade/Smile in their sidebar).
    if (!widget.api.isLaboratory) {
      _patients.openToolHandler = (tool) => _go(switch (tool) {
            'shade' => AppNavItem.shade,
            'smile' => AppNavItem.smilePreview,
            _ => AppNavItem.scans,
          });
    }
    _inbox = NotificationInboxController(widget.api);
    _inbox.onError = (msg) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppSnackBars.error(context, msg);
      });
    };
    _inbox.addListener(_onInboxChanged);
    // Warm patient list + chat after first frame — start()/loadInbox notify
    // listeners, and doing that while the shell is still mounting dirties
    // badge ListenableBuilders mid-build.
    _patients.ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chat.start();
      _inbox.start();
    });
    // Dentists: learn whether they have a lab (a restored session doesn't say).
    if (widget.api.isDentist) {
      widget.api.fetchMe(forceRefresh: true).then((_) {
        if (mounted) setState(() {});
      }, onError: (_) {});
    }
  }

  void _onChatChanged() {
    final unread = _chat.totalUnread;
    if (_messageBadge != unread && mounted) {
      setState(() => _messageBadge = unread);
    }
  }

  void _onPatientSessionChanged() {
    if (!mounted) return;
    final toPatients = _patients.consumeNavigateToPatients();
    // Mention taps need an instant tab switch so the loader is not left
    // sitting on Messages for several frames.
    if (toPatients) {
      _go(AppNavItem.patients);
    }
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
    for (final tab in _adminTabs.values) {
      tab.dispose();
    }
    _patientStatus.dispose();
    super.dispose();
  }

  void _onInboxChanged() {
    if (!mounted) return;
    final toasts = _inbox.takePendingToasts();
    if (toasts.isEmpty) return;
    if (_active == AppNavItem.notifications) return;
    final allowed = toasts.where((n) {
      return _inbox.allowedBySettings('${n['type'] ?? ''}');
    }).toList();
    if (allowed.isEmpty) return;
    final first = allowed.first;
    final loc = AppLocalizations.of(context);
    var text = loc
        .localizeNotificationMessage(
          '${first['message'] ?? ''}',
          type: '${first['type'] ?? ''}',
          patientName: '${first['patient_name'] ?? ''}',
        )
        .trim();
    if (text.isEmpty) return;
    if (allowed.length > 1) {
      text = '$text  ${loc.notificationsMoreCount(allowed.length - 1)}';
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
    if ((item == AppNavItem.laboratories ||
            item == AppNavItem.adminSignups) &&
        !widget.api.isAdmin) {
      AppSnackBars.error(
        context,
        AppLocalizations.of(context).errNoPermission,
      );
      item = AppNavItem.dashboard;
    }
    if (item == _active) return;
    setState(() {
      _active = item;
      _mountedPages.add(item);
    });
    if (item == AppNavItem.notifications) {
      _pingInbox();
    }
    if (item == AppNavItem.messages) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _chat.loadInbox();
      });
    }
  }

  /// Deep link from the dashboard. Opening Patients this way clears the
  /// status filter unless [_openPatientsWithStatus] sets one.
  void _openAdmin(AppNavItem item, int tab) {
    _adminTabs[item]?.value = tab;
    if (item == AppNavItem.patients) _patientStatus.value = '';
    _go(item);
  }

  void _openPatientsWithStatus(String status) {
    _openAdmin(AppNavItem.patients, 0);
    _patientStatus.value = status;
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
    // No lab yet: the lab picker is the whole app (plus Settings / sign out).
    if (widget.api.needsLab) {
      return JoinLabPage(api: widget.api, onReady: () => setState(() {}));
    }
    final activeIndex = _navOrder.indexOf(_active);

    return ListenableBuilder(
      listenable: _patients,
      builder: (context, _) {
        // Keyboard overlays content — don't shrink the shell (sidebar / chrome
        // stay put under dialogs). Pages that need the inset (e.g. Messages)
        // pad themselves.
        return Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: BusyBarrier(
            busy: _patients.openingPatientDetail,
            message: AppLocalizations.of(context).patientsOpening,
            child: ColoredBox(
              color: AppColors.surface,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Screen size, not laid-out height — keyboard insets must not
                  // flip sidebar collapsed/expanded (that remounts Messages and
                  // dismisses the composer immediately).
                  final screen = MediaQuery.sizeOf(context);
                  final phone = AppBreakpoints.isPhoneSize(screen);
                  final stack = ClipRect(
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
                                        child: PageArea(child: _createPage(item)),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  );
                  // Bell, chat, search and profile — shared by admin, lab and dentist.
                  final pages = AdminChrome(
                    api: widget.api,
                    inbox: _inbox,
                    chat: _chat,
                    onOpen: _openAdmin,
                    openChat: (c) {
                      _chat.openConversation(c);
                      _go(AppNavItem.messages);
                    },
                    child: stack,
                  );

                  if (phone) {
                    return PhoneNavScope(
                      openMenu: () =>
                          _scaffoldKey.currentState?.openDrawer(),
                      child: Scaffold(
                        key: _scaffoldKey,
                        backgroundColor: Colors.transparent,
                        resizeToAvoidBottomInset: false,
                        drawer: Drawer(
                          backgroundColor: AppColors.sidebarBg,
                          width: (screen.width * 0.86).clamp(260.0, 320.0),
                          child: AppSidebar(
                            active: _active,
                            asDrawer: true,
                            onSelect: (item) {
                              _scaffoldKey.currentState?.closeDrawer();
                              _go(item);
                            },
                            messageBadge: _messageBadge,
                            admin: widget.api.isAdmin,
                            lab: widget.api.isLaboratory,
                            labBadge: _labBadge,
                          ),
                        ),
                        body: SafeArea(child: pages),
                      ),
                    );
                  }

                  return Row(
                    children: [
                      AppSidebar(
                        active: _active,
                        onSelect: _go,
                        messageBadge: _messageBadge,
                        admin: widget.api.isAdmin,
                            lab: widget.api.isLaboratory,
                            labBadge: _labBadge,
                      ),
                      Expanded(
                        child: SafeArea(
                          left: false,
                          child: pages,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
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
        if (widget.api.isAdmin) {
          return AdminDashboardPage(
            api: widget.api,
            onOpen: _openAdmin,
            onOpenStatus: _openPatientsWithStatus,
            active: active,
          );
        }
        if (widget.api.isLaboratory) {
          return LabDashboardPage(
            api: widget.api,
            onOpen: _openAdmin,
            onWaiting: (n) {
              if (mounted && n != _labBadge) setState(() => _labBadge = n);
            },
            active: active,
          );
        }
        return DashboardPage(
          api: widget.api,
          onOpen: _openAdmin,
          active: active,
        );
      case AppNavItem.patients:
        if (widget.api.isAdmin) {
          return AdminPatientsPage(
            api: widget.api,
            tab: _adminTabs[item]!,
            status: _patientStatus,
            active: active,
          );
        }
        return PatientsPage(
          api: widget.api,
          dentistName: _dentistName,
          patientSession: _patients,
          onNewPatient: () => _go(AppNavItem.newPatient),
          onInboxChanged: _pingInbox,
          active: active,
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
      case AppNavItem.interpreter:
        return InterpreterPage(
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
          patientSession: _patients,
        );
      case AppNavItem.laboratories:
        if (!widget.api.isAdmin) {
          return _ForbiddenRedirect(
            onLeave: () => _go(AppNavItem.dashboard),
          );
        }
        return LaboratoriesPage(
          api: widget.api,
          tab: _adminTabs[item],
          active: active,
          onMessage: (userId) async {
            await _chat.openOrCreateWith(userId);
            if (!mounted) return;
            _go(AppNavItem.messages);
          },
        );
      case AppNavItem.lab:
        if (!widget.api.isLaboratory) {
          return _ForbiddenRedirect(onLeave: () => _go(AppNavItem.dashboard));
        }
        return LabPage(
          api: widget.api,
          active: active,
          tab: _adminTabs[item],
          onOpenPatient: _patients.requestOpenPatientDetail,
          onWaiting: (n) {
            if (mounted && n != _labBadge) setState(() => _labBadge = n);
          },
        );
      case AppNavItem.review:
        if (!widget.api.isLaboratory) {
          return _ForbiddenRedirect(onLeave: () => _go(AppNavItem.dashboard));
        }
        return ReviewPage(
          api: widget.api,
          cases: _patients.cases,
          patients: _patients,
          active: active,
        );
      case AppNavItem.adminSignups:
        if (!widget.api.isAdmin) {
          return _ForbiddenRedirect(
            onLeave: () => _go(AppNavItem.dashboard),
          );
        }
        return AdminSignupsPage(api: widget.api, active: active);
      case AppNavItem.notifications:
        return NotificationsPage(
          inbox: _inbox,
          onNavigate: _go,
          onOpenTab: (item, tab) {
            _adminTabs[item]?.value = tab;
            _go(item);
          },
          onOpenPatient: (id) {
            _patients.requestOpenPatientDetail(id);
            _go(AppNavItem.patients);
          },
          active: active,
        );
      case AppNavItem.reports:
        return ReportsPage(
          api: widget.api,
          onNavigate: _go,
        );
      case AppNavItem.settings:
        return SettingsPage(api: widget.api, tab: _adminTabs[item]!, active: active);
    }
  }
}

/// Shown when a non-admin reaches System Users, then redirected away (403).
class _ForbiddenRedirect extends StatefulWidget {
  const _ForbiddenRedirect({required this.onLeave});

  final VoidCallback onLeave;

  @override
  State<_ForbiddenRedirect> createState() => _ForbiddenRedirectState();
}

class _ForbiddenRedirectState extends State<_ForbiddenRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppSnackBars.error(
        context,
        AppLocalizations.of(context).errNoPermission,
      );
      widget.onLeave();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Text(
        loc.errNoPermission,
        style: AppFonts.style(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

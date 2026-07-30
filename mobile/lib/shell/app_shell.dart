import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/ui_kit.dart';
import '../features/auth/login_screen.dart';
import '../features/camera/camera_page.dart';
import '../features/chat/messages_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/notifications/notifications_page.dart';
import '../features/patients/new_patient_page.dart';
import '../features/patients/patients_page.dart';
import '../features/profile/profile_page.dart';
import '../features/scan_body/scan_body_page.dart';
import '../features/scans/scans_page.dart';
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
  AppNavItem _active = AppNavItem.dashboard;
  int _patientRefresh = 0;
  late String _dentistName;

  @override
  void initState() {
    super.initState();
    _dentistName = widget.dentistName;
  }

  void _go(AppNavItem item) => setState(() => _active = item);

  void _signOut() {
    widget.api.logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(api: widget.api)),
      (_) => false,
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
            AppSidebar(active: _active, onSelect: _go),
            Expanded(child: _page()),
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
            setState(() {
              _patientRefresh++;
              _active = AppNavItem.patients;
            });
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
        return MessagesPage(api: widget.api);
      case AppNavItem.notifications:
        return const NotificationsPage();
      case AppNavItem.reports:
        return const _ComingSoon(title: 'Reports');
      case AppNavItem.settings:
        return const _ComingSoon(title: 'Settings');
      case AppNavItem.profile:
        return ProfilePage(
          api: widget.api,
          onProfileUpdated: (name) => setState(() => _dentistName = name),
          onSignOut: _signOut,
        );
    }
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              letterSpacing: -0.4,
            ),
          ),
          const Spacer(),
          Center(
            child: SectionCard(
              child: Column(
                children: [
                  Icon(
                    Icons.health_and_safety_outlined,
                    size: 40,
                    color: AppColors.muted.withValues(alpha: 0.55),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Coming soon',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

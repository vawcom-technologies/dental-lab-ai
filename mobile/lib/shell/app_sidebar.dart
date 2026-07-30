import 'package:flutter/material.dart';

import '../core/l10n/app_localizations.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand_logo.dart';

enum AppNavItem {
  dashboard,
  patients,
  newPatient,
  camera,
  scans,
  shade,
  smilePreview,
  scanBody,
  messages,
  notifications,
  reports,
  settings,
  profile,
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.active,
    required this.onSelect,
    this.collapsed = false,
    this.messageBadge = 3,
    this.notificationBadge = 5,
  });

  final AppNavItem active;
  final ValueChanged<AppNavItem> onSelect;
  final bool collapsed;
  final int messageBadge;
  final int notificationBadge;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final width = collapsed ? 72.0 : 248.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      decoration: BoxDecoration(
        color: AppColors.sidebarBg,
        borderRadius: AppRadii.border,
        boxShadow: NeoShadows.raised(depth: 0.85),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 10 : 16, 18, 14, 10),
              child: collapsed
                  ? const Center(child: BrandLogo(height: 40, scale: 1.2))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BrandLogo(height: 56, scale: 1.15),
                        const SizedBox(height: 8),
                        Text(
                          s.proEdition,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                children: [
                  _item(AppNavItem.dashboard, Icons.grid_view_rounded, s.navDashboard),
                  _item(AppNavItem.patients, Icons.people_outline, s.navPatients),
                  _item(AppNavItem.newPatient, Icons.person_add_alt_1_outlined, s.navNewPatient),
                  _item(AppNavItem.camera, Icons.photo_camera_outlined, s.navCamera),
                  _item(AppNavItem.scans, Icons.view_in_ar_outlined, s.navScans),
                  _item(AppNavItem.shade, Icons.palette_outlined, s.navShade),
                  _item(AppNavItem.smilePreview, Icons.sentiment_satisfied_alt_outlined, s.navSmilePreview),
                  _item(AppNavItem.scanBody, Icons.radio_button_checked_outlined, s.navScanBody),
                  _item(
                    AppNavItem.messages,
                    Icons.chat_bubble_outline,
                    s.navMessages,
                    badge: messageBadge,
                    badgeColor: AppColors.danger,
                  ),
                  _item(
                    AppNavItem.notifications,
                    Icons.notifications_none_rounded,
                    s.navNotifications,
                    badge: notificationBadge,
                    badgeColor: AppColors.warning,
                  ),
                  _item(AppNavItem.reports, Icons.bar_chart_rounded, s.navReports),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
              child: Column(
                children: [
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(bottom: 10),
                    color: AppColors.border.withValues(alpha: 0.6),
                  ),
                  _item(AppNavItem.settings, Icons.settings_outlined, s.navSettings),
                  _item(AppNavItem.profile, Icons.person_outline, s.navProfile),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    AppNavItem id,
    IconData icon,
    String label, {
    int? badge,
    Color? badgeColor,
  }) {
    final selected = active == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(id),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 12,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              color: selected ? AppColors.sidebarActive : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: selected ? NeoShadows.pressed() : null,
            ),
            child: Row(
              mainAxisAlignment:
                  collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.dentalBlue : AppColors.muted,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? AppColors.navy : AppColors.muted,
                      ),
                    ),
                  ),
                  if (badge != null && badge > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor ?? AppColors.danger,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

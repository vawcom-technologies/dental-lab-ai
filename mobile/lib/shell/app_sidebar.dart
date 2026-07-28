import 'package:flutter/material.dart';

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
    final width = collapsed ? 72.0 : 240.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 10 : 14, 16, 12, 16),
              child: collapsed
                  ? const Center(child: BrandLogo(height: 40, scale: 1.2))
                  : const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BrandLogo(height: 58, scale: 1.2),
                        SizedBox(height: 6),
                        Text(
                          'Pro Edition',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _item(AppNavItem.dashboard, Icons.grid_view_rounded, 'Dashboard'),
                  _item(AppNavItem.patients, Icons.people_outline, 'Patients'),
                  _item(AppNavItem.newPatient, Icons.person_add_alt_1_outlined, 'New Patient'),
                  _item(AppNavItem.camera, Icons.photo_camera_outlined, 'Camera'),
                  _item(AppNavItem.scans, Icons.view_in_ar_outlined, 'Scans'),
                  _item(AppNavItem.shade, Icons.palette_outlined, 'Shade Detection'),
                  _item(AppNavItem.smilePreview, Icons.sentiment_satisfied_alt_outlined, 'Smile Preview'),
                  _item(AppNavItem.scanBody, Icons.radio_button_checked_outlined, 'Scan Body'),
                  _item(
                    AppNavItem.messages,
                    Icons.chat_bubble_outline,
                    'Messages',
                    badge: messageBadge,
                    badgeColor: AppColors.danger,
                  ),
                  _item(
                    AppNavItem.notifications,
                    Icons.notifications_none_rounded,
                    'Notifications',
                    badge: notificationBadge,
                    badgeColor: AppColors.warning,
                  ),
                  _item(AppNavItem.reports, Icons.bar_chart_rounded, 'Reports'),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Column(
                children: [
                  _item(AppNavItem.settings, Icons.settings_outlined, 'Settings'),
                  _item(AppNavItem.profile, Icons.person_outline, 'Profile'),
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.sidebarActive : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => onSelect(id),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: selected
                ? const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: AppColors.dentalBlue, width: 3),
                    ),
                  )
                : null,
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 12,
              vertical: 10,
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
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
                        borderRadius: BorderRadius.circular(10),
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

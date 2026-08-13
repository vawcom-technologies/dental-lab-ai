import 'package:flutter/material.dart';

import '../core/haptics/app_haptics.dart';
import '../core/l10n/app_localizations.dart';
import '../core/navigation/app_page_routes.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_buttons.dart';
import '../core/widgets/brand_logo.dart';
import '../core/widgets/glass_surface.dart';
import '../core/widgets/touchable.dart';

enum AppNavItem {
  dashboard,
  patients,
  newPatient,
  appointments,
  camera,
  scans,
  shade,
  smilePreview,
  scanBody,
  messages,
  laboratories,
  notifications,
  reports,
  settings,
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.active,
    required this.onSelect,
    required this.onToggle,
    this.collapsed = false,
    this.messageBadge = 0,
    this.notificationBadge = 0,
    this.showLaboratories = false,
  });

  final AppNavItem active;
  final ValueChanged<AppNavItem> onSelect;
  final VoidCallback onToggle;
  final bool collapsed;
  final int messageBadge;
  final int notificationBadge;
  final bool showLaboratories;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final width = collapsed ? 72.0 : 248.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (collapsed && v > 250) {
          onToggle();
        } else if (!collapsed && v < -250) {
          onToggle();
        }
      },
      child: AnimatedContainer(
        duration: AppMotion.normal,
        curve: AppMotion.easeOut,
        width: width,
        margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
        // Keep content at the target width while the sidebar animates,
        // otherwise the logo row overflows mid-tween.
        child: GlassSurface(
          borderRadius: AppRadii.border,
          blur: 22,
          tint: AppColors.sidebarBg.withValues(alpha: 0.72),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: width,
              maxWidth: width,
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding:
                          EdgeInsets.fromLTRB(collapsed ? 10 : 16, 18, 14, 10),
                      child: collapsed
                          ? Column(
                              children: [
                                const BrandLogo(height: 40, scale: 1.2),
                                AppButtons.icon(
                                  onPressed: onToggle,
                                  tooltip: 'Expand sidebar',
                                  icon: Icons.chevron_right_rounded,
                                  color: AppColors.muted,
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child:
                                            BrandLogo(height: 56, scale: 1.15),
                                      ),
                                    ),
                                    AppButtons.icon(
                                      onPressed: onToggle,
                                      tooltip: 'Collapse sidebar',
                                      icon: Icons.chevron_left_rounded,
                                      color: AppColors.muted,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  s.proEdition,
                                  style: AppFonts.style(
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        children: [
                          _item(
                            AppNavItem.dashboard,
                            Icons.grid_view_rounded,
                            s.navDashboard,
                          ),
                          _item(
                            AppNavItem.patients,
                            Icons.people_outline,
                            s.navPatients,
                            selectedOverride: active == AppNavItem.newPatient,
                          ),
                          _item(
                            AppNavItem.appointments,
                            Icons.calendar_today_outlined,
                            s.navAppointments,
                          ),
                          _item(
                            AppNavItem.camera,
                            Icons.photo_camera_outlined,
                            s.navCamera,
                          ),
                          _item(
                            AppNavItem.scans,
                            Icons.view_in_ar_outlined,
                            s.navScans,
                          ),
                          _item(
                            AppNavItem.shade,
                            Icons.palette_outlined,
                            s.navShade,
                          ),
                          _item(
                            AppNavItem.smilePreview,
                            Icons.sentiment_satisfied_alt_outlined,
                            s.navSmilePreview,
                          ),
                          // Scan body parked — restore when needed.
                          // _item(
                          //   AppNavItem.scanBody,
                          //   Icons.radio_button_checked_outlined,
                          //   s.navScanBody,
                          // ),
                          _item(
                            AppNavItem.messages,
                            Icons.chat_bubble_outline,
                            s.navMessages,
                            badge: messageBadge,
                            badgeColor: AppColors.danger,
                          ),
                          if (showLaboratories)
                            _item(
                              AppNavItem.laboratories,
                              Icons.biotech_outlined,
                              s.navLaboratories,
                            ),
                          _item(
                            AppNavItem.notifications,
                            Icons.notifications_none_rounded,
                            s.navNotifications,
                            badge: notificationBadge,
                            badgeColor: AppColors.warning,
                          ),
                          _item(
                            AppNavItem.reports,
                            Icons.bar_chart_rounded,
                            s.navReports,
                          ),
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
                          _item(
                            AppNavItem.settings,
                            Icons.settings_outlined,
                            s.navSettings,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
    bool selectedOverride = false,
  }) {
    final selected = selectedOverride || active == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Touchable(
        onTap: () {
          if (selected && !selectedOverride) {
            AppHaptics.light();
            return;
          }
          AppHaptics.selection();
          onSelect(id);
        },
        haptic: false,
        borderRadius: BorderRadius.circular(14),
        minHeight: 44,
        child: AnimatedContainer(
          duration: AppMotion.normal,
          curve: AppMotion.spring,
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : 12,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.sidebarActive : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(
                    color: AppColors.dentalBlue.withValues(alpha: 0.22),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (selected && !collapsed)
                AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.spring,
                  width: 3,
                  height: 18,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: AppColors.dentalBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: selected ? AppColors.dentalBlue : AppColors.muted,
                  ),
                  if (badge != null && badge > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: badgeColor ?? AppColors.danger,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: AppMotion.fast,
                    curve: AppMotion.spring,
                    style: AppFonts.style(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.navy : AppColors.muted,
                    ),
                    child: Text(label),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

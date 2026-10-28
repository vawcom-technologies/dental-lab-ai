import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/auth/app_roles.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../models/chat_models.dart';

/// Photo and contact details of the person you're messaging.
Future<void> showUserProfileSheet(BuildContext context, UserProfile user) {
  return AppDialogs.sheet<void>(
    context: context,
    maxWidth: 400,
    builder: (_) => _UserProfileSheet(user: user),
  );
}

class _UserProfileSheet extends StatelessWidget {
  const _UserProfileSheet({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final u = user;
    final rows = [
      (CupertinoIcons.mail, loc.email, u.email),
      (CupertinoIcons.phone, loc.phone, u.phone),
      (CupertinoIcons.building_2_fill, loc.clinic, u.clinicName),
      if (AppRoles.isDentist(u.role)) (CupertinoIcons.lab_flask, loc.tr('admin.lab'), u.labName ?? loc.tr('admin.noLab')),
    ].where((r) => (r.$3 ?? '').trim().isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Photo grows in with a soft spring.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: const Cubic(0.22, 1.0, 0.36, 1.0),
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: UserAvatar(name: u.displayName, url: u.avatarUrl, size: 104),
          ),
          const SizedBox(height: 14),
          Text(
            u.displayName,
            textAlign: TextAlign.center,
            style: AppFonts.style(fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.navy, letterSpacing: -0.4),
          ),
          if ((u.role ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.dentalBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                AppRoles.label(u.role, loc),
                style: AppFonts.style(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dentalBlue),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (rows.isNotEmpty)
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  for (final (i, (icon, label, value)) in rows.indexed) ...[
                    if (i > 0) Divider(height: 1, indent: 48, color: AppColors.border.withValues(alpha: 0.5)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Icon(icon, size: 19, color: AppColors.dentalBlue),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label, style: AppFonts.style(fontSize: 12, color: AppColors.muted)),
                                CopyableText(
                                  value!,
                                  style: AppFonts.style(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          CupertinoButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              loc.tr('avatar.done'),
              style: AppFonts.style(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.dentalBlue),
            ),
          ),
        ],
      ),
    );
  }
}

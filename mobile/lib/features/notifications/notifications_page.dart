import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const Spacer(),
          Center(
            child: Column(
              children: [
                Icon(Icons.health_and_safety_outlined,
                    size: 40, color: AppColors.muted.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                const Text(
                  'This section is coming soon. Navigate using the sidebar to explore available features.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

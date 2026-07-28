import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import '../../shell/app_sidebar.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.dentistName,
    required this.api,
    required this.onNavigate,
  });

  final String dentistName;
  final ApiClient api;
  final ValueChanged<AppNavItem> onNavigate;

  @override
  Widget build(BuildContext context) {
    final short = dentistName.split(' ').isNotEmpty
        ? dentistName.split(' ').last
        : dentistName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Good morning, Dr. $short',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '7 cases require your attention today.',
                      style: TextStyle(color: AppColors.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => onNavigate(AppNavItem.newPatient),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Patient'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  side: BorderSide.none,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => onNavigate(AppNavItem.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Camera'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => onNavigate(AppNavItem.scans),
                icon: const Icon(Icons.view_in_ar_outlined, size: 18),
                label: const Text('Start Scan'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => onNavigate(AppNavItem.messages),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Messages'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: const [
              Expanded(
                child: _KpiCard(
                  title: 'Completed Cases',
                  value: '124',
                  hint: '+8 this week',
                  hintColor: AppColors.success,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'Avg. Processing',
                  value: '2.4d',
                  hint: '-0.3d vs last week',
                  hintColor: AppColors.success,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'Pending Scans',
                  value: '7',
                  hint: '3 require review',
                  hintColor: AppColors.warning,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'Rejected Scans',
                  value: '2',
                  hint: 'Down from 5 last week',
                  hintColor: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: SectionCard(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recent Patients',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _TableHeader(),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView(
                            children: const [
                              _PatientRow(
                                id: 'PT-2841',
                                name: 'Marcus Webb',
                                dentist: 'Dr. Sarah Chen',
                                status: 'in_progress',
                                updated: '2 hours ago',
                              ),
                              _PatientRow(
                                id: 'PT-2839',
                                name: 'Elaine Torres',
                                dentist: 'Dr. Park',
                                status: 'awaiting_scan',
                                updated: '4 hours ago',
                              ),
                              _PatientRow(
                                id: 'PT-2836',
                                name: 'Linda Moore',
                                dentist: 'Dr. Sarah Chen',
                                status: 'complete',
                                updated: 'Yesterday',
                              ),
                              _PatientRow(
                                id: 'PT-2834',
                                name: 'Robert Kim',
                                dentist: 'Dr. Park',
                                status: 'in_review',
                                updated: 'Yesterday',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Today's Activity",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView(
                            children: const [
                              _Activity(
                                time: '10:24',
                                text: 'Scan uploaded for Marcus Webb',
                              ),
                              _Activity(
                                time: '09:51',
                                text: 'AI shade detection completed — B2 confirmed',
                              ),
                              _Activity(
                                time: '09:33',
                                text: 'Message from Dr. Park re: Linda Moore case',
                              ),
                              _Activity(
                                time: '08:17',
                                text: 'Case PT-2836 marked complete',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.hint,
    required this.hintColor,
  });

  final String title;
  final String value;
  final String hint;
  final Color hintColor;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.navy)),
          const SizedBox(height: 6),
          Text(hint, style: TextStyle(color: hintColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('CASE ID', style: _h)),
          Expanded(flex: 3, child: Text('PATIENT', style: _h)),
          Expanded(flex: 3, child: Text('DENTIST', style: _h)),
          Expanded(flex: 2, child: Text('STATUS', style: _h)),
          Expanded(flex: 2, child: Text('UPDATED', style: _h)),
        ],
      ),
    );
  }
}

const _h = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: AppColors.muted,
  letterSpacing: 0.4,
);

class _PatientRow extends StatelessWidget {
  const _PatientRow({
    required this.id,
    required this.name,
    required this.dentist,
    required this.status,
    required this.updated,
  });

  final String id;
  final String name;
  final String dentist;
  final String status;
  final String updated;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(id, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                InitialsAvatar(name: name, size: 32),
                const SizedBox(width: 8),
                Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Expanded(flex: 3, child: Text(dentist, style: const TextStyle(color: AppColors.muted))),
          Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: StatusChip(statusKey: status))),
          Expanded(
            flex: 2,
            child: Text(updated, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _Activity extends StatelessWidget {
  const _Activity({required this.time, required this.text});

  final String time;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: const BoxDecoration(
              color: AppColors.dentalBlue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
                const SizedBox(height: 2),
                Text(time, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

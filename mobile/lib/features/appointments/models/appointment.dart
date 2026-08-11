import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Appointment workflow statuses (matches backend `AppointmentStatus`).
class AppointmentStatuses {
  static const scheduled = 'scheduled';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
  static const noShow = 'no_show';

  static const all = <String>[
    scheduled,
    completed,
    cancelled,
    noShow,
  ];

  static const filters = <({String key, String label})>[
    (key: 'all', label: 'All'),
    (key: scheduled, label: 'Scheduled'),
    (key: completed, label: 'Completed'),
    (key: cancelled, label: 'Cancelled'),
    (key: noShow, label: 'No Show'),
  ];

  static String normalize(String? raw) {
    final s = (raw ?? scheduled).trim().toLowerCase();
    if (s == 'noshow' || s == 'no-show') return noShow;
    // Legacy "confirmed" rows map to scheduled (status removed from product).
    if (s == 'confirmed') return scheduled;
    if (all.contains(s)) return s;
    return scheduled;
  }

  static String label(String? raw) {
    switch (normalize(raw)) {
      case completed:
        return 'Completed';
      case cancelled:
        return 'Cancelled';
      case noShow:
        return 'No Show';
      case scheduled:
      default:
        return 'Scheduled';
    }
  }
}

class AppointmentStatusStyle {
  const AppointmentStatusStyle(this.label, this.fg, this.bg);

  final String label;
  final Color fg;
  final Color bg;

  static AppointmentStatusStyle of(String? raw) {
    switch (AppointmentStatuses.normalize(raw)) {
      case AppointmentStatuses.completed:
        return const AppointmentStatusStyle(
          'Completed',
          AppColors.muted,
          Color(0xFFE8EDF4),
        );
      case AppointmentStatuses.cancelled:
        return const AppointmentStatusStyle(
          'Cancelled',
          AppColors.danger,
          AppColors.dangerSoft,
        );
      case AppointmentStatuses.noShow:
        return const AppointmentStatusStyle(
          'No Show',
          AppColors.warning,
          AppColors.warningSoft,
        );
      case AppointmentStatuses.scheduled:
      default:
        return const AppointmentStatusStyle(
          'Scheduled',
          AppColors.dentalBlue,
          Color(0xFFEAF3FC),
        );
    }
  }
}

class Appointment {
  const Appointment({
    required this.id,
    required this.patientId,
    required this.createdBy,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.reminderSent,
    required this.patientName,
    required this.patientEmail,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String patientId;
  final String createdBy;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final bool reminderSent;
  final String patientName;
  final String patientEmail;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static DateTime _parseDt(dynamic raw) {
    if (raw is DateTime) return raw.toLocal();
    final s = '$raw'.trim();
    if (s.isEmpty) return DateTime.now();
    return DateTime.parse(s.replaceFirst('Z', '+00:00')).toLocal();
  }

  static DateTime? _parseDtOrNull(dynamic raw) {
    if (raw == null) return null;
    final s = '$raw'.trim();
    if (s.isEmpty) return null;
    try {
      return _parseDt(raw);
    } catch (_) {
      return null;
    }
  }

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: '${json['id'] ?? ''}',
      patientId: '${json['patient_id'] ?? ''}',
      createdBy: '${json['created_by'] ?? ''}',
      description: '${json['description'] ?? ''}',
      startTime: _parseDt(json['start_time']),
      endTime: _parseDt(json['end_time']),
      status: AppointmentStatuses.normalize('${json['status'] ?? ''}'),
      reminderSent: json['reminder_sent'] == true,
      patientName: '${json['patient_name'] ?? ''}'.trim(),
      patientEmail: '${json['patient_email'] ?? ''}'.trim(),
      createdAt: _parseDtOrNull(json['created_at']),
      updatedAt: _parseDtOrNull(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'created_by': createdBy,
        'description': description,
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime.toUtc().toIso8601String(),
        'status': status,
        'reminder_sent': reminderSent,
        'patient_name': patientName,
        'patient_email': patientEmail,
        if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
      };

  Duration get duration => endTime.difference(startTime);

  bool get isUpcoming => startTime.isAfter(DateTime.now());
}

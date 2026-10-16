// Row types for the admin API (docs/roadmap.md, Phase 1 contract).

String _s(Object? v) => v == null ? '' : '$v'.trim();
String? _opt(Object? v) => _s(v).isEmpty ? null : _s(v);
DateTime? _date(Object? v) => DateTime.tryParse(_s(v))?.toLocal();
int _n(Object? v) => v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0;

class AdminSummary {
  const AdminSummary(this.raw);
  final Map<String, dynamic> raw;

  int get pendingSignups => _n(raw['pending_signups']);
  int get dentists => _n(raw['dentists']);
  int get labs => _n(raw['labs']);
  int get unassignedDentists => _n(raw['unassigned_dentists']);
  int get unassignedPatients => _n(raw['unassigned_patients']);
  int get pendingRemovals => _n(raw['pending_removals']);

  /// Keyed by DB status (`pending`, `in_progress`, …).
  int cases(String status) {
    final c = raw['cases'];
    return c is Map ? _n(c[status]) : 0;
  }
}

class Signup {
  Signup(Map<String, dynamic> j)
      : userId = _s(j['user_id']),
        name = _s(j['name']),
        email = _s(j['email']),
        phone = _opt(j['phone']),
        role = _s(j['role']),
        clinicName = _opt(j['clinic_name']),
        avatarUrl = _opt(j['avatar_url']),
        createdAt = _date(j['created_at']);

  final String userId, name, email, role;
  final String? phone, clinicName, avatarUrl;
  final DateTime? createdAt;
}

class RejectedSignup {
  RejectedSignup(Map<String, dynamic> j)
      : id = _s(j['id']),
        email = _s(j['email']),
        name = _s(j['name']),
        role = _s(j['role']),
        reason = _opt(j['reason']),
        rejectedAt = _date(j['rejected_at']),
        rejectedBy = _opt(j['rejected_by_name']);

  final String id, email, name, role;
  final String? reason, rejectedBy;
  final DateTime? rejectedAt;
}

class AdminLab {
  AdminLab(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = _s(j['name']),
        email = _s(j['email']),
        phone = _opt(j['phone']),
        dentistCount = _n(j['dentist_count']),
        hiddenFromLabs = j['hidden_from_labs'] == true,
        hideDentists = j['hide_dentists'] == true,
        deleted = j['deleted'] == true,
        avatarUrl = _opt(j['avatar_url']);

  final String id, name, email;
  final String? phone, avatarUrl;
  final int dentistCount;
  final bool hiddenFromLabs, hideDentists;

  /// Deactivated (can be reactivated).
  final bool deleted;
}

class AdminDentist {
  AdminDentist(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = _s(j['name']),
        email = _s(j['email']),
        phone = _opt(j['phone']),
        clinicName = _opt(j['clinic_name']),
        labId = _opt(j['lab_id']),
        labName = _opt(j['lab_name']),
        deleted = j['deleted'] == true,
        unassignedReason = _opt(j['unassigned_reason']),
        unassignedAt = _date(j['unassigned_at']),
        avatarUrl = _opt(j['avatar_url']);

  final String id, name, email;
  final String? phone, clinicName, labId, labName, avatarUrl;

  /// Deactivated (can be reactivated).
  final bool deleted;

  /// `lab_deleted`, `removed` or `no_lab`; null while in a lab.
  final String? unassignedReason;
  final DateTime? unassignedAt;
}

class RemovalRequest {
  RemovalRequest(Map<String, dynamic> j)
      : id = _s(j['id']),
        labName = _s(j['lab_name']),
        dentistName = _s(j['dentist_name']),
        reason = _opt(j['reason']),
        createdAt = _date(j['created_at']);

  final String id, labName, dentistName;
  final String? reason;
  final DateTime? createdAt;
}

class AdminPatient {
  AdminPatient(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = '${_s(j['first_name'])} ${_s(j['last_name'])}'.trim(),
        status = _s(j['status']),
        ownerName = _opt(j['owner_name']),
        labId = _opt(j['lab_id']),
        labName = _opt(j['lab_name']),
        unassignedReason = _opt(j['unassigned_reason']),
        updatedAt = _date(j['updated_at']),
        sharedWith = [
          for (final m in (j['shared_with'] as List? ?? const []))
            if (m is Map) (name: _s(m['name']), role: _s(m['role'])),
        ],
        events = [
          for (final m in (j['events'] as List? ?? const []))
            if (m is Map) CaseEvent(Map<String, dynamic>.from(m)),
        ];

  final String id, name, status;
  final String? ownerName, labId, labName;

  /// `owner_deleted` or `waiting_for_lab`; null when assigned.
  final String? unassignedReason;

  /// Sent to another lab that hasn't picked a dentist: [labName] is the
  /// receiving lab, [ownerName] the previous owner.
  bool get waitingForLab => unassignedReason == 'waiting_for_lab';
  final DateTime? updatedAt;

  /// Detail endpoint only.
  final List<({String name, String role})> sharedWith;
  final List<CaseEvent> events;
}

class CaseEvent {
  CaseEvent(Map<String, dynamic> j)
      : type = _s(j['type']),
        actor = _opt(j['actor_name']),
        remarks = _opt(j['remarks']),
        fromStatus = _opt(j['from_status']),
        toStatus = _opt(j['to_status']),
        at = _date(j['created_at']);

  final String type;
  final String? actor, remarks, fromStatus, toStatus;
  final DateTime? at;
}

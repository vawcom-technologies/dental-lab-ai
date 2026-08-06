class AdminUser {
  const AdminUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    this.clinicName,
    required this.verified,
    required this.deleted,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final String? clinicName;
  final bool verified;
  final bool deleted;
  final DateTime? updatedAt;

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: '${json['id'] ?? ''}',
      name: (json['name'] as String?)?.trim() ?? '',
      email: (json['email'] as String?)?.trim() ?? '',
      phone: _optionalString(json['phone']),
      role: (json['role'] as String?)?.trim() ?? '',
      clinicName: _optionalString(json['clinic_name']),
      verified: json['verified'] == true,
      deleted: json['deleted'] == true,
      updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}'),
    );
  }

  AdminUser copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? role,
    String? clinicName,
    bool? verified,
    bool? deleted,
    DateTime? updatedAt,
  }) {
    return AdminUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      clinicName: clinicName ?? this.clinicName,
      verified: verified ?? this.verified,
      deleted: deleted ?? this.deleted,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String? _optionalString(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}

class AdminUsersListResult {
  const AdminUsersListResult({
    required this.items,
    required this.skip,
    required this.limit,
    required this.count,
  });

  final List<AdminUser> items;
  final int skip;
  final int limit;
  final int count;
}

class AdminUserActionResult {
  const AdminUserActionResult({
    required this.message,
    this.user,
  });

  final String message;
  final AdminUser? user;
}

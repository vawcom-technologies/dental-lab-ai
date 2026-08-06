/// GDPR patient domain models + AgentResponse envelope.
library;

class AgentApiException implements Exception {
  AgentApiException({
    required this.httpCode,
    required this.code,
    required this.message,
    this.action,
  });

  final int httpCode;
  final String code;
  final String message;
  final String? action;

  bool get isForbidden => httpCode == 403 || code.contains('403');

  @override
  String toString() => message;
}

class AgentEnvelope {
  const AgentEnvelope({
    required this.status,
    required this.httpCode,
    required this.action,
    required this.authenticatedUserId,
    this.targetPatientId,
    this.payload = const {},
    this.errorCode,
    this.errorMessage,
  });

  final String status;
  final int httpCode;
  final String action;
  final String authenticatedUserId;
  final String? targetPatientId;
  final Map<String, dynamic> payload;
  final String? errorCode;
  final String? errorMessage;

  bool get isSuccess =>
      status == 'SUCCESS' && (httpCode == 200 || httpCode == 201);

  factory AgentEnvelope.fromJson(Map<String, dynamic> json) {
    final error = json['error'];
    Map<String, dynamic>? errMap;
    if (error is Map) {
      errMap = Map<String, dynamic>.from(error);
    }
    final payloadRaw = json['payload'];
    return AgentEnvelope(
      status: '${json['status'] ?? ''}',
      httpCode: (json['http_code'] as num?)?.toInt() ?? 0,
      action: '${json['action'] ?? ''}',
      authenticatedUserId: '${json['authenticated_user_id'] ?? ''}',
      targetPatientId: _optString(json['target_patient_id']),
      payload: payloadRaw is Map
          ? Map<String, dynamic>.from(payloadRaw)
          : const {},
      errorCode: errMap == null ? null : _optString(errMap['code']),
      errorMessage: errMap == null ? null : _optString(errMap['message']),
    );
  }

  void throwIfError() {
    if (isSuccess) return;
    throw AgentApiException(
      httpCode: httpCode == 0 ? 400 : httpCode,
      code: errorCode ?? 'UNKNOWN_ERROR',
      message: errorMessage ?? 'An unexpected error occurred.',
      action: action,
    );
  }
}

class GdprPatient {
  const GdprPatient({
    required this.id,
    required this.createdBy,
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.address,
    required this.phone,
    required this.healthInsurance,
    this.deleted = false,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String createdBy;
  final String firstName;
  final String lastName;
  final String dateOfBirth; // YYYY-MM-DD
  final String address;
  final String phone;
  final String healthInsurance;
  final bool deleted;
  final DateTime? deletedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get fullName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? 'Unnamed patient' : n;
  }

  bool isOwnedBy(String? userId) =>
      userId != null && userId.isNotEmpty && createdBy == userId;

  GdprPatient copyWith({
    String? firstName,
    String? lastName,
    String? dateOfBirth,
    String? address,
    String? phone,
    String? healthInsurance,
    bool? deleted,
    DateTime? deletedAt,
    DateTime? updatedAt,
  }) {
    return GdprPatient(
      id: id,
      createdBy: createdBy,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      healthInsurance: healthInsurance ?? this.healthInsurance,
      deleted: deleted ?? this.deleted,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory GdprPatient.fromJson(Map<String, dynamic> json) {
    return GdprPatient(
      id: '${json['id'] ?? ''}',
      createdBy: '${json['created_by'] ?? ''}',
      firstName: (json['first_name'] as String?)?.trim() ?? '',
      lastName: (json['last_name'] as String?)?.trim() ?? '',
      dateOfBirth: _dateString(json['date_of_birth']),
      address: (json['address'] as String?)?.trim() ?? '',
      phone: (json['phone'] as String?)?.trim() ?? '',
      healthInsurance: (json['health_insurance'] as String?)?.trim() ?? '',
      deleted: json['deleted'] == true,
      deletedAt: _parseDate(json['deleted_at']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toLegacyMap() => {
        'id': id,
        'created_by': createdBy,
        'first_name': firstName,
        'last_name': lastName,
        'date_of_birth': dateOfBirth,
        'dob': dateOfBirth,
        'address': address,
        'phone': phone,
        'health_insurance': healthInsurance,
        'deleted': deleted,
      };
}

class PatientNote {
  const PatientNote({
    required this.id,
    required this.patientId,
    required this.authorId,
    required this.noteContent,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String patientId;
  final String authorId;
  final String noteContent;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PatientNote.fromJson(Map<String, dynamic> json) {
    return PatientNote(
      id: '${json['id'] ?? ''}',
      patientId: '${json['patient_id'] ?? ''}',
      authorId: '${json['author_id'] ?? ''}',
      noteContent: (json['note_content'] as String?) ?? '',
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  PatientNote copyWith({String? noteContent, DateTime? updatedAt}) {
    return PatientNote(
      id: id,
      patientId: patientId,
      authorId: authorId,
      noteContent: noteContent ?? this.noteContent,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

String? _optString(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

String _dateString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value.split('T').first;
  return value.toString().split('T').first;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

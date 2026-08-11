import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api/api_client.dart';
import '../../core/auth/auth_aware_http_client.dart';
import '../../core/auth/session_coordinator.dart';
import 'patient_models.dart';

/// GDPR patient REST client — all `/api/patients*` endpoints.
class PatientsApiService {
  PatientsApiService(this._api);

  final ApiClient _api;

  String get _base => _api.baseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_api.token != null) 'Authorization': 'Bearer ${_api.token}',
      };

  Future<AgentEnvelope> _send(
    Future<http.Response> Function() call,
  ) async {
    final res = await call();
    // AuthAwareHttpClient already fires on 401; keep an explicit guard for
    // envelope-shaped auth failures that still arrive with a 401 transport code.
    if (res.statusCode == 401 ||
        AuthAwareHttpClient.looksLikeCredentialFailure(res.body)) {
      SessionCoordinator.onUnauthorized(_api);
    }
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) {
        throw AgentApiException(
          httpCode: res.statusCode,
          code: 'INVALID_RESPONSE',
          message: 'Unexpected response from server.',
        );
      }
      body = Map<String, dynamic>.from(decoded);
    } catch (e) {
      if (e is AgentApiException) rethrow;
      throw AgentApiException(
        httpCode: res.statusCode,
        code: 'PARSE_ERROR',
        message: 'Request failed (${res.statusCode})',
      );
    }
    final envelope = AgentEnvelope.fromJson(body);
    // Prefer envelope http_code; fall back to transport status.
    if (!envelope.isSuccess) {
      throw AgentApiException(
        httpCode: envelope.httpCode != 0 ? envelope.httpCode : res.statusCode,
        code: envelope.errorCode ?? 'ERROR_${res.statusCode}',
        message: envelope.errorMessage ??
            'An unexpected error occurred.',
        action: envelope.action,
      );
    }
    return envelope;
  }

  Future<List<GdprPatient>> listPatients() async {
    final env = await _send(
      () => _api.httpClient.get(Uri.parse('$_base/api/patients'), headers: _headers),
    );
    final raw = env.payload['patients'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => GdprPatient.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<GdprPatient> getPatient(String patientId) async {
    final env = await _send(
      () => _api.httpClient.get(
        Uri.parse('$_base/api/patients/$patientId'),
        headers: _headers,
      ),
    );
    final raw = env.payload['patient'];
    if (raw is! Map) {
      throw AgentApiException(
        httpCode: 502,
        code: 'MISSING_PATIENT',
        message: 'Patient payload missing.',
      );
    }
    return GdprPatient.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<GdprPatient> createPatient({
    required String firstName,
    required String lastName,
    required String dateOfBirth,
    required String email,
    required String address,
    required String phone,
    required String healthInsurance,
  }) async {
    final env = await _send(
      () => _api.httpClient.post(
        Uri.parse('$_base/api/patients'),
        headers: _headers,
        body: jsonEncode({
          'first_name': firstName,
          'last_name': lastName,
          'date_of_birth': dateOfBirth,
          'email': email,
          'address': address,
          'phone': phone,
          'health_insurance': healthInsurance,
        }),
      ),
    );
    final raw = env.payload['patient'];
    if (raw is! Map) {
      throw AgentApiException(
        httpCode: 502,
        code: 'MISSING_PATIENT',
        message: 'Patient payload missing.',
      );
    }
    return GdprPatient.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<GdprPatient> updatePatient(
    String patientId,
    Map<String, dynamic> fieldsToUpdate,
  ) async {
    final env = await _send(
      () => _api.httpClient.patch(
        Uri.parse('$_base/api/patients/$patientId'),
        headers: _headers,
        body: jsonEncode({'fields_to_update': fieldsToUpdate}),
      ),
    );
    final raw = env.payload['patient'];
    if (raw is! Map) {
      throw AgentApiException(
        httpCode: 502,
        code: 'MISSING_PATIENT',
        message: 'Patient payload missing.',
      );
    }
    return GdprPatient.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> deletePatient(
    String patientId, {
    required bool hard,
  }) async {
    await _send(
      () => _api.httpClient.delete(
        Uri.parse('$_base/api/patients/$patientId').replace(
          queryParameters: {'delete_type': hard ? 'hard' : 'soft'},
        ),
        headers: _headers,
      ),
    );
  }

  /// Owner → immediate grant; approved shared user → pending request.
  Future<AccessMutationResult> grantOrRequestAccess({
    required String patientId,
    required String targetUserId,
    required bool asOwner,
  }) async {
    final env = await _send(
      () => _api.httpClient.post(
        Uri.parse('$_base/api/patients/$patientId/access'),
        headers: _headers,
        body: jsonEncode({'target_user_id': targetUserId}),
      ),
    );
    final raw = env.payload['access'];
    PatientAccessEntry? entry;
    if (raw is Map) {
      entry = PatientAccessEntry.fromJson(Map<String, dynamic>.from(raw));
    }
    final immediate = asOwner ||
        entry?.status == PatientAccessStatus.approved ||
        env.action == 'grant_patient_access';
    return AccessMutationResult(immediate: immediate, access: entry);
  }

  Future<void> revokeAccess({
    required String patientId,
    required String targetUserId,
  }) async {
    await _send(
      () => _api.httpClient.delete(
        Uri.parse('$_base/api/patients/$patientId/access/$targetUserId'),
        headers: _headers,
      ),
    );
  }

  Future<List<PendingAccessRequest>> listPendingAccessRequests() async {
    final env = await _send(
      () => _api.httpClient.get(
        Uri.parse('$_base/api/patients/access/pending'),
        headers: _headers,
      ),
    );
    final raw = env.payload['pending_requests'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => PendingAccessRequest.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<EligibleAccessUser>> listEligibleUsers(String patientId) async {
    final env = await _send(
      () => _api.httpClient.get(
        Uri.parse('$_base/api/patients/$patientId/eligible-users'),
        headers: _headers,
      ),
    );
    final raw = env.payload['eligible_users'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => EligibleAccessUser.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<PatientAccessEntry> resolveAccessRequest({
    required String requestId,
    required String action,
  }) async {
    final env = await _send(
      () => _api.httpClient.patch(
        Uri.parse('$_base/api/patients/access/requests/$requestId'),
        headers: _headers,
        body: jsonEncode({'action': action}),
      ),
    );
    final raw = env.payload['access'] ?? env.payload['request'];
    if (raw is! Map) {
      throw AgentApiException(
        httpCode: 502,
        code: 'MISSING_ACCESS',
        message: 'Access decision payload missing.',
      );
    }
    return PatientAccessEntry.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<PatientAccessSnapshot> listPatientAccess(String patientId) async {
    final env = await _send(
      () => _api.httpClient.get(
        Uri.parse('$_base/api/patients/$patientId/access'),
        headers: _headers,
      ),
    );
    final ownerRaw = env.payload['owner'];
    final listRaw = env.payload['access_list'] ?? env.payload['access'];
    final isOwner = env.payload['is_owner'] == true;
    final owner = ownerRaw is Map
        ? PatientAccessOwner.fromJson(Map<String, dynamic>.from(ownerRaw))
        : null;
    final accessList = listRaw is List
        ? listRaw
            .whereType<Map>()
            .map(
              (e) => PatientAccessEntry.fromJson(
                Map<String, dynamic>.from({
                  ...Map<String, dynamic>.from(e),
                  'patient_id': e['patient_id'] ?? patientId,
                }),
              ),
            )
            .toList()
        : const <PatientAccessEntry>[];
    return PatientAccessSnapshot(
      isOwner: isOwner,
      owner: owner,
      accessList: accessList,
    );
  }

  Future<List<PatientNote>> listNotes(String patientId) async {
    final env = await _send(
      () => _api.httpClient.get(
        Uri.parse('$_base/api/patients/$patientId/notes'),
        headers: _headers,
      ),
    );
    final raw = env.payload['notes'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => PatientNote.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<PatientNote> uploadNote({
    required String patientId,
    required String noteContent,
  }) async {
    final env = await _send(
      () => _api.httpClient.post(
        Uri.parse('$_base/api/patients/$patientId/notes'),
        headers: _headers,
        body: jsonEncode({'note_content': noteContent}),
      ),
    );
    final raw = env.payload['note'];
    if (raw is! Map) {
      throw AgentApiException(
        httpCode: 502,
        code: 'MISSING_NOTE',
        message: 'Note payload missing.',
      );
    }
    return PatientNote.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<PatientNote> editNote({
    required String noteId,
    required String newNoteContent,
  }) async {
    final env = await _send(
      () => _api.httpClient.patch(
        Uri.parse('$_base/api/patients/notes/$noteId'),
        headers: _headers,
        body: jsonEncode({'new_note_content': newNoteContent}),
      ),
    );
    final raw = env.payload['note'];
    if (raw is! Map) {
      throw AgentApiException(
        httpCode: 502,
        code: 'MISSING_NOTE',
        message: 'Note payload missing.',
      );
    }
    return PatientNote.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> deleteNote(String noteId) async {
    await _send(
      () => _api.httpClient.delete(
        Uri.parse('$_base/api/patients/notes/$noteId'),
        headers: _headers,
      ),
    );
  }
}

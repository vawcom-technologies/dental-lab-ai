import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api/api_client.dart';
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
      () => http.get(Uri.parse('$_base/api/patients'), headers: _headers),
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
      () => http.get(
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
    required String address,
    required String phone,
    required String healthInsurance,
  }) async {
    final env = await _send(
      () => http.post(
        Uri.parse('$_base/api/patients'),
        headers: _headers,
        body: jsonEncode({
          'first_name': firstName,
          'last_name': lastName,
          'date_of_birth': dateOfBirth,
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
      () => http.patch(
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
      () => http.delete(
        Uri.parse('$_base/api/patients/$patientId').replace(
          queryParameters: {'delete_type': hard ? 'hard' : 'soft'},
        ),
        headers: _headers,
      ),
    );
  }

  Future<void> grantAccess({
    required String patientId,
    required String targetUserId,
  }) async {
    await _send(
      () => http.post(
        Uri.parse('$_base/api/patients/$patientId/access'),
        headers: _headers,
        body: jsonEncode({'target_user_id': targetUserId}),
      ),
    );
  }

  Future<void> revokeAccess({
    required String patientId,
    required String targetUserId,
  }) async {
    await _send(
      () => http.delete(
        Uri.parse('$_base/api/patients/$patientId/access/$targetUserId'),
        headers: _headers,
      ),
    );
  }

  Future<List<PatientNote>> listNotes(String patientId) async {
    final env = await _send(
      () => http.get(
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
      () => http.post(
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
      () => http.patch(
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
      () => http.delete(
        Uri.parse('$_base/api/patients/notes/$noteId'),
        headers: _headers,
      ),
    );
  }
}

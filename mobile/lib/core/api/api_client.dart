import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../features/laboratories/admin_user.dart';
import '../auth/app_roles.dart';
import '../haptics/app_haptics.dart';

class ApiClient {
  ApiClient({
    this.baseUrl = const String.fromEnvironment(
      'API_BASE',
      defaultValue: 'http://127.0.0.1:8000',
    ),
  });

  final String baseUrl;
  String? _token;
  String? _refreshToken;
  String? _userId;
  String? _role;
  String? _name;
  String? _email;
  String? _clinicName;
  String? _phone;

  String? get token => _token;
  String? get refreshToken => _refreshToken;
  String? get userId => _userId;
  String? get role => _role;
  bool get isDentist => AppRoles.isDentist(_role);
  bool get isLaboratory => AppRoles.isLaboratory(_role);
  String? get userName => _name;
  String? get email => _email;
  String? get clinicName => _clinicName;
  String? get phone => _phone;

  void setToken(String? token) => _token = token;

  String? _asString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  void _applyAuth(Map<String, dynamic> data) {
    final access = data['access_token'] as String?;
    if (access != null && access.isNotEmpty) {
      _token = access;
    }
    _refreshToken = data['refresh_token'] as String? ?? _refreshToken;
    _userId = _asString(data['user_id']) ?? _userId;
    _role = data['role'] as String?;
    _name = data['name'] as String?;
    _email = data['email'] as String?;
    _clinicName = data['clinic_name'] as String?;
    _phone = data['phone'] as String?;
  }

  void _applyProfile(Map<String, dynamic> data) {
    _userId = _asString(data['id']) ?? _userId;
    _role = data['role'] as String? ?? _role;
    _name = data['name'] as String? ?? _name;
    _email = data['email'] as String? ?? _email;
    _clinicName = data['clinic_name'] as String?;
    _phone = data['phone'] as String?;
  }

  void logout() {
    _token = null;
    _refreshToken = null;
    _userId = null;
    _role = null;
    _name = null;
    _email = null;
    _clinicName = null;
    _phone = null;
  }

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Map<String, String> get _authHeaders => {
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/signin'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _applyAuth(data);
    AppHaptics.success();
    return data;
  }

  /// Backward-compatible alias for [signIn].
  Future<Map<String, dynamic>> login(String email, String password) =>
      signIn(email, password);

  Future<Map<String, dynamic>> signUp({
    required String email,
    required String name,
    required String password,
    String? clinicName,
    String? phone,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/signup'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'name': name,
        'password': password,
        'clinic_name': clinicName,
        'phone': phone,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _applyAuth(data);
    if (data['email_confirmation_required'] != true) {
      AppHaptics.success();
    }
    return data;
  }

  /// Backward-compatible alias for [signUp].
  Future<Map<String, dynamic>> register({
    required String email,
    required String name,
    required String password,
    String? clinicName,
    String? phone,
  }) =>
      signUp(
        email: email,
        name: name,
        password: password,
        clinicName: clinicName,
        phone: phone,
      );

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMe() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _applyProfile(data);
    return data;
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? email,
    String? clinicName,
    String? phone,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    if (clinicName != null) body['clinic_name'] = clinicName;
    if (phone != null) body['phone'] = phone;
    final res = await http.patch(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _applyProfile(data);
    AppHaptics.success();
    return data;
  }

  Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/me/password'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    AppHaptics.success();
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] is String) {
        return body['message'] as String;
      }
    } catch (_) {}
    return 'Password updated';
  }

  Future<List<Map<String, dynamic>>> listPatients() async {
    final res = await http.get(Uri.parse('$baseUrl/api/patients'), headers: _jsonHeaders);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final decoded = jsonDecode(res.body);
    // GDPR AgentResponse envelope
    if (decoded is Map) {
      final status = '${decoded['status'] ?? ''}';
      if (status == 'ERROR') {
        final err = decoded['error'];
        final msg = err is Map
            ? '${err['message'] ?? 'Failed to list patients'}'
            : 'Failed to list patients';
        throw Exception(msg);
      }
      final payload = decoded['payload'];
      final patients = payload is Map ? payload['patients'] : null;
      if (patients is List) {
        return patients
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return const [];
    }
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }
    return const [];
  }

  /// Contacts for patient access sharing (`GET /api/users`).
  Future<List<Map<String, dynamic>>> listChatContacts({int limit = 100}) async {
    final uri = Uri.parse('$baseUrl/api/users').replace(
      queryParameters: {'limit': '$limit'},
    );
    final res = await http.get(uri, headers: _jsonHeaders);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final body = jsonDecode(res.body);
    if (body is! List) return const [];
    return body
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> createPatient(Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/patients'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
    final decoded = jsonDecode(res.body);
    if (decoded is Map) {
      final status = '${decoded['status'] ?? ''}';
      if (status == 'ERROR') {
        final err = decoded['error'];
        final msg = err is Map
            ? '${err['message'] ?? 'Failed to create patient'}'
            : 'Failed to create patient';
        throw Exception(msg);
      }
      final payload = decoded['payload'];
      final patient = payload is Map ? payload['patient'] : null;
      if (patient is Map) return Map<String, dynamic>.from(patient);
      return Map<String, dynamic>.from(decoded);
    }
    throw Exception('Invalid create patient response');
  }

  Future<void> deletePatient(Object id, {bool hard = false}) async {
    final uri = Uri.parse('$baseUrl/api/patients/$id').replace(
      queryParameters: {'delete_type': hard ? 'hard' : 'soft'},
    );
    final res = await http.delete(uri, headers: _jsonHeaders);
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_errorMessage(res));
    }
    // GDPR envelope may still return ERROR with 200-family codes rarely;
    // parse when JSON body present.
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && '${decoded['status']}' == 'ERROR') {
          final err = decoded['error'];
          throw Exception(
            err is Map
                ? '${err['message'] ?? 'Delete failed'}'
                : 'Delete failed',
          );
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Delete')) rethrow;
      }
    }
    AppHaptics.warn();
  }

  Map<String, dynamic> _agentPayload(http.Response res, {String fallback = 'Request failed'}) {
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) throw Exception(fallback);
    if ('${decoded['status'] ?? ''}' == 'ERROR') {
      final err = decoded['error'];
      throw Exception(
        err is Map ? '${err['message'] ?? fallback}' : fallback,
      );
    }
    final payload = decoded['payload'];
    if (payload is Map) return Map<String, dynamic>.from(payload);
    return Map<String, dynamic>.from(decoded);
  }

  Future<List<Map<String, dynamic>>> listPatientPhotos(String patientId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/patients/$patientId/photos'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final payload = _agentPayload(res, fallback: 'Failed to list photos');
    final photos = payload['photos'];
    if (photos is! List) return const [];
    return photos
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> uploadPatientPhoto({
    required String patientId,
    required String angle,
    required List<int> bytes,
    required String filename,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/patients/$patientId/photos'),
    );
    req.headers.addAll(_authHeaders);
    req.fields['angle'] = angle;
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 201) {
      // Prefer GDPR AgentResponse error message when present.
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['error'] is Map) {
          throw Exception(
            '${decoded['error']['message'] ?? _errorMessage(res)}',
          );
        }
      } catch (e) {
        if (e is Exception && !'$e'.startsWith('FormatException')) rethrow;
      }
      throw Exception(_errorMessage(res));
    }
    final payload = _agentPayload(res, fallback: 'Failed to upload photo');
    final photo = payload['photo'];
    if (photo is Map) return Map<String, dynamic>.from(photo);
    return payload;
  }

    Future<void> deletePatientPhoto({
    required String patientId,
    required String photoId,
  }) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/patients/$patientId/photos/$photoId'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_errorMessage(res));
    }
    if (res.body.isNotEmpty) {
      _agentPayload(res, fallback: 'Failed to delete photo');
    }
    AppHaptics.warn();
  }

  Future<Map<String, dynamic>> renamePatientPhoto({
    required String patientId,
    required String photoId,
    required String filename,
  }) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/patients/$patientId/photos/$photoId'),
      headers: _jsonHeaders,
      body: jsonEncode({'filename': filename}),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final payload = _agentPayload(res, fallback: 'Failed to rename photo');
    final photo = payload['photo'];
    if (photo is Map) return Map<String, dynamic>.from(photo);
    return payload;
  }

  Future<List<Map<String, dynamic>>> listCases() async {
    final res = await http.get(Uri.parse('$baseUrl/api/cases'), headers: _jsonHeaders);
    // Cases router is not always mounted (GDPR cutover) — treat as empty.
    if (res.statusCode == 404) return const [];
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final body = jsonDecode(res.body);
    if (body is! List) return const [];
    return body.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createCase(int patientId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/cases'),
      headers: _jsonHeaders,
      body: jsonEncode({'patient_id': patientId}),
    );
    if (res.statusCode != 201) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateCaseStatus(int caseId, String status) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/cases/$caseId'),
      headers: _jsonHeaders,
      body: jsonEncode({'status': status}),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    AppHaptics.selection();
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Bump a new case into active work after clinical capture.
  Future<void> markCaseInProgressIfPending(int caseId, String? currentStatus) async {
    final status = (currentStatus ?? 'pending').toLowerCase();
    if (status != 'pending' && status != 'awaiting_scan') return;
    await updateCaseStatus(caseId, 'in_progress');
  }

  Future<List<Map<String, dynamic>>> listPhotos(int caseId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/photos'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> uploadPhoto({
    required int caseId,
    required String angle,
    required List<int> bytes,
    required String filename,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/cases/$caseId/photos'),
    );
    req.headers.addAll(_authHeaders);
    req.fields['angle'] = angle;
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listScans(int caseId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/scans'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  /// Downsampled XYZ preview for the chairside 3D viewer.
  Future<Map<String, dynamic>> fetchScanPreview({
    required int caseId,
    required int scanId,
  }) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/scans/$scanId/preview'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Full original mesh bytes (PLY/STL/OBJ) for solid 3D rendering.
  Future<({Uint8List bytes, String filename})> fetchScanFile({
    required int caseId,
    required int scanId,
  }) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/scans/$scanId/file'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    var name = 'scan.ply';
    final cd = res.headers['content-disposition'];
    if (cd != null) {
      final match = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
      if (match != null && match.group(1)!.isNotEmpty) {
        name = match.group(1)!;
      }
    }
    return (bytes: res.bodyBytes, filename: name);
  }

  Future<Map<String, dynamic>> uploadScan({
    required int caseId,
    required List<int> bytes,
    required String filename,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/cases/$caseId/scans'),
    );
    req.headers.addAll(_authHeaders);
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteScan({required int caseId, required int scanId}) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/cases/$caseId/scans/$scanId'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
  }

  Future<Map<String, dynamic>> suggestShade(List<int> bytes, String filename) async {
    final name = filename.trim().isEmpty ? 'tooth.jpg' : filename;
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/ai/shade/suggest'),
    );
    req.headers.addAll(_authHeaders);
    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: name,
      ),
    );
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Re-match zones after the dentist edits a tooth outline polygon.
  Future<Map<String, dynamic>> resampleShadeOutline({
    required List<int> bytes,
    required String filename,
    required List<List<double>> outline,
    required int toothIndex,
  }) async {
    final name = filename.trim().isEmpty ? 'tooth.jpg' : filename;
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/ai/shade/resample-outline'),
    );
    req.headers.addAll(_authHeaders);
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: name),
    );
    req.fields['outline_json'] = jsonEncode(outline);
    req.fields['tooth_index'] = '$toothIndex';
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveShadeAnalysis({
    required int caseId,
    required List<Map<String, dynamic>> teeth,
    int selectedToothIndex = 0,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/cases/$caseId/shade/analysis'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'teeth': teeth,
        'selected_tooth_index': selectedToothIndex,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patchShadeZoneOverride({
    required int caseId,
    required int analysisId,
    required int zoneId,
    String? overrideShade,
  }) async {
    final res = await http.patch(
      Uri.parse(
        '$baseUrl/api/cases/$caseId/shade/analysis/$analysisId/zones/$zoneId',
      ),
      headers: _jsonHeaders,
      body: jsonEncode({'override_shade': overrideShade}),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    AppHaptics.success();
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteShadeAnalysis({
    required int caseId,
    required int analysisId,
  }) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/cases/$caseId/shade/analysis/$analysisId'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.warn();
  }

  Future<Map<String, dynamic>> saveShade({
    required int caseId,
    String? aiSuggested,
    double? confidence,
    required String finalShade,
    required bool overridden,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/cases/$caseId/shade'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'ai_suggested_shade': aiSuggested,
        'confidence_score': confidence,
        'final_shade': finalShade,
        'overridden_by_dentist': overridden,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteShade({required int caseId, required int shadeId}) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/cases/$caseId/shade/$shadeId'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.warn();
  }

  /// Clinic analytics. Pass [days] = 0 for all-time.
  Future<Map<String, dynamic>> fetchReportsSummary({int days = 30}) async {
    final uri = Uri.parse('$baseUrl/api/reports/summary').replace(
      queryParameters: {'days': '$days'},
    );
    final res = await http.get(uri, headers: _jsonHeaders);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> validateScan(List<int> bytes, String filename) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/ai/scan/validate'),
    );
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveShape({
    required int caseId,
    required String shapeId,
    required double x,
    required double y,
    required double rotation,
    required double scale,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/cases/$caseId/shape'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'shape_id': shapeId,
        'position_x': x,
        'position_y': y,
        'rotation': rotation,
        'scale': scale,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> latestShape(int caseId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/shape'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    if (res.body.isEmpty || res.body == 'null') return null;
    return jsonDecode(res.body) as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>> matchScanBody(double diameterMm) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/ai/scan-body/match'),
      headers: {
        ..._authHeaders,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'diameter_mm': diameterMm.toString()},
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> detectScanBody(
    List<int> bytes,
    String filename, {
    double? pixelsPerMm,
    double? knownDiameterMm,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/ai/scan-body/detect'),
    );
    req.headers.addAll(_authHeaders);
    if (pixelsPerMm != null) {
      req.fields['pixels_per_mm'] = pixelsPerMm.toString();
    }
    if (knownDiameterMm != null) {
      req.fields['known_diameter_mm'] = knownDiameterMm.toString();
    }
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> scanBodyTable() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/ai/scan-body/table'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['rows'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> saveScanBody({
    required int caseId,
    double? detectedDiameter,
    double? tableDiameterMm,
    String? tooth,
    String? manufacturer,
    String? platform,
    double? confidence,
    bool overridden = false,
    String? detectionMethod,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/cases/$caseId/scan-body'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'detected_diameter': detectedDiameter,
        'table_diameter_mm': tableDiameterMm,
        'matched_tooth_position': tooth,
        'matched_manufacturer': manufacturer,
        'matched_platform': platform,
        'confidence_score': confidence,
        'overridden_by_dentist': overridden,
        'detection_method': detectionMethod,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> latestScanBody(int caseId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/scan-body'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    if (res.body.isEmpty || res.body == 'null') return null;
    return jsonDecode(res.body) as Map<String, dynamic>?;
  }

  Future<List<Map<String, dynamic>>> listMessageThreads() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/messages/threads'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listMessages(int caseId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/messages'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> sendMessage({
    required int caseId,
    required String body,
    String type = 'text',
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/cases/$caseId/messages'),
      headers: _jsonHeaders,
      body: jsonEncode({'type': type, 'body': body}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.light();
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> markThreadRead(int caseId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/cases/$caseId/messages/read'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
  }

  Future<List<Map<String, dynamic>>> listNotifications({
    bool unreadOnly = false,
    String? type,
  }) async {
    final params = <String, String>{};
    if (unreadOnly) params['unread_only'] = 'true';
    if (type != null && type.isNotEmpty) params['type'] = type;
    final uri = Uri.parse('$baseUrl/api/notifications').replace(
      queryParameters: params.isEmpty ? null : params,
    );
    final res = await http.get(uri, headers: _jsonHeaders);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  Future<int> notificationsUnreadCount() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/notifications/unread-count'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markNotificationRead(int id) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/notifications/$id/read'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
  }

  Future<void> markAllNotificationsRead() async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/notifications/read-all'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
  }

  // ── Admin users ──────────────────────────────────────────────────────────

  Future<AdminUsersListResult> listAdminUsers({
    int skip = 0,
    int limit = 50,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/users').replace(
      queryParameters: {
        'skip': '$skip',
        'limit': '$limit',
      },
    );
    final res = await http.get(uri, headers: _jsonHeaders);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final rawItems = data['items'];
    final items = <AdminUser>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          items.add(AdminUser.fromJson(item));
        } else if (item is Map) {
          items.add(AdminUser.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return AdminUsersListResult(
      items: items,
      skip: (data['skip'] as num?)?.toInt() ?? skip,
      limit: (data['limit'] as num?)?.toInt() ?? limit,
      count: (data['count'] as num?)?.toInt() ?? items.length,
    );
  }

  Future<AdminUserActionResult> verifyAdminUser(String userId) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/admin/users/$userId/verify'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return _parseAdminUserAction(res.body);
  }

  Future<AdminUserActionResult> softDeleteAdminUser(String userId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/admin/users/$userId/soft-delete'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    AppHaptics.warn();
    return _parseAdminUserAction(res.body);
  }

  Future<AdminUserActionResult> hardDeleteAdminUser(String userId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/admin/users/$userId/hard-delete'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    AppHaptics.warn();
    return _parseAdminUserAction(res.body);
  }

  AdminUserActionResult _parseAdminUserAction(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final userRaw = data['user'];
    AdminUser? user;
    if (userRaw is Map<String, dynamic>) {
      user = AdminUser.fromJson(userRaw);
    } else if (userRaw is Map) {
      user = AdminUser.fromJson(Map<String, dynamic>.from(userRaw));
    }
    return AdminUserActionResult(
      message: (data['message'] as String?) ?? 'Done',
      user: user,
    );
  }

  String _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map) {
        // GDPR AgentResponse envelope
        if (body['status'] == 'ERROR') {
          final err = body['error'];
          if (err is Map && err['message'] != null) {
            return err['message'].toString();
          }
        }
        if (body['detail'] != null) {
          return _formatDetail(body['detail']);
        }
        if (body['message'] is String) {
          return body['message'] as String;
        }
      }
    } catch (_) {}
    return 'Request failed (${res.statusCode})';
  }

  String _formatDetail(dynamic detail) {
    if (detail is String) return detail;
    if (detail is List) {
      final messages = <String>[];
      for (final item in detail) {
        if (item is Map) {
          final msg = item['msg']?.toString();
          if (msg == null || msg.isEmpty) continue;
          final loc = item['loc'];
          String? field;
          if (loc is List && loc.isNotEmpty) {
            final last = loc.last?.toString();
            if (last != null && last != 'body' && int.tryParse(last) == null) {
              field = last;
            }
          }
          messages.add(field != null ? '$field: $msg' : msg);
        } else if (item != null) {
          messages.add(item.toString());
        }
      }
      if (messages.isNotEmpty) return messages.join('\n');
    }
    if (detail is Map) {
      final msg = detail['msg']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
    }
    return detail.toString();
  }
}

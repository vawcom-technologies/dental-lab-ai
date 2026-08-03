import 'dart:convert';

import 'package:http/http.dart' as http;

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
    String role = 'dentist',
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

  Future<void> changePassword({
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
  }

  Future<List<Map<String, dynamic>>> listPatients() async {
    final res = await http.get(Uri.parse('$baseUrl/api/patients'), headers: _jsonHeaders);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createPatient(Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/patients'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 201) throw Exception(_errorMessage(res));
    AppHaptics.success();
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deletePatient(int id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/patients/$id'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 204) throw Exception(_errorMessage(res));
    AppHaptics.warn();
  }

  Future<List<Map<String, dynamic>>> listCases() async {
    final res = await http.get(Uri.parse('$baseUrl/api/cases'), headers: _jsonHeaders);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
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

  Future<String> exportDatevXml(int patientId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/exports/$patientId/datev.xml'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return res.body;
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

  String _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        return _formatDetail(body['detail']);
      }
      if (body is Map && body['message'] is String) {
        return body['message'] as String;
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

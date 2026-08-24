import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../features/appointments/models/appointment.dart';
import '../../features/laboratories/admin_user.dart';
import '../auth/app_roles.dart';
import '../auth/auth_aware_http_client.dart';
import '../auth/session_coordinator.dart';
import '../auth/token_store.dart';
import '../errors/user_facing_error.dart';
import '../haptics/app_haptics.dart';
import '../offline/sync_queue.dart';
import 'api_host.dart';
import 'cached_http_client.dart';

class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? httpClient,
    TokenStore? tokenStore,
  }) : baseUrl = baseUrl ?? resolveApiBase(),
       _tokens = tokenStore ?? TokenStore() {
    if (httpClient is CachedHttpClient) {
      _http = httpClient;
    } else {
      final inner = httpClient ??
          AuthAwareHttpClient(
            inner: http.Client(),
            onUnauthorized: () => SessionCoordinator.onUnauthorized(this),
            isAuthExempt: SessionCoordinator.isAuthExemptUri,
            refreshAccess: tryRefreshAccess,
            currentAccessToken: () => _token,
          );
      _http = CachedHttpClient(inner: inner);
    }
  }

  final String baseUrl;
  late final http.Client _http;
  final TokenStore _tokens;
  final List<void Function()> _authListeners = [];
  Future<bool>? _refreshInFlight;

  /// Shared client for feature services (patients, chat, …).
  http.Client get httpClient => _http;
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

  void addAuthListener(void Function() listener) {
    _authListeners.add(listener);
  }

  void removeAuthListener(void Function() listener) {
    _authListeners.remove(listener);
  }

  void _notifyAuthListeners() {
    for (final listener in List<void Function()>.from(_authListeners)) {
      listener();
    }
  }

  Future<void> _persistTokens() async {
    await _tokens.save(
      accessToken: _token,
      refreshToken: _refreshToken,
    );
  }

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
    unawaited(_persistTokens());
    _notifyAuthListeners();
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
    clearHttpCache();
    _token = null;
    _refreshToken = null;
    _userId = null;
    _role = null;
    _name = null;
    _email = null;
    _clinicName = null;
    _phone = null;
    unawaited(_tokens.clear());
    unawaited(LocalEncryptedStore.clearAll());
    _notifyAuthListeners();
  }

  /// Best-effort server revoke, then local purge.
  Future<void> signOutFull() async {
    final refresh = _refreshToken;
    final access = _token;
    logout();
    try {
      await _http.post(
        Uri.parse('$baseUrl/api/auth/logout'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (refresh != null && refresh.isNotEmpty) 'refresh_token': refresh,
          if (access != null && access.isNotEmpty) 'access_token': access,
        }),
      );
    } catch (_) {}
    await _tokens.clear();
  }

  /// Cold start: rotate the stored refresh token into a live session.
  Future<bool> tryRestoreSession() async {
    final refresh = await _tokens.readRefresh();
    if (refresh == null || refresh.isEmpty) return false;
    _refreshToken = refresh;
    _token = await _tokens.readAccess();
    final ok = await tryRefreshAccess();
    if (!ok) {
      logout();
      await _tokens.clear();
      return false;
    }
    return true;
  }

  /// Rotate refresh → new access. Shared by 401 interceptor and auto-signin.
  Future<bool> tryRefreshAccess() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _refreshAccessOnce();
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<bool> _refreshAccessOnce() async {
    final refresh = _refreshToken ?? await _tokens.readRefresh();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await _http.post(
        Uri.parse('$baseUrl/api/auth/refresh'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refresh}),
      );
      if (res.statusCode != 200) return false;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return false;
      _applyAuth(Map<String, dynamic>.from(decoded));
      await _persistTokens();
      return _token != null && _token!.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Drop in-memory GET responses (logout / account switch).
  void clearHttpCache() {
    final client = _http;
    if (client is CachedHttpClient) {
      client.clearCache();
    }
  }

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Map<String, String> get _authHeaders => {
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Map<String, String> _getHeaders({bool forceRefresh = false}) => {
        ..._jsonHeaders,
        if (forceRefresh) CachedHttpClient.forceRefreshHeader: '1',
      };

  Map<String, String> _getAuthHeaders({bool forceRefresh = false}) => {
        ..._authHeaders,
        if (forceRefresh) CachedHttpClient.forceRefreshHeader: '1',
      };

  /// Headers for authenticated media (thumbnails, Image.network).
  Map<String, String> get mediaHeaders => Map<String, String>.from(_authHeaders);

  /// Turn a relative `/api/...` media path into an absolute URL.
  String resolveMediaUrl(String url) {
    final value = url.trim();
    if (value.isEmpty) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) return '$baseUrl$value';
    return '$baseUrl/$value';
  }

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    final res = await _http.post(
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
    String? role,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/auth/signup'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'name': name,
        'password': password,
        'clinic_name': clinicName,
        'phone': phone,
        if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
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
    String? role,
  }) =>
      signUp(
        email: email,
        name: name,
        password: password,
        clinicName: clinicName,
        phone: phone,
        role: role,
      );

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMe({bool forceRefresh = false}) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _getHeaders(forceRefresh: forceRefresh),
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
    final res = await _http.patch(
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
    final res = await _http.post(
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

  /// Permanently deletes this account and all associated clinical / chat data.
  Future<String> deleteAccount({required String password}) async {
    final res = await _http.delete(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _jsonHeaders,
      body: jsonEncode({'password': password}),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] is String) {
        return body['message'] as String;
      }
    } catch (_) {}
    return 'Account deleted';
  }

  Future<List<Map<String, dynamic>>> listPatients({
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/patients'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
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
  Future<List<Map<String, dynamic>>> listChatContacts({
    int limit = 100,
    bool forceRefresh = false,
  }) async {
    final uri = Uri.parse('$baseUrl/api/users').replace(
      queryParameters: {'limit': '$limit'},
    );
    final res = await _http.get(
      uri,
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final body = jsonDecode(res.body);
    if (body is! List) return const [];
    return body
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> createPatient(Map<String, dynamic> body) async {
    final res = await _http.post(
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
      throw Exception('Could not create the patient. Please try again.');
  }

  Future<Map<String, dynamic>> updatePatient(
    String patientId,
    Map<String, dynamic> fieldsToUpdate,
  ) async {
    final res = await _http.patch(
      Uri.parse('$baseUrl/api/patients/$patientId'),
      headers: _jsonHeaders,
      body: jsonEncode({'fields_to_update': fieldsToUpdate}),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final payload = _agentPayload(res, fallback: 'Failed to update patient');
    final patient = payload['patient'];
    if (patient is Map) {
      AppHaptics.selection();
      return Map<String, dynamic>.from(patient);
    }
    throw Exception('Could not update the patient. Please try again.');
  }

  Future<void> deletePatient(Object id, {bool hard = false}) async {
    final uri = Uri.parse('$baseUrl/api/patients/$id').replace(
      queryParameters: {'delete_type': hard ? 'hard' : 'soft'},
    );
    final res = await _http.delete(uri, headers: _jsonHeaders);
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

  Future<List<Map<String, dynamic>>> listPatientPhotos(
    String patientId, {
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/patients/$patientId/photos'),
      headers: _getHeaders(forceRefresh: forceRefresh),
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
    final streamed = await _http.send(req);
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
    final res = await _http.delete(
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
    final res = await _http.patch(
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

  /// Open a camera photo in shade_detections (no re-upload). Returns the new row.
  Future<Map<String, dynamic>> copyToShadeDetection(String photoId) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/patient-photos/$photoId/copy-to-shade'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
    return _decodeMap(res.body);
  }

  /// Open a camera photo in smile_previews (no re-upload). Returns the new row.
  Future<Map<String, dynamic>> copyToSmilePreview(String photoId) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/patient-photos/$photoId/copy-to-smile'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
    return _decodeMap(res.body);
  }

  Future<List<Map<String, dynamic>>> listCases({bool forceRefresh = false}) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/cases'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    // Cases router is not always mounted (GDPR cutover) — treat as empty.
    if (res.statusCode == 404) return const [];
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final body = jsonDecode(res.body);
    if (body is! List) return const [];
    return body.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createCase(int patientId) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/cases'),
      headers: _jsonHeaders,
      body: jsonEncode({'patient_id': patientId}),
    );
    if (res.statusCode != 201) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateCaseStatus(int caseId, String status) async {
    final res = await _http.patch(
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

  Future<List<Map<String, dynamic>>> listPhotos(
    int caseId, {
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/photos'),
      headers: _getHeaders(forceRefresh: forceRefresh),
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
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listScans(
    int caseId, {
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/scans'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  /// Downsampled XYZ preview for the chairside 3D viewer.
  Future<Map<String, dynamic>> fetchScanPreview({
    required int caseId,
    required int scanId,
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/scans/$scanId/preview'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Full original mesh bytes (PLY/STL/OBJ) for solid 3D rendering.
  Future<({Uint8List bytes, String filename})> fetchScanFile({
    required int caseId,
    required int scanId,
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/scans/$scanId/file'),
      headers: _getAuthHeaders(forceRefresh: forceRefresh),
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
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deleteScan({required int caseId, required int scanId}) async {
    final res = await _http.delete(
      Uri.parse('$baseUrl/api/cases/$caseId/scans/$scanId'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
  }

  // ── Patient clinical media (scans / shade-detections / smile-previews) ──

  List<Map<String, dynamic>> _decodeMapList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw Exception('Something went wrong. Please try again.');
  }

  Future<List<Map<String, dynamic>>> listPatientScans(
    String patientId, {
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/patients/$patientId/scans'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return _decodeMapList(res.body);
  }

  Future<Map<String, dynamic>> uploadPatientScan({
    required String patientId,
    required List<int> bytes,
    required String filename,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/patients/$patientId/scans'),
    );
    req.headers.addAll(_authHeaders);
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
    return _decodeMap(res.body);
  }

  Future<void> deletePatientScan(String scanId) async {
    final res = await _http.delete(
      Uri.parse('$baseUrl/api/scans/$scanId'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
  }

  Future<List<Map<String, dynamic>>> listShadeDetections(
    String patientId, {
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/patients/$patientId/shade-detections'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return _decodeMapList(res.body);
  }

  Future<Map<String, dynamic>> uploadShadeDetection({
    required String patientId,
    required List<int> bytes,
    required String filename,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/patients/$patientId/shade-detections'),
    );
    req.headers.addAll(_authHeaders);
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
    return _decodeMap(res.body);
  }

  Future<Map<String, dynamic>> saveShadeDetectionAnalysis({
    required String shadeId,
    required List<Map<String, dynamic>> teeth,
    int selectedToothIndex = 0,
    String? summaryShade,
    bool hasOverride = false,
    String? detectedShade,
    double? confidence,
    bool overridden = false,
    String? finalShade,
  }) async {
    final res = await _http.patch(
      Uri.parse('$baseUrl/api/shade-detections/$shadeId'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'teeth': teeth,
        'selected_tooth_index': selectedToothIndex,
        'summary_shade': summaryShade,
        'has_override': hasOverride,
        'detected_shade': detectedShade,
        'confidence': confidence,
        'overridden': overridden,
        'final_shade': finalShade,
      }),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    AppHaptics.success();
    return _decodeMap(res.body);
  }

  Future<void> deleteShadeDetection(String shadeId) async {
    final res = await _http.delete(
      Uri.parse('$baseUrl/api/shade-detections/$shadeId'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
  }

  Future<List<Map<String, dynamic>>> listSmilePreviews(
    String patientId, {
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/patients/$patientId/smile-previews'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return _decodeMapList(res.body);
  }

  Future<Map<String, dynamic>> uploadSmilePreview({
    required String patientId,
    required List<int> bytes,
    required String filename,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/patients/$patientId/smile-previews'),
    );
    req.headers.addAll(_authHeaders);
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
    return _decodeMap(res.body);
  }

  Future<void> deleteSmilePreview(String smileId) async {
    final res = await _http.delete(
      Uri.parse('$baseUrl/api/smile-previews/$smileId'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
  }

  /// Download media bytes from a public (or signed) URL such as R2 `file_url`.
  Future<Uint8List> downloadMediaBytes(
    String url, {
    bool forceRefresh = false,
  }) async {
    final uri = Uri.parse(resolveMediaUrl(url));
    final res = await _http.get(
      uri,
      headers: _getAuthHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) {
      throw Exception('Could not download the file. Please try again.');
    }
    return res.bodyBytes;
  }

  static const _shadeAnalyzeTimeout = Duration(seconds: 90);

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
    final streamed = await _http.send(req).timeout(_shadeAnalyzeTimeout);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Analyze a shade photo already stored on the server (no image re-upload).
  Future<Map<String, dynamic>> suggestShadeFromDetection(
    String shadeDetectionId,
  ) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/ai/shade/suggest-from-detection'),
          headers: _jsonHeaders,
          body: jsonEncode({'shade_detection_id': shadeDetectionId}),
        )
        .timeout(_shadeAnalyzeTimeout);
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
    final streamed = await _http.send(req).timeout(_shadeAnalyzeTimeout);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resampleShadeOutlineFromDetection({
    required String shadeDetectionId,
    required List<List<double>> outline,
    required int toothIndex,
  }) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/ai/shade/resample-outline-from-detection'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'shade_detection_id': shadeDetectionId,
            'outline': outline,
            'tooth_index': toothIndex,
          }),
        )
        .timeout(_shadeAnalyzeTimeout);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveShadeAnalysis({
    required int caseId,
    required List<Map<String, dynamic>> teeth,
    int selectedToothIndex = 0,
  }) async {
    final res = await _http.post(
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
    final res = await _http.patch(
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
    final res = await _http.delete(
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
    final res = await _http.post(
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
    final res = await _http.delete(
      Uri.parse('$baseUrl/api/cases/$caseId/shade/$shadeId'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.warn();
  }

  /// Clinic analytics. Pass [days] = 0 for all-time.
  Future<Map<String, dynamic>> fetchReportsSummary({
    int days = 30,
    bool forceRefresh = false,
  }) async {
    final uri = Uri.parse('$baseUrl/api/reports/summary').replace(
      queryParameters: {'days': '$days'},
    );
    final res = await _http.get(
      uri,
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> validateScan(List<int> bytes, String filename) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/ai/scan/validate'),
    );
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await _http.send(req);
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
    final res = await _http.post(
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

  Future<Map<String, dynamic>?> latestShape(
    int caseId, {
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/shape'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    if (res.body.isEmpty || res.body == 'null') return null;
    return jsonDecode(res.body) as Map<String, dynamic>?;
  }

  // Scan body parked — restore when needed.
  Future<Map<String, dynamic>> matchScanBody(double diameterMm) async {
    final res = await _http.post(
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
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> scanBodyTable({
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/ai/scan-body/table'),
      headers: _getHeaders(forceRefresh: forceRefresh),
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
    final res = await _http.post(
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

  Future<Map<String, dynamic>?> latestScanBody(
    int caseId, {
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/scan-body'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    if (res.body.isEmpty || res.body == 'null') return null;
    return jsonDecode(res.body) as Map<String, dynamic>?;
  }

  Future<List<Map<String, dynamic>>> listMessageThreads({
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/messages/threads'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listMessages(
    int caseId, {
    bool forceRefresh = false,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/cases/$caseId/messages'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> sendMessage({
    required int caseId,
    required String body,
    String type = 'text',
  }) async {
    final res = await _http.post(
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
    final res = await _http.post(
      Uri.parse('$baseUrl/api/cases/$caseId/messages/read'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
  }

  Future<List<Map<String, dynamic>>> listNotifications({
    bool unreadOnly = false,
    String? type,
    bool forceRefresh = false,
  }) async {
    final params = <String, String>{};
    if (unreadOnly) params['unread_only'] = 'true';
    if (type != null && type.isNotEmpty) params['type'] = type;
    final uri = Uri.parse('$baseUrl/api/notifications').replace(
      queryParameters: params.isEmpty ? null : params,
    );
    final res = await _http.get(
      uri,
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  Future<int> notificationsUnreadCount({bool forceRefresh = false}) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/notifications/unread-count'),
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markNotificationRead(String id) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/notifications/$id/read'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
  }

  Future<void> markAllNotificationsRead() async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/notifications/read-all'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
  }

  // ── Appointments ─────────────────────────────────────────────────────────

  Future<List<Appointment>> listAppointments({
    String? status,
    String? patientId,
    bool upcomingOnly = true,
    bool forceRefresh = false,
  }) async {
    final params = <String, String>{
      'upcoming_only': '$upcomingOnly',
    };
    if (status != null && status.isNotEmpty && status != 'all') {
      params['status'] = status;
    }
    if (patientId != null && patientId.isNotEmpty) {
      params['patient_id'] = patientId;
    }
    final uri = Uri.parse('$baseUrl/api/appointments').replace(
      queryParameters: params,
    );
    final res = await _http.get(
      uri,
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final decoded = jsonDecode(res.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => Appointment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Appointment> createAppointment({
    required String patientId,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/appointments'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'patient_id': patientId,
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime.toUtc().toIso8601String(),
        'description': ?description,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
    return Appointment.fromJson(
      Map<String, dynamic>.from(jsonDecode(res.body) as Map),
    );
  }

  Future<Appointment> updateAppointment({
    required String appointmentId,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    String? status,
  }) async {
    final body = <String, dynamic>{};
    if (description != null) body['description'] = description;
    if (startTime != null) {
      body['start_time'] = startTime.toUtc().toIso8601String();
    }
    if (endTime != null) {
      body['end_time'] = endTime.toUtc().toIso8601String();
    }
    if (status != null) body['status'] = status;

    final res = await _http.patch(
      Uri.parse('$baseUrl/api/appointments/$appointmentId'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    AppHaptics.success();
    return Appointment.fromJson(
      Map<String, dynamic>.from(jsonDecode(res.body) as Map),
    );
  }

  Future<void> deleteAppointment(String appointmentId) async {
    final res = await _http.delete(
      Uri.parse('$baseUrl/api/appointments/$appointmentId'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.warn();
  }

  // ── Admin users ──────────────────────────────────────────────────────────

  Future<AdminUsersListResult> listAdminUsers({
    int skip = 0,
    int limit = 50,
    bool forceRefresh = false,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/users').replace(
      queryParameters: {
        'skip': '$skip',
        'limit': '$limit',
      },
    );
    final res = await _http.get(
      uri,
      headers: _getHeaders(forceRefresh: forceRefresh),
    );
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
    final res = await _http.patch(
      Uri.parse('$baseUrl/api/admin/users/$userId/verify'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return _parseAdminUserAction(res.body);
  }

  Future<AdminUserActionResult> softDeleteAdminUser(String userId) async {
    final res = await _http.delete(
      Uri.parse('$baseUrl/api/admin/users/$userId/soft-delete'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    AppHaptics.warn();
    return _parseAdminUserAction(res.body);
  }

  Future<AdminUserActionResult> hardDeleteAdminUser(String userId) async {
    final res = await _http.delete(
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
    String? detail;
    String? code;
    try {
      final body = jsonDecode(res.body);
      if (body is Map) {
        if (body['status'] == 'ERROR') {
          final err = body['error'];
          if (err is Map) {
            if (err['message'] != null) {
              detail = err['message'].toString();
            }
            if (err['code'] != null) {
              code = err['code'].toString();
            }
          }
        }
        code ??= body['code']?.toString();
        if (detail == null && body['detail'] != null) {
          detail = _formatDetail(body['detail']);
        }
        if (detail == null && body['message'] is String) {
          detail = body['message'] as String;
        }
      }
    } catch (_) {}
    return friendlyHttpError(
      statusCode: res.statusCode,
      detail: detail,
      code: code,
    );
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

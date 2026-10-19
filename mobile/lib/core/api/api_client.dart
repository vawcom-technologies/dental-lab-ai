import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../features/appointments/models/appointment.dart';
import '../auth/app_roles.dart';
import '../auth/auth_aware_http_client.dart';
import '../auth/session_coordinator.dart';
import '../auth/token_store.dart';
import '../errors/user_facing_error.dart';
import '../haptics/app_haptics.dart';
import '../offline/sync_queue.dart';
import 'api_host.dart';
import 'cached_http_client.dart';
import '../widgets/user_avatar.dart';

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
    AvatarSource.api = this;
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
  String? _avatarUrl;
  String? _labId;
  String? _labName;
  Map<String, dynamic>? _pendingJoin;
  bool _labKnown = false;

  String? get token => _token;
  String? get refreshToken => _refreshToken;
  String? get userId => _userId;
  String? get role => _role;
  bool get isAdmin => AppRoles.isAdmin(_role);
  bool get isDentist => AppRoles.isDentist(_role);
  bool get isLaboratory => AppRoles.isLaboratory(_role);
  String? get userName => _name;
  String? get email => _email;
  String? get clinicName => _clinicName;
  String? get phone => _phone;

  /// Profile photo path/URL; show with [UserAvatar].
  String? get avatarUrl => _avatarUrl;

  /// Dentists: their lab (null until a lab accepts them).
  String? get labId => _labId;
  String? get labName => _labName;

  /// Dentists without a lab: their open join request `{id, lab_id,
  /// lab_name, created_at}`, or null. From /me only.
  Map<String, dynamic>? get pendingJoin => _pendingJoin;

  /// A dentist must join a lab before using the app. False until the lab
  /// info has been loaded (sign-in or /me), so a restored session doesn't
  /// flash the lab picker.
  bool get needsLab => isDentist && _labKnown && (_labId == null || _labId!.isEmpty);

  /// Only fields present in [data] change (a token refresh may omit them).
  void _applyLab(Map<String, dynamic> data, {required bool withPending}) {
    if (data.containsKey('lab_id')) {
      _labId = _asString(data['lab_id']);
      _labKnown = true;
    }
    if (data.containsKey('lab_name')) _labName = data['lab_name'] as String?;
    if (withPending && data.containsKey('pending_join')) {
      final p = data['pending_join'];
      _pendingJoin = p is Map ? Map<String, dynamic>.from(p) : null;
    }
  }

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
    _avatarUrl = data['avatar_url'] as String?;
    _applyLab(data, withPending: false);
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
    _avatarUrl = data['avatar_url'] as String? ?? _avatarUrl;
    _applyLab(data, withPending: true);
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
    _avatarUrl = null;
    _labId = null;
    _labName = null;
    _pendingJoin = null;
    _labKnown = false;
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
    ({Uint8List bytes, String contentType})? avatar,
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
        // Small (≤ ~600px) photo, base64 so signup stays one JSON call.
        if (avatar != null) 'avatar': base64Encode(avatar.bytes),
        if (avatar != null) 'avatar_content_type': avatar.contentType,
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

  /// [status]: only patients in that case status (e.g. `in_review`).
  Future<List<Map<String, dynamic>>> listPatients({
    bool forceRefresh = false,
    String? status,
  }) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/patients')
          .replace(queryParameters: status == null ? null : {'status': status}),
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
    String? replaces,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/patients/$patientId/scans'),
    );
    req.headers.addAll(_authHeaders);
    // Locked case: the server swaps this in for the old scan.
    if (replaces != null) req.fields['replaces'] = replaces;
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

  // ── Scan inbox (files sent from the PC web page) ──

  Future<List<Map<String, dynamic>>> listScanInbox() async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/scan-inbox'),
      headers: _getHeaders(forceRefresh: true),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return _decodeMapList(res.body);
  }

  /// Preview bytes of an inbox item (owner only).
  Future<Uint8List> downloadScanInboxFile(String id) =>
      downloadMediaBytes('/api/scan-inbox/$id/file', forceRefresh: true);

  /// Scans go to the patient's scans, photos to the patient's photos.
  /// Returns `{kind: scan|photo, record_id, ...}`.
  Future<Map<String, dynamic>> assignScanInbox(
    String id,
    String patientId, {
    String? angle,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/scan-inbox/$id/assign'),
      headers: _jsonHeaders,
      body: jsonEncode({'patient_id': patientId, 'angle': ?angle}),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    // The POST only evicts /api/scan-inbox; the patient's photos/scans changed too.
    final cache = _http;
    if (cache is CachedHttpClient) {
      cache.invalidateFor(Uri.parse('$baseUrl/api/patients/$patientId'));
    }
    AppHaptics.success();
    return _decodeMap(res.body);
  }

  Future<void> deleteScanInbox(String id) async {
    final res = await _http.delete(
      Uri.parse('$baseUrl/api/scan-inbox/$id'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_errorMessage(res));
    }
    AppHaptics.success();
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

  /// Save a shade result to the patient record. First save ([shadeId] null)
  /// stores the image — the analysed [bytes], or camera [photoId] copied
  /// server-side — together with [analysis]; later saves update [analysis].
  Future<Map<String, dynamic>> saveShadeDetection({
    required String patientId,
    String? shadeId,
    List<int>? bytes,
    String? filename,
    String? photoId,
    required Map<String, dynamic> analysis,
    String? replaces,
  }) async {
    final http.Response res;
    if (shadeId != null && shadeId.isNotEmpty) {
      res = await _http.patch(
        Uri.parse('$baseUrl/api/shade-detections/$shadeId'),
        headers: _jsonHeaders,
        body: jsonEncode(analysis),
      );
    } else {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/patients/$patientId/shade-detections'),
      );
      req.headers.addAll(_authHeaders);
      req.fields['analysis'] = jsonEncode(analysis);
      if (replaces != null) req.fields['replaces'] = replaces;
      if (photoId != null && photoId.isNotEmpty) {
        req.fields['photo_id'] = photoId;
      } else if (bytes != null) {
        req.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename ?? 'tooth.jpg',
        ));
      }
      res = await http.Response.fromStream(await _http.send(req));
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
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

  /// Save a smile preview: [composite] is the photo with overlays, [overlay]
  /// the shape placements. A new smile ([smileId] null) also sends the photo
  /// without overlays — [baseBytes], or camera [basePhotoId] copied
  /// server-side. A reopened smile only replaces composite + placements.
  Future<Map<String, dynamic>> saveSmilePreview({
    required String patientId,
    String? smileId,
    required List<int> composite,
    List<int>? baseBytes,
    String? baseFilename,
    String? basePhotoId,
    required Map<String, dynamic> overlay,
    String? replaces,
  }) async {
    final isUpdate = smileId != null && smileId.isNotEmpty;
    final req = http.MultipartRequest(
      isUpdate ? 'PATCH' : 'POST',
      Uri.parse(isUpdate
          ? '$baseUrl/api/smile-previews/$smileId'
          : '$baseUrl/api/patients/$patientId/smile-previews'),
    );
    req.headers.addAll(_authHeaders);
    req.fields['overlay'] = jsonEncode(overlay);
    if (!isUpdate && replaces != null) req.fields['replaces'] = replaces;
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      composite,
      filename: 'smile_preview.jpg',
    ));
    if (!isUpdate) {
      if (basePhotoId != null && basePhotoId.isNotEmpty) {
        req.fields['base_photo_id'] = basePhotoId;
      } else if (baseBytes != null) {
        req.files.add(http.MultipartFile.fromBytes(
          'base',
          baseBytes,
          filename: baseFilename ?? 'smile_photo.jpg',
        ));
      }
    }
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

  /// [fromCamera]: tight camera crops — server pads context before KAIST.
  Future<Map<String, dynamic>> suggestShade(
    List<int> bytes,
    String filename, {
    bool fromCamera = false,
  }) async {
    final name = filename.trim().isEmpty ? 'tooth.jpg' : filename;
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/ai/shade/suggest'),
    );
    req.headers.addAll(_authHeaders);
    if (fromCamera) req.fields['from_camera'] = 'true';
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
    String? arch,
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
    // Lower teeth: zones run cervical → incisal upward on the photo.
    if (arch != null) req.fields['arch'] = arch;
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

  /// Server checks the stored scan (cached on the row) — no re-upload.
  Future<Map<String, dynamic>> validatePatientScan(String scanId) async {
    final res = await _http
        .post(Uri.parse('$baseUrl/api/scans/$scanId/validate'), headers: _jsonHeaders)
        .timeout(const Duration(seconds: 120));
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
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

  // ── Case flow (docs/roadmap.md, Phase 2) ──────────────────────────────────

  /// Status, items, allowed actions and history of a patient's case.
  Future<Map<String, dynamic>> patientCase(String patientId) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/patients/$patientId/case'),
      headers: _getHeaders(forceRefresh: true),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return _decodeMap(res.body);
  }

  /// Send to the lab. Throws [CaseIncomplete] (409) when items are missing
  /// and [confirmIncomplete] is false. Returns the new case summary.
  Future<Map<String, dynamic>> submitCase(
    String patientId, {
    bool confirmIncomplete = false,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/patients/$patientId/submit'),
      headers: _jsonHeaders,
      body: jsonEncode({'confirm_incomplete': confirmIncomplete}),
    );
    if (res.statusCode == 409) {
      final body = jsonDecode(res.body);
      if (body is Map && body['code'] == 'INCOMPLETE') {
        throw CaseIncomplete([for (final m in (body['missing'] as List? ?? const [])) '$m']);
      }
    }
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    AppHaptics.success();
    return _decodeMap(res.body);
  }

  /// Lab review: approve, or reject with [remarks] (required to reject).
  Future<Map<String, dynamic>> reviewCase(
    String patientId, {
    required bool approve,
    String? remarks,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/patients/$patientId/review'),
      headers: _jsonHeaders,
      body: jsonEncode({'decision': approve ? 'approve' : 'reject', 'remarks': ?remarks}),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    AppHaptics.success();
    return _decodeMap(res.body);
  }

  // ── Lab (docs/roadmap.md, Phase 3) ───────────────────────────────────────
  // [labId] is the signed-in lab's own id (the admin may pass any lab).

  List<Map<String, dynamic>> _list(dynamic data) => data is List
      ? data.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : const [];

  Future<List<Map<String, dynamic>>> labDentists(String labId) async =>
      _list(await _json('GET', 'labs/$labId/dentists'));

  /// 409 when a removal request for this dentist is already pending.
  Future<void> labRequestRemoval(String labId, {required String dentistId, required String reason}) =>
      _json('POST', 'labs/$labId/removal-requests', body: {'dentist_id': dentistId, 'reason': reason});

  /// Join requests to this lab and the lab's own removal requests.
  Future<List<Map<String, dynamic>>> labRequests(String labId) async =>
      _list(await _json('GET', 'labs/$labId/requests'));

  Future<void> labDecideJoin(String labId, String requestId, {required bool accept}) =>
      _json('POST', 'labs/$labId/requests/$requestId/${accept ? 'accept' : 'reject'}');

  /// `{hidden_from_labs, hide_dentists}`.
  Future<Map<String, dynamic>> labSettings(String labId) async =>
      Map<String, dynamic>.from(await _json('GET', 'labs/$labId/settings') as Map);

  /// Changes one or both; returns both.
  Future<Map<String, dynamic>> updateLabSettings(String labId, {bool? hiddenFromLabs, bool? hideDentists}) async =>
      Map<String, dynamic>.from(await _json('PATCH', 'labs/$labId/settings', body: {
        'hidden_from_labs': ?hiddenFromLabs,
        'hide_dentists': ?hideDentists,
      }) as Map);

  /// Dentist asks to join a lab. 409: already pending / already in a lab.
  Future<void> requestJoinLab(String labId) => _json('POST', 'labs/$labId/join-requests');

  /// Withdraw the dentist's own pending join request.
  Future<void> withdrawJoinRequest() => _json('DELETE', 'labs/join-requests/mine');

  /// Lab directory for pickers: `[{id, name, avatar_url}]`, hidden labs left out.
  Future<List<Map<String, dynamic>>> searchLabs({String q = ''}) async =>
      _list(await _json('GET', 'labs', query: {'q': q}));

  Future<List<Map<String, dynamic>>> labTransfers(String labId) async =>
      _list(await _json('GET', 'labs/$labId/transfers'));

  Future<void> transferForward(String id) => _json('POST', 'transfers/$id/forward');

  Future<void> transferAccept(String id, {required String dentistId}) =>
      _json('POST', 'transfers/$id/accept', body: {'dentist_id': dentistId});

  Future<void> transferReject(String id, {String? reason}) =>
      _json('POST', 'transfers/$id/reject', body: {'reason': ?reason});

  /// Owner asks to share with another lab: 400 not linked to a lab, 409 open.
  Future<void> requestTransfer(String patientId, {required String toLabId}) =>
      _json('POST', 'patients/$patientId/transfers', body: {'to_lab_id': toLabId});

  /// Lab moves a patient to (or picks) one of its dentists. 403: not given it.
  Future<void> assignPatient(String patientId, {required String dentistId}) =>
      _json('POST', 'patients/$patientId/assign', body: {'dentist_id': dentistId});

  // ── Admin (contract in docs/roadmap.md, Phase 1) ────────────────────────

  /// Admin call; returns decoded JSON. GETs skip the cache: one admin action
  /// changes counts on several screens.
  Future<dynamic> _admin(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) =>
      _json(method, 'admin/$path', query: query, body: body);

  /// JSON call to `/api/[path]` with flat error bodies; returns decoded JSON.
  /// GETs skip the cache (these screens change each other's data).
  Future<dynamic> _json(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final q = {...?query}..removeWhere((_, v) => v.isEmpty);
    final uri = Uri.parse('$baseUrl/api/$path')
        .replace(queryParameters: q.isEmpty ? null : q);
    final req = http.Request(method, uri)
      ..headers.addAll(method == 'GET' ? _getHeaders(forceRefresh: true) : _jsonHeaders);
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_errorMessage(res));
    }
    if (method != 'GET') AppHaptics.success();
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  List<Map<String, dynamic>> _adminList(dynamic data) => data is List
      ? data.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : const [];

  Future<Map<String, dynamic>> adminSummary() async =>
      Map<String, dynamic>.from(await _admin('GET', 'summary') as Map);

  Future<List<Map<String, dynamic>>> adminSignups() async =>
      _adminList(await _admin('GET', 'signups'));

  Future<void> adminApproveSignup(String userId, {String? labId}) =>
      _admin('POST', 'signups/$userId/approve',
          body: {'lab_id': ?labId});

  Future<void> adminRejectSignup(String userId, {String? reason}) =>
      _admin('POST', 'signups/$userId/reject',
          body: {if (reason != null && reason.isNotEmpty) 'reason': reason});

  Future<List<Map<String, dynamic>>> adminRejected() async =>
      _adminList(await _admin('GET', 'rejected'));

  Future<void> adminRemoveRejected(String id) =>
      _admin('DELETE', 'rejected/$id');

  Future<List<Map<String, dynamic>>> adminLabs() async =>
      _adminList(await _admin('GET', 'labs'));

  Future<List<Map<String, dynamic>>> adminDentists({
    String? labId,
    bool unassigned = false,
    String q = '',
  }) async =>
      _adminList(await _admin('GET', 'dentists', query: {
        'lab_id': labId ?? '',
        'unassigned': unassigned ? 'true' : '',
        'q': q,
      }));

  Future<void> adminSetDentistLab(String dentistId, String? labId) =>
      _admin('PUT', 'dentists/$dentistId/lab', body: {'lab_id': labId});

  Future<List<Map<String, dynamic>>> adminRemovalRequests() async =>
      _adminList(await _admin('GET', 'lab-requests',
          query: {'kind': 'remove', 'status': 'pending'}));

  /// [approve] false denies the request.
  Future<void> adminDecideLabRequest(String id, {required bool approve}) =>
      _admin('POST', 'lab-requests/$id/${approve ? 'approve' : 'deny'}');

  Future<List<Map<String, dynamic>>> adminPatients({
    String status = '',
    String? labId,
    bool unassigned = false,
    String q = '',
  }) async =>
      _adminList(await _admin('GET', 'patients', query: {
        'status': status,
        'lab_id': labId ?? '',
        'unassigned': unassigned ? 'true' : '',
        'q': q,
      }));

  Future<Map<String, dynamic>> adminPatient(String id) async =>
      Map<String, dynamic>.from(await _admin('GET', 'patients/$id') as Map);

  Future<void> adminOverrideStatus(String patientId, String status, String note) =>
      _admin('PATCH', 'patients/$patientId/status',
          body: {'status': status, 'note': note});

  /// Without [dentistId] the patient waits for [labId] to choose a dentist.
  Future<void> adminReassignPatient(
    String patientId,
    String labId, {
    String? dentistId,
  }) =>
      _admin('POST', 'patients/$patientId/reassign',
          body: {'lab_id': labId, 'dentist_id': ?dentistId});

  /// Soft = deactivate (can't sign in, everything kept, reversible).
  /// Hard = delete permanently; the backend unassigns patients / dentists.
  Future<void> adminDeleteUser(String userId, {bool hard = false}) =>
      _admin('DELETE', 'users/$userId/${hard ? 'hard' : 'soft'}-delete');

  /// Admin-only: replace any user's profile photo. Returns the new URL.
  Future<String?> adminSetAvatar(
    String userId, {
    required Uint8List bytes,
    required String contentType,
  }) async {
    final req = http.MultipartRequest(
      'PUT',
      Uri.parse('$baseUrl/api/admin/users/$userId/avatar'),
    )
      ..headers.addAll(_authHeaders)
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: 'avatar.${contentType.endsWith('png') ? 'png' : 'jpg'}',
      ));
    final res = await http.Response.fromStream(await _http.send(req));
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final url = (jsonDecode(res.body) as Map)['avatar_url'] as String?;
    if (userId == _userId) _avatarUrl = url;
    AvatarSource.changed.value++;
    return url;
  }

  Future<void> adminReactivateUser(String userId) =>
      _admin('PATCH', 'users/$userId/reactivate');

  Future<Map<String, dynamic>> interpreterCatalog() async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/interpreter/languages'),
      headers: _getHeaders(),
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw Exception('Invalid interpreter catalog');
  }

  Future<Map<String, dynamic>> interpreterTurn({
    required String text,
    required String sourceLang,
    required String targetLang,
    String? formality,
  }) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/interpreter/turn'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'text': text,
            'source_lang': sourceLang,
            'target_lang': targetLang,
            if (formality != null) 'formality': formality,
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return _mapBody(res, fallback: 'Translation failed');
  }

  Future<Map<String, dynamic>> interpreterTurnAudio({
    required List<int> bytes,
    required String filename,
    required String sourceLang,
    required String targetLang,
    String? formality,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/interpreter/turn-audio'),
    );
    req.headers.addAll(_authHeaders);
    req.fields['source_lang'] = sourceLang;
    req.fields['target_lang'] = targetLang;
    if (formality != null) req.fields['formality'] = formality;
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await _http.send(req);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return _mapBody(res, fallback: 'Voice translation failed');
  }

  /// MP3 for interpreter languages without an Apple voice.
  Future<List<int>> interpreterSpeak({
    required String text,
    required String lang,
  }) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/api/interpreter/speak'),
          headers: _jsonHeaders,
          body: jsonEncode({'text': text, 'lang': lang}),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    return res.bodyBytes;
  }

  Map<String, dynamic> _mapBody(http.Response res, {required String fallback}) {
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw Exception(fallback);
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

/// Submit refused because items are missing: `scan`, `shade` (saved shade
/// analysis) and/or `smile` (smile preview).
class CaseIncomplete implements Exception {
  const CaseIncomplete(this.missing);

  final List<String> missing;

  @override
  String toString() => 'Case incomplete: ${missing.join(', ')}';
}

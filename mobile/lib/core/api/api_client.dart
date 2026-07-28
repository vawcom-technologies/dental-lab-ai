import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({
    this.baseUrl = const String.fromEnvironment(
      'API_BASE',
      defaultValue: 'http://127.0.0.1:8000',
    ),
  });

  final String baseUrl;
  String? _token;

  String? get token => _token;

  void setToken(String? token) => _token = token;

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Map<String, String> get _authHeaders => {
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
    );
    if (res.statusCode != 200) throw Exception(_errorMessage(res));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _token = data['access_token'] as String;
    return data;
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
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> deletePatient(int id) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/patients/$id'),
      headers: _jsonHeaders,
    );
    if (res.statusCode != 204) throw Exception(_errorMessage(res));
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

  Future<Map<String, dynamic>> suggestShade(List<int> bytes, String filename) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/ai/shade/suggest'),
    );
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
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
    return jsonDecode(res.body) as Map<String, dynamic>;
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
    double pixelsPerMm = 20,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/ai/scan-body/detect'),
    );
    req.headers.addAll(_authHeaders);
    req.fields['pixels_per_mm'] = pixelsPerMm.toString();
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

  String _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) return body['detail'].toString();
    } catch (_) {}
    return 'Request failed (${res.statusCode})';
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/api/api_client.dart';
import '../models/chat_models.dart';

/// REST client for `/api/conversations*` and `/api/media/chat-upload`.
class ChatApiService {
  ChatApiService(this._api);

  final ApiClient _api;

  String get _base => _api.baseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_api.token != null) 'Authorization': 'Bearer ${_api.token}',
      };

  Map<String, String> get _authHeaders => {
        'Accept': 'application/json',
        if (_api.token != null) 'Authorization': 'Bearer ${_api.token}',
      };

  Future<List<Conversation>> fetchConversations() async {
    final res = await http.get(
      Uri.parse('$_base/api/conversations'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    final body = jsonDecode(res.body);
    if (body is! List) return const [];
    return body
        .whereType<Map>()
        .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Conversation> getOrCreateConversation(String targetUserId) async {
    final res = await http.post(
      Uri.parse('$_base/api/conversations/get-or-create'),
      headers: _headers,
      body: jsonEncode({'target_user_id': targetUserId}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    final body = jsonDecode(res.body);
    if (body is! Map) {
      throw Exception('Invalid conversation response');
    }
    return Conversation.fromJson(Map<String, dynamic>.from(body));
  }

  /// `GET /api/users` — verified contacts available for new conversations.
  Future<List<UserProfile>> fetchUsers({
    String? search,
    String? role,
    int limit = 20,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
    };
    final uri = Uri.parse('$_base/api/users').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    final body = jsonDecode(res.body);
    if (body is! List) return const [];
    return body
        .whereType<Map>()
        .map((e) => UserProfile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<PaginatedMessagesResponse> fetchMessages(
    String conversationId, {
    String? before,
    int limit = 50,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      if (before != null && before.isNotEmpty) 'before': before,
    };
    final uri = Uri.parse('$_base/api/conversations/$conversationId/messages')
        .replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    final body = jsonDecode(res.body);
    if (body is! Map) {
      throw Exception('Invalid messages response');
    }
    return PaginatedMessagesResponse.fromJson(Map<String, dynamic>.from(body));
  }

  /// `POST /api/media/chat-upload` — byte-based multipart (Web / Android / iOS).
  Future<Message> sendMediaMessage({
    required Uint8List fileBytes,
    required String fileName,
    required String conversationId,
    required String mediaType,
    double? durationSeconds,
    String? content,
    String? replyToMessageId,
  }) async {
    final uri = Uri.parse('$_base/api/media/chat-upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_authHeaders);
    request.fields['conversation_id'] = conversationId;
    request.fields['media_type'] = mediaType;
    if (durationSeconds != null) {
      request.fields['duration_seconds'] = durationSeconds.toString();
    }
    final caption = content?.trim();
    if (caption != null && caption.isNotEmpty) {
      request.fields['content'] = caption;
    }
    final replyId = replyToMessageId?.trim();
    if (replyId != null && replyId.isNotEmpty) {
      request.fields['reply_to_message_id'] = replyId;
    }

    final safeName = fileName.trim().isEmpty ? 'upload.bin' : fileName.trim();
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: safeName,
      ),
    );

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_errorMessage(res));
    }
    final body = jsonDecode(res.body);
    if (body is! Map) {
      throw Exception('Invalid media upload response');
    }
    return Message.fromJson(Map<String, dynamic>.from(body));
  }

  String _errorMessage(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        final detail = body['detail'];
        if (detail is String) return detail;
        if (detail is List) {
          return detail
              .map((e) => e is Map ? '${e['msg'] ?? e}' : '$e')
              .join('\n');
        }
        return detail.toString();
      }
    } catch (_) {}
    return 'Request failed (${res.statusCode})';
  }
}

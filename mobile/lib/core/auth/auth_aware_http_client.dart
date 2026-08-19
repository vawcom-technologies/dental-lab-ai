import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// HTTP client that refreshes JWTs on 401, then retries once.
///
/// Concurrent 401s share a single refresh. Auth endpoints never trigger
/// refresh or forced logout (wrong password must stay on the login form).
class AuthAwareHttpClient extends http.BaseClient {
  AuthAwareHttpClient({
    required http.Client inner,
    required void Function() onUnauthorized,
    required bool Function(Uri url) isAuthExempt,
    required Future<bool> Function() refreshAccess,
    required String? Function() currentAccessToken,
  })  : _inner = inner,
        _onUnauthorized = onUnauthorized,
        _isAuthExempt = isAuthExempt,
        _refreshAccess = refreshAccess,
        _currentAccessToken = currentAccessToken;

  final http.Client _inner;
  final void Function() _onUnauthorized;
  final bool Function(Uri url) _isAuthExempt;
  final Future<bool> Function() _refreshAccess;
  final String? Function() _currentAccessToken;

  static const _retryDelay = Duration(milliseconds: 180);

  Future<bool>? _refreshing;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return _send(request, allowRefresh: true);
  }

  Future<http.StreamedResponse> _send(
    http.BaseRequest request, {
    required bool allowRefresh,
  }) async {
    final replay = _replayableCopy(request);
    try {
      return await _sendOnce(
        request,
        replay: replay,
        allowRefresh: allowRefresh,
      );
    } on http.ClientException catch (error) {
      if (replay == null || !_shouldRetry(request.method, error)) {
        rethrow;
      }
      await Future<void>.delayed(_retryDelay);
      return _sendOnce(
        replay,
        replay: _replayableCopy(replay),
        allowRefresh: allowRefresh,
      );
    }
  }

  Future<http.StreamedResponse> _sendOnce(
    http.BaseRequest request, {
    required http.BaseRequest? replay,
    required bool allowRefresh,
  }) async {
    final streamed = await _inner.send(request);
    if (_isAuthExempt(request.url)) return streamed;

    if (streamed.statusCode == 401) {
      final bytes = await streamed.stream.toBytes();
      if (allowRefresh && replay != null) {
        final ok = await _sharedRefresh();
        if (ok) {
          final retry = _replayableCopy(replay) ?? replay;
          _applyAccessToken(retry);
          return _send(retry, allowRefresh: false);
        }
      }
      _onUnauthorized();
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable([bytes]),
        streamed.statusCode,
        contentLength: bytes.length,
        request: streamed.request,
        headers: streamed.headers,
        reasonPhrase: streamed.reasonPhrase,
        isRedirect: streamed.isRedirect,
        persistentConnection: streamed.persistentConnection,
      );
    }

    if (streamed.statusCode >= 400) {
      final bytes = await streamed.stream.toBytes();
      final body = utf8.decode(bytes, allowMalformed: true);
      if (looksLikeCredentialFailure(body)) {
        _onUnauthorized();
      }
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable([bytes]),
        streamed.statusCode,
        contentLength: bytes.length,
        request: streamed.request,
        headers: streamed.headers,
        reasonPhrase: streamed.reasonPhrase,
        isRedirect: streamed.isRedirect,
        persistentConnection: streamed.persistentConnection,
      );
    }

    return streamed;
  }

  Future<bool> _sharedRefresh() {
    final existing = _refreshing;
    if (existing != null) return existing;
    final future = _refreshAccess();
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) {
        _refreshing = null;
      }
    });
  }

  void _applyAccessToken(http.BaseRequest request) {
    final token = _currentAccessToken();
    if (token == null || token.isEmpty) return;
    request.headers['Authorization'] = 'Bearer $token';
  }

  /// Copies a JSON/text [http.Request] so a dropped keep-alive can be retried.
  static http.BaseRequest? _replayableCopy(http.BaseRequest request) {
    if (request is! http.Request) return null;
    final copy = http.Request(request.method, request.url)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..encoding = request.encoding
      ..bodyBytes = request.bodyBytes;
    copy.headers.addAll(request.headers);
    return copy;
  }

  static bool _shouldRetry(String method, http.ClientException error) {
    switch (method.toUpperCase()) {
      case 'GET':
      case 'HEAD':
      case 'OPTIONS':
        break;
      default:
        return false;
    }
    final msg = error.message.toLowerCase();
    return msg.contains('connection closed') ||
        msg.contains('connection reset') ||
        msg.contains('connection refused') ||
        msg.contains('broken pipe') ||
        msg.contains('timed out') ||
        msg.contains('network is unreachable');
  }

  static bool looksLikeCredentialFailure(String body) {
    final lower = body.toLowerCase();
    return lower.contains('could not validate credentials') ||
        lower.contains('not authenticated') ||
        lower.contains('invalid or expired token') ||
        lower.contains('jwt expired');
  }

  @override
  void close() => _inner.close();
}

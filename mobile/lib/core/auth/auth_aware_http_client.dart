import 'dart:convert';

import 'package:http/http.dart' as http;

/// HTTP client that detects session expiry (401 / credential errors) once.
class AuthAwareHttpClient extends http.BaseClient {
  AuthAwareHttpClient({
    required http.Client this._inner,
    required void Function() this._onUnauthorized,
    required bool Function(Uri url) this._isAuthExempt,
  });

  final http.Client _inner;
  final void Function() _onUnauthorized;
  final bool Function(Uri url) _isAuthExempt;

  static const _retryDelay = Duration(milliseconds: 180);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final replay = _replayableCopy(request);
    try {
      return await _sendOnce(request);
    } on http.ClientException catch (error) {
      if (replay == null || !_shouldRetry(request.method, error)) {
        rethrow;
      }
      await Future<void>.delayed(_retryDelay);
      return _sendOnce(replay);
    }
  }

  Future<http.StreamedResponse> _sendOnce(http.BaseRequest request) async {
    final streamed = await _inner.send(request);
    if (_isAuthExempt(request.url)) return streamed;

    if (streamed.statusCode == 401) {
      _onUnauthorized();
      return streamed;
    }

    // For other error statuses, scan body for credential-failure messages.
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

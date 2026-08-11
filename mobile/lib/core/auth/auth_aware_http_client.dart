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

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
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

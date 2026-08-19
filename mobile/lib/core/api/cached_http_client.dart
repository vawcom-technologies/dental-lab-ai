import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// In-memory GET cache with a 5-minute TTL.
///
/// Wrap the real transport ([AuthAwareHttpClient] / [http.Client]) so 401
/// handling still runs on network responses. Cache hits never touch the
/// network. Mutating methods evict related GET entries.
class CachedHttpClient extends http.BaseClient {
  CachedHttpClient({
    required http.Client inner,
    Duration ttl = defaultTtl,
  })  : _inner = inner,
        ttl = ttl;

  static const Duration defaultTtl = Duration(minutes: 5);

  /// Stripped before the request is forwarded. Set by [ApiClient] GET helpers
  /// when pull-to-refresh must bypass the cache.
  static const String forceRefreshHeader = 'x-cache-bypass';

  /// Skip caching large / binary payloads (scans, R2 media, videos).
  static const int maxCachedBodyBytes = 1024 * 1024;

  final http.Client _inner;
  final Duration ttl;
  final Map<String, _CacheEntry> _cache = {};

  void clearCache() => _cache.clear();

  /// Drop GET entries whose origin+path matches [url] or shares its API prefix.
  void invalidateFor(Uri url) {
    final prefixes = _invalidationPrefixes(url);
    if (prefixes.isEmpty) {
      _cache.remove(_cacheKey(url));
      return;
    }
    _cache.removeWhere((key, _) {
      final cached = Uri.tryParse(key);
      if (cached == null) return false;
      final cachedBase = _originAndPath(cached);
      for (final prefix in prefixes) {
        if (cachedBase == prefix || cachedBase.startsWith('$prefix/')) {
          return true;
        }
      }
      return false;
    });
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final method = request.method.toUpperCase();
    final bypass = _takeForceRefresh(request);

    if (method != 'GET') {
      if (_isMutating(method)) {
        invalidateFor(request.url);
      }
      return _inner.send(request);
    }

    final key = _cacheKey(request.url);
    if (bypass) {
      _cache.remove(key);
    } else {
      final hit = _cache[key];
      if (hit != null) {
        if (hit.isFresh(ttl)) {
          return hit.toStreamed(request);
        }
        _cache.remove(key);
      }
    }

    final streamed = await _inner.send(request);
    if (!_shouldCache(streamed)) {
      return streamed;
    }

    final bytes = await streamed.stream.toBytes();
    if (bytes.length > maxCachedBodyBytes) {
      return _replay(streamed, bytes);
    }

    final entry = _CacheEntry(
      bytes: Uint8List.fromList(bytes),
      statusCode: streamed.statusCode,
      headers: Map<String, String>.from(streamed.headers),
      createdAt: DateTime.now(),
      reasonPhrase: streamed.reasonPhrase,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
    );
    _cache[key] = entry;
    return entry.toStreamed(request);
  }

  @override
  void close() => _inner.close();

  static bool _isMutating(String method) {
    switch (method) {
      case 'POST':
      case 'PUT':
      case 'PATCH':
      case 'DELETE':
        return true;
      default:
        return false;
    }
  }

  static bool _takeForceRefresh(http.BaseRequest request) {
    final headers = request.headers;
    final raw = headers[forceRefreshHeader] ??
        headers['X-Cache-Bypass'] ??
        headers['x-cache-bypass'];
    headers.remove(forceRefreshHeader);
    headers.remove('X-Cache-Bypass');
    headers.remove('x-cache-bypass');
    if (raw == null) return false;
    final value = raw.trim().toLowerCase();
    return value == '1' || value == 'true' || value == 'yes';
  }

  static bool _shouldCache(http.StreamedResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }
    final ct = (response.headers['content-type'] ?? '').toLowerCase();
    if (ct.startsWith('image/') ||
        ct.startsWith('video/') ||
        ct.startsWith('audio/') ||
        ct.contains('octet-stream')) {
      return false;
    }
    return true;
  }

  static String _cacheKey(Uri url) => url.toString();

  static String _originAndPath(Uri uri) {
    var path = uri.path.isEmpty ? '/' : uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return '${uri.scheme}://${uri.authority}$path';
  }

  /// Full path plus ancestors down to `/api/{resource}` so
  /// `POST /api/patients` clears `GET /api/patients` and
  /// `PATCH /api/patients/:id` clears both the row and the collection.
  static List<String> _invalidationPrefixes(Uri uri) {
    final origin = '${uri.scheme}://${uri.authority}';
    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final parts = [
      for (final p in path.split('/'))
        if (p.isNotEmpty) p,
    ];
    if (parts.isEmpty) return const [];
    final prefixes = <String>[];
    while (parts.length >= 2) {
      prefixes.add('$origin/${parts.join('/')}');
      if (parts.length == 2) break;
      parts.removeLast();
    }
    return prefixes;
  }

  static http.StreamedResponse _replay(
    http.StreamedResponse streamed,
    List<int> bytes,
  ) {
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
}

class _CacheEntry {
  const _CacheEntry({
    required this.bytes,
    required this.statusCode,
    required this.headers,
    required this.createdAt,
    this.reasonPhrase,
    this.isRedirect = false,
    this.persistentConnection = true,
  });

  final Uint8List bytes;
  final int statusCode;
  final Map<String, String> headers;
  final DateTime createdAt;
  final String? reasonPhrase;
  final bool isRedirect;
  final bool persistentConnection;

  bool isFresh(Duration ttl) => DateTime.now().difference(createdAt) < ttl;

  http.StreamedResponse toStreamed(http.BaseRequest request) {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      statusCode,
      contentLength: bytes.length,
      request: request,
      headers: Map<String, String>.from(headers),
      reasonPhrase: reasonPhrase,
      isRedirect: isRedirect,
      persistentConnection: persistentConnection,
    );
  }
}

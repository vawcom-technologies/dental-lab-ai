import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain / Keystore persistence for JWTs. Never use SharedPreferences.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _accessKey = 'edp.access_token';
  static const _refreshKey = 'edp.refresh_token';

  final FlutterSecureStorage _storage;

  Future<void> save({
    required String? accessToken,
    required String? refreshToken,
  }) async {
    if (accessToken != null && accessToken.isNotEmpty) {
      await _storage.write(key: _accessKey, value: accessToken);
    } else {
      await _storage.delete(key: _accessKey);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshKey, value: refreshToken);
    } else {
      await _storage.delete(key: _refreshKey);
    }
  }

  Future<String?> readAccess() => _storage.read(key: _accessKey);

  Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

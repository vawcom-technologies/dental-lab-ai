import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'enc_cache_scrub.dart'
    if (dart.library.io) 'enc_cache_scrub_io.dart' as disk;

/// Local AES cache (chairside) before sync.
///
/// Key material lives in [FlutterSecureStorage] (per-device). Ciphertext is
/// stored in SharedPreferences under `enc_file_*` (and wiped on logout).
class LocalEncryptedStore {
  LocalEncryptedStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const prefsPrefix = 'enc_file_';
  static const _deviceKeyName = 'edp.device_aes_key';

  final FlutterSecureStorage _storage;
  enc.Key? _key;

  Future<enc.Key> _ensureKey() async {
    final cached = _key;
    if (cached != null) return cached;
    var b64 = await _storage.read(key: _deviceKeyName);
    if (b64 == null || b64.isEmpty) {
      final generated = enc.Key.fromSecureRandom(32);
      b64 = base64Encode(generated.bytes);
      await _storage.write(key: _deviceKeyName, value: b64);
      _key = generated;
      return generated;
    }
    final key = enc.Key(base64Decode(b64));
    _key = key;
    return key;
  }

  Future<void> save({
    required String relativePath,
    required Uint8List bytes,
  }) async {
    final key = await _ensureKey();
    final iv = enc.IV.fromSecureRandom(16);
    final cipher = enc.Encrypter(enc.AES(key)).encryptBytes(bytes, iv: iv);
    final packed = Uint8List(16 + cipher.bytes.length)
      ..setAll(0, iv.bytes)
      ..setAll(16, cipher.bytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$prefsPrefix$relativePath', base64Encode(packed));
  }

  Future<Uint8List> read(String relativePath) async {
    final prefs = await SharedPreferences.getInstance();
    final b64 = prefs.getString('$prefsPrefix$relativePath');
    if (b64 == null) {
      throw StateError('Missing encrypted cache: $relativePath');
    }
    final packed = base64Decode(b64);
    if (packed.length <= 16) {
      throw StateError('Corrupt encrypted cache: $relativePath');
    }
    final key = await _ensureKey();
    final iv = enc.IV(packed.sublist(0, 16));
    final decrypted = enc.Encrypter(enc.AES(key)).decryptBytes(
      enc.Encrypted(packed.sublist(16)),
      iv: iv,
    );
    return Uint8List.fromList(decrypted);
  }

  /// Drop every `enc_file_*` cache entry (prefs + leftover files on disk).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = [
      for (final key in prefs.getKeys())
        if (key.startsWith(prefsPrefix)) key,
    ];
    for (final key in keys) {
      await prefs.remove(key);
    }
    await disk.scrubEncFilesOnDisk(prefix: prefsPrefix);
  }
}

enum SyncOpType { photoUpload, scanUpload, patientCreate }

class SyncQueueItem {
  SyncQueueItem({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final SyncOpType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int attempts;
  String? lastError;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'attempts': attempts,
        'lastError': lastError,
      };

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) => SyncQueueItem(
        id: json['id'] as String,
        type: SyncOpType.values.byName(json['type'] as String),
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.parse(json['createdAt'] as String),
        attempts: json['attempts'] as int? ?? 0,
        lastError: json['lastError'] as String?,
      );
}

/// Offline-first sync queue. Enqueue when offline; flush when online.
class SyncQueue {
  static const _prefsKey = 'elite_dent_sync_queue_v1';

  Future<List<SyncQueueItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => SyncQueueItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _save(List<SyncQueueItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> enqueue(SyncQueueItem item) async {
    final items = await load();
    items.add(item);
    await _save(items);
  }

  Future<void> remove(String id) async {
    final items = await load();
    items.removeWhere((e) => e.id == id);
    await _save(items);
  }

  Future<void> update(SyncQueueItem item) async {
    final items = await load();
    final i = items.indexWhere((e) => e.id == item.id);
    if (i >= 0) {
      items[i] = item;
      await _save(items);
    }
  }

  Future<int> pendingCount() async => (await load()).length;
}

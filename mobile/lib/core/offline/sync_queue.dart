import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:shared_preferences/shared_preferences.dart';

/// Local AES encrypted cache (chairside) before sync.
/// Uses SharedPreferences so it works on web + iPad.
class LocalEncryptedStore {
  LocalEncryptedStore({String? passphrase})
      : _key = enc.Key.fromUtf8(
          (passphrase ?? 'elite-dent-week2-dev-key!!').padRight(32).substring(0, 32),
        );

  final enc.Key _key;
  final _iv = enc.IV.fromLength(16);

  Future<void> save({
    required String relativePath,
    required Uint8List bytes,
  }) async {
    final encrypted = enc.Encrypter(enc.AES(_key)).encryptBytes(bytes, iv: _iv);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('enc_file_$relativePath', base64Encode(encrypted.bytes));
  }

  Future<Uint8List> read(String relativePath) async {
    final prefs = await SharedPreferences.getInstance();
    final b64 = prefs.getString('enc_file_$relativePath');
    if (b64 == null) {
      throw StateError('Missing encrypted cache: $relativePath');
    }
    final decrypted = enc.Encrypter(enc.AES(_key)).decryptBytes(
      enc.Encrypted(base64Decode(b64)),
      iv: _iv,
    );
    return Uint8List.fromList(decrypted);
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

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'sync_queue.dart';

class SyncService {
  SyncService({required this.api, SyncQueue? queue})
      : queue = queue ?? SyncQueue();

  final ApiClient api;
  final SyncQueue queue;
  final store = LocalEncryptedStore();

  /// SharedPreferences / localStorage can't hold Exocad-sized PLYs (~tens of MB).
  /// Base64 + AES inflate size further, so keep a conservative ceiling.
  static const maxLocalCacheBytes = 900 * 1024;

  Future<bool> get isOnline async {
    final results = await Connectivity().checkConnectivity();
    if (results.isEmpty) return false;
    return !results.every((r) => r == ConnectivityResult.none);
  }

  bool _fitsLocalCache(Uint8List bytes) => bytes.length <= maxLocalCacheBytes;

  Never _tooLargeForOfflineCache(String kind) {
    throw Exception(
      kIsWeb
          ? 'This $kind is too large for the browser offline cache '
              '(localStorage quota). Stay online and upload again — '
              'files go straight to the server when connected.'
          : 'This $kind is too large for the encrypted offline cache on this device. '
              'Connect to the network and upload again.',
    );
  }

  /// Save photo locally encrypted; upload now or enqueue if offline.
  Future<Map<String, dynamic>> capturePhoto({
    required String patientId,
    required String angle,
    required Uint8List bytes,
    required String filename,
  }) =>
      _capture(
        kind: 'photo',
        type: SyncOpType.photoUpload,
        patientId: patientId,
        bytes: bytes,
        filename: filename,
        extra: {'angle': angle},
      );

  Future<Map<String, dynamic>> captureScan({
    required String patientId,
    required Uint8List bytes,
    required String filename,
  }) =>
      _capture(
        kind: 'scan',
        type: SyncOpType.scanUpload,
        patientId: patientId,
        bytes: bytes,
        filename: filename,
      );

  /// Upload now when online (never block chairside on a cache write); on
  /// failure or offline, encrypt locally and queue it.
  Future<Map<String, dynamic>> _capture({
    required String kind,
    required SyncOpType type,
    required String patientId,
    required Uint8List bytes,
    required String filename,
    Map<String, dynamic> extra = const {},
  }) async {
    final rel = 'patient_$patientId/${kind}s/${DateTime.now().millisecondsSinceEpoch}_$filename';
    final payload = {'patientId': patientId, 'relativePath': rel, 'filename': filename, ...extra};
    Object? error;
    if (await isOnline) {
      try {
        return await _upload(type, payload, bytes);
      } catch (e) {
        if (!_fitsLocalCache(bytes)) rethrow;
        error = e;
      }
    } else if (!_fitsLocalCache(bytes)) {
      _tooLargeForOfflineCache(kind);
    }
    await store.save(relativePath: rel, bytes: bytes);
    await queue.enqueue(
      SyncQueueItem(
        id: '${kind}_${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        payload: payload,
        createdAt: DateTime.now(),
        lastError: error?.toString(),
      ),
    );
    return {
      'queued': true,
      'relative_path': rel,
      'note': error == null
          ? 'Offline — encrypted locally and queued for sync.'
          : 'Saved encrypted offline; will sync when online.',
    };
  }

  Future<Map<String, dynamic>> _upload(SyncOpType type, Map<String, dynamic> p, Uint8List bytes) {
    final patientId = p['patientId'] as String;
    final filename = p['filename'] as String;
    return switch (type) {
      SyncOpType.photoUpload => api.uploadPatientPhoto(
          patientId: patientId,
          angle: p['angle'] as String,
          bytes: bytes,
          filename: filename,
        ),
      SyncOpType.scanUpload => api.uploadPatientScan(patientId: patientId, bytes: bytes, filename: filename),
      SyncOpType.patientCreate => throw UnsupportedError('patientCreate is not queued'),
    };
  }

  /// Flush pending queue items to the API.
  Future<int> flush() async {
    if (!await isOnline) return 0;
    final items = await queue.load();
    var synced = 0;
    for (final item in items) {
      // Queued before patient-scoped uploads (old integer caseId): no way to
      // map it to a patient, so drop it instead of retrying forever.
      if (item.type != SyncOpType.patientCreate && item.payload['patientId'] is! String) {
        debugPrint('Sync: dropping ${item.id}, queued with old caseId ${item.payload['caseId']}');
        await queue.remove(item.id);
        continue;
      }
      try {
        if (item.type != SyncOpType.patientCreate) {
          final bytes = await store.read(item.payload['relativePath'] as String);
          await _upload(item.type, item.payload, bytes);
        }
        await queue.remove(item.id);
        synced++;
      } catch (e) {
        item.attempts += 1;
        item.lastError = e.toString();
        await queue.update(item);
        debugPrint('Sync failed for ${item.id}: $e');
      }
    }
    return synced;
  }
}

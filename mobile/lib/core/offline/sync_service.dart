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

  Future<bool> get isOnline async {
    final results = await Connectivity().checkConnectivity();
    if (results.isEmpty) return false;
    return !results.every((r) => r == ConnectivityResult.none);
  }

  /// Save photo locally encrypted; upload now or enqueue if offline.
  Future<Map<String, dynamic>> capturePhoto({
    required int caseId,
    required String angle,
    required Uint8List bytes,
    required String filename,
  }) async {
    final rel = 'case_$caseId/photos/${DateTime.now().millisecondsSinceEpoch}_$filename';
    await store.save(relativePath: rel, bytes: bytes);

    if (await isOnline) {
      try {
        return await api.uploadPhoto(
          caseId: caseId,
          angle: angle,
          bytes: bytes,
          filename: filename,
        );
      } catch (e) {
        await queue.enqueue(
          SyncQueueItem(
            id: 'photo_${DateTime.now().microsecondsSinceEpoch}',
            type: SyncOpType.photoUpload,
            payload: {
              'caseId': caseId,
              'angle': angle,
              'relativePath': rel,
              'filename': filename,
            },
            createdAt: DateTime.now(),
            lastError: e.toString(),
          ),
        );
        return {
          'queued': true,
          'relative_path': rel,
          'note': 'Saved encrypted offline; will sync when online.',
        };
      }
    }

    await queue.enqueue(
      SyncQueueItem(
        id: 'photo_${DateTime.now().microsecondsSinceEpoch}',
        type: SyncOpType.photoUpload,
        payload: {
          'caseId': caseId,
          'angle': angle,
          'relativePath': rel,
          'filename': filename,
        },
        createdAt: DateTime.now(),
      ),
    );
    return {
      'queued': true,
      'relative_path': rel,
      'note': 'Offline — encrypted locally and queued for sync.',
    };
  }

  Future<Map<String, dynamic>> captureScan({
    required int caseId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final rel = 'case_$caseId/scans/${DateTime.now().millisecondsSinceEpoch}_$filename';
    await store.save(relativePath: rel, bytes: bytes);

    if (await isOnline) {
      try {
        return await api.uploadScan(caseId: caseId, bytes: bytes, filename: filename);
      } catch (e) {
        await queue.enqueue(
          SyncQueueItem(
            id: 'scan_${DateTime.now().microsecondsSinceEpoch}',
            type: SyncOpType.scanUpload,
            payload: {
              'caseId': caseId,
              'relativePath': rel,
              'filename': filename,
            },
            createdAt: DateTime.now(),
            lastError: e.toString(),
          ),
        );
        return {
          'queued': true,
          'note': 'Saved encrypted offline; will sync when online.',
        };
      }
    }

    await queue.enqueue(
      SyncQueueItem(
        id: 'scan_${DateTime.now().microsecondsSinceEpoch}',
        type: SyncOpType.scanUpload,
        payload: {
          'caseId': caseId,
          'relativePath': rel,
          'filename': filename,
        },
        createdAt: DateTime.now(),
      ),
    );
    return {
      'queued': true,
      'note': 'Offline — encrypted locally and queued for sync.',
    };
  }

  /// Flush pending queue items to the API.
  Future<int> flush() async {
    if (!await isOnline) return 0;
    final items = await queue.load();
    var synced = 0;
    for (final item in items) {
      try {
        switch (item.type) {
          case SyncOpType.photoUpload:
            final bytes = await store.read(item.payload['relativePath'] as String);
            await api.uploadPhoto(
              caseId: item.payload['caseId'] as int,
              angle: item.payload['angle'] as String,
              bytes: bytes,
              filename: item.payload['filename'] as String,
            );
          case SyncOpType.scanUpload:
            final bytes = await store.read(item.payload['relativePath'] as String);
            await api.uploadScan(
              caseId: item.payload['caseId'] as int,
              bytes: bytes,
              filename: item.payload['filename'] as String,
            );
          case SyncOpType.patientCreate:
            // Reserved for Week 2+ full offline patient create
            break;
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

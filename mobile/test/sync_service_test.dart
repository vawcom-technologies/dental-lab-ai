import 'dart:typed_data';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/offline/sync_queue.dart';
import 'package:dental_lab_ai/core/offline/sync_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Always online, without the connectivity plugin.
class _OnlineSync extends SyncService {
  _OnlineSync({required super.api});

  @override
  Future<bool> get isOnline async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('flush uploads to patient endpoints and drops old caseId items', () async {
    final urls = <String>[];
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient.streaming((req, body) async {
        urls.add(req.url.path);
        await body.drain<void>();
        return http.StreamedResponse(Stream.value('{"id":"x"}'.codeUnits), 201);
      }),
    );
    final sync = _OnlineSync(api: api);
    await sync.store.save(relativePath: 'patient_p1/scans/a.ply', bytes: Uint8List.fromList([1, 2]));
    final now = DateTime.now();
    await sync.queue.enqueue(SyncQueueItem(
      id: 'old',
      type: SyncOpType.scanUpload,
      payload: {'caseId': 7, 'relativePath': 'case_7/scans/a.ply', 'filename': 'a.ply'},
      createdAt: now,
    ));
    await sync.queue.enqueue(SyncQueueItem(
      id: 'new',
      type: SyncOpType.scanUpload,
      payload: {'patientId': 'p1', 'relativePath': 'patient_p1/scans/a.ply', 'filename': 'a.ply'},
      createdAt: now,
    ));

    expect(await sync.flush(), 1);
    expect(urls, ['/api/patients/p1/scans']);
    expect(await sync.queue.pendingCount(), 0, reason: 'old item dropped, new one synced');
  });
}

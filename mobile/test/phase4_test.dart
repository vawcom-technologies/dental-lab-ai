import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/errors/user_facing_error.dart';
import 'package:dental_lab_ai/core/l10n/app_localizations.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/features/chat/models/chat_models.dart';
import 'package:dental_lab_ai/features/lab/join_lab_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Fake backend for a dentist; [me] is what /api/auth/me returns now.
class _Backend {
  Map<String, dynamic> me = {'id': 'd1', 'role': 'dentist', 'lab_id': null, 'lab_name': null, 'pending_join': null};
  final calls = <String>[];

  ApiClient api() => ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          final path = '${req.method} ${req.url.path}';
          final body = switch (path) {
            'GET /api/auth/me' => me,
            'GET /api/labs' => [
                {'id': 'lab1', 'name': 'Dentallabor Süd'},
              ],
            'POST /api/auth/signin' => {'access_token': 't', 'user_id': 'd1', 'role': 'dentist'},
            'POST /api/auth/me/lab-join-deferred' => {
                ...me,
                'lab_join_deferred_at': '2026-10-19T12:00:00Z',
              },
            'GET /api/patients' => {
                'status': 'SUCCESS',
                'payload': {'patients': <Map<String, dynamic>>[]},
              },
            _ => <String, dynamic>{},
          };
          return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
}

final _de = AppLocalizations('de');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('needsLab only once /me says the dentist has no lab', () async {
    final b = _Backend();
    final api = b.api();
    await api.signIn('d@x.de', 'pw'); // sign-in without lab fields
    expect(api.needsLab, isFalse, reason: 'unknown yet: no flash of the picker');
    await api.fetchMe(forceRefresh: true);
    expect(api.needsLab, isTrue);
    b.me = {...b.me, 'lab_id': 'lab1', 'lab_name': 'Dentallabor Süd'};
    await api.fetchMe(forceRefresh: true);
    expect(api.needsLab, isFalse);
    expect(api.labName, 'Dentallabor Süd');
  });

  test('needsLab is false after Request later (deferred)', () async {
    final b = _Backend();
    final api = b.api();
    await api.signIn('d@x.de', 'pw');
    await api.fetchMe(forceRefresh: true);
    expect(api.needsLab, isTrue);
    b.me = {
      ...b.me,
      'lab_join_deferred_at': '2026-10-19T12:00:00Z',
    };
    await api.fetchMe(forceRefresh: true);
    expect(api.labJoinDeferred, isTrue);
    expect(api.needsLab, isFalse);
  });

  testWidgets('join page: waiting state, withdraw, then into the app', (tester) async {
    final b = _Backend()
      ..me['pending_join'] = {'id': 'j1', 'lab_id': 'lab1', 'lab_name': 'Dentallabor Süd', 'created_at': '2026-10-18T09:00:00Z'};
    final api = b.api();
    await api.signIn('d@x.de', 'pw');
    var ready = false;
    tester.view.physicalSize = const Size(1194, 834) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(home: JoinLabPage(api: api, onReady: () => ready = true)),
    ));
    await tester.pumpAndSettle();
    expect(find.text(_de.trp('join.waiting', {'lab': 'Dentallabor Süd'})), findsOneWidget);

    // Withdraw → DELETE, then /me shows no pending: back to the lab list.
    b.me['pending_join'] = null;
    await tester.tap(find.text(_de.tr('join.withdraw')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_de.tr('join.withdraw')).last); // confirm
    await tester.pumpAndSettle();
    expect(b.calls, contains('DELETE /api/labs/join-requests/mine'));
    expect(find.text('Dentallabor Süd'), findsOneWidget);
    expect(find.text(_de.tr('join.request')), findsOneWidget);

    // The lab accepted meanwhile: a recheck opens the app.
    b.me = {...b.me, 'lab_id': 'lab1', 'lab_name': 'Dentallabor Süd'};
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(ready, isTrue);
  });

  test('dentists in chat read "Lab · Clinic"', () {
    final u = UserProfile.fromJson({
      'id': 'd1', 'name': 'Dr. Weiss', 'role': 'dentist', 'lab_name': 'Dentallabor Süd', 'clinic_name': 'Praxis Weiss',
    });
    expect(u.subtitle, 'Dentallabor Süd · Praxis Weiss');
  });

  test('NO_LAB on create maps to a clear message (403 only)', () {
    expect(friendlyHttpError(statusCode: 403, code: 'NO_LAB'), AppLocalizations.current.tr('join.noLabError'));
    expect(friendlyHttpError(statusCode: 400, code: 'NO_LAB', detail: 'Choose a lab first.'), 'Choose a lab first.');
  });

  testWidgets('join page: Request later unlocks the app', (tester) async {
    final b = _Backend();
    final api = b.api();
    await api.signIn('d@x.de', 'pw');
    await api.fetchMe(forceRefresh: true);
    var ready = false;
    tester.view.physicalSize = const Size(1194, 834) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(home: JoinLabPage(api: api, onReady: () => ready = true)),
    ));
    await tester.pumpAndSettle();
    expect(find.text(_de.tr('join.requestLater')), findsOneWidget);
    await tester.tap(find.text(_de.tr('join.requestLater')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_de.tr('join.requestLater')).last);
    await tester.pumpAndSettle();
    expect(b.calls, contains('POST /api/auth/me/lab-join-deferred'));
    expect(ready, isTrue);
    expect(api.labJoinDeferred, isTrue);
    expect(api.needsLab, isFalse);
  });
}

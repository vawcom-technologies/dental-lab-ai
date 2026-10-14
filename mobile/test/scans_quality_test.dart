import 'dart:async';
import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/app_localizations.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/core/session/patient_session.dart';
import 'package:dental_lab_ai/core/theme/app_theme.dart';
import 'package:dental_lab_ai/features/scans/scans_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One patient with one scan that has no stored result and no preview file
/// (the case that used to show nothing at all).
ApiClient _api(
  List<http.Response> validateReplies,
  List<String> calls, {
  Map<String, Object?> row = const {},
  Future<http.Response>? pendingValidate,
}) =>
    ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        final path = req.url.path;
        if (path == '/api/patients') {
          return http.Response(jsonEncode([
            {'id': 'p1', 'first_name': 'Ann', 'last_name': 'Lee'},
          ]), 200);
        }
        if (path == '/api/patients/p1/scans') {
          return http.Response(jsonEncode([
            {'id': 's1', 'patient_id': 'p1', 'file_name': 'a.ply', 'file_url': '', ...row},
          ]), 200);
        }
        if (path == '/api/scans/s1/validate') {
          calls.add(path);
          return pendingValidate ?? validateReplies.removeAt(0);
        }
        return http.Response('[]', 200);
      }),
    );

Future<void> _pump(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(1180, 820) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ScansPage(api: api, patientSession: PatientSession(api)),
        ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _t(String key) => AppLocalizations.current.tr(key);

void main() {
  testWidgets('failed check shows an error with Retry, and Retry gets a result',
      (tester) async {
    final calls = <String>[];
    final api = _api([
      http.Response('{"detail":"boom"}', 500),
      http.Response(jsonEncode({
        'id': 's1', 'patient_id': 'p1', 'uploaded_by': 'u1', 'file_key': 'k',
        'file_url': '', 'file_name': 'a.ply', 'validation_result': 'good',
        'issues': [], 'reasons': ['Checks passed'], 'prompt_rescan': false,
      }), 200),
    ], calls);
    await _pump(tester, api);

    expect(calls, hasLength(1)); // checked even though the preview can't load
    expect(find.text(_t('s.qError')), findsOneWidget);

    // The "preview unavailable" snackbar sits over the button until it times out.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text(_t('common.retry')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(calls, hasLength(2));
    expect(find.text(_t('s.qGood')), findsOneWidget);
    expect(find.text(_t('s.qError')), findsNothing);
  });

  testWidgets('bad scan explains each issue in plain German, never server text',
      (tester) async {
    final api = _api([
      http.Response(jsonEncode({
        'id': 's1', 'patient_id': 'p1', 'uploaded_by': 'u1', 'file_key': 'k',
        'file_url': '', 'file_name': 'a.ply', 'validation_result': 'bad',
        'issues': [
          {'severity': 'high', 'code': 'rough_surface', 'message': 'rough patches 1.2%'},
          {'severity': 'medium', 'code': 'some_future_check', 'message': 'new thing'},
        ],
        'reasons': ['Rough, ridged or stepped patches'], 'prompt_rescan': true,
      }), 200),
    ], []);
    await _pump(tester, api);
    // German is the app default.
    expect(find.text('Dieser Scan hat Probleme – bitte neu scannen, bevor der Patient geht.'),
        findsOneWidget);
    expect(find.text('Raue oder unebene Stellen'), findsOneWidget);
    expect(find.textContaining('Speichel oder Blut'), findsOneWidget);
    expect(find.text('Neu scannen'), findsWidgets); // severity label (+ list label)
    expect(find.textContaining('rough patches'), findsNothing);
    expect(find.textContaining('Rough, ridged'), findsNothing);
    // A code this build doesn't know still shows, with a generic title.
    expect(find.text('Scanproblem'), findsOneWidget);
    expect(find.text('new thing'), findsOneWidget);
  });

  testWidgets('raw list row renders while its check is still running', (tester) async {
    // The server lists unchecked scans with untyped empty highlight fields.
    final reply = Completer<http.Response>();
    final api = _api([], [],
        row: {'validation_result': null, 'rough_points': [], 'rough_radius': 0},
        pendingValidate: reply.future);
    await _pump(tester, api);
    expect(tester.takeException(), isNull);
    expect(find.text(_t('s.qChecking')), findsOneWidget);
    reply.complete(http.Response('{}', 500)); // let the request's timer finish
    await tester.pump(const Duration(seconds: 1));
  });
}

import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/app_localizations.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/core/session/patient_session.dart';
import 'package:dental_lab_ai/features/scans/mesh_viewer.dart';
import 'package:dental_lab_ai/features/scans/scans_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

ApiClient _api() => ApiClient(
      baseUrl: 'http://x',
      httpClient: MockClient((req) async {
        final path = req.url.path;
        if (path.contains('login')) {
          return http.Response(jsonEncode({'access_token': 't', 'user_id': 'u1', 'role': 'dentist'}), 200);
        }
        if (path == '/api/patients') {
          return http.Response(
              jsonEncode({
                'status': 'SUCCESS',
                'http_code': 200,
                'payload': {
                  'patients': [
                    {'id': 'p1', 'first_name': 'Lena', 'last_name': 'Weber', 'status': 'in_progress', 'created_by': 'u1'},
                  ],
                },
              }),
              200);
        }
        if (path == '/api/patients/p1/scans') {
          return http.Response(
              jsonEncode([
                {
                  'id': 's1',
                  'filename': 'Oberkiefer_Weber_sehr_langer_Dateiname_2026-10-19.stl',
                  'validation_result': 'bad',
                  'prompt_rescan': true,
                  'on_case': false,
                  'created_at': '2026-10-19T09:12:00Z',
                  'issues': [
                    {'code': 'holes', 'severity': 'high', 'message': 'Holes in the mesh'},
                    {'code': 'unknown_x', 'severity': 'medium', 'message': 'Something else entirely, described at length'},
                  ],
                },
              ]),
              200);
        }
        // Lists for list endpoints, objects for the rest (case, quality check).
        final list = path.contains('inbox') || path.endsWith('photos') || path.endsWith('scans');
        return http.Response(list ? '[]' : '{}', 200);
      }),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
  });

  for (final size in const [Size(1180, 820), Size(820, 1180), Size(1376, 1032)]) {
    testWidgets('scans: fullscreen in and out never squeezes the inspector at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final api = _api();
      await tester.runAsync(() => api.signIn('a@b.de', 'x'));
      final session = PatientSession(api);
      await tester.runAsync(() => session.ensureLoaded());
      session.select(session.patients.first);
      await tester.pumpWidget(LocaleScope(
        controller: LocaleController(),
        child: MaterialApp(home: Scaffold(body: ScansPage(api: api, patientSession: session, active: true))),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
      final toggle = find.byWidgetPredicate(
          (w) => w is Icon && (w.icon == Icons.fullscreen || w.icon == Icons.fullscreen_exit));
      for (final tip in ['enter', 'exit']) {
        await tester.tap(toggle.first);
        // Step through the animation frame by frame.
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          expect(tester.takeException(), isNull, reason: '$tip frame $i');
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('scans: hold the viewer for the action sheet; bad-scan details open in a sheet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1180, 820) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final api = _api();
    await tester.runAsync(() => api.signIn('a@b.de', 'x'));
    final session = PatientSession(api);
    await tester.runAsync(() => session.ensureLoaded());
    session.select(session.patients.first);
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(home: Scaffold(body: ScansPage(api: api, patientSession: session, active: true))),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    final de = AppLocalizations('de');
    // Hold the viewer (not the list row).
    await tester.longPress(find.byType(MeshViewer));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text(de.scansDelete), findsWidgets);
    expect(find.text(de.tr('sq.whyBad')), findsOneWidget);
    await tester.tap(find.text(de.tr('sq.whyBad')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(CupertinoActionSheet), findsNothing);
    expect(find.text(de.tr('sq.badTitle')), findsOneWidget);
    expect(find.text(de.tr('sq.holes.t')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

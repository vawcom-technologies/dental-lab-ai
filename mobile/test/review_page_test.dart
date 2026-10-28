import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/core/session/patient_session.dart';
import 'package:dental_lab_ai/features/cases/review_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

Map<String, dynamic> _patient(String status, {bool updated = false}) => {
      'id': 'p-$status',
      'first_name': 'Max',
      'last_name': status,
      'status': status,
      'updated_at': '2026-10-05T09:00:00Z',
      'dentist_updated': updated,
    };

final _case = {
  'status': 'rejected',
  'items': {'scan': true, 'shade': true, 'smile': true},
  'missing': [],
  'lab': {'id': 'l1', 'name': 'Süd'},
  'shared_with_lab': true,
  'can_submit': false,
  'can_review': false,
  'can_suggest': false,
  'updated_since_rejection': true,
  'lab_review': {'feedback': {}, 'suggestions': {}},
  'last_rejection': {
    'remarks': 'Fix it',
    'items': [
      {'item': 'scan', 'status': 'needs_work', 'note': 'Blurry'},
    ],
  },
  'events': [],
};

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
  });

  for (final size in const [Size(1194, 834), Size(834, 1194), Size(390, 844)]) {
    testWidgets('lab review queue at $size: every tab loads, rejected shows "updated"', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/case')) {
            return http.Response(jsonEncode(_case), 200);
          }
          if (req.url.path != '/api/patients') return http.Response('[]', 200);
          final st = req.url.queryParameters['status'] ?? 'in_review';
          return http.Response(
            jsonEncode({
              'status': 'SUCCESS',
              'payload': {'patients': [_patient(st, updated: st == 'rejected')]},
            }),
            200,
          );
        }),
      );
      final session = PatientSession(api);
      await tester.pumpWidget(LocaleScope(
        controller: LocaleController(),
        child: MaterialApp(
          home: Scaffold(body: ReviewPage(api: api, cases: session.cases, patients: session)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Max in_review'), findsOneWidget);
      await tester.tap(find.textContaining('Abgelehnt').first);
      await tester.pumpAndSettle();
      expect(find.text('Max rejected'), findsOneWidget);
      await tester.tap(find.text('Max rejected'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Vom Labor abgelehnt'), findsOneWidget);
    });
  }
}

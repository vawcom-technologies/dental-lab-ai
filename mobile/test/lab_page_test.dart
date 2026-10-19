import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/app_localizations.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/core/theme/app_theme.dart';
import 'package:dental_lab_ai/features/lab/lab_dashboard_page.dart';
import 'package:dental_lab_ai/features/lab/lab_page.dart';
import 'package:dental_lab_ai/shell/app_shell.dart';
import 'package:dental_lab_ai/features/patients/patients_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _requests = <http.Request>[];

final _fixtures = <String, Object>{
  'GET /api/labs/lab1/dentists': [
    {'id': 'd1', 'name': 'Dr. Weiss', 'email': 'weiss@x.de', 'clinic_name': 'Praxis Weiss'},
  ],
  'GET /api/labs/lab1/requests': [
    {
      'id': 'q1', 'kind': 'join', 'status': 'pending', 'reason': null, 'created_at': '2026-10-10T09:00:00Z',
      'dentist': {'id': 'd2', 'name': 'Dr. Neu', 'email': 'neu@x.de', 'clinic_name': 'Praxis Neu'},
    },
    {
      'id': 'q2', 'kind': 'remove', 'status': 'approved', 'reason': 'Moved away', 'created_at': '2026-10-01T09:00:00Z',
      'dentist': {'id': 'd3', 'name': 'Dr. Alt'},
    },
  ],
  'GET /api/labs/lab1/transfers': [
    {
      'id': 't1', 'kind': 'share', 'status': 'accepted', 'waiting_on_us': false, 'patient_id': 'p9',
      'patient_name': 'Old Patient', 'from_lab': {'id': 'lab1', 'name': 'Süd'}, 'to_lab': {'id': 'lab2', 'name': 'Nord'},
      'created_at': '2026-10-02T09:00:00Z',
    },
    {
      'id': 't2', 'kind': 'handover', 'status': 'awaiting_recipient', 'waiting_on_us': true, 'patient_id': 'p1',
      'patient_name': 'Max Mustermann', 'from_lab': {'id': 'lab2', 'name': 'Nord'}, 'to_lab': {'id': 'lab1', 'name': 'Süd'},
      'requested_by_name': 'Dentallabor Nord', 'created_at': '2026-10-05T09:00:00Z',
    },
  ],
  'GET /api/labs/lab1/settings': {'hidden_from_labs': true, 'hide_dentists': false},
  'PATCH /api/labs/lab1/settings': {'hidden_from_labs': true, 'hide_dentists': true},
  'GET /api/patients/access/pending': {'status': 'SUCCESS', 'http_code': 200, 'payload': {'pending_requests': []}},
};

class _LabApi extends ApiClient {
  _LabApi()
      : super(
          baseUrl: 'http://test',
          httpClient: MockClient((req) async {
            _requests.add(req);
            final body = _fixtures['${req.method} ${req.url.path}'] ?? const [];
            return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
          }),
        );

  @override
  String? get userId => 'lab1';

  @override
  bool get isLaboratory => true;
}

final _de = AppLocalizations('de');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
  });
  setUp(_requests.clear);

  for (final size in const [Size(1194, 834), Size(834, 1194), Size(390, 844)]) {
    testWidgets('lab page tabs lay out at $size', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LocaleScope(
        controller: LocaleController(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: LabPage(api: _LabApi(), onOpenPatient: (_) {})),
        ),
      ));
      await _settle(tester);
      expect(find.text('Dr. Weiss'), findsOneWidget);
      for (final tab in ['lab.tab.requests', 'lab.tab.transfers', 'lab.tab.sharing', 'lab.tab.settings']) {
        await tester.tap(find.text(_de.tr(tab)));
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: tab);
      }
    });
  }

  testWidgets('transfers: waiting on us first, with the right actions', (tester) async {
    tester.view.physicalSize = const Size(1194, 834) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(home: Scaffold(body: LabPage(api: _LabApi(), onOpenPatient: (_) {}))),
    ));
    await _settle(tester);
    await tester.tap(find.text(_de.tr('lab.tab.transfers')));
    await _settle(tester);
    final waiting = tester.getTopLeft(find.text('Max Mustermann')).dy;
    final done = tester.getTopLeft(find.text('Old Patient')).dy;
    expect(waiting, lessThan(done));
    // Sent to us: Accept + Reject + open; nothing to forward.
    expect(find.text(_de.tr('lab.accept')), findsOneWidget);
    expect(find.text(_de.tr('lab.forward')), findsNothing);
    expect(find.text(_de.tr('lab.openPatient')), findsOneWidget);
  });

  test('settings: GET to read, PATCH only the change', () async {
    final api = _LabApi();
    expect((await api.labSettings('lab1'))['hidden_from_labs'], isTrue);
    expect(_requests.single.method, 'GET');
    await api.updateLabSettings('lab1', hideDentists: true);
    expect(_requests.last.method, 'PATCH');
    expect(jsonDecode(_requests.last.body), {'hide_dentists': true});
  });

  test('lab-created patient carries its target', () async {
    Map<String, dynamic>? sent;
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'status': 'SUCCESS', 'http_code': 201, 'payload': {'patient': {'id': 'p1', 'first_name': 'A', 'last_name': 'B'}}}),
          200,
        );
      }),
    );
    await PatientsApiService(api).createPatient(
      firstName: 'A',
      lastName: 'B',
      dateOfBirth: '2000-01-01',
      email: 'a@b.de',
      address: 'x',
      phone: '+49',
      healthInsurance: 'y',
      target: {'send_to_lab_id': 'lab2'},
    );
    expect(sent!['send_to_lab_id'], 'lab2');
    expect(sent!.containsKey('dentist_id'), isFalse);
  });

  for (final size in const [Size(1194, 834), Size(834, 1194), Size(390, 844)]) {
    testWidgets('lab dashboard at $size: lays out, lists what waits on the lab', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LocaleScope(
        controller: LocaleController(),
        child: MaterialApp(theme: AppTheme.light(), home: AppShell(api: _LabApi(), dentistName: 'Süd')),
      ));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      final dash = find.byType(LabDashboardPage);
      expect(dash, findsOneWidget);
      // Only the transfer waiting on us, and only the pending join.
      expect(find.descendant(of: dash, matching: find.text('Max Mustermann')), findsOneWidget);
      expect(find.descendant(of: dash, matching: find.text('Old Patient')), findsNothing);
      expect(find.descendant(of: dash, matching: find.text('Dr. Neu')), findsOneWidget);
      if (size.width > 600) {
        final scroll = tester.state<ScrollableState>(find.descendant(of: dash, matching: find.byType(Scrollable)).first);
        expect(scroll.position.maxScrollExtent, 0, reason: 'iPad dashboard fits one screen');
      }
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
    });
  }
}

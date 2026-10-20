import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/app_localizations.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/core/theme/app_theme.dart';
import 'package:dental_lab_ai/core/session/patient_session.dart';
import 'package:dental_lab_ai/features/cases/review_page.dart';
import 'package:dental_lab_ai/features/patients/patients_page.dart';
import 'package:dental_lab_ai/features/lab/lab_dashboard_page.dart';
import 'package:dental_lab_ai/features/lab/lab_page.dart';
import 'package:dental_lab_ai/features/lab/lab_pickers.dart';
import 'package:flutter/cupertino.dart';
import 'package:dental_lab_ai/shell/app_shell.dart';
import 'package:dental_lab_ai/shell/app_sidebar.dart';
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
  'GET /api/patients': {
    'status': 'SUCCESS',
    'http_code': 200,
    'payload': {
      'patients': [
        {'id': 'p5', 'first_name': 'Lena', 'last_name': 'Lab', 'status': 'rejected', 'created_by': 'd1'},
        {'id': 'p2', 'first_name': 'Erika', 'last_name': 'Muster', 'status': 'in_review', 'created_by': 'd9'},
      ],
    },
  },
  'GET /api/patients/p5/case': {
    'status': 'rejected',
    'items': {'scan': true, 'shade': true, 'smile': false},
    'lab': {'id': 'lab1', 'name': 'Süd'},
    'shared_with_lab': true,
    'can_review': true,
    'owner': {'id': 'd1', 'name': 'Dr. Weiss', 'clinic_name': 'Praxis Weiss'},
    'last_rejection': {'remarks': 'Margin unclear', 'items': [], 'by': 'Süd', 'at': '2026-10-10T09:00:00Z'},
    'events': [
      {'type': 'rejected', 'actor_name': 'Süd', 'created_at': '2026-10-10T09:00:00Z'},
    ],
  },
  'GET /api/patients/p5': {
    'status': 'SUCCESS',
    'http_code': 200,
    'payload': {
      'patient': {'id': 'p5', 'first_name': 'Lena', 'last_name': 'Lab', 'status': 'rejected', 'created_by': 'd1', 'email': 'lena@x.de'},
    },
  },
  'GET /api/patients/p5/access': {'status': 'SUCCESS', 'http_code': 200, 'payload': {}},
  'GET /api/patients/p5/notes': {'status': 'SUCCESS', 'http_code': 200, 'payload': {'notes': []}},
  'GET /api/patients/p5/shade-detections': [
    {
      'id': 's1', 'file_url': '', 'created_at': '2026-10-09T09:00:00Z',
      'analysis': {'final_shade': 'A2', 'detected_shade': 'A3', 'overridden': true},
    },
  ],
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

/// iPad 11" and 13" first (both orientations), then phones down to the SE.
const _ipads = [Size(1180, 820), Size(1194, 834), Size(1210, 834), Size(1366, 1024), Size(1376, 1032)];
final _sizes = [
  for (final s in _ipads) ...[s, s.flipped],
  const Size(375, 667),
  const Size(390, 844),
  const Size(430, 932),
];

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
      for (final tab in ['lab.tab.requests', 'lab.tab.transfers', 'lab.tab.sharing']) {
        await tester.tap(find.text(_de.tr(tab)));
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: tab);
      }
      expect(find.text(_de.tr('lab.tab.settings')), findsNothing);
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
    // Wide: pick it, its actions show in the side panel.
    expect(find.text(_de.tr('lab.pickItem')), findsOneWidget);
    expect(find.text(_de.tr('lab.accept')), findsNothing);
    await tester.tap(find.text('Max Mustermann'));
    await _settle(tester);
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

  for (final size in _sizes) {
    testWidgets('dentist details open beside the list (sheet on phone) at $size', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      String? opened;
      await tester.pumpWidget(LocaleScope(
        controller: LocaleController(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: LabPage(api: _LabApi(), onOpenPatient: (id) => opened = id)),
        ),
      ));
      await _settle(tester);
      // Side panel from ~13" portrait up; a sheet on 11" portrait and phones.
      expect(find.text(_de.tr('lab.pickDentist')), size.width >= 1000 ? findsOneWidget : findsNothing);
      await tester.tap(find.text('Dr. Weiss'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('weiss@x.de'), findsOneWidget);
      expect(find.text(_de.tr('case.message')), findsOneWidget);
      // Only this dentist's patients.
      expect(find.text('Erika Muster'), findsNothing);
      await tester.tap(find.text('Lena Lab'));
      await _settle(tester);
      expect(opened, 'p5');
    });
  }

  testWidgets('review: rejected case can be approved or re-reviewed; shade shows the pick', (tester) async {
    tester.view.physicalSize = const Size(1194, 834) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final api = _LabApi();
    final session = PatientSession(api);
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ReviewPage(api: api, cases: session.cases, patients: session)),
      ),
    ));
    await _settle(tester);
    await tester.tap(find.text(_de.tr('review.tab.rejected')).first);
    await _settle(tester);
    await tester.tap(find.text('Lena Lab'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(_de.tr('case.updateFeedback')), findsOneWidget);
    expect(find.text(_de.tr('case.approve')), findsOneWidget);
    expect(find.text(_de.tr('case.message')), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
    expect(find.text(_de.tr('records.dentistPick')), findsOneWidget);
    expect(find.text(_de.trp('records.aiWas', {'shade': 'A3'})), findsOneWidget);
  });

  for (final size in _sizes) {
    testWidgets('lab patients: detail lays out (beside the list when wide) at $size', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final api = _LabApi();
      final session = PatientSession(api);
      await tester.pumpWidget(LocaleScope(
        controller: LocaleController(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: PatientsPage(api: api, dentistName: 'Süd', patientSession: session)),
        ),
      ));
      await _settle(tester);
      await tester.tap(find.text('Lena Lab').first);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      // Case tab first, decision pinned under it.
      expect(find.text(_de.tr('case.updateFeedback')), findsOneWidget);
    });
  }

  // Every lab page from the rail, on every iPad in both orientations.
  const railPages = [
    Icons.people_outline,
    Icons.fact_check_outlined,
    Icons.apartment_rounded,
    Icons.calendar_today_outlined,
    Icons.translate_rounded,
    Icons.chat_bubble_outline,
    Icons.bar_chart_rounded,
    Icons.settings_outlined,
  ];
  for (final size in [for (final s in _ipads) ...[s, s.flipped]]) {
    testWidgets('lab shell: every page lays out at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 40);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LocaleScope(
        controller: LocaleController(),
        child: MaterialApp(theme: AppTheme.light(), home: AppShell(api: _LabApi(), dentistName: 'Süd')),
      ));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'dashboard');
      for (final icon in railPages) {
        await tester.tap(find.descendant(of: find.byType(AppSidebar), matching: find.byIcon(icon)));
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: '$icon');
      }
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
    });
  }

  for (final size in _sizes) {
    testWidgets('requests: detail beside the list when wide, actions on cards when narrow at $size', (tester) async {
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
      await tester.tap(find.text(_de.tr('lab.tab.requests')));
      await _settle(tester);
      final wide = size.width >= 1000;
      expect(find.text(_de.tr('lab.accept')), wide ? findsNothing : findsOneWidget);
      await tester.tap(find.text('Dr. Neu'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(_de.tr('lab.accept')), findsOneWidget);
      if (wide) expect(find.text('neu@x.de'), findsWidgets);
    });
  }

  testWidgets('dentist picker: long list scrolls and filters by name or clinic', (tester) async {
    tester.view.physicalSize = const Size(1194, 834) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    String? picked;
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await pickSearchable<String>(
                context,
                title: 'Pick',
                items: [
                  for (var i = 0; i < 40; i++) (value: 'd$i', name: 'Dr. Nr $i', detail: i == 33 ? 'Praxis Sonne' : 'Praxis $i', avatar: null),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(CupertinoSearchTextField), 'sonne');
    await _settle(tester);
    expect(find.text('Dr. Nr 33'), findsOneWidget);
    expect(find.text('Dr. Nr 1'), findsNothing);
    await tester.tap(find.text('Dr. Nr 33'));
    await _settle(tester);
    expect(picked, 'd33');
  });
}

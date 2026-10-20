import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/app_localizations.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/features/cases/case_panel.dart';
import 'package:dental_lab_ai/features/cases/case_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

Map<String, dynamic> _summary({String status = 'in_progress', Map<String, dynamic>? rejection}) => {
      'status': status,
      'auto_submit': false,
      'items': {'scan': true, 'shade': false, 'smile': false},
      'missing': ['shade', 'smile'],
      'lab': {'id': 'l1', 'name': 'Dentallabor Süd'},
      'shared_with_lab': true,
      'can_submit': true,
      'can_review': false,
      'last_rejection': rejection,
      'events': [
        {'type': 'created', 'actor_name': 'Dr. Weiss', 'created_at': '2026-10-01T09:00:00Z'},
      ],
    };

final _de = AppLocalizations('de');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
  });

  test('case summary parses items, lab, lock state', () {
    final info = CaseInfo(_summary(status: 'completed'));
    expect(info.hasScan, isTrue);
    expect(info.hasShade, isFalse);
    expect(info.missing, ['shade', 'smile']);
    expect(info.labName, 'Dentallabor Süd');
    expect(info.locked, isTrue);
    expect(CaseInfo(_summary(status: 'in_review')).locked, isTrue);
    expect(CaseInfo(_summary(status: 'rejected')).locked, isFalse);
  });

  testWidgets('incomplete submit warns, then "Submit anyway" confirms', (tester) async {
    final bodies = <Map<String, dynamic>>[];
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        bodies.add(body);
        if (body['confirm_incomplete'] == false) {
          return http.Response(jsonEncode({'code': 'INCOMPLETE', 'detail': 'Missing items', 'missing': ['shade', 'smile']}), 409);
        }
        return http.Response(jsonEncode(_summary(status: 'in_review')), 200);
      }),
    );
    final store = CaseStore(api);
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        home: Scaffold(body: Builder(
          builder: (context) => TextButton(
            onPressed: () => submitCaseToLab(context, store, 'p1'),
            child: const Text('go'),
          ),
        )),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    // Names the missing items.
    expect(find.textContaining(_de.tr('case.item.shade')), findsOneWidget);
    expect(find.textContaining(_de.tr('case.item.smile')), findsOneWidget);
    await tester.tap(find.text(_de.tr('case.submitAnyway')));
    await tester.pumpAndSettle();
    expect(bodies.map((b) => b['confirm_incomplete']), [false, true]);
    expect(store.of('p1')!.status, 'in_review');
  });

  testWidgets('400 on submit shows the server message', (tester) async {
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async =>
          http.Response(jsonEncode({'code': 'NO_LAB', 'detail': 'Choose a lab first.'}), 400)),
    );
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        home: Scaffold(body: Builder(
          builder: (context) => TextButton(
            onPressed: () => submitCaseToLab(context, CaseStore(api), 'p1'),
            child: const Text('go'),
          ),
        )),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a lab first.'), findsOneWidget);
  });

  testWidgets('reject needs remarks and sends per-item feedback', (tester) async {
    Map<String, dynamic>? sent;
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_summary(status: 'rejected')), 200);
      }),
    );
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        home: Scaffold(body: Builder(
          builder: (context) => TextButton(
            onPressed: () => reviewCase(context, CaseStore(api), 'p1', approve: false),
            child: const Text('go'),
          ),
        )),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    final reject = find.text(_de.tr('case.reject'));
    await tester.tap(reject);
    await tester.pumpAndSettle();
    expect(sent, isNull, reason: 'empty remarks must not send');
    await tester.enterText(find.byType(TextField).first, 'Margin unclear on 21');
    await tester.pump();
    await tester.tap(reject);
    await tester.pumpAndSettle();
    expect(sent!['decision'], 'reject');
    expect(sent!['remarks'], 'Margin unclear on 21');
    expect(sent!['items'], isA<List>());
    expect((sent!['items'] as List).length, 3);
  });

  testWidgets('rejection banner shows remarks and item notes', (tester) async {
    final info = CaseInfo(_summary(
      status: 'rejected',
      rejection: {
        'remarks': 'Rescan 21 please',
        'by': 'Dentallabor Süd',
        'at': '2026-10-05T09:00:00Z',
        'items': [
          {'item': 'scan', 'status': 'needs_work', 'note': 'Blurry bite'},
          {'item': 'shade', 'status': 'ok'},
        ],
      },
    ));
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(home: Scaffold(body: CaseRejectionBanner(info: info))),
    ));
    expect(find.text('Rescan 21 please'), findsOneWidget);
    expect(find.textContaining('Dentallabor Süd'), findsOneWidget);
    expect(find.textContaining('Blurry bite'), findsOneWidget);
    expect(find.textContaining(_de.tr('case.itemOk')), findsOneWidget);
  });

  testWidgets('banner: accept a lab suggestion, then Resubmit', (tester) async {
    final calls = <String>[];
    var accepted = false;
    Map<String, dynamic> body() => {
          ..._summary(status: 'rejected', rejection: {'remarks': 'Lab made changes, please confirm.', 'items': []}),
          'is_owner': true,
          'updated_since_rejection': accepted,
          'lab_review': {
            'suggestions': accepted
                ? {}
                : {'shade': {'id': 's-p1-shade', 'for_id': 'sh1', 'by': 'Dentallabor Süd'}},
          },
        };
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.url.path.endsWith('/accept')) accepted = true;
        return http.Response(jsonEncode(body()), 200);
      }),
    );
    final store = CaseStore(api);
    await store.refresh('p1');
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: store,
            builder: (_, _) => CaseRejectionBanner(info: store.of('p1'), store: store, patientId: 'p1'),
          ),
        ),
      ),
    ));
    final resubmit = find.widgetWithText(FilledButton, _de.tr('case.resubmit'));
    expect(tester.widget<FilledButton>(resubmit).onPressed, isNull, reason: 'suggestion pending');
    await tester.tap(find.text(_de.tr('case.accept')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /api/patients/p1/suggestions/shade/accept'));
    expect(find.text(_de.tr('case.accept')), findsNothing);
    expect(find.text(_de.tr('case.updatedChip')), findsOneWidget);
    await tester.tap(find.text(_de.tr('case.resubmit')));
    await tester.pumpAndSettle();
    expect(calls.last, 'POST /api/patients/p1/submit');
  });

  testWidgets('feedback bar fills in the saved note once the case loads', (tester) async {
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((req) async => http.Response(
            jsonEncode({
              ..._summary(status: 'in_review'),
              'can_suggest': true,
              'lab_review': {
                'feedback': {'shade': {'status': 'needs_work', 'note': 'Too warm'}},
                'suggestions': {},
              },
            }),
            200,
          )),
    );
    final store = CaseStore(api);
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        home: Scaffold(body: CaseFeedbackBar(store: store, patientId: 'p1', item: 'shade')),
      ),
    ));
    await tester.runAsync(() => store.refresh('p1')); // arrives after the bar was built
    await tester.pump();
    expect(find.text('Too warm'), findsOneWidget);
  });

  test('replacement upload sends replaces', () async {
    http.BaseRequest? seen;
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient.streaming((req, body) async {
        seen = req;
        final text = await body.bytesToString();
        expect(text, contains('name="replaces"'));
        expect(text, contains('old-scan-1'));
        return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'id': 'new'}))), 201);
      }),
    );
    await api.uploadPatientScan(patientId: 'p1', bytes: [1, 2, 3], filename: 'a.ply', replaces: 'old-scan-1');
    expect(seen!.url.path, '/api/patients/p1/scans');
  });
}

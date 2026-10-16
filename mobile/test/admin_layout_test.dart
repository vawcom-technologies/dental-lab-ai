import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/app_localizations.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/core/theme/app_theme.dart';
import 'package:dental_lab_ai/features/admin/admin_dashboard_page.dart';
import 'package:dental_lab_ai/features/admin/admin_patients_page.dart';
import 'package:dental_lab_ai/features/admin/admin_top_bar.dart';
import 'package:dental_lab_ai/core/widgets/ui_kit.dart';
import 'package:dental_lab_ai/shell/app_shell.dart';
import 'package:dental_lab_ai/shell/app_sidebar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sample answers for the admin contract (docs/roadmap.md, Phase 1).
final _fixtures = <String, Object>{
  '/api/admin/summary': {
    'pending_signups': 2,
    'dentists': 14,
    'labs': 3,
    'unassigned_dentists': 1,
    'unassigned_patients': 2,
    'pending_removals': 1,
    'cases': {'pending': 4, 'in_progress': 9, 'in_review': 3, 'completed': 21, 'rejected': 1},
  },
  '/api/admin/signups': [
    {
      'user_id': 'u1',
      'name': 'Dr. Annemarie Schwarzenberger-Hohenstein',
      'email': 'annemarie.schwarzenberger@praxis-am-rosenplatz.de',
      'phone': '+49 30 1234567',
      'role': 'dentist',
      'clinic_name': 'Zahnarztpraxis am Rosenplatz',
      'created_at': '2026-10-01T09:00:00Z',
    },
    {'user_id': 'u2', 'name': 'Dentallabor Nord', 'email': 'nord@lab.de', 'role': 'laboratory'},
  ],
  '/api/admin/rejected': [
    {
      'id': 'r1',
      'email': 'spam@example.com',
      'name': 'Spam',
      'role': 'dentist',
      'reason': 'Not a clinic',
      'rejected_at': '2026-09-01T09:00:00Z',
      'rejected_by_name': 'Admin',
    },
  ],
  '/api/admin/labs': [
    {'id': 'l1', 'name': 'Dentallabor Süd', 'email': 'sued@lab.de', 'dentist_count': 1, 'hidden_from_labs': true, 'hide_dentists': true},
    {'id': 'l2', 'name': 'Empty Lab', 'email': 'empty@lab.de', 'dentist_count': 0, 'deleted': true},
  ],
  '/api/admin/dentists': [
    {'id': 'd1', 'name': 'Dr. Weiss', 'email': 'weiss@x.de', 'clinic_name': 'Praxis Weiss', 'lab_id': 'l1', 'lab_name': 'Dentallabor Süd'},
    {'id': 'd2', 'name': 'Dr. Ohne', 'email': 'ohne@x.de', 'clinic_name': 'Praxis Ohne', 'lab_id': null, 'lab_name': null, 'deleted': true, 'unassigned_reason': 'lab_deleted', 'unassigned_at': '2026-10-02T09:00:00Z'},
  ],
  '/api/admin/lab-requests': [
    {'id': 'q1', 'kind': 'remove', 'lab_id': 'l1', 'lab_name': 'Dentallabor Süd', 'dentist_id': 'd1', 'dentist_name': 'Dr. Weiss', 'reason': 'Moved away', 'created_at': '2026-10-10T09:00:00Z'},
  ],
  '/api/admin/patients': [
    {'id': 'p1', 'first_name': 'Max', 'last_name': 'Mustermann', 'status': 'in_review', 'owner_name': 'Dr. Weiss', 'lab_id': 'l1', 'lab_name': 'Dentallabor Süd', 'unassigned_reason': null, 'updated_at': '2026-10-12T09:00:00Z'},
    {'id': 'p2', 'first_name': 'Erika', 'last_name': 'Musterfrau', 'status': 'pending', 'owner_name': 'Dr. Alt', 'lab_id': 'l1', 'lab_name': 'Dentallabor Süd', 'unassigned_reason': 'waiting_for_lab'},
  ],
  '/api/conversations': [
    {
      'id': 'c1', 'user_a': 'admin', 'user_b': 'l1', 'unread_count': 1,
      'partner': {'id': 'l1', 'name': 'Dentallabor Süd', 'role': 'laboratory'},
      'last_message': {'id': 'm1', 'conversation_id': 'c1', 'sender_id': 'l1', 'content': 'Can you move Dr. Weiss?'},
      'updated_at': '2026-10-16T08:00:00Z',
    },
  ],
  '/api/conversations/c1/messages': {
    'items': [
      {'id': 'm1', 'conversation_id': 'c1', 'sender_id': 'l1', 'content': 'Can you move Dr. Weiss?', 'created_at': '2026-10-16T08:00:00Z'},
    ],
    'has_more': false,
  },
  '/api/admin/patients/p1': {
    'id': 'p1', 'first_name': 'Max', 'last_name': 'Mustermann', 'status': 'rejected', 'owner_name': 'Dr. Weiss', 'lab_name': 'Dentallabor Süd',
    'unassigned_reason': 'owner_deleted',
    'shared_with': [{'user_id': 'l1', 'name': 'Dentallabor Süd', 'role': 'laboratory'}],
    'events': [
      {'type': 'created', 'actor_name': 'Dr. Weiss', 'created_at': '2026-10-01T09:00:00Z'},
      {'type': 'rejected', 'actor_name': 'Dentallabor Süd', 'remarks': 'Margin unclear on 21, please rescan.', 'from_status': 'in_review', 'to_status': 'rejected', 'created_at': '2026-10-05T09:00:00Z'},
    ],
  },
};

/// Every URL the fake backend was asked for.
final _requests = <Uri>[];

class _AdminApi extends ApiClient {
  _AdminApi()
      : super(
          baseUrl: 'http://test',
          httpClient: MockClient((req) async {
            _requests.add(req.url);
            final body = _fixtures[req.url.path] ?? const [];
            return http.Response(jsonEncode(body), 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }),
        );

  @override
  bool get isAdmin => true;
}

final _de = AppLocalizations('de');

Future<void> _pump(WidgetTester tester, Size logical) async {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(api: _AdminApi(), dentistName: 'Admin'),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Opens a page from the rail (iPad) or the drawer (phone).
Future<void> _open(WidgetTester tester, String label, {required bool phone}) async {
  if (phone) {
    await tester.tap(find.byIcon(Icons.menu_rounded).first);
    await _settle(tester);
    await tester.tap(find.descendant(of: find.byType(AppSidebar), matching: find.text(label)));
  } else {
    await tester.tap(find.byTooltip(label));
  }
  await _settle(tester);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rejected sign-up / sign-in maps to the clear message', () {
    final msg = friendlyHttpError(statusCode: 403, detail: 'REGISTRATION_REJECTED');
    expect(msg, AppLocalizations.current.errRegistrationRejected);
  });

  const sizes = {
    'iPad landscape': Size(1194, 834),
    'iPad portrait': Size(834, 1194),
    'phone': Size(390, 844),
  };

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('$name: every admin page lays out', (tester) async {
      final phone = name == 'phone';
      await _pump(tester, size);
      expect(find.text(_de.tr('admin.recentPatients')), findsOneWidget);
      expect(find.text(_de.tr('admin.quickActions')), findsOneWidget);
      // Clinical tools are not offered to the admin.
      expect(find.byIcon(Icons.palette_outlined), findsNothing);
      expect(tester.takeException(), isNull, reason: 'dashboard');

      // Bell opens the notifications popover; tapping outside closes it.
      await tester.tap(find.descendant(
          of: find.byType(AdminTopActions), matching: find.byIcon(Icons.notifications_none_rounded)));
      await _settle(tester);
      expect(find.text(_de.notificationsEmpty), findsOneWidget);
      await tester.tapAt(const Offset(5, 400));
      await _settle(tester);
      // Profile menu.
      await tester.tap(find.descendant(of: find.byType(AdminTopActions), matching: find.byType(UserAvatar)));
      await _settle(tester);
      expect(find.text(_de.signOut), findsOneWidget);
      await tester.tapAt(const Offset(5, 400));
      await _settle(tester);
      // Quick chat opens the thread inside its card; back returns to the list.
      final preview = find.text('Can you move Dr. Weiss?');
      final dashScroll = find
          .descendant(of: find.byType(AdminDashboardPage), matching: find.byType(Scrollable))
          .first;
      await tester.ensureVisible(preview);
      await _settle(tester);
      await tester.tap(preview);
      await _settle(tester);
      expect(find.byType(CupertinoTextField), findsOneWidget);
      expect(find.text('Can you move Dr. Weiss?'), findsWidgets);
      expect(find.byType(AdminSearchPage), findsNothing); // still on the dashboard
      // The test has no chat socket; let its error toast time out first.
      await tester.pump(const Duration(seconds: 4));
      await tester.ensureVisible(find.descendant(
          of: find.byType(AdminDashboardPage), matching: find.byIcon(Icons.arrow_back_ios_new_rounded)));
      await _settle(tester);
      await tester.tap(find.descendant(
          of: find.byType(AdminDashboardPage), matching: find.byIcon(Icons.arrow_back_ios_new_rounded)));
      await _settle(tester);
      expect(find.byType(CupertinoTextField), findsNothing);
      expect(tester.takeException(), isNull, reason: 'quick chat');
      await tester.drag(dashScroll, const Offset(0, 3000));
      await _settle(tester);

      // Search grows into its own page and finds labs and dentists.
      await tester.tap(find.text(_de.tr('admin.searchHint')));
      await _settle(tester);
      expect(find.byType(AdminSearchPage), findsOneWidget);
      await tester.enterText(find.byType(CupertinoSearchTextField), 'weiss');
      await _settle(tester);
      Finder inSearch(String t) =>
          find.descendant(of: find.byType(AdminSearchPage), matching: find.text(t));
      expect(inSearch('Dr. Weiss'), findsOneWidget);
      expect(inSearch('Empty Lab'), findsNothing);
      await tester.tap(find.text(_de.cancel));
      await _settle(tester);
      expect(find.byType(AdminSearchPage), findsNothing);
      expect(tester.takeException(), isNull, reason: 'top bar');

      await _open(tester, _de.navSignups, phone: phone);
      expect(find.text('nord@lab.de'), findsOneWidget);
      // Approving a dentist opens the lab picker (ListTiles on a frosted
      // sheet must not trip the "ink splashes may be invisible" assert).
      await tester.tap(find.text(_de.tr('admin.approve')).first);
      await _settle(tester);
      expect(find.text('Dentallabor Süd'), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'lab picker');
      await tester.tap(find.text(_de.cancel).last);
      await _settle(tester);
      await _tapText(tester, _de.tr('admin.rejectList'));
      expect(find.text('spam@example.com'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'signups');

      await _open(tester, _de.navLaboratories, phone: phone);
      expect(find.text('Dr. Weiss'), findsOneWidget);
      // Deactivated lab offers Reactivate.
      expect(find.text(_de.tr('admin.reactivate')), findsWidgets);
      await _tapText(tester, _de.tr('admin.unassignedDentists'));
      expect(find.textContaining(_de.tr('admin.unassigned.lab_deleted')), findsWidgets);
      await _tapText(tester, _de.tr('admin.removalRequests'));
      // Visited tabs stay mounted (kept alive), so the name shows on each.
      expect(find.textContaining('Moved away'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'users');

      await _open(tester, _de.navPatients, phone: phone);
      expect(find.text('Wartet auf Dentallabor Süd'), findsOneWidget);
      expect(find.text('von Dr. Alt'), findsOneWidget);
      await _tapText(tester, 'Max Mustermann');
      expect(find.byType(AdminPatientDetail), findsOneWidget);
      if (!phone) {
        // iPad (both orientations): detail opens in the page, list stays visible.
        expect(find.text('Erika Musterfrau').hitTestable(), findsOneWidget);
      }
      final remarks = find.text('Margin unclear on 21, please rescan.');
      await tester.scrollUntilVisible(
        remarks,
        200,
        scrollable: find
            .descendant(of: find.byType(AdminPatientDetail), matching: find.byType(Scrollable))
            .first,
      );
      expect(remarks, findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'patient detail');

      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
    });
  }

  testWidgets('donut legend opens Patients on that status', (tester) async {
    await _pump(tester, const Size(1194, 834));
    _requests.clear();
    final rejected = _de.statusLabel('rejected');
    await tester.tap(find
        .descendant(of: find.byType(AdminDashboardPage), matching: find.text(rejected))
        .first);
    await _settle(tester);
    expect(find.byType(AdminPatientsPage).hitTestable(), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is SoftFilterChip && w.label == rejected && w.selected),
      findsOneWidget,
    );
    expect(
      _requests.any((u) => u.path == '/api/admin/patients' && u.queryParameters['status'] == 'rejected'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  // Dashboard fits one screen on every iPad (no page scroll, only the
  // pull-to-refresh bounce); phones scroll.
  const ipads = {
    'iPad mini': Size(1133, 744),
    'iPad 10.2"': Size(1080, 810),
    'iPad 9.7"': Size(1024, 768),
    'iPad Air 11"': Size(1180, 820),
    'iPad Pro 11"': Size(1194, 834),
    'iPad Pro 12.9"': Size(1366, 1024),
    'iPad Pro 13" (M4)': Size(1376, 1032),
  };
  for (final MapEntry(key: name, value: landscape) in ipads.entries) {
    for (final size in [landscape, landscape.flipped]) {
      final o = size == landscape ? 'landscape' : 'portrait';
      testWidgets('$name $o: dashboard fits without scrolling', (tester) async {
        await _pump(tester, size);
        expect(tester.takeException(), isNull);
        final scroll = tester.state<ScrollableState>(find
            .descendant(of: find.byType(AdminDashboardPage), matching: find.byType(Scrollable))
            .first);
        expect(scroll.position.maxScrollExtent, 0);
        await tester.pumpWidget(const SizedBox());
        await _settle(tester);
      });
    }
  }
}

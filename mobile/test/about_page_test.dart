import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(ApiClient, LocaleController)> _setup(String role) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final locale = LocaleController();
  await locale.setLanguage('en');
  final api = ApiClient(
    baseUrl: 'http://x',
    httpClient: MockClient((req) async {
      if (req.method == 'POST') {
        return http.Response(
            jsonEncode({'access_token': 't', 'user_id': 'u1', 'role': role, 'name': 'Test', 'email': 'test@example.com'}), 200);
      }
      return http.Response(req.url.path.endsWith('rejected') ? '[]' : '{}', 200);
    }),
  );
  await api.signIn('test@example.com', 'x');
  return (api, locale);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
  });

  for (final role in ['dentist', 'laboratory', 'admin']) {
    for (final size in [const Size(1376, 1032), const Size(1180, 820), const Size(820, 1180), const Size(390, 844)]) {
      testWidgets('$role: settings tabs and About page lay out at ${size.width}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final (api, locale) = await tester.runAsync(() => _setup(role)) ?? (throw StateError('setup'));
        await tester.pumpWidget(LocaleScope(
          controller: locale,
          child: MaterialApp(home: Scaffold(body: SettingsPage(api: api))),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // AI defaults are gone for everyone; the reject list is admin-only.
        expect(find.text('AI defaults'), findsNothing);
        expect(find.text('Reject list', skipOffstage: false), role == 'admin' ? findsOneWidget : findsNothing);
        // Tabs with content; About opens as its own page from Account.
        for (final tab in ['Preferences', 'Account']) {
          await tester.tap(find.text(tab, skipOffstage: false).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: tab);
        }
        expect(find.byType(AboutContent), findsNothing);
        await tester.ensureVisible(find.text('About Elite Dent'));
        await tester.tap(find.text('About Elite Dent'));
        await tester.pumpAndSettle();
        expect(find.byType(AboutPage), findsOneWidget);
        await tester.drag(find.byType(AboutContent), const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(AboutPage), findsNothing);
        await locale.setLanguage('de');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('search finds settings by what you want to do, and jumps there', (tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (api, locale) = await tester.runAsync(() => _setup('dentist')) ?? (throw StateError('setup'));
    await tester.pumpWidget(LocaleScope(
      controller: locale,
      child: MaterialApp(home: Scaffold(body: SettingsPage(api: api))),
    ));
    await tester.pumpAndSettle();
    final field = find.byType(EditableText).first;
    // An intent, not the setting's name.
    await tester.enterText(field, 'forgot');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Update password'), findsWidgets);
    // German keywords work in the English UI too.
    await tester.enterText(field, 'sprache');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('App language'), findsOneWidget);
    await tester.tap(find.text('App language'));
    await tester.pumpAndSettle();
    // Landed on the Preferences tab, search cleared.
    expect(find.text('English'), findsWidgets);
    expect(find.text('No matching settings'), findsNothing);
    await tester.enterText(field, 'zzzz');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('No matching settings'), findsOneWidget);
  });
}

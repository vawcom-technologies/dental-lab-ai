import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/features/settings/settings_page.dart';

void main() {
  for (final role in ['dentist', 'laboratory', 'admin']) {
    for (final size in [const Size(1376, 1032), const Size(1180, 820), const Size(820, 1180), const Size(390, 844)]) {
      testWidgets('$role: About opens, scrolls and closes cleanly at ${size.width}',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final locale = LocaleController();
        final api = ApiClient(
          baseUrl: 'http://x',
          httpClient: MockClient((_) async => http.Response(
                jsonEncode({
                  'access_token': 't',
                  'user_id': 'u1',
                  'role': role,
                  'name': 'Test',
                  'email': 'test@example.com',
                }),
                200,
              )),
        );
        await api.signIn('test@example.com', 'x');
        await tester.pumpWidget(LocaleScope(
          controller: locale,
          child: MaterialApp(home: Scaffold(body: SettingsPage(api: api))),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final wide = size.width >= 1000;
        // Admins also get the reject list; dentists the AI section.
        expect(find.text('Sperrliste'), role == 'admin' ? findsOneWidget : findsNothing);
        expect(find.text('KI-Standards'), role == 'dentist' ? findsWidgets : findsNothing);
        await tester.tap(find.text('Über uns').first);
        await tester.pumpAndSettle();
        expect(find.byType(AboutContent), findsOneWidget);
        await tester.drag(find.byType(AboutContent), const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (!wide) {
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.byType(AboutContent), findsNothing);
          await tester.tap(find.text('Über uns'));
          await tester.pumpAndSettle();
        }
        // Change language while About is showing.
        await locale.setLanguage('en');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}

import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/features/auth/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('names get capital first letters, rest kept as typed', () {
    expect(capitalizeName('  anna-lena   müller '), 'Anna-Lena Müller');
    expect(capitalizeName('mcDonald'), 'McDonald');
    expect(capitalizeName(''), '');
  });

  testWidgets('dentists sign up with first + last name; labs with one lab name', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(820, 1180) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final locale = LocaleController();
    await locale.setLanguage('en');
    final api = ApiClient(baseUrl: 'http://x', httpClient: MockClient((_) async => http.Response(jsonEncode({}), 200)));
    await tester.pumpWidget(LocaleScope(
      controller: locale,
      child: MaterialApp(home: RegisterScreen(api: api)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('First name *'), findsOneWidget);
    expect(find.text('Last name *'), findsOneWidget);
    expect(find.text('Lab name *'), findsNothing);
    // Dentists must add a photo; labs see it as optional.
    await tester.tap(find.textContaining('Lab').first);
    await tester.pumpAndSettle();
    expect(find.text('First name *'), findsNothing);
    expect(find.text('Lab name *'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/core/session/patient_session.dart';
import 'package:dental_lab_ai/features/interpreter/apple_translate.dart';
import 'package:dental_lab_ai/features/interpreter/interpreter_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('doctor text turn shows translation on the patient pane',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'settings_language': 'de',
      'interpreter.doctor_lang': 'de',
      'interpreter.patient_lang': 'ar',
      'interpreter.auto_speak': false,
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleTranslate.channel, (call) async {
      expect(call.method, 'translate');
      return 'من فضلك افتح فمك';
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppleTranslate.channel, null);
    });

    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/patients')) {
        return http.Response(
          jsonEncode({
            'status': 'SUCCESS',
            'payload': {'patients': <Map<String, dynamic>>[]},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/interpreter/languages')) {
        return http.Response(
          jsonEncode({
            'languages': [
              {
                'code': 'de',
                'name': 'German',
                'native': 'Deutsch',
                'rtl': false,
                'clinic': true,
                'speech': 'de_DE',
              },
              {
                'code': 'ar',
                'name': 'Arabic',
                'native': 'العربية',
                'rtl': true,
                'clinic': true,
                'speech': 'ar_SA',
              },
            ],
            'providers': {'translate': 'gtx', 'stt': 'none'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/interpreter/turn')) {
        fail('interpreter should not call the translate API');
      }
      return http.Response('not found', 404);
    });

    final api = ApiClient(
      baseUrl: 'http://interpreter.test',
      httpClient: client,
    );
    final locale = LocaleController();
    await locale.load();
    final patients = PatientSession(api);

    await tester.pumpWidget(
      LocaleScope(
        controller: locale,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: InterpreterPage(api: api, patientSession: patients),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Dolmetscher'), findsOneWidget);
    expect(find.byKey(const ValueKey('interpreter-doctor-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('interpreter-doctor-field')),
      'Bitte den Mund öffnen',
    );
    await tester.tap(find.byKey(const ValueKey('interpreter-doctor-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('من فضلك افتح فمك'), findsWidgets);
  });

  testWidgets('falls back to the API when Apple cannot translate the pair',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'settings_language': 'de',
      'interpreter.doctor_lang': 'de',
      'interpreter.patient_lang': 'ar',
      'interpreter.auto_speak': false,
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleTranslate.channel, (call) async {
      throw PlatformException(code: 'unsupported');
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppleTranslate.channel, null);
    });

    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/patients')) {
        return http.Response(
          jsonEncode({
            'status': 'SUCCESS',
            'payload': {'patients': <Map<String, dynamic>>[]},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/interpreter/languages')) {
        return http.Response(
          jsonEncode({
            'languages': [
              {
                'code': 'de',
                'name': 'German',
                'native': 'Deutsch',
                'rtl': false,
                'clinic': true,
                'speech': 'de_DE',
              },
              {
                'code': 'ku',
                'name': 'Kurdish',
                'native': 'Kurdî',
                'rtl': true,
                'clinic': true,
                'speech': '',
              },
            ],
            'providers': {'translate': 'gtx', 'stt': 'none'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/interpreter/turn')) {
        return http.Response(
          jsonEncode({
            'original': 'Bitte warten',
            'translated': 'Ji kerema xwe li bendê bin',
            'source_lang': 'de',
            'target_lang': 'ku',
            'provider': 'gtx',
            'stt': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final api = ApiClient(
      baseUrl: 'http://interpreter.test',
      httpClient: client,
    );
    final locale = LocaleController();
    await locale.load();
    final patients = PatientSession(api);

    await tester.pumpWidget(
      LocaleScope(
        controller: locale,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: InterpreterPage(api: api, patientSession: patients),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byKey(const ValueKey('interpreter-doctor-field')),
      'Bitte warten',
    );
    await tester.tap(find.byKey(const ValueKey('interpreter-doctor-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ji kerema xwe li bendê bin'), findsWidgets);
  });
}

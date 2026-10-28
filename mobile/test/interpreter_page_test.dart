import 'dart:async';
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

  testWidgets('register-sensitive target goes to the LLM, not Apple', (
    tester,
  ) async {
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
          fail('Apple must not translate a register-sensitive target');
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
        return http.Response(
          jsonEncode({'translated': 'من فضلك افتح فمك حضرتك'}),
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

    expect(find.text('Dolmetscher'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('interpreter-doctor-field')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('interpreter-doctor-field')),
      'Bitte den Mund öffnen',
    );
    await tester.tap(find.byKey(const ValueKey('interpreter-doctor-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('من فضلك افتح فمك حضرتك'), findsWidgets);

    // Speaker: "loading" until sound starts, then Stop.
    final started = Completer<Object?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => switch (call.method) {
        'speak' => await started.future,
        'getVoices' => <Object>[],
        _ => 1,
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null));
    await tester.tap(find.byKey(const ValueKey('interpreter-patient-speak')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Stimme wird geladen…'), findsOneWidget);
    started.complete(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Stimme wird geladen…'), findsNothing);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
  });

  testWidgets('falls back to the API when Apple cannot translate the pair', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'settings_language': 'de',
      'interpreter.doctor_lang': 'de',
      'interpreter.patient_lang': 'ku',
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
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['formality'], 'formal');
        return http.Response(
          jsonEncode({
            'original': 'Bitte warten',
            'translated': 'Ji kerema xwe li bendê bin',
            'source_lang': 'de',
            'target_lang': 'ku',
            'provider': 'gtx',
            'stt': false,
            'formality': 'formal',
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

  testWidgets('repeated doctor phrase becomes a pill that fills the box', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'settings_language': 'de',
      'interpreter.doctor_lang': 'de',
      'interpreter.patient_lang': 'en',
      'interpreter.auto_speak': false,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          AppleTranslate.channel,
          (call) async => 'Hello',
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppleTranslate.channel, null);
    });
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/patients')) {
        return http.Response(
          jsonEncode({
            'status': 'SUCCESS',
            'payload': {'patients': <Map<String, dynamic>>[]},
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
    await tester.pumpWidget(
      LocaleScope(
        controller: locale,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: InterpreterPage(
                api: api,
                patientSession: PatientSession(api),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final field = find.byKey(const ValueKey('interpreter-doctor-field'));
    Future<void> send() async {
      await tester.enterText(field, 'Bitte weit öffnen');
      await tester.tap(find.byKey(const ValueKey('interpreter-doctor-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Once something is said, phrases sit behind the quick-phrases button.
    final quick = find.byTooltip('Schnellsätze');
    await send();
    expect(quick, findsNothing); // one-off: no phrase
    await send();
    expect(quick, findsOneWidget);
    await tester.tap(quick);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Bitte weit öffnen'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field).controller!.text,
      'Bitte weit öffnen',
    );
  });

  Future<void> pumpWithPackMissing(
    WidgetTester tester, {
    required Future<Object?> Function(MethodCall) apple,
    required Future<http.Response> Function(http.Request) backend,
    String patientLang = 'en',
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'settings_language': 'de',
      'interpreter.doctor_lang': 'de',
      'interpreter.patient_lang': patientLang,
      'interpreter.auto_speak': false,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleTranslate.channel, apple);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppleTranslate.channel, null);
    });
    final api = ApiClient(
      baseUrl: 'http://interpreter.test',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/patients')) {
          return http.Response(
            jsonEncode({
              'status': 'SUCCESS',
              'payload': {'patients': <Map<String, dynamic>>[]},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return backend(request);
      }),
    );
    final locale = LocaleController();
    await locale.load();
    await tester.pumpWidget(
      LocaleScope(
        controller: locale,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: InterpreterPage(
                api: api,
                patientSession: PatientSession(api),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('interpreter-doctor-field')),
      'Bitte weit öffnen',
    );
    await tester.tap(find.byKey(const ValueKey('interpreter-doctor-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('missing language pack asks first; download then translates', (
    tester,
  ) async {
    final calls = <String>[];
    var installed = false;
    await pumpWithPackMissing(
      tester,
      apple: (call) async {
        calls.add(call.method);
        if (call.method == 'prepare') {
          installed = true;
          return 'ok';
        }
        if (!installed) {
          throw PlatformException(code: 'notInstalled');
        }
        return 'Hello';
      },
      backend: (_) async => fail('must not use the backend'),
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(calls, ['translate']); // nothing downloaded before consent
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, ['translate', 'prepare', 'translate']);
    expect(find.text('Hello'), findsWidgets);
  });

  testWidgets('missing pack: cancel sends nothing and restores the text', (
    tester,
  ) async {
    await pumpWithPackMissing(
      tester,
      apple: (call) async => throw PlatformException(code: 'notInstalled'),
      backend: (_) async => fail('must not use the backend'),
    );
    await tester.tap(find.text('Abbrechen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('interpreter-doctor-field')),
          )
          .controller!
          .text,
      'Bitte weit öffnen',
    );
  });

  testWidgets('LLM unreachable: installed Apple pack is used, tone flagged', (
    tester,
  ) async {
    final calls = <String>[];
    await pumpWithPackMissing(
      tester,
      apple: (call) async {
        calls.add(call.method);
        return call.method == 'status' ? 'installed' : 'مرحبا';
      },
      backend: (_) async => http.Response('down', 503),
      patientLang: 'ar',
    );
    expect(find.byType(AlertDialog), findsNothing); // never prompts here
    expect(find.text('مرحبا'), findsWidgets);
    expect(find.textContaining('Höflichkeit nicht geprüft'), findsOneWidget);
    expect(calls, ['status', 'translate']);
  });

  testWidgets('a repeated doctor sentence is translated once', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'settings_language': 'de',
      'interpreter.doctor_lang': 'de',
      'interpreter.patient_lang': 'ar',
      'interpreter.auto_speak': false,
    });
    var llmCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/patients')) {
        return http.Response(
          jsonEncode({
            'status': 'SUCCESS',
            'payload': {'patients': <Map<String, dynamic>>[]},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/interpreter/turn')) {
        llmCalls++;
        return http.Response(
          jsonEncode({'translated': 'افتح فمك من فضلك'}),
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
    await tester.pumpWidget(
      LocaleScope(
        controller: locale,
        child: MaterialApp(
          home: Scaffold(
            body: InterpreterPage(
              api: api,
              patientSession: PatientSession(api),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    for (final text in ['Bitte den Mund öffnen', '  bitte den  Mund öffnen ']) {
      await tester.enterText(
        find.byKey(const ValueKey('interpreter-doctor-field')),
        text,
      );
      await tester.tap(find.byKey(const ValueKey('interpreter-doctor-send')));
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(llmCalls, 1);
    expect(find.text('افتح فمك من فضلك'), findsWidgets);
  });
}

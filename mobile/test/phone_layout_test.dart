import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/layout/adaptive.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(home: child),
    );
  }

  testWidgets('phone login is a single column, not a 50/50 split',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(LoginScreen(api: ApiClient())));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data == 'Sign in' || w.data == 'Anmelden'),
      ),
      findsWidgets,
    );
    expect(find.text('Pro Edition'), findsOneWidget);

    final phone = tester.element(find.byType(LoginScreen));
    expect(AppBreakpoints.isPhone(phone), isTrue);

    // The tablet split is a Row of two Expanded panes. Phone uses a Column
    // with a rounded sheet, so the language control still exists.
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('DE'), findsOneWidget);
  });

  testWidgets('iPad login keeps the side-by-side hero and form', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(LoginScreen(api: ApiClient())));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(LoginScreen));
    expect(AppBreakpoints.isPhone(ctx), isFalse);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data == 'Sign in' || w.data == 'Anmelden'),
      ),
      findsWidgets,
    );
    expect(find.text('Pro Edition'), findsOneWidget);
  });
}

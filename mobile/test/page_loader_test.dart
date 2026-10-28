import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/core/widgets/tooth_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page(Widget left, Widget right) => LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        home: Scaffold(
          body: PageArea(
            child: Row(children: [Expanded(child: left), Expanded(child: right)]),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a page loader in a column draws once, at the page centre', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_page(const ToothPageLoader(), const ToothPageLoader()));
    await tester.pump();
    await tester.pump();
    final shown = find.byType(ToothLoadingIndicator);
    expect(shown, findsOneWidget);
    expect(tester.getCenter(shown).dx, closeTo(600, 1));
  });

  testWidgets('inPlace stays in its own box', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_page(const ToothPageLoader(inPlace: true), const SizedBox()));
    await tester.pump();
    expect(tester.getCenter(find.byType(ToothLoadingIndicator)).dx, closeTo(300, 1));
  });

  testWidgets('hiding the page during layout does not assert (shell tab switch)', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final on = ValueNotifier(true);
    await tester.pumpWidget(LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        home: Scaffold(
          body: PageArea(
            child: ValueListenableBuilder<bool>(
              valueListenable: on,
              builder: (_, v, _) => TickerMode(
                enabled: v,
                // Rebuilt from layout, like AdminFuture's pages.
                child: LayoutBuilder(builder: (_, _) => const ToothPageLoader()),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(ToothLoadingIndicator), findsOneWidget);
    on.value = false;
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ToothLoadingIndicator), findsNothing);
    on.value = true;
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ToothLoadingIndicator), findsOneWidget);
  });
}

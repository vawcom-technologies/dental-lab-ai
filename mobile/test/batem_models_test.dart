import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/features/shapes/shape_overlay_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Shape library includes the three implant models', () {
    expect(ShapeLibrary.total, 15);
    expect(
      ShapeLibrary.items.map((e) => e.label),
      containsAll(['Implant natural', 'Implant bright', 'Implant classic']),
    );
  });

  Future<LocaleController> englishLocale() async {
    SharedPreferences.setMockInitialValues({});
    final controller = LocaleController();
    await controller.setLanguage('en');
    return controller;
  }

  testWidgets('each Batem model starts Closed except the selected one',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = await englishLocale();
    final openIds = <int>{ShapeLibrary.items.first.id};

    await tester.pumpWidget(
      LocaleScope(
        controller: controller,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 1700,
              child: BatemModelAccordion(
                selectedIndex: 0,
                openIds: openIds,
                onToggle: (_) {},
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Closed'), findsNWidgets(ShapeLibrary.total - 1));
    expect(find.text('Use this model'), findsOneWidget);
  });

  testWidgets('Batem models open and close independently', (tester) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = await englishLocale();
    var selected = 0;
    final openIds = <int>{ShapeLibrary.items.first.id};

    await tester.pumpWidget(
      LocaleScope(
        controller: controller,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 1900,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return BatemModelAccordion(
                    selectedIndex: selected,
                    openIds: openIds,
                    onToggle: (id) => setState(() {
                      if (!openIds.remove(id)) openIds.add(id);
                    }),
                    onSelect: (i) => setState(() {
                      selected = i;
                      openIds.add(ShapeLibrary.at(i).id);
                    }),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Classic oval'));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsNWidgets(2));
    expect(find.text('Use this model'), findsNWidgets(2));

    await tester.tap(find.text('Use this model').last);
    await tester.pumpAndSettle();
    expect(selected, 1);

    await tester.tap(find.text('Soft oval'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(openIds.contains(1), isFalse);
    expect(openIds.contains(2), isTrue);
  });
}

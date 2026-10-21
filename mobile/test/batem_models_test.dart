import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/features/shapes/shape_overlay_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Shape library includes the two implant models', () {
    expect(ShapeLibrary.total, 14);
    expect(
      ShapeLibrary.catalog.map((e) => e.label),
      containsAll(['Implant natural', 'Implant classic']),
    );
  });

  Future<LocaleController> englishLocale() async {
    SharedPreferences.setMockInitialValues({});
    final controller = LocaleController();
    await controller.setLanguage('en');
    return controller;
  }

  testWidgets('models grid: every model visible, one tap picks, check marks it', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await englishLocale();
    final picked = <int>[];
    var selected = <int>{0};
    await tester.pumpWidget(
      LocaleScope(
        controller: controller,
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) => SizedBox(
                width: 400,
                height: 2300,
                child: BatemModelGrid(
                  selectedIndexes: selected,
                  onSelect: (i) => set(() {
                    picked.add(i);
                    selected = {...selected, i};
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // No open/close step and no "Use this model" button any more.
    expect(find.text('Use this model'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.tap(find.text('Classic oval'));
    await tester.pumpAndSettle();
    expect(picked, [1]);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
  });
}

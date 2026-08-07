import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/features/shade/shade_page.dart';
import 'package:dental_lab_ai/features/shade/tooth_overlay.dart';
import 'package:dental_lab_ai/main.dart';
import 'package:dental_lab_ai/shell/app_sidebar.dart';

void main() {
  test('Outline edit history undoes and redoes a drag', () {
    final history = OutlineEditHistory();
    var current = OutlineEditHistory.snapOf(
      [
        [0.1, 0.1],
        [0.2, 0.2],
      ],
      [0.0, 0.0],
    );
    final before = OutlineEditHistory.snapOf(current.verts, current.bulges);
    current = OutlineEditHistory.snapOf(
      [
        [0.3, 0.3],
        [0.2, 0.2],
      ],
      [0.01, 0.0],
    );
    history.record(before);

    expect(history.canUndo, isTrue);
    expect(history.canRedo, isFalse);

    final undone = history.undo(current)!;
    expect(undone.verts, before.verts);
    expect(undone.bulges, before.bulges);
    expect(history.canRedo, isTrue);

    final redone = history.redo(undone)!;
    expect(redone.verts, current.verts);
    expect(redone.bulges, current.bulges);
  });

  testWidgets('Login screen shows Elite Dent logo', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(DentalLabApp(localeController: LocaleController()));
    expect(find.byType(Image), findsWidgets);
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('Sidebar closes with left swipe and opens with right swipe',
      (tester) async {
    var collapsed = false;
    await tester.pumpWidget(
      LocaleScope(
        controller: LocaleController(),
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppSidebar(
                  active: AppNavItem.shade,
                  collapsed: collapsed,
                  onSelect: (_) {},
                  onToggle: () => setState(() => collapsed = !collapsed),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.fling(find.byType(AppSidebar), const Offset(-300, 0), 800);
    await tester.pumpAndSettle();
    expect(collapsed, isTrue);

    await tester.fling(find.byType(AppSidebar), const Offset(300, 0), 800);
    await tester.pumpAndSettle();
    expect(collapsed, isFalse);
  });

  testWidgets('Session panel collapses and reopens with swipes',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleScope(
        controller: LocaleController(),
        child: MaterialApp(
          home: Scaffold(body: ShadePage(api: _EmptyApi())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byKey(const ValueKey('session-panel')),
      const Offset(300, 0),
      800,
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open session panel'), findsOneWidget);

    await tester.fling(
      find.byKey(const ValueKey('session-panel')),
      const Offset(-300, 0),
      800,
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close session panel'), findsOneWidget);
  });
}

class _EmptyApi extends ApiClient {
  @override
  Future<List<Map<String, dynamic>>> listPatients() async => [];
}

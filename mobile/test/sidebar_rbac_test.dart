import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/features/laboratories/laboratories_page.dart';
import 'package:dental_lab_ai/shell/app_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _textAny(List<String> values) {
  return find.byWidgetPredicate(
    (widget) => widget is Text && values.contains(widget.data),
  );
}

void main() {
  Widget wrap(Widget child) {
    return LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  Future<void> setWideSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('hides System Users for dentist and laboratory (flag off)',
      (tester) async {
    await setWideSurface(tester);
    await tester.pumpWidget(
      wrap(
        AppSidebar(
          active: AppNavItem.dashboard,
          onSelect: (_) {},
          onToggle: () {},
        ),
      ),
    );

    expect(
      _textAny(['System Users', 'Systembenutzer']),
      findsNothing,
    );
    expect(_textAny(['Laboratories', 'Labore']), findsNothing);
    expect(find.byIcon(Icons.manage_accounts_outlined), findsNothing);
  });

  testWidgets('shows System Users with the users icon for admin',
      (tester) async {
    await setWideSurface(tester);
    await tester.pumpWidget(
      wrap(
        AppSidebar(
          active: AppNavItem.dashboard,
          onSelect: (_) {},
          onToggle: () {},
          showLaboratories: true,
        ),
      ),
    );

    expect(
      _textAny(['System Users', 'Systembenutzer']),
      findsOneWidget,
    );
    expect(_textAny(['Laboratories', 'Labore']), findsNothing);
    expect(find.byIcon(Icons.manage_accounts_outlined), findsOneWidget);
    expect(find.byIcon(Icons.biotech_outlined), findsNothing);
  });

  testWidgets('System Users page is blocked for non-admin roles',
      (tester) async {
    await tester.pumpWidget(
      wrap(LaboratoriesPage(api: _NonAdminApi())),
    );

    expect(
      _textAny([
        'You do not have permission to do this.',
        'Sie haben keine Berechtigung für diese Aktion.',
      ]),
      findsOneWidget,
    );
    expect(
      _textAny(['System Users', 'Systembenutzer']),
      findsNothing,
    );
  });
}

class _NonAdminApi extends ApiClient {
  @override
  bool get isAdmin => false;
}

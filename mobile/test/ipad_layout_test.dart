import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/core/theme/app_theme.dart';
import 'package:dental_lab_ai/core/widgets/ui_kit.dart';
import 'package:dental_lab_ai/features/shade/shade_session_pane.dart';
import 'package:dental_lab_ai/shell/app_shell.dart';
import 'package:dental_lab_ai/shell/app_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real iPad logical sizes (landscape). Portrait is the same size flipped.
const _ipads = {
  'iPad Air 11"': Size(1180, 820),
  'iPad Pro 11" (M1-M2)': Size(1194, 834),
  'iPad Pro 11" (M4)': Size(1210, 834),
  'iPad Pro 12.9"': Size(1366, 1024),
  'iPad Pro 13" (M4)': Size(1376, 1032),
};

/// Every page reachable from the sidebar, by its icon.
const _pages = {
  AppNavItem.dashboard: Icons.grid_view_rounded,
  AppNavItem.patients: Icons.people_outline,
  AppNavItem.appointments: Icons.calendar_today_outlined,
  AppNavItem.camera: Icons.photo_camera_outlined,
  AppNavItem.scans: Icons.view_in_ar_outlined,
  AppNavItem.shade: Icons.palette_outlined,
  AppNavItem.smilePreview: Icons.sentiment_satisfied_alt_outlined,
  AppNavItem.interpreter: Icons.translate_rounded,
  AppNavItem.messages: Icons.chat_bubble_outline,
  AppNavItem.notifications: Icons.notifications_none_rounded,
  AppNavItem.reports: Icons.bar_chart_rounded,
  AppNavItem.settings: Icons.settings_outlined,
};

/// Backend that answers every request with an empty list.
ApiClient _emptyApi() => ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );

Future<void> _pumpShell(WidgetTester tester, Size logical) async {
  const dpr = 2.0;
  tester.view.physicalSize = logical * dpr;
  tester.view.devicePixelRatio = dpr;
  // Status bar + home indicator, as on a real iPad.
  tester.view.padding = const FakeViewPadding(top: 24 * dpr, bottom: 20 * dpr);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    LocaleScope(
      controller: LocaleController(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(api: _emptyApi(), dentistName: 'Dr Test'),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _open(WidgetTester tester, AppNavItem item) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppSidebar),
      matching: find.byIcon(_pages[item]!),
    ),
  );
  await _settle(tester);
}

/// Pages load async (patients, history) and animate; pump several frames so
/// chained setStates and implicit animations all finish. (No pumpAndSettle:
/// the inbox poll timer never settles.)
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> _expandSidebar(WidgetTester tester) async {
  await tester.tap(find.descendant(
    of: find.byType(AppSidebar),
    matching: find.byIcon(Icons.chevron_right_rounded),
  ));
  await _settle(tester);
  expect(_sidebarWidth(tester), 248);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Sidebar width without its 12pt left margin.
double _sidebarWidth(WidgetTester tester) =>
    tester.getSize(find.byType(AppSidebar)).width - 12;

/// True when the header's action buttons sit on the title row.
bool _headerOneRow(WidgetTester tester) {
  // Only the dashboard is mounted when this runs, so there is one header.
  final header = find.byType(PageHeader).first;
  final badge = find.descendant(of: header, matching: find.byType(NeoIconBadge));
  final button = find.descendant(
    of: header,
    matching: find.byIcon(Icons.add_rounded),
  );
  return (tester.getCenter(badge).dy - tester.getCenter(button).dy).abs() < 12;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final MapEntry(key: name, value: landscape) in _ipads.entries) {
    final is11 = landscape.width < 1300;

    testWidgets('$name landscape: sidebar, header, shade pane', (tester) async {
      await _pumpShell(tester, landscape);

      // 11" gets the icon rail; 12.9"/13" keep the labelled sidebar.
      expect(_sidebarWidth(tester), is11 ? 72 : 248);
      expect(_headerOneRow(tester), isTrue,
          reason: 'dashboard header should fit on one row');

      await _open(tester, AppNavItem.shade);
      final pane = tester.getSize(find.byType(ShadeSessionPane)).width;
      expect(pane, 300);
      await _unmount(tester);
    });

    for (final size in [landscape, landscape.flipped]) {
      final orientation = size == landscape ? 'landscape' : 'portrait';
      testWidgets('$name $orientation: every page lays out without overflow',
          (tester) async {
        await _pumpShell(tester, size);
        for (final item in _pages.keys) {
          await _open(tester, item);
          // Overflow / layout errors surface as test exceptions.
          expect(tester.takeException(), isNull, reason: '$item');
        }
        await _unmount(tester);
      });
    }
  }

  testWidgets('11" landscape with sidebar expanded still fits', (tester) async {
    await _pumpShell(tester, const Size(1194, 834));
    await _expandSidebar(tester);

    // Too narrow for one row: header stacks with compact (22pt) title.
    expect(_headerOneRow(tester), isFalse);
    final title = tester.widget<Text>(
      find.descendant(
        of: find.byType(PageHeader).first,
        matching: find.byType(Text),
      ).first,
    );
    expect(title.style?.fontSize, 22);

    // Shade session list narrows so photo + result keep their room.
    // (Picking a page folds the sidebar back, so expand again.)
    await _open(tester, AppNavItem.shade);
    expect(tester.getSize(find.byType(ShadeSessionPane)).width, 300);
    await _expandSidebar(tester);
    expect(tester.getSize(find.byType(ShadeSessionPane)).width, 252);
    await _unmount(tester);
  });
}

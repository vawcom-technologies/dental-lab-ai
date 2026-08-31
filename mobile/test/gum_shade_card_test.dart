import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/features/shade/shade_override_pane.dart';
import 'package:dental_lab_ai/features/shade/shade_result_pane.dart';
import 'package:dental_lab_ai/features/shade/shade_shared.dart';

Widget _pane({
  required String detected,
  Map<String, dynamic>? gum,
}) {
  return LocaleScope(
    controller: LocaleController(),
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 900,
          child: ShadeResultPane(
            teeth: const [],
            selectedToothIndex: null,
            focusZone: 'middle',
            pendingShade: null,
            detected: detected,
            confidence: 0.87,
            selected: detected,
            finalShade: null,
            overallTopMatches: const [],
            gum: gum,
            saving: false,
            swatch: shadeSwatch,
            zoneEffective: (_) => null,
            zoneOf: (_, __) => null,
            zoneOverridden: (_) => false,
            onSelectTooth: (_, {zone}) {},
            onDeleteTooth: () {},
            onBeginZoneOverride: (_, __) {},
            onSelectGum: () {},
            onBeginGumOverride: () {},
            onOverallShade: (_) {},
            onAcceptAi: () {},
            onSaveOverride: () {},
            magnifierFocal: ValueNotifier<Offset?>(null),
            magnifierViewSize: null,
            previewBytes: null,
            analysisImageSize: Size.zero,
            dragTick: ValueNotifier<int>(0),
            editOutline: null,
            editBulges: null,
            activeHandleIndex: null,
            activeEdgeIndex: null,
          ),
        ),
      ),
    ),
  );
}

Widget _override({required int tab}) {
  return LocaleScope(
    controller: LocaleController(),
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 320,
          child: ShadeOverridePane(
            focusZone: 'middle',
            selectedToothIndex: 0,
            selected: 'A2',
            topMatches: const [],
            overallTopMatches: const [],
            swatch: shadeSwatch,
            onShadeChoice: (_) {},
            onOverallShadeChoice: (_) {},
            selectedGum: 'G3',
            onGumShadeChoice: (_) {},
            tab: tab,
            onTabChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Results pane shows gum card under VITA hero', (tester) async {
    await tester.pumpWidget(
      _pane(
        detected: 'A2',
        gum: {
          'detected_shade': 'G3',
          'confidence': 0.72,
          'sampled_rgb': [180, 110, 120],
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A2'), findsWidgets);
    expect(find.text('G3'), findsOneWidget);
    expect(find.byType(GumShadeCard), findsOneWidget);
  });

  testWidgets('Results pane shows empty gum card after detect', (tester) async {
    await tester.pumpWidget(_pane(detected: 'A2'));
    await tester.pumpAndSettle();

    expect(find.text('A2'), findsWidgets);
    expect(find.text('G3'), findsNothing);
    expect(find.byType(GumShadeCard), findsOneWidget);
  });

  testWidgets('override teeth tab has VITA samples not G chips', (tester) async {
    await tester.pumpWidget(_override(tab: 0));
    await tester.pumpAndSettle();

    expect(find.text('A1'), findsWidgets);
    expect(find.text('G5'), findsNothing);
  });

  testWidgets('override gum tab shows G1–G5 chips', (tester) async {
    await tester.pumpWidget(_override(tab: 1));
    await tester.pumpAndSettle();

    for (final s in kGingivaShades) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text('A1'), findsNothing);
  });

  testWidgets('override teeth tab has no G1–G4 chips either', (tester) async {
    await tester.pumpWidget(_override(tab: 0));
    await tester.pumpAndSettle();

    for (final s in kGingivaShades) {
      expect(find.text(s), findsNothing);
    }
  });
}

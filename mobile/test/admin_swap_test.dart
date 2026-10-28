import 'package:dental_lab_ai/core/widgets/page_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Painted opacity of the tab holding [text].
double _opacityOf(WidgetTester tester, String text) => tester
    .renderObject<RenderAnimatedOpacity>(
      find.ancestor(of: find.text(text, skipOffstage: false), matching: find.byType(AnimatedOpacity)).first,
    )
    .opacity
    .value;

void main() {
  testWidgets('switching tabs fully hides the previous one', (tester) async {
    final tab = ValueNotifier(0);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<int>(
        valueListenable: tab,
        builder: (_, t, _) => AdminSwap(index: t, builder: (i) => Text('tab $i')),
      ),
    ));
    tab.value = 1;
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, 'tab 0'), 0, reason: 'old tab must fade out, not stay on top');
    expect(_opacityOf(tester, 'tab 1'), 1);
    tab.value = 0;
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, 'tab 1'), 0);
    expect(_opacityOf(tester, 'tab 0'), 1);
  });
}

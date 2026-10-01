import 'package:dental_lab_ai/core/widgets/tooth_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RotatingLoadingText cycles messages', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RotatingLoadingText(
            messages: ['one', 'two', 'three'],
            interval: Duration(milliseconds: 100),
          ),
        ),
      ),
    );

    expect(find.text('one'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('two'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('three'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('single message stays put', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RotatingLoadingText(
            messages: ['only'],
            interval: Duration(milliseconds: 50),
          ),
        ),
      ),
    );
    expect(find.text('only'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('only'), findsOneWidget);
  });
}

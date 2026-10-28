import 'package:dental_lab_ai/core/widgets/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a toast raised inside a dialog shows above it', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialog) => AlertDialog(
                content: TextButton(
                  onPressed: () => AppSnackBars.success(dialog, 'Saved here'),
                  child: const Text('save'),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('save'));
    await tester.pump(const Duration(milliseconds: 400));
    // Visible and on top: not hidden behind the dialog's barrier.
    expect(find.text('Saved here').hitTestable(), findsOneWidget);
    await tester.pumpAndSettle(); // it dismisses itself
    expect(find.text('Saved here'), findsNothing);
  });
}

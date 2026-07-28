import 'package:flutter_test/flutter_test.dart';
import 'package:dental_lab_ai/main.dart';

void main() {
  testWidgets('Login screen shows Elite Dent logo', (tester) async {
    await tester.pumpWidget(const DentalLabApp());
    expect(find.byType(Image), findsWidgets);
    expect(find.text('Sign in'), findsOneWidget);
  });
}

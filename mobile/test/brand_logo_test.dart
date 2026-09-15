import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/core/widgets/brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BrandLogo uses the EliteDent wordmark asset', (tester) async {
    await tester.pumpWidget(
      LocaleScope(
        controller: LocaleController(),
        child: const MaterialApp(
          home: Scaffold(body: Center(child: BrandLogo(height: 48))),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    final asset = provider is ResizeImage
        ? provider.imageProvider
        : provider;
    expect(asset, isA<AssetImage>());
    expect((asset as AssetImage).assetName, BrandLogo.assetPath);
    expect(BrandLogo.assetPath, 'assets/brand/logo.png');
    expect(find.bySemanticsLabel('EliteDent'), findsOneWidget);
  });
}

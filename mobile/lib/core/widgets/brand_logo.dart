import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Official EliteDent wordmark from elite-d.de (transparent PNG).
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.height = 40,
    this.width,
    this.showWordmarkFallback = true,
  });

  static const assetPath = 'assets/brand/logo.png';

  final double height;
  final double? width;
  final bool showWordmarkFallback;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheHeight = (height * dpr).round().clamp(64, 2048);
    return Image.asset(
      assetPath,
      height: height,
      width: width,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      cacheHeight: cacheHeight,
      semanticLabel: 'EliteDent',
      errorBuilder: (_, _, _) {
        if (!showWordmarkFallback) return const SizedBox.shrink();
        return Text(
          'EliteDent',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: height * 0.45,
            color: AppColors.navy,
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Elite Dent logo (transparent PNG — white background removed).
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.height = 40,
    this.scale = 1.15,
    this.showWordmarkFallback = true,
  });

  static const assetPath = 'assets/brand/logo.png';

  final double height;
  final double scale;
  final bool showWordmarkFallback;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheHeight = (height * scale * dpr).round().clamp(64, 2048);
    return Transform.scale(
      scale: scale,
      child: Image.asset(
        assetPath,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        cacheHeight: cacheHeight,
        errorBuilder: (_, _, _) {
          if (!showWordmarkFallback) return const SizedBox.shrink();
          return Text(
            'Elite Dent',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: height * 0.45,
              color: AppColors.navy,
            ),
          );
        },
      ),
    );
  }
}

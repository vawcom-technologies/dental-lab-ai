import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/l10n/app_localizations.dart';

/// FDI chart asset (patient view). Molars (x6–x8) are not selectable.
const kFdiChartAsset = 'assets/clinical/fdi_chart.png';

/// Upper arch left→right in the photo (patient's right → left).
const kUpperFdiSelectableLtr = [15, 14, 13, 12, 11, 21, 22, 23, 24, 25];

/// Lower arch left→right in the photo (patient's right → left).
const kLowerFdiSelectableLtr = [45, 44, 43, 42, 41, 31, 32, 33, 34, 35];

const kSelectableFdi = {
  ...kUpperFdiSelectableLtr,
  ...kLowerFdiSelectableLtr,
};

/// Normalized center of each red FDI badge on [kFdiChartAsset] (1200×1200).
/// Measured from red-digit blobs; molars omitted.
const Map<int, Offset> kFdiCircleCenters = {
  11: Offset(0.4726, 0.1317),
  12: Offset(0.4306, 0.1459),
  13: Offset(0.3914, 0.1700),
  14: Offset(0.3598, 0.2039),
  15: Offset(0.3364, 0.2437),
  21: Offset(0.5279, 0.1321),
  22: Offset(0.5715, 0.1462),
  23: Offset(0.6103, 0.1704),
  24: Offset(0.6433, 0.2043),
  25: Offset(0.6702, 0.2441),
  31: Offset(0.5259, 0.8658),
  32: Offset(0.5736, 0.8529),
  33: Offset(0.6112, 0.8268),
  34: Offset(0.6450, 0.7962),
  35: Offset(0.6680, 0.7569),
  41: Offset(0.4750, 0.8639),
  42: Offset(0.4328, 0.8531),
  43: Offset(0.3948, 0.8270),
  44: Offset(0.3568, 0.7963),
  45: Offset(0.3254, 0.7571),
};

/// Visual ring ≈ badge size on the PNG (measured ~0.018–0.021).
const double kFdiBadgeRadius = 0.020;

/// Tap target slightly larger than the printed circle (fat-finger).
const double kFdiHitRadius = 0.034;

List<int> centeredFdiWindow(List<int> pool, int count) {
  if (count <= 0) return const [];
  if (count >= pool.length) return List<int>.from(pool);
  final start = (pool.length - count) ~/ 2;
  return pool.sublist(start, start + count);
}

double _toothSortX(Map<String, dynamic> tooth) {
  final geo = tooth['geometry'];
  if (geo is Map) {
    final label = geo['label'];
    if (label is Map && label['x'] is num) {
      return (label['x'] as num).toDouble();
    }
    final bbox = geo['bbox'];
    if (bbox is Map && bbox['x'] is num) {
      final x = (bbox['x'] as num).toDouble();
      final w = (bbox['w'] as num?)?.toDouble() ?? 0;
      return x + w / 2;
    }
  }
  final archIdx = tooth['arch_index'];
  if (archIdx is num) return archIdx.toDouble();
  return (tooth['tooth_index'] as num?)?.toDouble() ?? 0;
}

/// FDI → detected `tooth_index` for the current analyze result.
Map<int, int> mapFdiToToothIndex(List<Map<String, dynamic>> teeth) {
  final usable = [
    for (final t in teeth)
      if (t['rejected'] != true && t['tooth_index'] is num) t,
  ];
  if (usable.isEmpty) return const {};

  final fromBackend = <int, int>{};
  for (final t in usable) {
    final fdi = t['fdi'];
    if (fdi is num) {
      final n = fdi.toInt();
      if (n >= 11 && n <= 48) {
        fromBackend[n] = (t['tooth_index'] as num).toInt();
      }
    }
  }
  if (fromBackend.isNotEmpty) return fromBackend;

  final upper = [
    for (final t in usable)
      if (t['arch']?.toString() == 'upper') t,
  ]..sort((a, b) => _toothSortX(a).compareTo(_toothSortX(b)));
  final lower = [
    for (final t in usable)
      if (t['arch']?.toString() == 'lower') t,
  ]..sort((a, b) => _toothSortX(a).compareTo(_toothSortX(b)));

  final out = <int, int>{};

  void assign(List<Map<String, dynamic>> row, List<int> pool) {
    final fdis = centeredFdiWindow(pool, row.length);
    for (var i = 0; i < fdis.length; i++) {
      out[fdis[i]] = (row[i]['tooth_index'] as num).toInt();
    }
  }

  if (upper.isNotEmpty || lower.isNotEmpty) {
    assign(upper, kUpperFdiSelectableLtr);
    assign(lower, kLowerFdiSelectableLtr);
    return out;
  }

  final single = [...usable]
    ..sort((a, b) => _toothSortX(a).compareTo(_toothSortX(b)));
  assign(single, kUpperFdiSelectableLtr);
  return out;
}

class FdiToothChart extends StatelessWidget {
  const FdiToothChart({
    super.key,
    required this.teeth,
    required this.selectedToothIndex,
    required this.onSelectTooth,
  });

  final List<Map<String, dynamic>> teeth;
  final int? selectedToothIndex;
  final ValueChanged<int> onSelectTooth;

  @override
  Widget build(BuildContext context) {
    final fdiMap = mapFdiToToothIndex(teeth);
    final selectedFdi = () {
      for (final e in fdiMap.entries) {
        if (e.value == selectedToothIndex) return e.key;
      }
      return null;
    }();
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          selectedFdi == null
              ? AppLocalizations.of(context).tr('sh.pinchTap')
              : AppLocalizations.of(context).trp('sh.selFdi', {'n': selectedFdi}),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
                return const SizedBox.shrink();
              }
              // Portrait: split the chart on the horizontal dotted line so the
              // upper jaw sits left and the lower jaw right. Landscape keeps
              // the full square chart.
              if (portrait) {
                return _portraitSplit(
                  constraints: constraints,
                  fdiMap: fdiMap,
                  selectedFdi: selectedFdi,
                );
              }
              return _landscapeSquare(
                constraints: constraints,
                fdiMap: fdiMap,
                selectedFdi: selectedFdi,
              );
            },
          ),
        ),
        if (fdiMap.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              AppLocalizations.of(context).tr('sh.uploadDetect'),
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
      ],
    );
  }

  Widget _landscapeSquare({
    required BoxConstraints constraints,
    required Map<int, int> fdiMap,
    required int? selectedFdi,
  }) {
    // Hit targets are normalized to the square PNG. Size the stack to
    // the fitted square — not maxWidth alone (height often clamps first).
    final side = constraints.maxWidth < constraints.maxHeight
        ? constraints.maxWidth
        : constraints.maxHeight;
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      boundaryMargin: const EdgeInsets.all(64),
      clipBehavior: Clip.hardEdge,
      child: Center(
        child: SizedBox(
          width: side,
          height: side,
          child: _chartStack(
            width: side,
            height: side,
            // Full square — no vertical crop.
            imageTop: 0,
            imageHeight: side,
            centers: kFdiCircleCenters,
            mapCenter: (c) => c,
            radiusSide: side,
            fdiMap: fdiMap,
            selectedFdi: selectedFdi,
          ),
        ),
      ),
    );
  }

  /// Upper half (y 0–0.5) on the left, lower half (y 0.5–1) on the right.
  Widget _portraitSplit({
    required BoxConstraints constraints,
    required Map<int, int> fdiMap,
    required int? selectedFdi,
  }) {
    const gap = 8.0;
    // Each half is 2:1 (full chart width × half height).
    final paneH = constraints.maxHeight;
    final paneW = paneH * 2;
    final fullH = paneH * 2; // square chart height at this width
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: paneW,
          height: paneH,
          child: _chartStack(
            width: paneW,
            height: paneH,
            // Top half of the square PNG.
            imageTop: 0,
            imageHeight: fullH,
            centers: {
              for (final e in kFdiCircleCenters.entries)
                if (e.value.dy < 0.5) e.key: e.value,
            },
            mapCenter: (c) => Offset(c.dx, c.dy * 2),
            radiusSide: paneW,
            fdiMap: fdiMap,
            selectedFdi: selectedFdi,
          ),
        ),
        const SizedBox(width: gap),
        SizedBox(
          width: paneW,
          height: paneH,
          child: _chartStack(
            width: paneW,
            height: paneH,
            // Bottom half: shift the full image up by one pane.
            imageTop: -paneH,
            imageHeight: fullH,
            centers: {
              for (final e in kFdiCircleCenters.entries)
                if (e.value.dy >= 0.5) e.key: e.value,
            },
            mapCenter: (c) => Offset(c.dx, (c.dy - 0.5) * 2),
            radiusSide: paneW,
            fdiMap: fdiMap,
            selectedFdi: selectedFdi,
          ),
        ),
      ],
    );
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      boundaryMargin: const EdgeInsets.all(48),
      clipBehavior: Clip.hardEdge,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: paneW * 2 + gap,
          height: paneH,
          child: row,
        ),
      ),
    );
  }

  /// Chart image + FDI hit targets. [imageTop]/[imageHeight] place the PNG
  /// inside a clipped pane so portrait can show only the upper or lower half.
  Widget _chartStack({
    required double width,
    required double height,
    required double imageTop,
    required double imageHeight,
    required Map<int, Offset> centers,
    required Offset Function(Offset) mapCenter,
    required double radiusSide,
    required Map<int, int> fdiMap,
    required int? selectedFdi,
  }) {
    return ClipRect(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            width: width,
            top: imageTop,
            height: imageHeight,
            child: Image.asset(
              kFdiChartAsset,
              fit: BoxFit.fill,
              width: width,
              height: imageHeight,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
          ),
          for (final e in centers.entries)
            _FdiCircleButton(
              fdi: e.key,
              center: mapCenter(e.value),
              paneWidth: width,
              paneHeight: height,
              radiusSide: radiusSide,
              enabled: fdiMap.containsKey(e.key),
              selected: e.key == selectedFdi,
              onTap: () {
                final idx = fdiMap[e.key];
                if (idx != null) onSelectTooth(idx);
              },
            ),
        ],
      ),
    );
  }
}

class _FdiCircleButton extends StatelessWidget {
  const _FdiCircleButton({
    required this.fdi,
    required this.center,
    required this.paneWidth,
    required this.paneHeight,
    required this.radiusSide,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final int fdi;
  /// Normalized center in the pane (0–1 on each axis).
  final Offset center;
  final double paneWidth;
  final double paneHeight;
  /// Full-chart side used for badge/hit radius (width of the PNG).
  final double radiusSide;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hit = kFdiHitRadius * radiusSide;
    final badge = kFdiBadgeRadius * radiusSide;
    final left = center.dx * paneWidth - hit;
    final top = center.dy * paneHeight - hit;

    final fill = selected
        ? AppColors.dentalBlue.withValues(alpha: 0.28)
        : enabled
            ? AppColors.dentalBlue.withValues(alpha: 0.08)
            : Colors.transparent;
    final border = selected
        ? AppColors.dentalBlue
        : enabled
            ? AppColors.dentalBlue.withValues(alpha: 0.55)
            : Colors.transparent;

    return Positioned(
      left: left,
      top: top,
      width: hit * 2,
      height: hit * 2,
      child: Tooltip(
        message: enabled ? 'FDI $fdi' : AppLocalizations.of(context).trp('sh.fdiND', {'n': fdi}),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Center(
              child: Container(
                width: badge * 2,
                height: badge * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  border: Border.all(
                    color: border,
                    width: selected ? 2.5 : (enabled ? 1.5 : 0),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

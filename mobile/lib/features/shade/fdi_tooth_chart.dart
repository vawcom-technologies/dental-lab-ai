import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          selectedFdi == null
              ? 'Pinch to zoom · tap a numbered circle'
              : 'Selected FDI $selectedFdi · pinch to zoom',
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
              // Hit targets are normalized to the square PNG. Size the stack to
              // the fitted square — not maxWidth alone (height often clamps first).
              final side = constraints.maxWidth < constraints.maxHeight
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              if (side <= 0) return const SizedBox.shrink();
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                boundaryMargin: const EdgeInsets.all(64),
                clipBehavior: Clip.hardEdge,
                child: Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          kFdiChartAsset,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.medium,
                          gaplessPlayback: true,
                        ),
                        for (final e in kFdiCircleCenters.entries)
                          _FdiCircleButton(
                            fdi: e.key,
                            center: e.value,
                            side: side,
                            enabled: fdiMap.containsKey(e.key),
                            selected: e.key == selectedFdi,
                            onTap: () {
                              final idx = fdiMap[e.key];
                              if (idx != null) onSelectTooth(idx);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (fdiMap.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Upload & detect a smile first — only found teeth are selectable.',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
      ],
    );
  }
}

class _FdiCircleButton extends StatelessWidget {
  const _FdiCircleButton({
    required this.fdi,
    required this.center,
    required this.side,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final int fdi;
  final Offset center;
  final double side;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hit = kFdiHitRadius * side;
    final badge = kFdiBadgeRadius * side;
    final left = center.dx * side - hit;
    final top = center.dy * side - hit;

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
        message: enabled ? 'FDI $fdi' : 'FDI $fdi (not detected)',
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

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'shade_shared.dart';

class ShadeOverridePane extends StatelessWidget {
  const ShadeOverridePane({
    super.key,
    required this.focusZone,
    required this.selectedToothIndex,
    required this.selected,
    required this.topMatches,
    required this.overallTopMatches,
    required this.swatch,
    required this.onShadeChoice,
    required this.onOverallShadeChoice,
  });

  final String focusZone;
  final int? selectedToothIndex;
  final String selected;
  final List<Map<String, dynamic>> topMatches;
  final List<Map<String, dynamic>> overallTopMatches;
  final Color Function(String) swatch;
  final ValueChanged<String> onShadeChoice;
  final ValueChanged<String> onOverallShadeChoice;

  @override
  Widget build(BuildContext context) {
    final zoneLabel = capitalizeZone(focusZone);
    final toothLabel = selectedToothIndex == null
        ? null
        : 'T${selectedToothIndex! + 1} · $zoneLabel';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;
        final chipW = wide ? 48.0 : 42.0;

        return SectionCard(
          depth: 0,
          color: Colors.white,
          boxShadow: kShadeCardGlow,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Manual Override — VITA Classical',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                if (toothLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Editing $toothLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dentalBlue,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                ..._shadeBody(
                  wide: wide,
                  chipW: chipW,
                  toothLabel: toothLabel,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _shadeBody({
    required bool wide,
    required double chipW,
    required String? toothLabel,
  }) {
    final guideBlocks = [
      const Text(
        'All VITA Classical shades',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
      const SizedBox(height: 4),
      _shadeWrap(kVitaShades, wide: wide, chipW: chipW),
      const SizedBox(height: 14),
      const Text(
        'Target shades',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
      const SizedBox(height: 4),
      _shadeWrap(kTargetShades, wide: wide, chipW: chipW),
      const SizedBox(height: 14),
      const Text(
        'Tooth samples',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
      const SizedBox(height: 4),
      _vitaToothRow(wide: wide),
    ];

    if (topMatches.isEmpty && overallTopMatches.isEmpty) return guideBlocks;

    final similarMatches = topMatches.take(5).toList();
    final overallMatches = overallTopMatches.take(5).toList();

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (similarMatches.isNotEmpty)
            Expanded(
              child: _matchBlock(
                title: 'Similar shades',
                subtitle: toothLabel == null
                    ? 'For the focused zone'
                    : 'For $toothLabel',
                matches: similarMatches,
                onPick: onShadeChoice,
              ),
            ),
          if (similarMatches.isNotEmpty && overallMatches.isNotEmpty)
            const SizedBox(width: 12),
          if (overallMatches.isNotEmpty)
            Expanded(
              child: _matchBlock(
                title: 'Best overall',
                subtitle: 'Across all teeth',
                matches: overallMatches,
                onPick: onOverallShadeChoice,
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      ...guideBlocks,
    ];
  }

  Widget _matchBlock({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> matches,
    required ValueChanged<String> onPick,
  }) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < matches.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                SimilarShadeChip(
                  shade: matches[i]['shade']?.toString() ?? '',
                  deltaE: matches[i]['delta_e_2000'],
                  selected: selected == matches[i]['shade']?.toString(),
                  swatch: swatch,
                  onTap: () {
                    final s = matches[i]['shade']?.toString();
                    if (s != null && s.isNotEmpty) onPick(s);
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _shadeWrap(
    List<String> shades, {
    required bool wide,
    required double chipW,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: shades.map((s) {
        final isSelected = selected == s;
        return InkWell(
          onTap: () => onShadeChoice(s),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: chipW,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? AppColors.navy : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: wide ? 22 : 18,
                    width: double.infinity,
                    child: shadeEnamelFill(s),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  s,
                  style: TextStyle(
                    fontSize: wide ? 10 : 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _vitaToothRow({required bool wide}) {
    final h = wide ? 52.0 : 44.0;
    final w = wide ? 34.0 : 28.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final shade in kVitaShades) ...[
            if (shade != kVitaShades.first) const SizedBox(width: 4),
            InkWell(
              onTap: () => onShadeChoice(shade),
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: w,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: selected == shade
                            ? Border.all(color: AppColors.navy, width: 2)
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.asset(
                          vitaToothAsset(shade),
                          width: w,
                          height: h,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: swatch(shade)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      shade,
                      style: TextStyle(
                        fontSize: wide ? 10 : 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SimilarShadeChip extends StatelessWidget {
  const SimilarShadeChip({
    super.key,
    required this.shade,
    required this.deltaE,
    required this.selected,
    required this.swatch,
    required this.onTap,
  });

  final String shade;
  final Object? deltaE;
  final bool selected;
  final Color Function(String) swatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (shade.isEmpty) return const SizedBox.shrink();
    final deText = deltaE is num
        ? 'ΔE ${(deltaE as num).toStringAsFixed(1)}'
        : (deltaE?.toString() ?? '');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 72,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
        decoration: BoxDecoration(
          color: swatch(shade).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: shadeEnamelFill(shade),
            ),
            const SizedBox(height: 5),
            Text(
              shade,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: AppColors.navy,
              ),
            ),
            if (deText.isNotEmpty)
              Text(
                deText,
                style: const TextStyle(fontSize: 10, color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}

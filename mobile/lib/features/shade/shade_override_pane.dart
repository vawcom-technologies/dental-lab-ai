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
    required this.swatch,
    required this.onShadeChoice,
  });

  final String focusZone;
  final int? selectedToothIndex;
  final String selected;
  final List<Map<String, dynamic>> topMatches;
  final Color Function(String) swatch;
  final ValueChanged<String> onShadeChoice;

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
          boxShadow: kShadeCardGlow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Builder(
                builder: (context) {
                  final vitaWrap = Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: kVitaShades.map((s) {
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
                              color: isSelected
                                  ? AppColors.navy
                                  : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                height: wide ? 22 : 18,
                                decoration: BoxDecoration(
                                  color: swatch(s),
                                  borderRadius: BorderRadius.circular(5),
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

                  if (topMatches.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'All VITA Classical shades',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        vitaWrap,
                      ],
                    );
                  }

                  final similarHeading = SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        const Text(
                          'Similar shades',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          toothLabel == null
                              ? 'For the focused zone'
                              : 'For $toothLabel',
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  );
                  final similarMatches = topMatches.take(5).toList();
                  final similarShades = SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth - 32,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < similarMatches.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            SimilarShadeChip(
                              shade:
                                  similarMatches[i]['shade']?.toString() ?? '',
                              deltaE: similarMatches[i]['delta_e_2000'],
                              selected: selected ==
                                  similarMatches[i]['shade']?.toString(),
                              swatch: swatch,
                              onTap: () {
                                final s =
                                    similarMatches[i]['shade']?.toString();
                                if (s != null && s.isNotEmpty) {
                                  onShadeChoice(s);
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                  final allShades = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'All VITA Classical shades',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      vitaWrap,
                    ],
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      similarHeading,
                      const SizedBox(height: 16),
                      similarShades,
                      const SizedBox(height: 14),
                      allShades,
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
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
                color: swatch(shade),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
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

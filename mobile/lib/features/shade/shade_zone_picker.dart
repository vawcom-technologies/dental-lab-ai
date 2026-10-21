import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'shade_shared.dart';

/// One-step shade pick for a tooth zone (or the gum): the AI's pick and its
/// closest matches first, then every shade in VITA order. Returns the shade,
/// or null when cancelled.
Future<String?> pickZoneShade(
  BuildContext context, {
  required String title,
  required List<String> shades,
  required Color Function(String) swatch,
  String? detected,
  String? current,
  List<Map<String, dynamic>> matches = const [],
  bool guideImages = false,
  Widget? preview,
}) {
  return AppDialogs.sheet<String>(
    context: context,
    // Landscape: wider, photo beside the shades. Portrait keeps the normal
    // width and puts the photo on top.
    maxWidth: preview != null && MediaQuery.orientationOf(context) == Orientation.landscape ? 1040 : 560,
    builder: (ctx) => _ZonePicker(
      title: title,
      shades: shades,
      swatch: swatch,
      detected: detected,
      current: current,
      matches: matches,
      guideImages: guideImages,
      preview: preview,
    ),
  );
}

class _ZonePicker extends StatelessWidget {
  const _ZonePicker({
    required this.title,
    required this.shades,
    required this.swatch,
    this.detected,
    this.current,
    this.matches = const [],
    this.guideImages = false,
    this.preview,
  });

  /// Zoomable photo with the selected tooth highlighted, left of the shades.
  final Widget? preview;

  /// Show the real VITA shade-guide tooth photos (enamel shades only).
  final bool guideImages;
  final String title;
  final List<String> shades;
  final Color Function(String) swatch;
  final String? detected;
  final String? current;
  final List<Map<String, dynamic>> matches;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    // ΔE (colour distance) per shade, from this zone's matches.
    final de = <String, double>{
      for (final m in matches)
        if (m['delta_e_2000'] is num) '${m['shade']}': (m['delta_e_2000'] as num).toDouble(),
    };
    String? deNote(String s) => de[s] == null ? null : 'ΔE ${de[s]!.toStringAsFixed(1)}';
    final close = [
      for (final m in matches)
        if ('${m['shade'] ?? ''}' case final s when s.isNotEmpty && shades.contains(s) && s != detected) s,
    ].take(4).toList();
    // VITA groups (A, B, C, D, then the rest) read as rows.
    final groups = <String, List<String>>{};
    for (final s in shades) {
      final key = kVitaShades.contains(s) ? s[0] : '·';
      (groups[key] ??= []).add(s);
    }
    Widget tile(String s, {String? note}) => _ShadeTile(
          shade: s,
          color: swatch(s),
          selected: s == current,
          note: note,
          onTap: () => Navigator.pop(context, s),
        );
    // Solid white, not frosted: the VITA tooth photos have white backgrounds.
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: _withPreview(context, SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: AppFonts.style(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  ),
                  IconButton(
                    tooltip: loc.cancel,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                  ),
                ],
              ),
              if (detected != null || close.isNotEmpty) ...[
                const SizedBox(height: 6),
                SectionLabel(loc.tr('sh.pickSuggested')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (detected != null)
                      tile(detected!, note: [loc.tr('sh.pickAi'), ?deNote(detected!)].join('\n')),
                    for (final s in close) tile(s, note: deNote(s)),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (guideImages) ...[
                SectionLabel(loc.tr('sh.pickGuide')),
                const SizedBox(height: 8),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kVitaShades.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final v = kVitaShades[i];
                      final on = v == current;
                      return Pressable(
                        onTap: () => Navigator.pop(context, v),
                        scale: 0.94,
                        builder: (_, _) => Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: on ? AppColors.dentalBlue : Colors.transparent, width: 2),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.asset(
                                  vitaToothAsset(v),
                                  width: 40,
                                  height: 68,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(width: 40, height: 68, color: swatch(v)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(v, style: AppFonts.style(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.navy)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SectionLabel(loc.tr('sh.pickAll')),
              const SizedBox(height: 8),
              for (final row in groups.values) ...[
                Wrap(spacing: 8, runSpacing: 8, children: [for (final s in row) tile(s)]),
                const SizedBox(height: 8),
              ],
            ],
          ),
        )),
      ),
    );
  }

  /// Photo left of the shades (or above them on a narrow sheet).
  Widget _withPreview(BuildContext context, Widget shadesList) {
    final p = preview;
    if (p == null) return shadesList;
    return LayoutBuilder(
      builder: (context, box) {
        final side = MediaQuery.orientationOf(context) == Orientation.landscape && box.maxWidth >= 760;
        final photo = Padding(
          padding: side ? const EdgeInsets.fromLTRB(16, 16, 0, 16) : const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: ClipRRect(borderRadius: BorderRadius.circular(16), child: p),
        );
        if (side) {
          return SizedBox(
            height: box.maxHeight.isFinite ? box.maxHeight : 560,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: photo),
                Expanded(flex: 5, child: shadesList),
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [SizedBox(height: 280, child: photo), Flexible(child: shadesList)],
        );
      },
    );
  }
}

class _ShadeTile extends StatelessWidget {
  const _ShadeTile({
    required this.shade,
    required this.color,
    required this.selected,
    required this.onTap,
    this.note,
  });

  final String shade;
  final Color color;
  final bool selected;
  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Big targets: 64pt wide, a real colour chip, the code under it.
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      builder: (_, _) => AnimatedContainer(
        duration: AppMotion.fast,
        width: 72,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.dentalBlue.withValues(alpha: 0.10) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.dentalBlue : AppColors.border.withValues(alpha: 0.7),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 30,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            ),
            const SizedBox(height: 5),
            Text(shade, style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navy)),
            if (note != null)
              Text(note!,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.aiPurple)),
          ],
        ),
      ),
    );
  }
}

import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'shade_override_pane.dart' show SimilarShadeChip;
import 'shade_shared.dart';
import 'tooth_overlay.dart';

class ShadeResultPane extends StatelessWidget {
  const ShadeResultPane({
    super.key,
    required this.teeth,
    required this.selectedToothIndex,
    required this.focusZone,
    required this.pendingShade,
    required this.detected,
    required this.confidence,
    required this.selected,
    required this.finalShade,
    required this.overallTopMatches,
    required this.saving,
    required this.swatch,
    required this.zoneEffective,
    required this.zoneOf,
    required this.zoneOverridden,
    required this.onSelectTooth,
    required this.onDeleteTooth,
    required this.onBeginZoneOverride,
    required this.onOverallShade,
    required this.onAcceptAi,
    required this.onSaveOverride,
    required this.magnifierFocal,
    required this.magnifierViewSize,
    required this.previewBytes,
    required this.analysisImageSize,
    required this.dragTick,
    required this.editOutline,
    required this.editBulges,
    required this.activeHandleIndex,
    required this.activeEdgeIndex,
  });

  final List<Map<String, dynamic>> teeth;
  final int? selectedToothIndex;
  final String focusZone;
  final String? pendingShade;
  final String detected;
  final double confidence;
  final String selected;
  final String? finalShade;
  final List<Map<String, dynamic>> overallTopMatches;
  final bool saving;
  final Color Function(String) swatch;
  final String? Function(Map<String, dynamic>?) zoneEffective;
  final Map<String, dynamic>? Function(Map<String, dynamic>, String) zoneOf;
  final bool Function(Map<String, dynamic>?) zoneOverridden;
  final void Function(int index, {String? zone}) onSelectTooth;
  final VoidCallback onDeleteTooth;
  final void Function(int index, String zone) onBeginZoneOverride;
  final ValueChanged<String> onOverallShade;
  final VoidCallback onAcceptAi;
  final VoidCallback onSaveOverride;
  final ValueNotifier<Offset?> magnifierFocal;
  final Size? magnifierViewSize;
  final Uint8List? previewBytes;
  final Size analysisImageSize;
  final ValueNotifier<int> dragTick;
  final List<List<double>>? editOutline;
  final List<double>? editBulges;
  final int? activeHandleIndex;
  final int? activeEdgeIndex;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        SectionCard(
          depth: 0,
          color: Colors.white,
          boxShadow: kShadeCardGlow,
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Result',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (teeth.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...teeth.map((t) {
                            final idx = (t['tooth_index'] as num).toInt();
                            final rejected = t['rejected'] == true;
                            final active = selectedToothIndex == idx;
                            final label =
                                t['label']?.toString() ?? 'Tooth ${idx + 1}';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => onSelectTooth(idx),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Ink(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? AppColors.dentalBlue
                                              .withValues(alpha: 0.12)
                                          : AppColors.neo,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: active
                                            ? AppColors.dentalBlue
                                            : AppColors.border,
                                        width: active ? 1.8 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              label,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13,
                                              ),
                                            ),
                                            if (rejected) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                t['reject_reason']
                                                        ?.toString() ??
                                                    'flagged',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors.warning,
                                                ),
                                              ),
                                            ],
                                            const Spacer(),
                                            if (active) ...[
                                              IconButton(
                                                tooltip: 'Delete tooth',
                                                onPressed: onDeleteTooth,
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 20,
                                                  color: AppColors.danger,
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                  minWidth: 36,
                                                  minHeight: 36,
                                                ),
                                              ),
                                              const Text(
                                                'Selected',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.dentalBlue,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            for (final zName
                                                in kShadeZones) ...[
                                              if (zName != kShadeZones.first)
                                                const SizedBox(width: 6),
                                              Expanded(
                                                child: MiniZoneChip(
                                                  label:
                                                      capitalizeZone(zName),
                                                  shade: () {
                                                    final focusedZone =
                                                        active &&
                                                            focusZone ==
                                                                zName;
                                                    if (focusedZone &&
                                                        pendingShade !=
                                                            null) {
                                                      return pendingShade;
                                                    }
                                                    return zoneEffective(
                                                      zoneOf(t, zName),
                                                    );
                                                  }(),
                                                  overridden: zoneOverridden(
                                                    zoneOf(t, zName),
                                                  ),
                                                  pending: active &&
                                                      focusZone == zName &&
                                                      pendingShade != null,
                                                  focused: active &&
                                                      focusZone == zName,
                                                  swatch: swatch,
                                                  onTap: () {
                                                    onSelectTooth(
                                                      idx,
                                                      zone: zName,
                                                    );
                                                  },
                                                  onOverride: () {
                                                    onBeginZoneOverride(
                                                      idx,
                                                      zName,
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: detected == '—'
                                ? AppColors.neo
                                : AppColors.aiPurpleSoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: detected == '—'
                                  ? AppColors.border
                                  : AppColors.aiPurple.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.border),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: detected == '—'
                                    ? const ColoredBox(
                                        color: AppColors.border,
                                        child: Icon(
                                          Icons.image_search_outlined,
                                          color: AppColors.muted,
                                          size: 26,
                                        ),
                                      )
                                    : shadeEnamelFill(detected),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      detected == '—'
                                          ? 'No detection yet'
                                          : detected,
                                      style: TextStyle(
                                        fontSize: detected == '—' ? 18 : 28,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navy,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      confidence > 0
                                          ? '${(confidence * 100).round()}% match · $focusZone'
                                          : 'Upload a photo to analyze',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (confidence > 0) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: confidence.clamp(0, 1),
                              minHeight: 6,
                              backgroundColor: AppColors.border,
                              color: AppColors.aiPurple,
                            ),
                          ),
                        ],
                        if (pendingShade == null &&
                            selected != '—' &&
                            selected != detected) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warningSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Override selected: $selected',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                        if (finalShade != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Saved final: $finalShade',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                        if (overallTopMatches.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Top matches',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Across all teeth',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: overallTopMatches.take(5).map((m) {
                              final s = m['shade']?.toString() ?? '';
                              if (s.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              final active =
                                  selected == s && pendingShade == null;
                              final de = m['delta_e_2000'];
                              return SimilarShadeChip(
                                shade: s,
                                deltaE: de,
                                selected: active,
                                swatch: swatch,
                                onTap: () => onOverallShade(s),
                              );
                            }).toList(),
                          ),
                        ],
                        const Spacer(),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: saving || detected == '—'
                              ? null
                              : onAcceptAi,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            minimumSize: const Size.fromHeight(40),
                          ),
                          child: saving
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ToothLoadingIndicator(
                                      size: 18,
                                      compact: true,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 10),
                                    Text('Saving…'),
                                  ],
                                )
                              : Text(
                                  detected == '—'
                                      ? 'Accept AI'
                                      : 'Accept $detected',
                                ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: saving ? null : onSaveOverride,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                          ),
                          child: Text(
                            selected == '—' || selected == detected
                                ? 'Save override'
                                : 'Save override ($selected)',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Loupe mounts on drag start (setState); during drag only notifiers
        // move the focal / repaint the outline — Image.memory stays mounted.
        if (magnifierViewSize != null && previewBytes != null)
          Positioned.fill(
            child: ShadeOutlineLoupe(
              focalListenable: magnifierFocal,
              viewSize: magnifierViewSize!,
              previewBytes: previewBytes!,
              analysisImageSize: analysisImageSize,
              dragTick: dragTick,
              teeth: teeth,
              selectedToothIndex: selectedToothIndex,
              focusZone: focusZone,
              editOutline: editOutline,
              editBulges: editBulges,
              activeHandleIndex: activeHandleIndex,
              activeEdgeIndex: activeEdgeIndex,
            ),
          ),
      ],
    );
  }
}

class ShadeOutlineLoupe extends StatelessWidget {
  const ShadeOutlineLoupe({
    super.key,
    required this.focalListenable,
    required this.viewSize,
    required this.previewBytes,
    required this.analysisImageSize,
    required this.dragTick,
    required this.teeth,
    required this.selectedToothIndex,
    required this.focusZone,
    required this.editOutline,
    required this.editBulges,
    required this.activeHandleIndex,
    required this.activeEdgeIndex,
  });

  final ValueNotifier<Offset?> focalListenable;
  final Size viewSize;
  final Uint8List previewBytes;
  final Size analysisImageSize;
  final ValueNotifier<int> dragTick;
  final List<Map<String, dynamic>> teeth;
  final int? selectedToothIndex;
  final String focusZone;
  final List<List<double>>? editOutline;
  final List<double>? editBulges;
  final int? activeHandleIndex;
  final int? activeEdgeIndex;

  static const _mag = 2.6;

  @override
  Widget build(BuildContext context) {
    final imgSize =
        analysisImageSize == Size.zero ? viewSize : analysisImageSize;

    // Image + overlay built once as AnimatedBuilder child — no LayoutBuilder
    // (breaks under IntrinsicWidth from Material buttons in this column).
    final scene = SizedBox(
      width: viewSize.width,
      height: viewSize.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            previewBytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.none,
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: ToothOverlayPainter(
                repaint: dragTick,
                teeth: teeth,
                selectedToothIndex: selectedToothIndex,
                imageSize: imgSize,
                focusZone: focusZone,
                editMode: true,
                editOutline: editOutline,
                editBulges: editBulges,
                activeHandleIndex: activeHandleIndex,
                activeEdgeIndex: activeEdgeIndex,
                paintSelectedOnlyWhileDragging: true,
              ),
            ),
          ),
        ],
      ),
    );

    return SectionCard(
      depth: 0,
      boxShadow: kShadeCardGlow,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadii.border,
        child: ColoredBox(
          color: const Color(0xFF15263F),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: AnimatedBuilder(
                  animation: focalListenable,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: scene,
                  ),
                  builder: (context, child) {
                    final focal = focalListenable.value;
                    if (focal == null) return const SizedBox.shrink();
                    return CustomSingleChildLayout(
                      delegate: _LoupePanDelegate(
                        focal: focal,
                        viewSize: viewSize,
                        mag: _mag,
                      ),
                      child: SizedBox(
                        width: viewSize.width * _mag,
                        height: viewSize.height * _mag,
                        child: child,
                      ),
                    );
                  },
                ),
              ),
              const IgnorePointer(
                child: Center(
                  child: Icon(
                    Icons.add,
                    size: 22,
                    color: Colors.white70,
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Edge view',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pans the magnified scene so [focal] sits at the loupe center.
class _LoupePanDelegate extends SingleChildLayoutDelegate {
  _LoupePanDelegate({
    required this.focal,
    required this.viewSize,
    required this.mag,
  });

  final Offset focal;
  final Size viewSize;
  final double mag;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.tight(
      Size(viewSize.width * mag, viewSize.height * mag),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return Offset(
      size.width / 2 - focal.dx * mag,
      size.height / 2 - focal.dy * mag,
    );
  }

  @override
  bool shouldRelayout(covariant _LoupePanDelegate oldDelegate) {
    return oldDelegate.focal != focal ||
        oldDelegate.viewSize != viewSize ||
        oldDelegate.mag != mag;
  }
}

class MiniZoneChip extends StatelessWidget {
  const MiniZoneChip({
    super.key,
    required this.label,
    required this.shade,
    required this.overridden,
    required this.focused,
    required this.swatch,
    required this.onTap,
    required this.onOverride,
    this.pending = false,
  });

  final String label;
  final String? shade;
  final bool overridden;
  final bool pending;
  final bool focused;
  final Color Function(String) swatch;
  final VoidCallback onTap;
  final VoidCallback onOverride;

  @override
  Widget build(BuildContext context) {
    final swatchBox = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 18,
        width: double.infinity,
        child: shade == null
            ? const ColoredBox(color: AppColors.border)
            : shadeEnamelFill(shade!),
      ),
    );

    final borderColor = pending
        ? AppColors.warning
        : (overridden
            ? AppColors.warning
            : (focused ? AppColors.dentalBlue : AppColors.border));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.neo,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: focused || overridden || pending ? 1.5 : 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: focused ? 0.35 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (focused)
                      ImageFiltered(
                        imageFilter:
                            ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
                        child: swatchBox,
                      )
                    else
                      swatchBox,
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      shade ?? '—',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: (overridden || pending)
                            ? AppColors.warning
                            : AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              if (focused)
                Positioned.fill(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 72,
                        maxHeight: 28,
                      ),
                      child: Material(
                        color: AppColors.navy.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(7),
                        child: InkWell(
                          onTap: onOverride,
                          borderRadius: BorderRadius.circular(7),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            child: Text(
                              'Override',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

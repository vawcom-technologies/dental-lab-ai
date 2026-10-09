import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'fdi_tooth_chart.dart';
import 'shade_override_pane.dart' show SimilarShadeChip;
import 'shade_shared.dart';
import 'tooth_overlay.dart';
import '../../core/l10n/app_localizations.dart';

class ShadeResultPane extends StatefulWidget {
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
    this.gum,
    this.pendingGumShade,
    required this.saving,
    required this.swatch,
    required this.zoneEffective,
    required this.zoneOf,
    required this.zoneOverridden,
    required this.onSelectTooth,
    required this.onDeleteTooth,
    required this.onBeginZoneOverride,
    this.onSelectGum,
    this.onBeginGumOverride,
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
    this.portrait = false,
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
  final Map<String, dynamic>? gum;
  final String? pendingGumShade;
  final bool saving;
  final Color Function(String) swatch;
  final String? Function(Map<String, dynamic>?) zoneEffective;
  final Map<String, dynamic>? Function(Map<String, dynamic>, String) zoneOf;
  final bool Function(Map<String, dynamic>?) zoneOverridden;
  final void Function(int index, {String? zone}) onSelectTooth;
  final VoidCallback onDeleteTooth;
  final void Function(int index, String zone) onBeginZoneOverride;

  /// Switch Manual Override to the gum tab (card tap). Distinct from Override.
  final VoidCallback? onSelectGum;
  final VoidCallback? onBeginGumOverride;
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

  /// Portrait: content-sized card (tooth grid + detail) under the action bar.
  final bool portrait;

  @override
  State<ShadeResultPane> createState() => _ShadeResultPaneState();
}

class _ShadeResultPaneState extends State<ShadeResultPane> {
  /// 0 = Results, 1 = Tooth Selection (local UI only; selection is parent state).
  int _tab = 0;
  final _openArch = <String>{'upper', 'lower'};
  final _openTooth = <int>{};

  @override
  void initState() {
    super.initState();
    final sel = widget.selectedToothIndex;
    if (sel != null) _openTooth.add(sel);
  }

  @override
  void didUpdateWidget(covariant ShadeResultPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sel = widget.selectedToothIndex;
    if (sel != null && sel != oldWidget.selectedToothIndex) {
      _openTooth.add(sel);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.portrait) return _buildPortrait(context);
    final loc = AppLocalizations.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        SectionCard(
          depth: 0,
          color: Colors.white,
          boxShadow: kShadeCardGlow,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text(loc.shadeResult),
                    icon: const Icon(Icons.palette_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(loc.shadeToothSelection),
                    icon: const Icon(Icons.grid_view_rounded, size: 16),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                    Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _tab == 0
                    ? _buildResultsScroll(context)
                    : FdiToothChart(
                        teeth: widget.teeth,
                        selectedToothIndex: widget.selectedToothIndex,
                        onSelectTooth: (index) => widget.onSelectTooth(index),
                      ),
              ),
            ],
          ),
        ),
        if (_tab == 0 &&
            widget.magnifierViewSize != null &&
            widget.previewBytes != null)
          Positioned.fill(
            child: ShadeOutlineLoupe(
              focalListenable: widget.magnifierFocal,
              viewSize: widget.magnifierViewSize!,
              previewBytes: widget.previewBytes!,
              analysisImageSize: widget.analysisImageSize,
              dragTick: widget.dragTick,
              teeth: widget.teeth,
              selectedToothIndex: widget.selectedToothIndex,
              focusZone: widget.focusZone,
              editOutline: widget.editOutline,
              editBulges: widget.editBulges,
              activeHandleIndex: widget.activeHandleIndex,
              activeEdgeIndex: widget.activeEdgeIndex,
            ),
          ),
      ],
    );
  }

  // ── Portrait layout ──────────────────────────────────────────────────────

  Widget _buildPortrait(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SectionCard(
      depth: 0,
      color: Colors.white,
      boxShadow: kShadeCardGlow,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text(loc.shadeResult)),
                  ButtonSegment(value: 1, label: Text(loc.shadeToothSelection)),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              if (widget.gum != null) _portraitGumChip(context),
            ],
          ),
          const SizedBox(height: 16),
          if (_tab == 1)
            SizedBox(
              height: 320,
              child: FdiToothChart(
                teeth: widget.teeth,
                selectedToothIndex: widget.selectedToothIndex,
                onSelectTooth: (index) => widget.onSelectTooth(index),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final grid = _portraitToothGrid(context);
                final detail = _portraitToothDetail(context);
                // Phones: grid above detail; tablets: side by side.
                if (c.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [grid, const SizedBox(height: 16), detail],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 115, child: grid),
                    const SizedBox(width: 18),
                    Expanded(flex: 100, child: detail),
                  ],
                );
              },
            ),
          const SizedBox(height: 16),
          _portraitSaveRow(context),
        ],
      ),
    );
  }

  Widget _portraitGumChip(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final gum = widget.gum!;
    final pending = widget.pendingGumShade;
    final shade = pending ?? gumEffectiveShade(gum);
    final conf = (gum['confidence'] as num?)?.toDouble() ?? 0;
    return Material(
      color: _gumRoseSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _gumRose.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: widget.onSelectGum,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: pending != null
                      ? gingivaSwatch(pending)
                      : gumSampledColor(gum),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                loc.shadeGumShade,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(width: 10),
              Text(
                shade ?? '—',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              if (conf > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '${(conf * 100).round()}%',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
              if (widget.onBeginGumOverride != null) ...[
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: widget.onBeginGumOverride,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(loc.shadeOverride),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Teeth in snake order (upper left→right, lower right→left) for ‹ ›.
  List<int> _portraitOrder(Map<int, int> fdiMap) => [
    for (final f in kUpperFdiSelectableLtr)
      if (fdiMap.containsKey(f)) fdiMap[f]!,
    for (final f in kLowerFdiSelectableLtr.reversed)
      if (fdiMap.containsKey(f)) fdiMap[f]!,
  ];

  Map<String, dynamic>? _toothByIndex(int? idx) {
    if (idx == null) return null;
    for (final t in widget.teeth) {
      if ((t['tooth_index'] as num?)?.toInt() == idx) return t;
    }
    return null;
  }

  Widget _portraitToothGrid(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final fdiMap = mapFdiToToothIndex(widget.teeth);
    const capStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: .6,
      color: AppColors.muted,
    );
    const line = Color(0xFFC9D4E5);

    Widget chip(int fdi, {required bool upper}) {
      final idx = fdiMap[fdi]!;
      final t = _toothByIndex(idx);
      final active = widget.selectedToothIndex == idx;
      final shade = t == null
          ? null
          : _zoneShadeForTooth(t, zone: 'middle', active: active);
      const big = Radius.circular(12);
      const small = Radius.circular(8);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: shade == null ? AppColors.neo : widget.swatch(shade),
            elevation: active ? 3 : 0,
            shadowColor: AppColors.navy.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: upper
                  ? const BorderRadius.vertical(top: big, bottom: small)
                  : const BorderRadius.vertical(top: small, bottom: big),
              side: BorderSide(
                color: active ? AppColors.navy : const Color(0xFFD9CFAE),
                width: active ? 3 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => widget.onSelectTooth(idx),
              child: SizedBox(
                height: 66,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$fdi',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        shade ?? '—',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5D4C22),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget arch(List<int> ltr, {required bool upper}) {
      final present = [
        for (final f in ltr)
          if (fdiMap.containsKey(f)) f,
      ];
      final right = [
        for (final f in present)
          if (f % 40 < 20) f,
      ];
      final left = [
        for (final f in present)
          if (f % 40 >= 20) f,
      ];
      return Row(
        crossAxisAlignment: upper
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [for (final f in right) chip(f, upper: upper)],
            ),
          ),
          Container(width: 2, height: 66, color: line),
          Expanded(
            child: Row(children: [for (final f in left) chip(f, upper: upper)]),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: fdiMap.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                loc.shadeUploadToAnalyze,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.smileUpperJaw.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: capStyle,
                ),
                const SizedBox(height: 8),
                arch(kUpperFdiSelectableLtr, upper: true),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  color: line,
                ),
                arch(kLowerFdiSelectableLtr, upper: false),
                const SizedBox(height: 8),
                Text(
                  loc.smileLowerJaw.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: capStyle,
                ),
              ],
            ),
    );
  }

  Widget _portraitToothDetail(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final order = _portraitOrder(mapFdiToToothIndex(widget.teeth));
    final idx = widget.selectedToothIndex;
    final t = _toothByIndex(idx);

    void step(int d) {
      if (order.isEmpty) return;
      final i = idx == null ? -1 : order.indexOf(idx);
      final n = i < 0 ? 0 : (i + d + order.length) % order.length;
      widget.onSelectTooth(order[n]);
    }

    Widget navBtn(IconData icon, int d) => SizedBox(
      width: 44,
      height: 44,
      child: OutlinedButton(
        onPressed: order.isEmpty ? null : () => step(d),
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: const BorderSide(color: Color(0xFFD5DDE9)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Icon(icon, color: AppColors.navy),
      ),
    );

    final zoneShades = t == null
        ? const <String, String?>{}
        : {
            for (final z in kShadeZones)
              z: _zoneShadeForTooth(t, zone: z, active: true),
          };
    final overall = zoneShades['middle'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            navBtn(Icons.chevron_left_rounded, -1),
            Expanded(
              child: Column(
                children: [
                  if (t != null)
                    Text(
                      _isLowerArch(t) ? loc.smileLowerJaw : loc.smileUpperJaw,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  Text(
                    t == null ? '—' : toothDisplayLabel(t),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
            navBtn(Icons.chevron_right_rounded, 1),
          ],
        ),
        const SizedBox(height: 12),
        if (t != null)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: overall == null
                        ? AppColors.neo
                        : widget.swatch(overall),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    overall ?? '—',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3F3214),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      for (final z in kShadeZones) ...[
                        if (z != kShadeZones.first) const SizedBox(height: 6),
                        _portraitZoneRow(t, idx!, z, zoneShades[z]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _portraitZoneRow(
    Map<String, dynamic> t,
    int idx,
    String zone,
    String? shade,
  ) {
    final focused = widget.focusZone == zone;
    final overridden = widget.zoneOverridden(widget.zoneOf(t, zone));
    return Material(
      color: focused ? const Color(0xFFE4EBF6) : const Color(0xFFF6F8FB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: focused ? AppColors.dentalBlue : const Color(0xFFE3E8F0),
          width: focused ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => widget.onSelectTooth(idx, zone: zone),
        onLongPress: () => widget.onBeginZoneOverride(idx, zone),
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    capitalizeZone(zone),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                if (overridden)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.edit, size: 14, color: AppColors.warning),
                  ),
                Container(
                  constraints: const BoxConstraints(minWidth: 40),
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: shade == null
                        ? AppColors.border
                        : widget.swatch(shade),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    shade ?? '—',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3F3214),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Same accept / save actions as the landscape results list.
  Widget _portraitSaveRow(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final detected = widget.detected;
    final selected = widget.selected;
    final saving = widget.saving;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: saving ? null : widget.onSaveOverride,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(
              selected == '—' || selected == detected
                  ? loc.shadeSaveOverride
                  : loc.shadeSaveOverrideShade(selected),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: saving || detected == '—' ? null : widget.onAcceptAi,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              minimumSize: const Size.fromHeight(44),
            ),
            child: saving
                ? const ToothLoadingIndicator(
                    size: 18,
                    compact: true,
                    color: Colors.white,
                  )
                : Text(
                    detected == '—'
                        ? loc.shadeAcceptAi
                        : loc.shadeAcceptShade(detected),
                  ),
          ),
        ),
      ],
    );
  }

  bool _isLowerArch(Map<String, dynamic> tooth) {
    final arch = tooth['arch']?.toString();
    if (arch == 'lower') return true;
    if (arch == 'upper') return false;
    final fdi = (tooth['fdi'] as num?)?.toInt();
    return fdi != null && fdi >= 31 && fdi <= 48;
  }

  Widget _archHeader(String id, String label) {
    final open = _openArch.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.neo,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            setState(() {
              if (open) {
                _openArch.remove(id);
              } else {
                _openArch.add(id);
              }
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                Icon(
                  open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.navy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _jawAccordion(
    BuildContext context,
    List<Map<String, dynamic>> teeth,
  ) {
    final loc = AppLocalizations.of(context);
    final upper = <Map<String, dynamic>>[];
    final lower = <Map<String, dynamic>>[];
    for (final t in teeth) {
      if (_isLowerArch(t)) {
        lower.add(t);
      } else {
        upper.add(t);
      }
    }
    return [
      if (upper.isNotEmpty) ...[
        _archHeader('upper', loc.smileUpperJaw),
        if (_openArch.contains('upper'))
          for (final t in upper) _toothCard(context, t),
      ],
      if (lower.isNotEmpty) ...[
        _archHeader('lower', loc.smileLowerJaw),
        if (_openArch.contains('lower'))
          for (final t in lower) _toothCard(context, t),
      ],
    ];
  }

  String? _zoneShadeForTooth(
    Map<String, dynamic> t, {
    required String zone,
    required bool active,
  }) {
    if (active && widget.focusZone == zone && widget.pendingShade != null) {
      return widget.pendingShade;
    }
    return widget.zoneEffective(widget.zoneOf(t, zone));
  }

  Widget _toothCard(BuildContext context, Map<String, dynamic> t) {
    final idx = (t['tooth_index'] as num).toInt();
    final rejected = t['rejected'] == true;
    final active = widget.selectedToothIndex == idx;
    final open = _openTooth.contains(idx);
    final label = toothDisplayLabel(t);
    final focusZone = widget.focusZone;
    final pendingShade = widget.pendingShade;
    final zoneShades = {
      for (final z in kShadeZones)
        z: _zoneShadeForTooth(t, zone: z, active: active),
    };
    final summaryShade =
        zoneShades['middle'] ?? zoneShades['cervical'] ?? zoneShades['incisal'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active
              ? AppColors.dentalBlue.withValues(alpha: 0.12)
              : AppColors.neo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? AppColors.dentalBlue : AppColors.border,
            width: active ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () {
                setState(() => _openTooth.add(idx));
                widget.onSelectTooth(idx);
              },
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                child: Row(
                  children: [
                    if (!open) ...[
                      _CollapsedShadePreview(
                        shade: summaryShade,
                        zoneShades: zoneShades,
                        swatch: widget.swatch,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          if (!open && summaryShade != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              [
                                for (final z in kShadeZones)
                                  if (zoneShades[z] != null)
                                    '${capitalizeZone(z)[0]} ${zoneShades[z]}',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (rejected)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          t['reject_reason']?.toString() ?? 'flagged',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    if (active) ...[
                      IconButton(
                        tooltip: AppLocalizations.of(context).shadeDeleteTooth,
                        onPressed: widget.onDeleteTooth,
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppColors.danger,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context).shadeSelected,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dentalBlue,
                        ),
                      ),
                    ],
                    IconButton(
                      tooltip: open
                          ? AppLocalizations.of(context).smileModelOpen
                          : AppLocalizations.of(context).smileModelClosed,
                      onPressed: () {
                        setState(() {
                          if (open) {
                            _openTooth.remove(idx);
                          } else {
                            _openTooth.add(idx);
                          }
                        });
                      },
                      icon: Icon(
                        open
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.navy,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: open
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: Row(
                          children: [
                            for (final zName in kShadeZones) ...[
                              if (zName != kShadeZones.first)
                                const SizedBox(width: 6),
                              Expanded(
                                child: MiniZoneChip(
                                  label: capitalizeZone(zName),
                                  shade: zoneShades[zName],
                                  sampleColor: () {
                                    final code = zoneShades[zName];
                                    if (code == null || code.isEmpty) {
                                      return AppColors.border;
                                    }
                                    return widget.swatch(code);
                                  }(),
                                  overridden: widget.zoneOverridden(
                                    widget.zoneOf(t, zName),
                                  ),
                                  pending:
                                      active &&
                                      focusZone == zName &&
                                      pendingShade != null,
                                  focused: active && focusZone == zName,
                                  onTap: () {
                                    widget.onSelectTooth(idx, zone: zName);
                                  },
                                  onOverride: () {
                                    widget.onBeginZoneOverride(idx, zName);
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsScroll(BuildContext context) {
    final teeth = widget.teeth;
    final focusZone = widget.focusZone;
    final pendingShade = widget.pendingShade;
    final detected = widget.detected;
    final confidence = widget.confidence;
    final selected = widget.selected;
    final finalShade = widget.finalShade;
    final overallTopMatches = widget.overallTopMatches;
    final saving = widget.saving;
    final swatch = widget.swatch;
    final onOverallShade = widget.onOverallShade;
    final onAcceptAi = widget.onAcceptAi;
    final onSaveOverride = widget.onSaveOverride;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          primary: false,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.gum != null ||
                  teeth.isNotEmpty ||
                  detected != '—') ...[
                GumShadeCard(
                  gum: widget.gum,
                  pendingShade: widget.pendingGumShade,
                  onTap: widget.onSelectGum,
                  onOverride: widget.onBeginGumOverride,
                ),
                const SizedBox(height: 10),
              ],
              if (teeth.isNotEmpty) ..._jawAccordion(context, teeth),
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
                          : ColoredBox(color: swatch(detected)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detected == '—'
                                ? AppLocalizations.of(
                                    context,
                                  ).shadeNoDetectionYet
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
                                ? '${(confidence * 100).round()}% ${AppLocalizations.of(context).tr('sh.match')} · $focusZone'
                                : AppLocalizations.of(
                                    context,
                                  ).shadeUploadToAnalyze,
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
                    AppLocalizations.of(
                      context,
                    ).shadeOverrideSelected(selected),
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
                  AppLocalizations.of(
                    context,
                  ).trp('sh.savedFinal', {'s': finalShade}),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ],
              if (overallTopMatches.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).shadeSimilarShades,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).shadeAcrossAllTeeth,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
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
                    final active = selected == s && pendingShade == null;
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
              const SizedBox(height: 14),
              FilledButton(
                onPressed: saving || detected == '—' ? null : onAcceptAi,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  minimumSize: const Size.fromHeight(40),
                ),
                child: saving
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ToothLoadingIndicator(
                            size: 18,
                            compact: true,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Text(AppLocalizations.of(context).saving),
                        ],
                      )
                    : Text(
                        detected == '—'
                            ? AppLocalizations.of(context).shadeAcceptAi
                            : AppLocalizations.of(
                                context,
                              ).shadeAcceptShade(detected),
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
                      ? AppLocalizations.of(context).shadeSaveOverride
                      : AppLocalizations.of(
                          context,
                        ).shadeSaveOverrideShade(selected),
                ),
              ),
            ],
          ),
        );
      },
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
    final imgSize = analysisImageSize == Size.zero
        ? viewSize
        : analysisImageSize;

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
            filterQuality: FilterQuality.high,
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
                  child: FittedBox(fit: BoxFit.fill, child: scene),
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
                  child: Icon(Icons.add, size: 22, color: Colors.white70),
                ),
              ),
              Positioned(
                left: 12,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    AppLocalizations.of(context).tr('sh.edgeView'),
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
    required this.sampleColor,
    required this.overridden,
    required this.focused,
    required this.onTap,
    required this.onOverride,
    this.pending = false,
  });

  final String label;
  final String? shade;
  final Color sampleColor;
  final bool overridden;
  final bool pending;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onOverride;

  @override
  Widget build(BuildContext context) {
    final borderColor = pending
        ? AppColors.warning
        : (overridden
              ? AppColors.warning
              : (focused ? AppColors.dentalBlue : AppColors.border));
    final hasShade = shade != null && shade!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          decoration: BoxDecoration(
            color: AppColors.neo,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: focused || overridden || pending ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 40,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: hasShade ? sampleColor : AppColors.border,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
              ),
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
              if (focused) ...[
                const SizedBox(height: 6),
                Material(
                  color: AppColors.navy.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    onTap: onOverride,
                    borderRadius: BorderRadius.circular(7),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Text(
                        AppLocalizations.of(context).shadeOverride,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsedShadePreview extends StatelessWidget {
  const _CollapsedShadePreview({
    required this.shade,
    required this.zoneShades,
    required this.swatch,
  });

  final String? shade;
  final Map<String, String?> zoneShades;
  final Color Function(String) swatch;

  @override
  Widget build(BuildContext context) {
    final has = shade != null && shade!.isNotEmpty;
    final middleColor = has ? swatch(shade!) : AppColors.border;
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 36,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: middleColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              has ? shade! : '—',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final z in kShadeZones) ...[
                if (z != kShadeZones.first) const SizedBox(width: 3),
                Expanded(
                  child: Tooltip(
                    message: zoneShades[z] == null
                        ? capitalizeZone(z)
                        : '${capitalizeZone(z)} · ${zoneShades[z]}',
                    child: Container(
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: zoneShades[z] == null
                            ? AppColors.border
                            : swatch(zoneShades[z]!),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        zoneShades[z] ?? '—',
                        style: TextStyle(
                          fontSize:
                              zoneShades[z] != null && zoneShades[z]!.length > 2
                              ? 6.5
                              : 8,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

const _gumRose = Color(0xFFC97B8A);
const _gumRoseSoft = Color(0xFFFCEEEF);

class GumShadeCard extends StatelessWidget {
  const GumShadeCard({
    super.key,
    this.gum,
    this.pendingShade,
    this.onTap,
    this.onOverride,
  });

  final Map<String, dynamic>? gum;
  final String? pendingShade;
  final VoidCallback? onTap;
  final VoidCallback? onOverride;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final pending = pendingShade != null && pendingShade!.isNotEmpty;
    final overridden = gumIsOverridden(gum);
    final detected = gumDetectedShade(gum);
    final effective = pendingShade ?? gumEffectiveShade(gum);
    final hasShade = effective != null && effective.isNotEmpty;
    final conf = (gum?['confidence'] as num?)?.toDouble() ?? 0;
    final sample = gum == null
        ? AppColors.border
        : (pending ? gingivaSwatch(pendingShade!) : gumSampledColor(gum!));
    final accent = pending || overridden ? AppColors.warning : _gumRose;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _gumRoseSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accent.withValues(
                alpha: pending || overridden ? 0.9 : 0.45,
              ),
              width: pending || overridden ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: sample,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: hasShade
                    ? null
                    : const Icon(
                        Icons.health_and_safety_outlined,
                        color: AppColors.muted,
                        size: 26,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.shadeGumShade,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasShade ? effective : loc.shadeNoGumDetected,
                      style: TextStyle(
                        fontSize: hasShade ? 28 : 16,
                        fontWeight: FontWeight.w800,
                        color: pending || overridden
                            ? AppColors.warning
                            : AppColors.navy,
                        height: 1.1,
                      ),
                    ),
                    if (pending ||
                        (overridden && detected != null) ||
                        (hasShade && conf > 0)) ...[
                      const SizedBox(height: 2),
                      Text(
                        pending
                            ? loc.shadeOverrideSelected(pendingShade!)
                            : (overridden && detected != null
                                  ? '${loc.shadeOverride} · $detected → $effective'
                                  : '${(conf * 100).round()}% ${AppLocalizations.of(context).tr('sh.match')}'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onOverride != null) ...[
                const SizedBox(width: 8),
                Material(
                  color: AppColors.navy.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    onTap: onOverride,
                    borderRadius: BorderRadius.circular(7),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Text(
                        loc.shadeOverride,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

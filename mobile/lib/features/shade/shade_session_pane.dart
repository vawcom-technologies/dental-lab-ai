import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/touchable.dart';
import '../../core/widgets/ui_kit.dart';
import 'shade_shared.dart';

class ShadeSessionPane extends StatelessWidget {
  const ShadeSessionPane({
    super.key,
    required this.collapsed,
    required this.history,
    required this.activeSessionKey,
    required this.swatch,
    required this.onCollapseChanged,
    required this.onOpen,
    required this.onDelete,
  });

  final bool collapsed;
  final List<Map<String, dynamic>> history;
  final String? activeSessionKey;
  final Color Function(String) swatch;
  final ValueChanged<bool> onCollapseChanged;
  final ValueChanged<int> onOpen;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final sessionWidth = collapsed ? 52.0 : (wide ? 300.0 : 252.0);
    return AnimatedContainer(
      duration: AppMotion.page,
      curve: AppMotion.spring,
      width: sessionWidth,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: sessionWidth,
          maxWidth: sessionWidth,
          child: GestureDetector(
            key: const ValueKey('session-panel'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (!collapsed && v > 250) {
                onCollapseChanged(true);
              } else if (collapsed && v < -250) {
                onCollapseChanged(false);
              }
            },
            child: SectionCard(
              depth: 0,
              boxShadow: kShadeCardGlow,
              padding: collapsed
                  ? EdgeInsets.zero
                  : const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: collapsed
                  ? Center(
                      child: AppButtons.icon(
                        onPressed: () => onCollapseChanged(false),
                        tooltip: 'Open session',
                        icon: Icons.chevron_left_rounded,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Session',
                                    style: AppFonts.style(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                      color: AppColors.navy,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Saved shades · tap to edit',
                                    style: AppFonts.style(
                                      color: AppColors.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AppButtons.icon(
                              onPressed: () => onCollapseChanged(true),
                              tooltip: 'Close session',
                              icon: Icons.chevron_right_rounded,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: history.isEmpty
                              ? Center(
                                  child: Text(
                                    'No saves yet',
                                    textAlign: TextAlign.center,
                                    style: AppFonts.style(
                                      color: AppColors.muted,
                                      fontSize: 14,
                                    ),
                                  ),
                                )
                              : ScrollConfiguration(
                                  behavior: const EliteScrollBehavior(),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    itemCount: history.length,
                                    itemBuilder: (context, i) {
                                      final h = history[i];
                                      final teethRaw = h['teeth'];
                                      final toothSummaries =
                                          <Map<String, dynamic>>[];
                                      if (teethRaw is List) {
                                        for (final t in teethRaw) {
                                          if (t is Map) {
                                            toothSummaries.add(
                                              Map<String, dynamic>.from(t),
                                            );
                                          }
                                        }
                                      }
                                      final sessionKey =
                                          '${h['session_key'] ?? h['case_id'] ?? i}';
                                      final shade =
                                          '${h['shade'] ?? '—'}';
                                      return SessionRecent(
                                        key: ValueKey('session-$sessionKey'),
                                        name: h['name'] as String? ?? 'Patient',
                                        shade: shade,
                                        conf: (h['conf'] as num?)?.toDouble() ??
                                            0,
                                        color: swatch(shade),
                                        isOverride: h['override'] == true,
                                        selected: activeSessionKey != null &&
                                            sessionKey == activeSessionKey,
                                        teeth: toothSummaries,
                                        swatch: swatch,
                                        onOpen: () => onOpen(i),
                                        onDelete: () => onDelete(i),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class SessionRecent extends StatefulWidget {
  const SessionRecent({
    super.key,
    required this.name,
    required this.shade,
    required this.conf,
    required this.color,
    required this.onOpen,
    required this.onDelete,
    required this.swatch,
    this.teeth = const [],
    this.isOverride = false,
    this.selected = false,
  });

  final String name;
  final String shade;
  final double conf;
  final Color color;
  final bool isOverride;
  final bool selected;
  final List<Map<String, dynamic>> teeth;
  final Color Function(String) swatch;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<SessionRecent> createState() => _SessionRecentState();
}

class _SessionRecentState extends State<SessionRecent> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final teeth = widget.teeth;
    final countLabel = teeth.isEmpty
        ? null
        : (teeth.length == 1 ? '1 tooth' : '${teeth.length} teeth');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.spring,
        decoration: BoxDecoration(
          color: widget.selected
              ? Colors.white.withValues(alpha: 0.95)
              : AppColors.neo,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.selected
                ? AppColors.dentalBlue
                : AppColors.border.withValues(alpha: 0.7),
            width: widget.selected ? 2 : 1,
          ),
          boxShadow: widget.selected
              ? NeoShadows.soft(depth: 0.55)
              : NeoShadows.soft(depth: 0.3),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Touchable(
                      onTap: widget.onOpen,
                      selectionHaptic: true,
                      borderRadius: BorderRadius.circular(12),
                      minHeight: 56,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: widget.color,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              widget.shade,
                              style: AppFonts.style(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.style(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: AppColors.navy,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    widget.shade,
                                    ?countLabel,
                                    if (widget.isOverride) 'Override',
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.style(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AppButtons.icon(
                    onPressed: widget.onDelete,
                    tooltip: 'Remove from session',
                    icon: Icons.close_rounded,
                    color: AppColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Touchable(
                      onTap: widget.onOpen,
                      selectionHaptic: true,
                      borderRadius: BorderRadius.circular(10),
                      minHeight: 44,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.selected ? 'Editing now' : 'Tap to edit',
                          style: AppFonts.style(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: widget.selected
                                ? AppColors.dentalBlue
                                : AppColors.navy,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (countLabel != null)
                    Touchable(
                      onTap: () {
                        AppHaptics.selection();
                        setState(() => _expanded = !_expanded);
                      },
                      minHeight: 44,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Text(
                              _expanded ? 'Hide' : 'Teeth',
                              style: AppFonts.style(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                            Icon(
                              _expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 22,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              if (_expanded && teeth.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final t in teeth) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['label']?.toString() ??
                              'Tooth ${((t['tooth_index'] as num?)?.toInt() ?? 0) + 1}',
                          style: AppFonts.style(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final z in kShadeZones)
                              SessionZoneChip(
                                zone: z[0].toUpperCase(),
                                shade: (t['zones'] is Map)
                                    ? (t['zones'] as Map)[z]?.toString()
                                    : null,
                                swatch: widget.swatch,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ] else if (teeth.isEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: widget.conf.clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    color: AppColors.aiPurple,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.conf > 0
                      ? '${(widget.conf * 100).round()}% confidence'
                      : 'Manual selection',
                  style: AppFonts.style(
                    fontSize: 12,
                    color: AppColors.muted,
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

class SessionZoneChip extends StatelessWidget {
  const SessionZoneChip({
    super.key,
    required this.zone,
    required this.shade,
    required this.swatch,
  });

  final String zone;
  final String? shade;
  final Color Function(String) swatch;

  @override
  Widget build(BuildContext context) {
    final has = shade != null && shade!.isNotEmpty && shade != '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: has ? swatch(shade!).withValues(alpha: 0.55) : AppColors.border,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$zone ${has ? shade : '—'}',
        style: AppFonts.style(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

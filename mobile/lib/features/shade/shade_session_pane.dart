import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import 'shade_shared.dart';

class ShadeSessionPane extends StatelessWidget {
  const ShadeSessionPane({
    super.key,
    required this.collapsed,
    required this.history,
    required this.activeCaseId,
    required this.swatch,
    required this.onCollapseChanged,
    required this.onOpen,
    required this.onDelete,
  });

  final bool collapsed;
  final List<Map<String, dynamic>> history;
  final int? activeCaseId;
  final Color Function(String) swatch;
  final ValueChanged<bool> onCollapseChanged;
  final ValueChanged<int> onOpen;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final sessionWidth = collapsed
        ? 52.0
        : (MediaQuery.sizeOf(context).width < 900 ? 160.0 : 200.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: sessionWidth,
      // Lay the panel out at its target width while the width
      // animates, otherwise the header Row overflows mid-tween.
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
                  : const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
              child: collapsed
                  ? Center(
                      child: IconButton(
                        onPressed: () => onCollapseChanged(false),
                        tooltip: 'Open session panel',
                        icon: const Icon(Icons.chevron_left_rounded),
                        color: AppColors.muted,
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Tooltip(
                          message: 'Close session panel',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => onCollapseChanged(true),
                              borderRadius: BorderRadius.circular(10),
                              child: const SizedBox(
                                width: 28,
                                child: Center(
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Session',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const Text(
                                'Saves this visit',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: history.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No saves yet',
                                          style: TextStyle(
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
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
                                          final caseKey =
                                              (h['case_id'] as num?)?.toInt() ??
                                                  i;
                                          final active =
                                              activeCaseId == caseKey;
                                          return SessionRecent(
                                            key: ValueKey('session-$caseKey'),
                                            name: h['name'] as String? ??
                                                'Patient',
                                            shade: h['shade'] as String,
                                            conf: (h['conf'] as num?)
                                                    ?.toDouble() ??
                                                0,
                                            color: swatch(
                                              h['shade'] as String,
                                            ),
                                            isOverride: h['override'] == true,
                                            selected: active,
                                            teeth: toothSummaries,
                                            swatch: swatch,
                                            onOpen: () => onOpen(i),
                                            onDelete: () => onDelete(i),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 28),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
          decoration: BoxDecoration(
            color: AppColors.neo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.selected
                  ? AppColors.navy
                  : AppColors.border.withValues(alpha: 0.7),
              width: widget.selected ? 1.5 : 1,
            ),
            boxShadow: NeoShadows.soft(depth: 0.35),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        if (countLabel != null) ...[
                          const SizedBox(height: 2),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                setState(() => _expanded = !_expanded),
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    countLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _expanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 16,
                                  color: AppColors.muted,
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.selected ? 'Editing now' : 'Tap to edit',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: widget.selected
                                  ? AppColors.navy
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    widget.shade,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Tooltip(
                    message: 'Remove from session',
                    child: InkWell(
                      onTap: widget.onDelete,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (countLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.selected ? 'Editing now' : 'Tap to edit',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: widget.selected ? AppColors.navy : AppColors.muted,
                  ),
                ),
              ],
              if (widget.isOverride) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warningSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'OVERRIDE',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (_expanded && teeth.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final t in teeth) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['label']?.toString() ??
                              'Tooth ${((t['tooth_index'] as num?)?.toInt() ?? 0) + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
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
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: widget.conf.clamp(0, 1),
                    minHeight: 5,
                    backgroundColor: AppColors.border,
                    color: AppColors.aiPurple,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.conf > 0
                      ? '${(widget.conf * 100).round()}% confidence'
                      : 'Manual selection',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: has ? swatch(shade!).withValues(alpha: 0.55) : AppColors.border,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$zone ${has ? shade : '—'}',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

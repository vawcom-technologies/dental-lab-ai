import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'page_kit.dart';
import 'ui_kit.dart';

/// One row of a [SplitList]: a card in the list, and in full in the panel.
class SplitItem {
  const SplitItem({
    required this.id,
    required this.title,
    this.leading,
    this.badges = const [],
    this.lines = const [],
    this.details = const [],
    this.actions = const [],
    this.extras = const [],
    this.panelBody,
    this.cardBody,
    this.group,
    this.highlight = false,
  });

  final String id;
  final String title;
  final Widget Function(double size)? leading;
  final List<Widget> badges;

  /// Card subtitle lines.
  final List<String> lines;

  /// Panel facts, one per row with an icon.
  final List<(IconData, String)> details;

  /// Decisions (Accept, Reject…): on the card when narrow, in the panel when wide.
  final List<Widget> actions;

  /// Ways to reach someone (Open patient, Message), shown before [actions].
  final List<Widget> extras;

  /// Anything else the panel shows under the details (e.g. a lab's dentists).
  final Widget? panelBody;

  /// Shown under the card on narrow screens, where there's no panel.
  final Widget? cardBody;

  /// Section header in the list; consecutive items share one.
  final String? group;

  /// Needs attention: outlined in the list on narrow screens.
  final bool highlight;
}

/// Loads rows, lists them, and on wide screens shows the picked one in full
/// on the right (My Lab, Users & labs). Narrow screens keep the actions on
/// the cards.
class SplitList<T> extends StatefulWidget {
  const SplitList({
    super.key,
    required this.load,
    required this.item,
    required this.empty,
    this.active = true,
    this.filter,
    this.filteredEmpty,
    this.splitWidth = 860,
  });

  final Future<List<T>> Function() load;
  final SplitItem Function(T row, VoidCallback reload) item;
  final Widget empty;
  final bool active;

  /// Client-side search over the loaded rows; re-applied on every rebuild.
  final List<T> Function(List<T> rows)? filter;

  /// Shown when [filter] leaves nothing.
  final Widget? filteredEmpty;
  final double splitWidth;

  @override
  State<SplitList<T>> createState() => _SplitListState<T>();
}

class _SplitListState<T> extends State<SplitList<T>> {
  String? _picked;
  List<SplitItem> _items = const [];
  Object? _rowsSeen;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final split = box.maxWidth >= widget.splitWidth;
        final list = AdminFuture<List<T>>(
          active: widget.active,
          load: widget.load,
          empty: widget.empty,
          builder: (context, rows, reload) {
            final shown = widget.filter?.call(rows) ?? rows;
            final items = [for (final r in shown) widget.item(r, reload)];
            _items = items;
            // New data or a new filter: let the panel catch up next frame.
            final seen = (rows, shown.length);
            if (split && _rowsSeen != seen) {
              _rowsSeen = seen;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }
            if (items.isEmpty && widget.filteredEmpty != null) {
              return [SliverFillRemaining(hasScrollBody: false, child: widget.filteredEmpty!)];
            }
            Widget card(SplitItem it) {
              final row = AdminRow(
                leading: it.leading?.call(42),
                title: it.title,
                badges: it.badges,
                lines: it.lines,
                actions: split ? const [] : [...it.extras, ...it.actions],
              );
              return AdminCard(
                selected: split ? _picked == it.id : it.highlight,
                onTap: split ? () => setState(() => _picked = it.id) : null,
                child: !split && it.cardBody != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [row, const SizedBox(height: 10), it.cardBody!],
                      )
                    : row,
              );
            }
            final slivers = <Widget>[];
            String? group;
            var chunk = <SplitItem>[];
            void flush() {
              if (chunk.isEmpty) return;
              slivers.add(adminSliverList<SplitItem>(chunk, id: (it) => it.id, gap: 10, (context, it) => card(it)));
              chunk = [];
            }

            for (final it in items) {
              if (it.group != group) {
                flush();
                group = it.group;
                if (it.group case final g?) {
                  slivers.add(SliverToBoxAdapter(
                    child: Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 10), child: SectionLabel(g)),
                  ));
                }
              }
              chunk.add(it);
            }
            flush();
            return slivers;
          },
        );
        if (!split) return list;
        // After approve/reject/reload the selected row may be gone — clear the
        // right panel instead of keeping a stale detail card.
        final picked = _items.where((it) => it.id == _picked).firstOrNull;
        if (_picked != null && picked == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _picked != null && !_items.any((it) => it.id == _picked)) {
              setState(() => _picked = null);
            }
          });
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: list),
            const SizedBox(width: 16),
            Expanded(
              flex: 6,
              child: AppSwitcher(
                child: picked == null
                    ? AdminCard(
                        key: const ValueKey('pick'),
                        child: AdminEmpty(
                          icon: Icons.touch_app_outlined,
                          title: loc.tr('lab.pickItem'),
                          subtitle: loc.tr('lab.pickItemSub'),
                        ),
                      )
                    : SplitPanel(key: ValueKey(picked.id), item: picked),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The right-hand panel for one [SplitItem].
class SplitPanel extends StatelessWidget {
  const SplitPanel({super.key, required this.item});

  final SplitItem item;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return AdminCard(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              if (it.leading != null) ...[it.leading!(56), const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.title,
                        style: AppFonts.style(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.navy)),
                    if (it.badges.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: it.badges),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (it.actions.isNotEmpty || it.extras.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [...it.extras, ...it.actions]),
          ],
          const SizedBox(height: 12),
          for (final (icon, text) in it.details)
            if (text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: AppColors.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(text, style: AppFonts.style(fontSize: 14, height: 1.35, color: AppColors.navy)),
                    ),
                  ],
                ),
              ),
          if (it.panelBody != null) ...[const SizedBox(height: 20), it.panelBody!],
        ],
      ),
    );
  }
}

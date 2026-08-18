import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Width breakpoints tuned for iPad (11" portrait ≈ 834pt, 13" ≈ 1032pt,
/// landscape 1194–1376pt). Pages measure their own content area via
/// LayoutBuilder, so these exclude the sidebar.
class AppBreakpoints {
  AppBreakpoints._();

  /// Below this content width, two-pane pages stack vertically.
  static const stack = 720.0;

  /// Below this window width, the sidebar collapses to icons.
  static const collapseSidebar = 1100.0;

  /// Below this content width, Shade photo + result stack instead of 50/50.
  static const shadeStack = 680.0;

  static bool isNarrowWindow(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.height > size.width || size.width < collapseSidebar;
  }

  static bool isPortrait(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.height > size.width;
  }
}

/// Two-pane layout: [panel] sits beside [content] when there is room and
/// stacks above it when narrow (e.g. iPad portrait).
class AdaptiveSplit extends StatelessWidget {
  const AdaptiveSplit({
    super.key,
    required this.panel,
    required this.content,
    this.panelFraction = 0.32,
    this.minPanelWidth = 260,
    this.maxPanelWidth = 380,
    this.breakpoint = AppBreakpoints.stack,
    this.gap = 12,
    this.panelOnRight = false,
    this.narrowPanelHeight,
    this.narrowContentMinHeight = 220,
    this.narrowContentFirst = false,
    this.narrowContentMaxHeight,
  });

  final Widget panel;
  final Widget content;

  /// Panel width as a fraction of available width when side-by-side,
  /// clamped to [minPanelWidth]..[maxPanelWidth].
  final double panelFraction;
  final double minPanelWidth;
  final double maxPanelWidth;
  final double breakpoint;
  final double gap;

  /// Side the panel occupies when wide. When stacked it always goes on top.
  final bool panelOnRight;

  /// Bounded height for the panel when stacked. Required if the panel
  /// contains Expanded/flex children; leave null to let it size itself.
  final double? narrowPanelHeight;

  /// Minimum height reserved for [content] when stacked in portrait.
  final double narrowContentMinHeight;

  /// When stacked, put [content] above [panel] (e.g. photo canvas first).
  final bool narrowContentFirst;

  /// Cap for [content] height when [narrowContentFirst] is true, so the
  /// panel (library / tools) stays on screen in portrait.
  final double? narrowContentMaxHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < breakpoint ||
            (constraints.maxHeight > constraints.maxWidth &&
                constraints.maxWidth < 980);
        if (!stacked) {
          final w = (constraints.maxWidth * panelFraction)
              .clamp(minPanelWidth, maxPanelWidth);
          final panelBox = SizedBox(width: w, child: panel);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: panelOnRight
                ? [Expanded(child: content), SizedBox(width: gap), panelBox]
                : [panelBox, SizedBox(width: gap), Expanded(child: content)],
          );
        }

        // Portrait / narrow: keep a usable stage below, clamp panel height.
        final maxPanel = math.max(
          160.0,
          constraints.maxHeight - gap - narrowContentMinHeight,
        );
        final panelHeight = narrowPanelHeight == null
            ? null
            : math.min(narrowPanelHeight!, maxPanel);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (narrowContentFirst) ...[
              if (narrowContentMaxHeight != null) ...[
                SizedBox(
                  height: math.min(
                    math.min(
                      narrowContentMaxHeight!,
                      constraints.maxHeight * 0.42,
                    ),
                    math.max(
                      180.0,
                      constraints.maxHeight - gap - 320,
                    ),
                  ),
                  child: content,
                ),
                SizedBox(height: gap),
                Expanded(child: panel),
              ] else ...[
                Expanded(child: content),
                SizedBox(height: gap),
                if (panelHeight == null)
                  panel
                else
                  SizedBox(height: panelHeight, child: panel),
              ],
            ] else ...[
              if (panelHeight == null)
                panel
              else
                SizedBox(height: panelHeight, child: panel),
              SizedBox(height: gap),
              Expanded(child: content),
            ],
          ],
        );
      },
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (narrowPanelHeight == null)
              panel
            else
              SizedBox(height: narrowPanelHeight, child: panel),
            SizedBox(height: gap),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

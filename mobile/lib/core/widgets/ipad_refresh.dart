import 'package:flutter/cupertino.dart';

/// Native iPadOS pull-to-refresh: spinner in the overscroll gap.
class IpadRefresh extends StatelessWidget {
  const IpadRefresh({
    super.key,
    required this.onRefresh,
    required this.slivers,
  });

  /// Full-viewport child (empty states). Still bounces so refresh works.
  /// At least the viewport's height, but grows (and scrolls) when the child
  /// is taller — SliverFillRemaining sized it from intrinsic height, which
  /// can come out a few pixels short and overflow on small screens.
  IpadRefresh.fill({
    super.key,
    required this.onRefresh,
    required Widget child,
  }) : slivers = [
          SliverLayoutBuilder(
            builder: (context, constraints) => SliverToBoxAdapter(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.remainingPaintExtent),
                child: child,
              ),
            ),
          ),
        ];

  final Future<void> Function() onRefresh;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      primary: false,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: onRefresh),
        ...slivers,
      ],
    );
  }
}

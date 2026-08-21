import 'package:flutter/cupertino.dart';

/// Native iPadOS pull-to-refresh: spinner in the overscroll gap.
class IpadRefresh extends StatelessWidget {
  const IpadRefresh({
    super.key,
    required this.onRefresh,
    required this.slivers,
  });

  /// Full-viewport child (empty states). Still bounces so refresh works.
  IpadRefresh.fill({
    super.key,
    required this.onRefresh,
    required Widget child,
  }) : slivers = [
          SliverFillRemaining(
            hasScrollBody: false,
            child: child,
          ),
        ];

  final Future<void> Function() onRefresh;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
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

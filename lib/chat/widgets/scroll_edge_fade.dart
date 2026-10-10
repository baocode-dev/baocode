import 'package:flutter/widgets.dart';

import 'edge_fade_mask.dart';

/// Fades the scroll view in [child] out towards an edge that more of it is
/// scrolled past ([EdgeFadeMask]), as it scrolls and as its content or size
/// changes. Follows the scroll view right under it, not those inside that.
class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({
    super.key,
    required this.child,
    this.fadeLength = 24,
    this.fadeOffset = 0,
  });

  final Widget child;
  final double fadeLength;
  final double fadeOffset;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  bool _moreBefore = false;
  bool _moreAfter = false;

  bool _sync(ScrollMetrics metrics) {
    if (!metrics.hasContentDimensions) return false;
    final before = metrics.pixels > metrics.minScrollExtent + 0.5;
    final after = metrics.pixels < metrics.maxScrollExtent - 0.5;
    if (before != _moreBefore || after != _moreAfter) {
      setState(() {
        _moreBefore = before;
        _moreAfter = after;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) =>
            notification.depth == 0 && _sync(notification.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) =>
              notification.depth == 0 && _sync(notification.metrics),
          child: EdgeFadeMask(
            top: _moreBefore,
            bottom: _moreAfter,
            fadeLength: widget.fadeLength,
            fadeOffset: widget.fadeOffset,
            child: widget.child,
          ),
        ),
      );
}

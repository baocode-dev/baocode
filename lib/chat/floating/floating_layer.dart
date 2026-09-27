import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'floating_placement.dart';

/// A floating element (popover, menu, tooltip) anchored to [child], shown
/// while [visible].
///
/// Positioned at layout time from the anchor's current rect, so it follows
/// the anchor as it scrolls, and kept inside the window (see
/// [computeFloatingPosition]): it prefers [placement], flips to the other
/// side when that does not fit, slides to stay on screen, and is capped to
/// the room available. With [hideWhenClipped] (the default) it is not shown
/// while the anchor is clipped out of view by any ancestor (scrolled out of
/// a list, or not painted at all), and comes back with it.
///
/// Opens with a quick fade and scale and closes with a shorter fade; while
/// closing, the last built content stays so the exit can animate after the
/// owner's state already says closed.
class FloatingLayer extends StatefulWidget {
  const FloatingLayer({
    super.key,
    required this.visible,
    required this.builder,
    required this.child,
    this.placement = (side: FloatingSide.top, align: FloatingAlign.start),
    this.gap = 6,
    this.anchorRect,
    this.hideWhenClipped = true,
    this.tapRegionGroupId,
    this.outerTapRegionGroupId,
    this.onTapOutside,
    this.enterDuration = defaultEnterDuration,
    this.exitDuration = defaultExitDuration,
  });

  final bool visible;
  final WidgetBuilder builder;
  final Widget child;
  final FloatingPlacement placement;
  final double gap;

  /// The rect to position against, from [child]'s rect (both in overlay
  /// coordinates), e.g. to anchor at the caret within a text field.
  final Rect Function(Rect childRect)? anchorRect;

  final bool hideWhenClipped;

  /// Taps in [TapRegion]s of this group (e.g. the button that toggles the
  /// popover) are not outside taps.
  final Object? tapRegionGroupId;

  /// A second group the floating element counts as inside of, e.g. that of
  /// a region around the whole composer it belongs to.
  final Object? outerTapRegionGroupId;
  final VoidCallback? onTapOutside;

  final Duration enterDuration;
  final Duration exitDuration;

  static const defaultEnterDuration = Duration(milliseconds: 140);
  static const defaultExitDuration = Duration(milliseconds: 100);

  /// Kept clear of the window edges.
  static const viewportPadding = 8.0;

  @override
  State<FloatingLayer> createState() => _FloatingLayerState();
}

class _FloatingLayerState extends State<FloatingLayer>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.enterDuration,
    reverseDuration: widget.exitDuration,
  )..addStatusListener(_handleStatus);
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );
  late final Animation<double> _scale = Tween<double>(begin: 0.96, end: 1)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
      );

  /// The content as last built while visible, shown during the exit.
  Widget? _content;

  @override
  void initState() {
    super.initState();
    // The overlay entry stays in place (empty while closed): showing it
    // cannot happen during build, and opening must not wait a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _portal.show();
    });
    if (widget.visible) _controller.value = 1;
  }

  @override
  void didUpdateWidget(FloatingLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller
      ..duration = widget.enterDuration
      ..reverseDuration = widget.exitDuration;
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        // Part-way in, so the very first frame already shows it: the
        // transition should not add a frame of latency.
        _controller.forward(from: math.max(_controller.value, 0.2));
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) setState(() => _content = null);
  }

  /// What of the screen the anchor can show in, in overlay coordinates
  /// (given the anchor's rect there): the intersection of the clips of all
  /// its ancestors, like floating-ui's clipping ancestors. Null if none clip.
  Rect? _clipRect(Rect anchorInOverlay) {
    final anchor = context.findRenderObject();
    if (anchor is! RenderBox || !anchor.attached || !anchor.hasSize) {
      return null;
    }
    Rect? clip;
    for (RenderObject child = anchor; child.parent != null;) {
      final parent = child.parent!;
      if (parent.describeApproximatePaintClip(child) case final local?) {
        final global = MatrixUtils.transformRect(
          parent.getTransformTo(null),
          local,
        );
        clip = clip?.intersect(global) ?? global;
      }
      child = parent;
    }
    if (clip == null) return null;
    final overlayOrigin =
        anchor.localToGlobal(Offset.zero) - anchorInOverlay.topLeft;
    return clip.shift(-overlayOrigin);
  }

  Widget _buildOverlay(BuildContext context, OverlayChildLayoutInfo info) {
    if (widget.visible) {
      _content = widget.builder(context);
    } else if (_controller.isDismissed) {
      _content = null;
    }
    final content = _content;
    if (content == null) return const SizedBox.shrink();

    final childRect = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    if (widget.hideWhenClipped &&
        isAnchorHidden(childRect, _clipRect(childRect))) {
      return const SizedBox.shrink();
    }
    return CustomSingleChildLayout(
      delegate: _FloatingLayoutDelegate(
        anchor: widget.anchorRect?.call(childRect) ?? childRect,
        bounds: (Offset.zero & info.overlaySize).deflate(
          FloatingLayer.viewportPadding,
        ),
        placement: widget.placement,
        gap: widget.gap,
      ),
      child: TapRegion(
        groupId: widget.outerTapRegionGroupId,
        child: TapRegion(
          groupId: widget.tapRegionGroupId,
          onTapOutside: (_) => widget.onTapOutside?.call(),
          child: IgnorePointer(
            // Closing: let clicks through to what is underneath.
            ignoring: !widget.visible,
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(scale: _scale, child: content),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: widget.child,
    );
  }
}

class _FloatingLayoutDelegate extends SingleChildLayoutDelegate {
  _FloatingLayoutDelegate({
    required this.anchor,
    required this.bounds,
    required this.placement,
    required this.gap,
  });

  final Rect anchor;
  final Rect bounds;
  final FloatingPlacement placement;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final room = availableExtent(
      anchor: anchor,
      bounds: bounds,
      side: placement.side,
      gap: gap,
    );
    return BoxConstraints.loose(
      placement.side.isVertical
          ? Size(bounds.width, room)
          : Size(room, bounds.height),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      computeFloatingPosition(
        anchor: anchor,
        size: childSize,
        bounds: bounds,
        placement: placement,
        gap: gap,
      ).offset;

  @override
  bool shouldRelayout(_FloatingLayoutDelegate oldDelegate) =>
      anchor != oldDelegate.anchor ||
      bounds != oldDelegate.bounds ||
      placement != oldDelegate.placement ||
      gap != oldDelegate.gap;
}

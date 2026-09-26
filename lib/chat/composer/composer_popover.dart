import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A popover above [child], shown while [visible], with a quick enter
/// transition (fade + scale from the anchor corner) and a shorter fade out.
///
/// The popover is laid out in the overlay and follows [child]; [offset] is
/// from [targetAnchor] of [child] to [followerAnchor] of the popover. While
/// closing, the last built popover stays on screen so the exit animates
/// even though the owner's state already says "closed".
class ComposerPopover extends StatefulWidget {
  const ComposerPopover({
    super.key,
    required this.visible,
    required this.popoverBuilder,
    required this.child,
    this.targetAnchor = Alignment.topLeft,
    this.followerAnchor = Alignment.bottomLeft,
    this.offset = Offset.zero,
    this.tapRegionGroupId,
    this.outerTapRegionGroupId,
    this.onTapOutside,
  });

  final bool visible;
  final WidgetBuilder popoverBuilder;
  final Widget child;
  final Alignment targetAnchor;
  final Alignment followerAnchor;
  final Offset offset;

  /// Taps in [TapRegion]s of this group (e.g. the button that toggles the
  /// popover) are not outside taps.
  final Object? tapRegionGroupId;

  /// A second group the popover counts as inside of, e.g. that of a region
  /// around the whole composer the popover belongs to.
  final Object? outerTapRegionGroupId;
  final VoidCallback? onTapOutside;

  static const enterDuration = Duration(milliseconds: 140);
  static const exitDuration = Duration(milliseconds: 100);

  @override
  State<ComposerPopover> createState() => _ComposerPopoverState();
}

class _ComposerPopoverState extends State<ComposerPopover>
    with SingleTickerProviderStateMixin {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ComposerPopover.enterDuration,
    reverseDuration: ComposerPopover.exitDuration,
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

  /// The popover as last built while visible, shown during the exit.
  Widget? _lastPopover;

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
  void didUpdateWidget(ComposerPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        // Part-way in, so the very first frame already shows the popover:
        // the transition should not add a frame of latency.
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
    // Closed: drop the popover.
    if (status == AnimationStatus.dismissed) {
      setState(() => _lastPopover = null);
    }
  }

  Widget _buildOverlay(BuildContext context) {
    if (widget.visible) {
      _lastPopover = widget.popoverBuilder(context);
    } else if (_controller.isDismissed) {
      _lastPopover = null;
    }
    if (_lastPopover == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: widget.targetAnchor,
        followerAnchor: widget.followerAnchor,
        offset: widget.offset,
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
                child: ScaleTransition(
                  scale: _scale,
                  alignment: widget.followerAnchor,
                  child: _lastPopover,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildOverlay,
        child: widget.child,
      ),
    );
  }
}

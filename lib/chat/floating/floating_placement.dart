import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Which side of the anchor a floating element goes on.
enum FloatingSide {
  top,
  bottom,
  left,
  right;

  FloatingSide get opposite => switch (this) {
    top => bottom,
    bottom => top,
    left => right,
    right => left,
  };

  bool get isVertical => this == top || this == bottom;
}

/// How the floating element lines up with the anchor along that side.
enum FloatingAlign { start, center, end }

/// Where a floating element goes relative to its anchor, as in
/// floating-ui's `placement` (`top-start` is `(top, start)`).
typedef FloatingPlacement = ({FloatingSide side, FloatingAlign align});

/// A computed position: the top-left of the floating element, and the
/// placement actually used (after flipping).
typedef FloatingPosition = ({Offset offset, FloatingPlacement placement});

/// Positions a floating element of [size] next to [anchor], inside
/// [bounds] (all in the same coordinates), like floating-ui's
/// `computePosition` with these middlewares:
///
/// - `offset`: [gap] between anchor and floating element.
/// - `flip`: when it overflows [bounds] on its side, try the opposite side
///   and keep whichever overflows less.
/// - `shift`: slide along the cross axis to stay inside [bounds], and, as a
///   last resort when neither side fits, along the main axis too (so it
///   stays on screen even if it covers the anchor).
FloatingPosition computeFloatingPosition({
  required Rect anchor,
  required Size size,
  required Rect bounds,
  required FloatingPlacement placement,
  double gap = 6,
  bool flip = true,
}) {
  Offset place(FloatingPlacement p) {
    double along(double start, double end, double extent) => switch (p.align) {
      FloatingAlign.start => start,
      FloatingAlign.center => (start + end - extent) / 2,
      FloatingAlign.end => end - extent,
    };
    return switch (p.side) {
      FloatingSide.top => Offset(
        along(anchor.left, anchor.right, size.width),
        anchor.top - gap - size.height,
      ),
      FloatingSide.bottom => Offset(
        along(anchor.left, anchor.right, size.width),
        anchor.bottom + gap,
      ),
      FloatingSide.left => Offset(
        anchor.left - gap - size.width,
        along(anchor.top, anchor.bottom, size.height),
      ),
      FloatingSide.right => Offset(
        anchor.right + gap,
        along(anchor.top, anchor.bottom, size.height),
      ),
    };
  }

  // How far past [bounds] it sticks out on its own side (<= 0: fits).
  double overflow(FloatingPlacement p, Offset at) => switch (p.side) {
    FloatingSide.top => bounds.top - at.dy,
    FloatingSide.bottom => at.dy + size.height - bounds.bottom,
    FloatingSide.left => bounds.left - at.dx,
    FloatingSide.right => at.dx + size.width - bounds.right,
  };

  var chosen = placement;
  var offset = place(chosen);
  if (flip && overflow(chosen, offset) > 0) {
    final other = (side: chosen.side.opposite, align: chosen.align);
    final otherOffset = place(other);
    if (overflow(other, otherOffset) < overflow(chosen, offset)) {
      chosen = other;
      offset = otherOffset;
    }
  }

  double clampTo(double value, double min, double max) =>
      max < min ? min : value.clamp(min, max);
  offset = Offset(
    clampTo(offset.dx, bounds.left, bounds.right - size.width),
    clampTo(offset.dy, bounds.top, bounds.bottom - size.height),
  );
  return (offset: offset, placement: chosen);
}

/// The most room a floating element on [side] of [anchor] (or on the
/// opposite side, if it flips) can have along the main axis, like
/// floating-ui's `size` middleware: use it to cap the element's extent.
double availableExtent({
  required Rect anchor,
  required Rect bounds,
  required FloatingSide side,
  double gap = 6,
}) {
  final (before, after) = side.isVertical
      ? (anchor.top - bounds.top, bounds.bottom - anchor.bottom)
      : (anchor.left - bounds.left, bounds.right - anchor.right);
  return math.max(0, math.max(before, after) - gap);
}

/// Whether [anchor] is clipped out of view by [clip] (e.g. scrolled out of
/// its list), as in floating-ui's `hide` middleware (`referenceHidden`).
bool isAnchorHidden(Rect anchor, Rect? clip) =>
    clip != null && (clip.isEmpty || !clip.overlaps(anchor));

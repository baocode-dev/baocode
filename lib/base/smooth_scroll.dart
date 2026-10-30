import 'dart:async';

import 'package:bao_editor/monaco/flutter/wheel_glide.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// The app's scrolling: Material's, but on macOS with no bounce at the
/// ends ([EdgeStopScrollPhysics]). The editors, which keep their own
/// offsets, fling by the same physics (`TrackpadFling`).
class BaoScrollBehavior extends MaterialScrollBehavior {
  const BaoScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      switch (getPlatform(context)) {
        TargetPlatform.macOS => const EdgeStopScrollPhysics(
          parent: RangeMaintainingScrollPhysics(),
        ),
        _ => super.getScrollPhysics(context),
      };
}

/// macOS's scrolling (a trackpad's fling slowing as it does there,
/// [BouncingScrollPhysics] at `fast`), stopping at an end as VS Code's
/// lists and editors do, not going past it and springing back.
class EdgeStopScrollPhysics extends BouncingScrollPhysics {
  const EdgeStopScrollPhysics({super.parent})
    : super(decelerationRate: ScrollDecelerationRate.fast);

  @override
  EdgeStopScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      EdgeStopScrollPhysics(parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) =>
      const ClampingScrollPhysics().applyBoundaryConditions(position, value);

  /// A flick goes as far as it would alone, not sped up by the fling it
  /// stops (iOS's): the same flick four times went twice as far by the
  /// fourth (tool/perf `follow.*`). The editors' `TrackpadFling` takes this
  /// too.
  @override
  double carriedMomentum(double existingVelocity) => 0;

  /// The fingers move the view from their first pixel, not after a dead
  /// zone (iOS's 3.5px) that left the view short of them all along. (None
  /// would be null, which [BouncingScrollPhysics] has no room for; it must
  /// be more than 0.)
  @override
  double get dragStartDistanceMotionThreshold => 0.01;
}

/// A [ScrollController] for lists a mouse wheel scrolls smoothly
/// ([WheelGliding]); a trackpad's scrolling is as it comes.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    super.onAttach,
    super.onDetach,
  });

  /// Where the list is going, as [offset] is where it is: where a wheel's
  /// notches are taking it, while they glide it ([WheelGliding.headedTo]).
  double get headedTo => switch (position) {
    final WheelGliding gliding => gliding.headedTo,
    final other => other.pixels,
  };

  @override
  void attach(ScrollPosition position) {
    _WheelSignal.watch();
    super.attach(position);
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SmoothScrollPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

/// A [SmoothScrollController] of its own for the scroll view [builder]
/// builds: for a widget with no state to keep one in.
class SmoothScrolling extends StatefulWidget {
  const SmoothScrolling({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<SmoothScrolling> createState() => _SmoothScrollingState();
}

class _SmoothScrollingState extends State<SmoothScrolling> {
  final _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

/// A [SmoothScrolling] whose offset is kept in the nearest [PageStorage]
/// under [identifier] as it goes, and where it starts when built there
/// again: an IDE tab's view switched back to (`IdeViewStates.bucket`).
class KeptScrolling extends StatefulWidget {
  const KeptScrolling({
    super.key,
    required this.identifier,
    required this.builder,
  });

  final Object identifier;

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<KeptScrolling> createState() => _KeptScrollingState();
}

class _KeptScrollingState extends State<KeptScrolling> {
  PageStorageBucket? _bucket;
  late final SmoothScrollController _controller;

  @override
  void initState() {
    super.initState();
    _bucket = PageStorage.maybeOf(context);
    final kept = _bucket?.readState(context, identifier: widget.identifier);
    _controller = SmoothScrollController(
      initialScrollOffset: kept is double ? kept : 0,
      keepScrollOffset: false,
    );
  }

  /// Kept while the list it scrolls is still there.
  @override
  void deactivate() {
    if (_controller.hasClients) {
      _bucket?.writeState(
        context,
        _controller.offset,
        identifier: widget.identifier,
      );
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext
    with WheelGliding {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });
}

/// The device of the wheel's (or trackpad's) scroll signal being handled:
/// seen as it comes, after every view under the pointer has (they ask to
/// take it), before the one that takes it does; forgotten after.
abstract final class _WheelSignal {
  static PointerDeviceKind? kind;
  static bool _watching = false;

  static void watch() {
    if (_watching) return;
    _watching = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_see);
  }

  static void _see(PointerEvent event) {
    if (event is! PointerScrollEvent) return;
    kind = event.kind;
    scheduleMicrotask(() => kind = null);
  }
}

/// A scroll position a mouse wheel scrolls smoothly: each notch moves it by
/// the distance the system gives (as Chrome takes it, not sped up), eased
/// out over a few frames ([WheelGlide]), under way in the frame after the
/// notch. The next notch adds to what the last had left, from where the
/// list is. A trackpad's scrolling, and anything else's, is as it comes.
///
/// Its controller is a [SmoothScrollController], which sees what device a
/// signal is from.
mixin WheelGliding on ScrollPositionWithSingleContext {
  @override
  void pointerScroll(double delta) {
    // A smooth wheel's steps, like a trackpad's, move it as they come.
    if (_WheelSignal.kind != PointerDeviceKind.mouse ||
        !WheelGlide.glides(delta)) {
      super.pointerScroll(delta);
      return;
    }
    final going = activity;
    final glide = WheelGlide.next(
      going is WheelScrollActivity ? going.glide : null,
      at: pixels,
      delta: delta,
      min: minScrollExtent,
      max: maxScrollExtent,
      frame: WheelGlide.frameOf(context.notificationContext),
    );
    if (glide == null) {
      // Back where it was going from (or still at an end): it stops.
      if (going is WheelScrollActivity) goBallistic(0);
      return;
    }
    // The user's, as a jump would be.
    updateUserScrollDirection(
      glide.distance > 0 ? ScrollDirection.reverse : ScrollDirection.forward,
    );
    beginActivity(
      WheelScrollActivity(this, vsync: context.vsync, glide: glide),
    );
  }

  /// Where the list is going: where a wheel's notches are taking it, while
  /// they move it; else where it is.
  double get headedTo => switch (activity) {
    final WheelScrollActivity wheel => pixels + wheel.glide.left,
    _ => pixels,
  };
}

/// A mouse wheel's notches scrolling a list ([WheelGlide]), stopped at an
/// end of it.
class WheelScrollActivity extends ScrollActivity {
  WheelScrollActivity(
    super.delegate, {
    required TickerProvider vsync,
    required this.glide,
  }) {
    _ticker = vsync.createTicker(_tick)..start();
  }

  final WheelGlide glide;

  late final Ticker _ticker;
  bool _disposed = false;

  void _tick(Duration _) {
    final position = delegate as ScrollPosition;
    final to = position.pixels + glide.step();
    final kept = to.clamp(position.minScrollExtent, position.maxScrollExtent);
    delegate.setPixels(kept);
    if (_disposed) return; // Stopped by what the move set off.
    if (glide.done || kept != to) delegate.goBallistic(0);
  }

  @override
  void dispatchOverscrollNotification(
    ScrollMetrics metrics,
    BuildContext context,
    double overscroll,
  ) {
    OverscrollNotification(
      metrics: metrics,
      context: context,
      overscroll: overscroll,
      velocity: velocity,
    ).dispatch(context);
  }

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool get isScrolling => true;

  /// Pixels a second, now.
  @override
  double get velocity => glide.velocity;

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    super.dispose();
  }
}

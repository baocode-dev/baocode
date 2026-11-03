import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../chat/widgets/hover_builder.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/islands.dart';

/// A draggable horizontal scrollbar, with vertical wheels scrolling tabs too.
///
/// Over a card's top left corner (under an [IslandCorner]): at its start,
/// its first tab flush with the card's edge; scrolled from it, the tabs
/// hidden from where the corner's rounding ends, the corner rounded, not
/// a tab's foot hanging past it ([IslandTabsScrolled]), eased between.
class TabStripScroll extends StatefulWidget {
  const TabStripScroll({
    super.key,
    required this.controller,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final ScrollController controller;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Scrolls the strip [tab] is in to show it all: past the card's corner,
  /// where the strip hides what is under that.
  static void reveal(BuildContext tab) {
    Scrollable.ensureVisible(
      tab,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    Scrollable.ensureVisible(
      tab,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    final strip = tab.findAncestorStateOfType<_TabStripScrollState>();
    if (strip == null || !strip._overCorner) return;
    final controller = strip.widget.controller;
    final box = tab.findRenderObject();
    final view = strip.context.findRenderObject();
    if (!controller.hasClients || box is! RenderBox || view is! RenderBox) {
      return;
    }
    final position = controller.position;
    if (position.pixels <= 0) return;
    final left = box.localToGlobal(Offset.zero, ancestor: view).dx;
    if (left < Islands.radius) {
      position.jumpTo(
        math.max(
          position.minScrollExtent,
          position.pixels - (Islands.radius - left),
        ),
      );
    }
  }

  @override
  State<TabStripScroll> createState() => _TabStripScrollState();
}

class _TabStripScrollState extends State<TabStripScroll> {
  bool _scrolled = false;

  /// Whether it is over a card's top left corner (see [TabStripScroll]).
  bool get _overCorner => IslandCorner.of(context) != null;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_moved);
  }

  @override
  void didUpdateWidget(TabStripScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_moved);
      widget.controller.addListener(_moved);
      _moved();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_moved);
    super.dispose();
  }

  void _moved() {
    final controller = widget.controller;
    final scrolled =
        controller.hasClients &&
        controller.position.hasPixels &&
        controller.position.pixels > 0.5;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  void _wheel(PointerSignalEvent event) {
    final controller = widget.controller;
    if (event is! PointerScrollEvent || !controller.hasClients) return;
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final position = controller.position;
      controller.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final hidden = _overCorner && _scrolled ? Islands.radius : 0.0;
    return HoverBuilder(
      builder: (context, hovered) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: RawScrollbar(
          controller: widget.controller,
          thumbVisibility: hovered,
          interactive: true,
          thickness: 3,
          radius: Radius.zero,
          thumbColor: themeColors['scrollbarSlider.background'],
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: Listener(
            onPointerSignal: _wheel,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: hidden),
              duration: IslandCornerRadius.duration,
              curve: Curves.easeOut,
              // Clipped alike throughout: the scroll view kept.
              builder: (context, hidden, child) =>
                  ClipRect(clipper: _HiddenLeft(hidden), child: child),
              child: IslandTabsScrolled(
                scrolled: _scrolled,
                child: SingleChildScrollView(
                  controller: widget.controller,
                  scrollDirection: Axis.horizontal,
                  padding: widget.padding,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// All but the left [hidden] of it, as far above and below as what is in
/// it reaches (a tab's foot over the card under it).
class _HiddenLeft extends CustomClipper<Rect> {
  _HiddenLeft(this.hidden);

  final double hidden;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(hidden, -size.height, size.width, size.height * 2);

  @override
  bool shouldReclip(_HiddenLeft old) => old.hidden != hidden;
}

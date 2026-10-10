import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../chat/widgets/hover_builder.dart';
import '../theme/workbench_theme.dart' show themeColors;

/// A draggable horizontal scrollbar, with vertical wheels scrolling tabs too.
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

  @override
  State<TabStripScroll> createState() => _TabStripScrollState();
}

class _TabStripScrollState extends State<TabStripScroll> {
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
  Widget build(BuildContext context) => HoverBuilder(
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
          child: SingleChildScrollView(
            controller: widget.controller,
            scrollDirection: Axis.horizontal,
            padding: widget.padding,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

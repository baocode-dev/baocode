import 'dart:async';

import 'package:flutter/material.dart';

/// One line of text, cut off with an ellipsis when too long for its room;
/// while the pointer is over it, it scrolls to show the rest, back and
/// forth, then shows its start again once the pointer leaves. Without
/// animations (the system's reduced motion), it is only cut off.
class HoverScrollText extends StatefulWidget {
  const HoverScrollText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  /// How fast it scrolls, in logical pixels a second.
  static const speed = 40.0;

  /// How long it rests at each end.
  static const pause = Duration(milliseconds: 900);

  @override
  State<HoverScrollText> createState() => _HoverScrollTextState();
}

class _HoverScrollTextState extends State<HoverScrollText> {
  final ScrollController _scroll = ScrollController();
  bool _hovered = false;

  /// Counts the hovers: a scroll begun for one ends as it ends.
  int _run = 0;

  /// The rest at an end before the next scroll.
  Timer? _rest;

  @override
  void dispose() {
    _stop();
    _scroll.dispose();
    super.dispose();
  }

  void _stop() {
    _run++;
    _rest?.cancel();
    _rest = null;
  }

  void _enter() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    setState(() => _hovered = true);
    _stop();
    final run = _run;
    // Once the scrolling text is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _next(run));
  }

  void _exit() {
    _stop();
    if (_hovered) setState(() => _hovered = false);
  }

  /// Rests, then scrolls to the other end, and so on while [run] goes.
  void _next(int run) {
    bool going() => mounted && run == _run && _scroll.hasClients;
    if (!going()) return;
    _rest = Timer(HoverScrollText.pause, () async {
      if (!going()) return;
      final end = _scroll.position.maxScrollExtent;
      if (end <= 0) return;
      final at = _scroll.offset;
      final to = at < end / 2 ? end : 0.0;
      await _scroll.animateTo(
        to,
        duration: Duration(
          milliseconds: ((to - at).abs() / HoverScrollText.speed * 1000)
              .round(),
        ),
        curve: Curves.linear,
      );
      _next(run);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final overflows =
            constraints.hasBoundedWidth && painter.width > constraints.maxWidth;
        painter.dispose();
        final Widget text = _hovered && overflows
            ? SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Text(widget.text, maxLines: 1, style: style),
              )
            : Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              );
        return MouseRegion(
          onEnter: overflows ? (_) => _enter() : null,
          onExit: (_) => _exit(),
          child: text,
        );
      },
    );
  }
}

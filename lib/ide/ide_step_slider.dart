import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// One of [count] steps along a track: a click picks the nearest, a drag
/// the one under the pointer as it goes (unless [tapOnly]), the arrow keys
/// the next. The app's own, not Material's Slider, whose value indicator's
/// OverlayPortal is a semantics node that moves between parents: the
/// desktop engines reject such updates (see test/semantics_tree.dart).
class IdeStepSlider extends StatefulWidget {
  const IdeStepSlider({
    super.key,
    required this.step,
    required this.count,
    required this.semanticLabel,
    required this.onChanged,
    this.tapOnly = false,
    this.width = 180,
  }) : assert(count > 1);

  final int step;
  final int count;

  /// What a screen reader says of it, at any step: its name and value.
  final String semanticLabel;
  final ValueChanged<int> onChanged;

  /// A step is picked by a click, not by dragging the thumb.
  final bool tapOnly;
  final double width;

  /// The thumb's halo's radius: the slider is twice as tall.
  static const _halo = 14.0;
  static const _thumb = 7.0;
  static const _trackHeight = 3.0;

  /// The part picked is this much taller than the rest, as Material's.
  static const _activeExtra = 2.0;
  static const _tick = 1.5;

  /// Where the track starts and ends, from each side: past the halo and a
  /// tick's radius, as Material's.
  static const _inset = _halo + _tick;

  @override
  State<IdeStepSlider> createState() => _IdeStepSliderState();
}

class _IdeStepSliderState extends State<IdeStepSlider> {
  var _hovered = false;
  var _pressed = false;
  var _focused = false;

  int get _last => widget.count - 1;

  /// The step nearest [x], across the track.
  int _stepAt(double x) {
    final track = widget.width - 2 * IdeStepSlider._inset;
    final fraction = ((x - IdeStepSlider._inset) / track).clamp(0.0, 1.0);
    return (fraction * _last).round();
  }

  void _pick(int step) {
    final picked = step.clamp(0, _last);
    if (picked != widget.step) widget.onChanged(picked);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final int? by = switch (key) {
      LogicalKeyboardKey.arrowRight => rtl ? -1 : 1,
      LogicalKeyboardKey.arrowLeft => rtl ? 1 : -1,
      LogicalKeyboardKey.arrowUp => 1,
      LogicalKeyboardKey.arrowDown => -1,
      _ => null,
    };
    if (by == null) return KeyEventResult.ignored;
    _pick(widget.step + by);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    return Semantics(
      slider: true,
      focusable: true,
      focused: _focused,
      // As Material's Slider said it: the name and value, whichever step.
      value: widget.semanticLabel,
      increasedValue: step < _last ? widget.semanticLabel : null,
      decreasedValue: step > 0 ? widget.semanticLabel : null,
      onIncrease: step < _last ? () => _pick(step + 1) : null,
      onDecrease: step > 0 ? () => _pick(step - 1) : null,
      excludeSemantics: true,
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              setState(() => _pressed = true);
              _pick(_stepAt(details.localPosition.dx));
            },
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onHorizontalDragStart: widget.tapOnly
                ? null
                : (details) {
                    setState(() => _pressed = true);
                    _pick(_stepAt(details.localPosition.dx));
                  },
            onHorizontalDragUpdate: widget.tapOnly
                ? null
                : (details) => _pick(_stepAt(details.localPosition.dx)),
            onHorizontalDragEnd: widget.tapOnly
                ? null
                : (_) => setState(() => _pressed = false),
            onHorizontalDragCancel: widget.tapOnly
                ? null
                : () => setState(() => _pressed = false),
            dragStartBehavior: DragStartBehavior.down,
            child: CustomPaint(
              size: Size(widget.width, 2 * IdeStepSlider._halo),
              painter: _StepSliderPainter(
                step: step,
                count: widget.count,
                accent: AppColors.accent,
                inactive: AppColors.textFaint.withValues(alpha: 0.35),
                inactiveTick: AppColors.textMuted,
                halo: _pressed || _hovered || _focused,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepSliderPainter extends CustomPainter {
  _StepSliderPainter({
    required this.step,
    required this.count,
    required this.accent,
    required this.inactive,
    required this.inactiveTick,
    required this.halo,
  });

  final int step;
  final int count;
  final Color accent;
  final Color inactive;
  final Color inactiveTick;
  final bool halo;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = IdeStepSlider._inset;
    final y = size.height / 2;
    final track = size.width - 2 * inset;
    final thumbX = inset + track * step / (count - 1);
    const half = IdeStepSlider._trackHeight / 2;
    const activeHalf = half + IdeStepSlider._activeExtra / 2;

    canvas.drawRRect(
      RRect.fromLTRBR(
        inset,
        y - half,
        size.width - inset,
        y + half,
        const Radius.circular(half),
      ),
      Paint()..color = inactive,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        inset - IdeStepSlider._activeExtra / 2,
        y - activeHalf,
        thumbX,
        y + activeHalf,
        const Radius.circular(activeHalf),
      ),
      Paint()..color = accent,
    );
    for (var i = 0; i < count; i++) {
      final x = inset + track * i / (count - 1);
      canvas.drawCircle(
        Offset(x, y),
        IdeStepSlider._tick,
        Paint()
          ..color = i <= step
              ? Colors.white.withValues(alpha: 0.7)
              : inactiveTick,
      );
    }
    if (halo) {
      canvas.drawCircle(
        Offset(thumbX, y),
        IdeStepSlider._halo,
        Paint()..color = accent.withValues(alpha: 0.12),
      );
    }
    // Its edge, as Material's thumb's shadow draws it.
    canvas.drawCircle(
      Offset(thumbX, y),
      IdeStepSlider._thumb + 0.6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.4),
    );
    canvas.drawCircle(
      Offset(thumbX, y),
      IdeStepSlider._thumb,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_StepSliderPainter old) =>
      old.step != step ||
      old.count != count ||
      old.accent != accent ||
      old.inactive != inactive ||
      old.inactiveTick != inactiveTick ||
      old.halo != halo;
}

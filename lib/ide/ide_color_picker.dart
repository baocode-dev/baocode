// The color picker of a document color's swatch (see ide_editor_colors.dart).
//
// Follows VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0)
// src/vs/editor/contrib/colorPicker/browser/colorPickerParts/: the header
// (the picked color with its presentation's label — click for the next
// presentation — and the original color — click to go back to it), and the
// body: a saturation/value box, an opacity strip and a hue strip.

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' hide ColorScheme;
import 'ide_editor_colors.dart';

class IdeColorPicker extends StatefulWidget {
  const IdeColorPicker({super.key, required this.picker, required this.colors});

  static const width = 240.0;
  static const height = 24.0 + 8 + 150 + 8;

  final EditorColorPicker picker;
  final WorkbenchColors colors;

  @override
  State<IdeColorPicker> createState() => _IdeColorPickerState();
}

class _IdeColorPickerState extends State<IdeColorPicker> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.picker.value);
    widget.picker.addListener(_changed);
  }

  @override
  void didUpdateWidget(IdeColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.picker, widget.picker)) {
      oldWidget.picker.removeListener(_changed);
      widget.picker.addListener(_changed);
      _hsv = HSVColor.fromColor(widget.picker.value);
    }
  }

  @override
  void dispose() {
    widget.picker.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final value = widget.picker.value;
    // Keep the hue (and saturation) a gray or black color loses.
    if (_hsv.toColor() != value) {
      final next = HSVColor.fromColor(value);
      _hsv = next.saturation == 0 || next.value == 0
          ? _hsv
                .withAlpha(next.alpha)
                .withValue(next.value)
                .withSaturation(next.value == 0 ? _hsv.saturation : 0)
          : next;
    }
    if (mounted) setState(() {});
  }

  void _preview(HSVColor hsv) {
    _hsv = hsv;
    unawaited(widget.picker.preview(hsv.toColor()));
    setState(() {});
  }

  void _commit() => unawaited(widget.picker.commit());

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final picker = widget.picker;
    final value = picker.value;
    final label = picker.presentation?.label ?? '';
    final light = value.computeLuminance() * value.a + (1 - value.a) > 0.5;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const ValueKey('color-picker'),
        width: IdeColorPicker.width,
        decoration: BoxDecoration(
          color: colors['editorHoverWidget.background'],
          border: Border.all(
            color: colors['editorHoverWidget.border'],
          ),
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: colors['widget.shadow'],
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('color-picker-presentation'),
                      onTap: () => unawaited(picker.nextPresentation()),
                      child: _Checkered(
                        color: value,
                        child: Center(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.codeStyle(12).copyWith(
                              color: light ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 74,
                    child: GestureDetector(
                      key: const ValueKey('color-picker-original'),
                      onTap: () {
                        _hsv = HSVColor.fromColor(picker.originalColor);
                        unawaited(picker.revert());
                      },
                      child: _Checkered(color: picker.originalColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _saturationBox()),
                  const SizedBox(width: 8),
                  SizedBox(width: 18, child: _opacityStrip()),
                  const SizedBox(width: 8),
                  SizedBox(width: 18, child: _hueStrip()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drag({
    required Key key,
    required Widget child,
    required void Function(Offset local, Size size) onPosition,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      return GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onPanDown: (details) => onPosition(details.localPosition, size),
        onPanUpdate: (details) => onPosition(details.localPosition, size),
        onPanEnd: (_) => _commit(),
        onPanCancel: _commit,
        child: child,
      );
    },
  );

  Widget _saturationBox() => _drag(
    key: const ValueKey('color-picker-saturation'),
    onPosition: (local, size) => _preview(
      _hsv
          .withSaturation((local.dx / size.width).clamp(0.0, 1.0))
          .withValue(1 - (local.dy / size.height).clamp(0.0, 1.0)),
    ),
    child: CustomPaint(painter: _SaturationPainter(_hsv)),
  );

  Widget _hueStrip() => _drag(
    key: const ValueKey('color-picker-hue'),
    // Upstream's hue strip runs from red at the top back to red.
    onPosition: (local, size) => _preview(
      _hsv.withHue(
        ((1 - (local.dy / size.height).clamp(0.0, 1.0)) * 360) % 360,
      ),
    ),
    child: CustomPaint(painter: _HuePainter(_hsv.hue)),
  );

  Widget _opacityStrip() => _drag(
    key: const ValueKey('color-picker-opacity'),
    onPosition: (local, size) => _preview(
      _hsv.withAlpha(1 - (local.dy / size.height).clamp(0.0, 1.0)),
    ),
    child: CustomPaint(painter: _OpacityPainter(_hsv)),
  );
}

/// [color] over a checkerboard, so transparency shows.
class _Checkered extends StatelessWidget {
  const _Checkered({required this.color, this.child});

  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _CheckerPainter(),
    child: ColoredBox(color: color, child: child ?? const SizedBox.expand()),
  );
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final dark = Paint()..color = const Color(0xffcccccc);
    const cell = 5.0;
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x + y) / cell).round().isOdd) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) => false;
}

class _SaturationPainter extends CustomPainter {
  _SaturationPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white,
            HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final center = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas
      ..drawCircle(
        center,
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      )
      ..drawCircle(
        center,
        6.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black54,
      );
  }

  @override
  bool shouldRepaint(_SaturationPainter oldDelegate) => oldDelegate.hsv != hsv;
}

void _paintSlider(Canvas canvas, Size size, double fraction) {
  final y = fraction * size.height;
  final rect = Rect.fromLTWH(-2, y - 2, size.width + 4, 4);
  canvas
    ..drawRect(rect, Paint()..color = Colors.white)
    ..drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black54,
    );
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            for (var h = 360; h >= 0; h -= 60)
              HSVColor.fromAHSV(1, h % 360, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    _paintSlider(canvas, size, 1 - hue / 360);
  }

  @override
  bool shouldRepaint(_HuePainter oldDelegate) => oldDelegate.hue != hue;
}

class _OpacityPainter extends CustomPainter {
  _OpacityPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _CheckerPainter().paint(canvas, size);
    final opaque = hsv.withAlpha(1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [opaque, opaque.withValues(alpha: 0)],
        ).createShader(rect),
    );
    _paintSlider(canvas, size, 1 - hsv.alpha);
  }

  @override
  bool shouldRepaint(_OpacityPainter oldDelegate) => oldDelegate.hsv != hsv;
}

// The small bar floating over selected text, and its buttons: a markdown
// editor's marks (see MarkdownFormatBar), the conversation's Copy, Quote
// and By the Way (see ChatHistoryView).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../chat/widgets/hover_builder.dart';
import '../theme/app_theme.dart';
import '../theme/svg_icons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_hover.dart';

/// The bar: [children] in a row, on the editor widgets' background, or
/// [color] within [border] (the chat's, its messages').
class SelectionBubble extends StatelessWidget {
  const SelectionBubble({
    super.key,
    required this.children,
    this.color,
    this.border,
  });

  final List<Widget> children;
  final Color? color;
  final Color? border;

  static const height = 32.0;

  /// Between it and the text it is over (or under).
  static const gap = 8.0;

  /// Where a bar of [size] goes in [view] by [around], what shows of the
  /// text it is for, as a document's editor has it: over it, in its
  /// middle; under it where there is no room over it; with room for
  /// neither (selected past both ends of the view), over the view's
  /// bottom. Kept [gap] off the view's sides.
  static Offset placeBy(Rect around, Rect view, Size size) {
    final over = around.top - gap - size.height;
    final under = around.bottom + gap;
    final double y;
    if (over >= view.top) {
      y = over;
    } else if (under + size.height <= view.bottom) {
      y = under;
    } else {
      y = math.max(view.top, view.bottom - size.height - gap);
    }
    final left = view.left + gap;
    final x = (around.center.dx - size.width / 2)
        .clamp(left, math.max(left, view.right - size.width - gap))
        .toDouble();
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: color ?? themeColors['editorWidget.background'],
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: border ?? themeColors['editorWidget.border']),
      boxShadow: [
        BoxShadow(
          color: themeColors['widget.shadow'],
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

/// Between groups of a [SelectionBubble]'s buttons.
class SelectionBubbleDivider extends StatelessWidget {
  const SelectionBubbleDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 16,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: AppColors.border,
  );
}

/// A [SelectionBubble]'s button: [icon] (one of [SvgIcons] too), and its
/// [label] if it has one, of [color] (muted by default); [hover] under it
/// hovered (the toolbars' by default). Pressing it keeps the focus where it
/// is (and the selection).
class SelectionBubbleButton extends StatelessWidget {
  const SelectionBubbleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.label,
    this.active = false,
    this.busy = false,
    this.color,
    this.hover,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;
  final String? label;
  final bool active;
  final bool busy;
  final Color? color;
  final Color? hover;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppColors.textPrimary
        : this.color ?? AppColors.textMuted;
    final hover = this.hover ?? themeColors['toolbar.hoverBackground'];
    final button = HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        // Keeps the editor's focus (and selection).
        onTapDown: (_) {},
        onTap: busy ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 24,
          constraints: const BoxConstraints(minWidth: 24),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 6),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active
                ? themeColors['toolbar.activeBackground']
                : hovered
                ? hover
                : hover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.center,
          child: label != null && icon == Icons.title
              ? Text(
                  label!,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      icon,
                      size: 15,
                      color: busy ? AppColors.accent : color,
                    ),
                    if (label case final label?) ...[
                      const SizedBox(width: 4),
                      Text(label, style: TextStyle(color: color, fontSize: 12)),
                    ],
                  ],
                ),
        ),
      ),
    );
    return switch (tooltip) {
      final tooltip? => IdeHover(message: tooltip, child: button),
      null => button,
    };
  }
}

/// Fills what it is given, and paints [child] (laid out at its own size)
/// where [place] puts it, read at paint time: after layout, so it goes with
/// what it is placed by elsewhere in the tree in the same frame (the
/// selection as it is dragged, the text as it scrolls), not a frame behind
/// it. Paints nothing where [place] gives no place. [repaint] says when it
/// may move.
class SelectionBubbleFollower extends SingleChildRenderObjectWidget {
  const SelectionBubbleFollower({
    super.key,
    required this.place,
    required this.repaint,
    required super.child,
  });

  final Offset? Function(RenderBox layer, Size child) place;
  final Listenable repaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFollower(place, repaint);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderFollower)
      ..place = place
      ..repaint = repaint;
  }
}

class _RenderFollower extends RenderProxyBox {
  _RenderFollower(this.place, this._repaint);

  Offset? Function(RenderBox layer, Size child) place;
  Offset? _painted;

  Listenable _repaint;
  set repaint(Listenable value) {
    if (identical(value, _repaint)) return;
    if (attached) {
      _repaint.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _repaint = value;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    child?.layout(constraints.loosen(), parentUsesSize: true);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    _painted = child == null ? null : place(this, child.size);
    if (child != null && _painted != null) {
      context.paintChild(child, offset + _painted!);
    }
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final painted = _painted;
    final child = this.child;
    if (painted == null || child == null) return false;
    return result.addWithPaintOffset(
      offset: painted,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final painted = _painted ?? Offset.zero;
    transform.translateByDouble(painted.dx, painted.dy, 0, 1);
  }
}

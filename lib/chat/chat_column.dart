import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// How far in from its right edge a chat's column keeps clear of what floats
/// over it there (the side panel's rail, over the top right pane): the chat
/// itself, its title bar and its scrollbar, still reach the edge.
class ChatColumnInset extends InheritedWidget {
  const ChatColumnInset({super.key, required this.right, required super.child});

  final double right;

  /// The inset where [context] is; none outside any.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatColumnInset>()?.right ?? 0;

  @override
  bool updateShouldNotify(ChatColumnInset oldWidget) =>
      oldWidget.right != right;
}

/// [child] no wider than [maxWidth], in the middle of the width it has (as
/// `Align` over a `ConstrainedBox` would lay it out), but narrower at its
/// right where it would come within [right] of that width's right edge: its
/// left stays where it would be without, level with the composer's, which
/// is always in the middle. Worked out as it is laid out, so a new width
/// only lays [child] out again.
class ChatColumn extends SingleChildRenderObjectWidget {
  const ChatColumn({
    super.key,
    required this.maxWidth,
    this.right = 0,
    super.child,
  });

  final double maxWidth;
  final double right;

  @override
  RenderChatColumn createRenderObject(BuildContext context) =>
      RenderChatColumn(maxWidth, right);

  @override
  void updateRenderObject(BuildContext context, RenderChatColumn renderObject) {
    renderObject
      ..maxWidth = maxWidth
      ..right = right;
  }
}

class RenderChatColumn extends RenderShiftedBox {
  RenderChatColumn(this._maxWidth, this._right) : super(null);

  double get maxWidth => _maxWidth;
  double _maxWidth;
  set maxWidth(double value) {
    if (value == _maxWidth) return;
    _maxWidth = value;
    markNeedsLayout();
  }

  double get right => _right;
  double _right;
  set right(double value) {
    if (value == _right) return;
    _right = value;
    markNeedsLayout();
  }

  /// The column's left and width in [width].
  static ({double left, double width}) place(
    double width, {
    required double maxWidth,
    double right = 0,
  }) {
    final centered = math.max(0.0, math.min(maxWidth, width));
    final left = (width - centered) / 2;
    return (
      left: left,
      width: math.max(0.0, math.min(centered, width - right - left)),
    );
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: place(
          constraints.maxWidth,
          maxWidth: _maxWidth,
          right: _right,
        ).width,
        maxHeight: constraints.maxHeight,
      );

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final height =
        child?.getDryLayout(_childConstraints(constraints)).height ?? 0;
    return constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(
        place(width, maxWidth: _maxWidth, right: _right).width,
      ) ??
      0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(
        place(width, maxWidth: _maxWidth, right: _right).width,
      ) ??
      0;

  @override
  double computeMinIntrinsicWidth(double height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(width, 0));
      return;
    }
    final (:left, width: column) = place(
      width,
      maxWidth: _maxWidth,
      right: _right,
    );
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    // Narrower than the column, in its middle.
    (child.parentData! as BoxParentData).offset = Offset(
      left + (column - child.size.width) / 2,
      0,
    );
    size = constraints.constrain(Size(width, child.size.height));
  }
}

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// How far in from its right edge a chat's column keeps clear of what floats
/// over it there (the side panel's rail, over the top right pane): the chat
/// itself, its title bar and its scrollbar, still reach the edge.
class ChatColumnInset extends InheritedWidget {
  const ChatColumnInset({
    super.key,
    this.right = 0,
    this.left = 0,
    this.rail,
    required super.child,
  });

  final double right;

  /// As [right], at the left: what floats there with the side panel at the
  /// conversations' left.
  final double left;

  /// What floats there (see [ChatRail]): what of the chat's margin it is
  /// over (the minimap's) keeps in line with it. None where nothing floats.
  final ChatRail? rail;

  /// [rail] where [context] is; none outside any.
  static ChatRail? railOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatColumnInset>()?.rail;

  /// The inset at the right where [context] is; none outside any.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatColumnInset>()?.right ?? 0;

  /// The inset at the left where [context] is; none outside any.
  static double leftOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatColumnInset>()?.left ?? 0;

  @override
  bool updateShouldNotify(ChatColumnInset oldWidget) =>
      oldWidget.right != right ||
      oldWidget.left != left ||
      oldWidget.rail != rail;
}

/// [child] no wider than [maxWidth], in the middle of the width it has (as
/// `Align` over a `ConstrainedBox` would lay it out), but narrower at its
/// right where it would come within [right] of that width's right edge: its
/// left stays where it would be without, level with the composer's, which
/// is always in the middle. Worked out as it is laid out, so a new width
/// only lays [child] out again.
///
/// It keeps [room] clear at its left (for the conversation's minimap) as
/// long as it is still at least [roomFrom] wide that way, narrower than
/// [maxWidth] if need be; in less width it gives the room up. Its right
/// keeps none: only [right] there, for what floats over it. With the
/// minimap at its right ([roomRight]), the room is kept there instead, and
/// none at its left: its left stays level with the composer's.
class ChatColumn extends SingleChildRenderObjectWidget {
  const ChatColumn({
    super.key,
    required this.maxWidth,
    this.right = 0,
    this.left = 0,
    this.room = 0,
    this.roomFrom = 0,
    this.roomRight = false,
    super.child,
  });

  final double maxWidth;
  final double right;

  /// As [right], at the left: its left no nearer than that to the edge.
  final double left;
  final double room;
  final double roomFrom;
  final bool roomRight;

  @override
  RenderChatColumn createRenderObject(BuildContext context) =>
      RenderChatColumn(maxWidth, right)
        ..left = left
        ..room = room
        ..roomFrom = roomFrom
        ..roomRight = roomRight;

  @override
  void updateRenderObject(BuildContext context, RenderChatColumn renderObject) {
    renderObject
      ..maxWidth = maxWidth
      ..right = right
      ..left = left
      ..room = room
      ..roomFrom = roomFrom
      ..roomRight = roomRight;
  }
}

class RenderChatColumn extends RenderShiftedBox {
  RenderChatColumn(this._maxWidth, this._right) : super(null);

  double get room => _room;
  double _room = 0;
  set room(double value) {
    if (value == _room) return;
    _room = value;
    markNeedsLayout();
  }

  bool get roomRight => _roomRight;
  bool _roomRight = false;
  set roomRight(bool value) {
    if (value == _roomRight) return;
    _roomRight = value;
    markNeedsLayout();
  }

  double get roomFrom => _roomFrom;
  double _roomFrom = 0;
  set roomFrom(double value) {
    if (value == _roomFrom) return;
    _roomFrom = value;
    markNeedsLayout();
  }

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

  double get left => _left;
  double _left = 0;
  set left(double value) {
    if (value == _left) return;
    _left = value;
    markNeedsLayout();
  }

  /// The column's left and width in [width].
  static ({double left, double width}) place(
    double width, {
    required double maxWidth,
    double right = 0,
    double left = 0,
    double room = 0,
    double roomFrom = 0,
    bool roomRight = false,
  }) {
    final centered = math.max(0.0, math.min(maxWidth, width));
    // In the middle, unless that comes within [left] (or the minimap's
    // [room]) of the left edge; the minimap at the right, its room is kept
    // from the right edge alone, as [right] is (the side panel's rail, which
    // it goes under, already keeps as much there).
    final roomy = room > 0 && width - room >= roomFrom;
    final clear = roomy && !roomRight ? math.max(left, room) : left;
    if (roomy && roomRight) right = math.max(right, room);
    final start = math.max((width - centered) / 2, math.min(clear, width));
    final end = math.max(start, (width + centered) / 2);
    return (
      left: start,
      width: math.max(0.0, math.min(end - start, width - right - start)),
    );
  }

  /// [maxWidth], or less in [width] to keep [room] clear either side while
  /// that leaves at least [roomFrom].
  static double roomy(
    double width,
    double maxWidth, {
    required double room,
    required double roomFrom,
  }) {
    final spared = width - 2 * room;
    return room > 0 && spared >= roomFrom
        ? math.min(maxWidth, spared)
        : maxWidth;
  }

  ({double left, double width}) _place(double width) => place(
    width,
    maxWidth: _maxWidth,
    right: _right,
    left: _left,
    room: _room,
    roomFrom: _roomFrom,
    roomRight: _roomRight,
  );

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: _place(constraints.maxWidth).width,
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
      child?.getMinIntrinsicHeight(_place(width).width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(_place(width).width) ?? 0;

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
    final (:left, width: column) = _place(width);
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    // Narrower than the column, in its middle.
    (child.parentData! as BoxParentData).offset = Offset(
      left + (column - child.size.width) / 2,
      0,
    );
    size = constraints.constrain(Size(width, child.size.height));
  }
}

/// What floats over a chat's margin (the side panel's rail): its render
/// object, once laid out ([box]), and news of it moving or changing size, as
/// [ChatRailReport] gives it.
///
/// Where it is is read off [box] against what is under it (as
/// `rail.box.getTransformTo(other)`): in the same units, however the window
/// is zoomed, and at the frame both were laid out in.
class ChatRail extends ChangeNotifier {
  RenderBox? _box;

  /// The rail's, while laid out.
  RenderBox? get box => switch (_box) {
    final box? when box.attached && box.hasSize => box,
    _ => null,
  };

  void _tell(RenderBox box) {
    _box = box;
    notifyListeners();
  }
}

/// [child] as [rail]'s: tells it after each frame [child] moved or changed
/// size in.
class ChatRailReport extends SingleChildRenderObjectWidget {
  const ChatRailReport({super.key, required this.rail, super.child});

  final ChatRail rail;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderChatRailReport(rail);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderChatRailReport).rail = rail;
  }
}

class _RenderChatRailReport extends RenderProxyBox {
  _RenderChatRailReport(this.rail);

  ChatRail rail;
  Rect? _told;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final at = localToGlobal(Offset.zero) & size;
    if (at == _told) return;
    _told = at;
    final rail = this.rail;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) rail._tell(this);
    });
  }
}

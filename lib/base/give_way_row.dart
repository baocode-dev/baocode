import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// One of a [GiveWayRow]'s children.
class GiveWay {
  /// [child] as it is, until the row has no room for it: then [compact] in
  /// its place where there is one, else nothing. [priority] is the order
  /// they give way in, the lowest first (the rightmost of equals); null,
  /// it never does.
  const GiveWay(this.child, {this.priority, this.compact})
    : fill = false,
      minWidth = 0;

  /// The child that takes what the others leave, as [Expanded] does; they
  /// give way before it is narrower than [minWidth].
  const GiveWay.fill(this.child, {this.minWidth = 0})
    : fill = true,
      priority = null,
      compact = null;

  final Widget child;
  final Widget? compact;
  final int? priority;
  final bool fill;
  final double minWidth;
}

/// A row kept within its width: its [GiveWay.fill] child takes what is
/// left, down to its least; past that the others give way, the lowest
/// priority first, to their compact form or gone whole, never cut in half
/// or pushed out of it. Its children are centered across it; what is gone
/// is neither painted nor hit, nor found by a test's finders.
class GiveWayRow extends StatelessWidget {
  const GiveWayRow({super.key, required this.children});

  /// At most one of them [GiveWay.fill].

  final List<GiveWay> children;

  @override
  Widget build(BuildContext context) {
    assert(children.where((item) => item.fill).length <= 1);
    return _GiveWayRow(
      children: [
        for (final (slot, item) in children.indexed) ...[
          _Slot(slot: slot, item: item, compact: false, child: item.child),
          if (item.compact case final compact?)
            _Slot(slot: slot, item: item, compact: true, child: compact),
        ],
      ],
    );
  }
}

class _GiveWayData extends ContainerBoxParentData<RenderBox> {
  int slot = 0;
  bool compact = false;
  GiveWay? item;

  /// Whether it showed at the last layout.
  bool shown = true;
}

class _Slot extends ParentDataWidget<_GiveWayData> {
  const _Slot({
    required this.slot,
    required this.item,
    required this.compact,
    required super.child,
  });

  final int slot;
  final GiveWay item;
  final bool compact;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _GiveWayData;
    if (data.slot == slot &&
        data.compact == compact &&
        data.item?.priority == item.priority &&
        data.item?.fill == item.fill &&
        data.item?.minWidth == item.minWidth) {
      data.item = item;
      return;
    }
    data
      ..slot = slot
      ..compact = compact
      ..item = item;
    if (renderObject.parent case final RenderObject row) row.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => GiveWayRow;
}

class _GiveWayRow extends MultiChildRenderObjectWidget {
  const _GiveWayRow({required super.children});

  @override
  MultiChildRenderObjectElement createElement() => _GiveWayRowElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGiveWayRow();
}

class _GiveWayRowElement extends MultiChildRenderObjectElement {
  _GiveWayRowElement(super.widget);

  /// What gave way is offstage, as an [Offstage]'s child is.
  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    for (final child in children) {
      final data = child.renderObject?.parentData;
      if (data is! _GiveWayData || data.shown) visitor(child);
    }
  }
}

class _RenderGiveWayRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GiveWayData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GiveWayData> {
  /// Whether what never gives way is wider than the row: cut at its end.
  bool _overflows = false;
  final _clip = LayerHandle<ClipRectLayer>();

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GiveWayData) child.parentData = _GiveWayData();
  }

  Iterable<RenderBox> get _children sync* {
    for (
      var child = firstChild;
      child != null;
      child = _data(child).nextSibling
    ) {
      yield child;
    }
  }

  static _GiveWayData _data(RenderBox child) =>
      child.parentData! as _GiveWayData;

  /// Each slot's child as it shows: the slots in order, the fill's null.
  /// [width] is each child's own.
  Map<int, RenderBox?> _pick(
    double maxWidth,
    double Function(RenderBox) width,
  ) {
    final shown = <int, RenderBox?>{};
    final compact = <int, RenderBox>{};
    var used = 0.0;
    for (final child in _children) {
      final data = _data(child);
      final item = data.item!;
      if (item.fill) {
        shown[data.slot] = null;
        used += item.minWidth;
      } else if (data.compact) {
        compact[data.slot] = child;
      } else {
        shown[data.slot] = child;
        used += width(child);
      }
    }
    if (maxWidth.isInfinite) return shown;
    final order =
        [
          for (final MapEntry(key: slot, value: child) in shown.entries)
            if (child != null && _data(child).item!.priority != null) slot,
        ]..sort((a, b) {
          final first = _data(shown[a]!).item!.priority!;
          final second = _data(shown[b]!).item!.priority!;
          return first != second ? first.compareTo(second) : b.compareTo(a);
        });
    for (final slot in order) {
      if (used <= maxWidth + precisionErrorTolerance) break;
      used -= width(shown[slot]!);
      if (compact[slot] case final instead?) {
        shown[slot] = instead;
        used += width(instead);
      } else {
        shown.remove(slot);
      }
    }
    return shown;
  }

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    final before = {
      for (final child in _children)
        if (_data(child).shown) child,
    };
    RenderBox? fill;
    for (final child in _children) {
      final data = _data(child)..shown = false;
      if (data.item!.fill) {
        fill = child;
      } else {
        child.layout(loose, parentUsesSize: true);
      }
    }
    final shown = _pick(maxWidth, (child) => child.size.width);
    final used = shown.values.fold(
      0.0,
      (sum, child) => sum + (child?.size.width ?? 0),
    );
    if (fill != null) {
      final rest = math.max(0.0, maxWidth - used);
      fill.layout(
        maxWidth.isFinite
            ? loose.copyWith(minWidth: rest, maxWidth: rest)
            : loose,
        parentUsesSize: true,
      );
    }
    var height = 0.0;
    for (final child in shown.values) {
      height = math.max(height, (child ?? fill!).size.height);
    }
    size = constraints.constrain(
      Size(
        maxWidth.isFinite ? maxWidth : used + (fill?.size.width ?? 0),
        height,
      ),
    );
    var x = 0.0;
    for (final child in shown.values) {
      final box = child ?? fill!;
      _data(box)
        ..shown = true
        ..offset = Offset(x, (size.height - box.size.height) / 2);
      x += box.size.width;
    }
    _overflows = x > size.width + precisionErrorTolerance;
    // What the screen reader is told of goes by what shows.
    if (before.length != shown.length ||
        !before.every((child) => _data(child).shown)) {
      markNeedsSemanticsUpdate();
    }
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    final sizes = {
      for (final child in _children) child: child.getDryLayout(loose),
    };
    final shown = _pick(constraints.maxWidth, (child) => sizes[child]!.width);
    var width = 0.0;
    var height = 0.0;
    for (final MapEntry(key: child, value: size) in sizes.entries) {
      if (!shown.containsValue(child) && !_data(child).item!.fill) continue;
      width += size.width;
      height = math.max(height, size.height);
    }
    return constraints.constrain(
      Size(constraints.hasBoundedWidth ? constraints.maxWidth : width, height),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var width = 0.0;
    for (final child in _children) {
      final data = _data(child);
      final item = data.item!;
      // The fill at its least; the rest as narrow as they go, gone where
      // they may be.
      if (item.fill) {
        width += item.minWidth;
      } else if (item.priority == null ? !data.compact : data.compact) {
        width += child.getMaxIntrinsicWidth(height);
      }
    }
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var width = 0.0;
    for (final child in _children) {
      if (!_data(child).compact) width += child.getMaxIntrinsicWidth(height);
    }
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _children.fold(
    0.0,
    (height, child) => math.max(height, child.getMinIntrinsicHeight(width)),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => _children.fold(
    0.0,
    (height, child) => math.max(height, child.getMaxIntrinsicHeight(width)),
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_overflows) {
      _clip.layer = null;
      _paintShown(context, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _paintShown,
      oldLayer: _clip.layer,
    );
  }

  void _paintShown(PaintingContext context, Offset offset) {
    for (final child in _children) {
      final data = _data(child);
      if (data.shown) context.paintChild(child, offset + data.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (
      var child = lastChild;
      child != null;
      child = _data(child).previousSibling
    ) {
      final data = _data(child);
      if (!data.shown) continue;
      final box = child;
      if (result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, transformed) =>
            box.hitTest(result, position: transformed),
      )) {
        return true;
      }
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final child in _children) {
      if (_data(child).shown) visitor(child);
    }
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _overflows ? Offset.zero & size : null;

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

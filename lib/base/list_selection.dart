// Selection across a scroll view's items, in place of the scroll view's own.
//
// Under a selection area a scroll view handles the selection of what it
// holds (Flutter's): it keeps a drag's ends with the scroll offset added,
// and takes the offset back off in global units. Under [UiZoom] those are
// not the list's: the ends land the zoom's share of the offset away from
// the pointer (far down a long document, lines away), and a drag reads as
// held past the bottom edge and scrolls the list on. As the chat's history
// does, the ends are kept here as points in items instead, and this does
// what the scroll view's handling would: scroll while a drag is held at an
// edge, and keep the end under the pointer while the list scrolls.

import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'safe_selection_indexes.dart';

/// A selection end: where in item [index] it is.
typedef _ItemPoint = ({int index, Offset local});

/// Selection across the items of the scroll view [child], under a
/// [SelectionArea]; the scroll view puts each item in a [ListSelectionItem].
class ListSelection extends StatefulWidget {
  const ListSelection({
    super.key,
    required this.controller,
    required this.child,
  });

  /// The scroll view's.
  final ScrollController controller;
  final Widget child;

  @override
  State<ListSelection> createState() => _ListSelectionState();
}

class _ListSelectionState extends State<ListSelection> {
  late final _delegate = _ListSelectionDelegate(this);

  /// The items built, by index.
  final Map<int, BuildContext> _items = {};

  int _pointersDown = 0;
  EdgeDraggingAutoScroller? _autoScroller;
  bool _reapplyScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(ListSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scrolled);
      widget.controller.addListener(_scrolled);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrolled);
    _autoScroller?.stopAutoScroll();
    _delegate.dispose();
    super.dispose();
  }

  /// Scrolled with the wheel mid-drag, the text moves under a still
  /// pointer: the end follows once the items scrolled in have registered
  /// (after the frame's own selection updates).
  void _scrolled() {
    if (_pointersDown <= 0 || _reapplyScheduled) return;
    _reapplyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Timer.run(() {
        _reapplyScheduled = false;
        if (mounted && _pointersDown > 0) _delegate.reapplyDragEnd();
      });
    });
  }

  void _pointerUp() {
    if (--_pointersDown > 0) return;
    _pointersDown = 0;
    _autoScroller?.stopAutoScroll();
    _delegate.endDrag();
  }

  /// Scrolls while a drag is held near or past an edge.
  void _autoScrollToward(Offset globalPosition) {
    if (_pointersDown <= 0 || !widget.controller.hasClients) return;
    final scrollable = widget.controller.position.context as ScrollableState;
    if (_autoScroller?.scrollable != scrollable) {
      _autoScroller?.stopAutoScroll();
      _autoScroller = EdgeDraggingAutoScroller(
        scrollable,
        onScrollViewScrolled: _delegate.reapplyDragEnd,
        velocityScalar: 30,
      );
    }
    _autoScroller!.startAutoScrollIfNecessary(
      Rect.fromCenter(center: globalPosition, width: 0, height: 0),
    );
  }

  // --- Points in items ------------------------------------------------------

  /// The items laid out, and their boxes.
  Iterable<(int, RenderBox)> _laidOut() sync* {
    for (final MapEntry(key: index, value: context) in _items.entries) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) yield (index, box);
    }
  }

  /// The item under (or nearest to) [globalPosition], and the point in it.
  _ItemPoint? _locate(Offset globalPosition) {
    _ItemPoint? best;
    var bestDistance = double.infinity;
    for (final (index, box) in _laidOut()) {
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = box.localToGlobal(box.size.bottomLeft(Offset.zero)).dy;
      final distance = globalPosition.dy < top
          ? top - globalPosition.dy
          : globalPosition.dy > bottom
          ? globalPosition.dy - bottom
          : 0.0;
      if (distance < bestDistance) {
        best = (index: index, local: box.globalToLocal(globalPosition));
        bestDistance = distance;
        if (distance == 0) break;
      }
    }
    return best;
  }

  /// Where [point] is now: in its item when that is laid out, else just
  /// past the laid-out items on its side, so all of those on that side are
  /// within the selection.
  Offset? _resolve(_ItemPoint point) {
    (int, RenderBox)? first;
    (int, RenderBox)? last;
    for (final item in _laidOut()) {
      final (index, box) = item;
      if (index == point.index) return box.localToGlobal(point.local);
      if (first == null || index < first.$1) first = item;
      if (last == null || index > last.$1) last = item;
    }
    if (first == null || last == null) return null;
    if (point.index < first.$1) {
      return first.$2.localToGlobal(Offset.zero) - const Offset(0, 1);
    }
    final box = last.$2;
    return box.localToGlobal(box.size.bottomRight(Offset.zero)) +
        const Offset(0, 1);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _pointersDown++,
    onPointerUp: (_) => _pointerUp(),
    onPointerCancel: (_) => _pointerUp(),
    child: SelectionContainer(
      delegate: _delegate,
      child: _ListSelectionScope(
        list: this,
        // The scroll view's own handling stays out of it: its items
        // register here themselves.
        child: SelectionContainer.disabled(child: widget.child),
      ),
    ),
  );
}

class _ListSelectionScope extends InheritedWidget {
  const _ListSelectionScope({required this.list, required super.child});

  final _ListSelectionState list;

  @override
  bool updateShouldNotify(_ListSelectionScope oldWidget) =>
      list != oldWidget.list;
}

/// Item [index] of the scroll view in a [ListSelection]: its text is
/// selectable, the list's selection.
class ListSelectionItem extends StatefulWidget {
  const ListSelectionItem({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<ListSelectionItem> createState() => _ListSelectionItemState();
}

class _ListSelectionItemState extends State<ListSelectionItem> {
  _ListSelectionState? _list;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final list = context
        .dependOnInheritedWidgetOfExactType<_ListSelectionScope>()
        ?.list;
    if (list == _list) return;
    _leave(widget.index);
    _list = list;
    list?._items[widget.index] = context;
  }

  @override
  void didUpdateWidget(ListSelectionItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    _leave(oldWidget.index);
    _list?._items[widget.index] = context;
  }

  void _leave(int index) {
    final items = _list?._items;
    if (items != null && identical(items[index], context)) items.remove(index);
  }

  @override
  void dispose() {
    _leave(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null) return widget.child;
    return SelectionRegistrarScope(
      registrar: list._delegate,
      child: widget.child,
    );
  }
}

/// The selection of a [ListSelection]: its ends as points in items, given
/// to the text as it is now wherever the list has scrolled.
class _ListSelectionDelegate extends StaticSelectionContainerDelegate
    with SafeSelectionIndexes {
  _ListSelectionDelegate(this._list);

  final _ListSelectionState _list;

  _ItemPoint? _start;
  _ItemPoint? _end;

  /// The drag's end, while a drag is under way: given again as the list
  /// scrolls under it.
  SelectionEdgeUpdateEvent? _dragEnd;

  /// The end, start or end, put in the text by an event other than a drag
  /// (a word, all, a key).
  _ItemPoint? _fromGeometry({required bool end}) {
    final index = end ? currentSelectionEndIndex : currentSelectionStartIndex;
    if (index < 0 || index >= selectables.length) return null;
    final selectable = selectables[index];
    final point = end
        ? selectable.value.endSelectionPoint
        : selectable.value.startSelectionPoint;
    if (point == null) return null;
    return _list._locate(
      MatrixUtils.transformPoint(
        selectable.getTransformTo(null),
        point.localPosition - Offset(0, point.lineHeight / 2),
      ),
    );
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    switch (event) {
      case ClearSelectionEvent():
        _start = _end = null;
        _dragEnd = null;
        return super.dispatchSelectionEvent(event);
      case SelectionEdgeUpdateEvent(type: SelectionEventType.startEdgeUpdate):
        _start = _list._locate(event.globalPosition);
        _refreshEdgeLocations();
        return super.dispatchSelectionEvent(event);
      case SelectionEdgeUpdateEvent():
        _end = _list._locate(event.globalPosition);
        _dragEnd = event;
        _refreshEdgeLocations();
        final result = super.dispatchSelectionEvent(event);
        _list._autoScrollToward(event.globalPosition);
        return result;
      case SelectAllSelectionEvent() ||
          SelectWordSelectionEvent() ||
          SelectParagraphSelectionEvent():
        final result = super.dispatchSelectionEvent(event);
        _start = _fromGeometry(end: false);
        _end = _fromGeometry(end: true);
        _dragEnd = null;
        return result;
      case GranularlyExtendSelectionEvent(:final isEnd) ||
          DirectionallyExtendSelectionEvent(:final isEnd):
        _refreshEdgeLocations();
        final result = super.dispatchSelectionEvent(event);
        if (isEnd) {
          _end = _fromGeometry(end: true) ?? _end;
        } else {
          _start = _fromGeometry(end: false) ?? _start;
        }
        return result;
      default:
        return super.dispatchSelectionEvent(event);
    }
  }

  /// [StaticSelectionContainerDelegate] gives text that joins the selection
  /// the ends where they last were, as if nothing moved; in a list it does,
  /// so it is told where they are now.
  void _refreshEdgeLocations() {
    for (final (point, forEnd) in [(_start, false), (_end, true)]) {
      if (point == null) continue;
      if (_list._resolve(point) case final position?) {
        updateLastSelectionEdgeLocation(
          globalSelectionEdgeLocation: position,
          forEnd: forEnd,
        );
      }
    }
  }

  /// Given the ends once the frame's other selection updates are done: text
  /// given new text this frame has none until its own container takes it
  /// in, and an event before that takes it off the list mid-loop (as the
  /// chat's history found).
  @override
  void didChangeSelectables() {
    if (_changePending) return;
    _changePending = true;
    scheduleMicrotask(() {
      _changePending = false;
      if (_disposed) return;
      _refreshEdgeLocations();
      super.didChangeSelectables();
    });
  }

  bool _changePending = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void reapplyDragEnd() {
    final end = _dragEnd;
    if (end == null) return;
    dispatchSelectionEvent(
      SelectionEdgeUpdateEvent.forEnd(
        globalPosition: end.globalPosition,
        granularity: end.granularity,
      ),
    );
  }

  void endDrag() => _dragEnd = null;
}

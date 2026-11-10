import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'finite_selection_edges.dart';

/// The cells of a table that scrolls sideways, selected as text is, and
/// copied a row to a line, its cells apart by tabs (as a spreadsheet takes
/// them).
///
/// Put in the scroll view, the scroll view's own selection handling off
/// ([SelectionContainer.disabled] around it), [registrar] the one around
/// that. Flutter's took a drag to the left or right of the table as one
/// past all of it, and it kept, from one drag to the next, whether the
/// first had begun in the table: a drag in a row, after one across the
/// table, out past the edge selected every row below; one from above the
/// table to beside a row, the whole table. Here an edge beside a row is at
/// that row's end (or start): at the edge of what shows if the drag began
/// in the table, which scrolls on toward it, else past all of the row.
class TableSelection extends StatefulWidget {
  const TableSelection({
    super.key,
    required this.registrar,
    required this.child,
  }) : lines = false;

  /// Lines of code that scroll sideways, the same way, copied a line to a
  /// line (laid out a few to a paragraph). Under Flutter's handling an
  /// edge below the code but left of it (where the text after it begins,
  /// left of the code past its line numbers) was before all of it: a drag
  /// on that text took the code's lines in, or selected nothing.
  const TableSelection.lines({
    super.key,
    required this.registrar,
    required this.child,
  }) : lines = true;

  final SelectionRegistrar? registrar;

  /// The table, each cell in a [TableCellSelection]; or the lines.
  final Widget child;

  final bool lines;

  @override
  State<TableSelection> createState() => _TableSelectionState();
}

class _TableSelectionState extends State<TableSelection> {
  final _delegate = _TableSelectionDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _delegate
      ..scrollable = Scrollable.maybeOf(context)
      ..joinsLines = widget.lines;
    return SelectionContainer(
      registrar: widget.registrar,
      delegate: _delegate,
      child: widget.child,
    );
  }
}

/// A cell of a [TableSelection]'s table: its text one piece to the table,
/// however many pieces it is in (a file link's icon splits it).
class TableCellSelection extends StatefulWidget {
  const TableCellSelection({super.key, required this.child});

  final Widget child;

  @override
  State<TableCellSelection> createState() => _TableCellSelectionState();
}

class _TableCellSelectionState extends State<TableCellSelection> {
  final _delegate = StaticSelectionContainerDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);
}

class _TableSelectionDelegate extends FiniteEdgesDelegate {
  ScrollableState? scrollable;

  /// The selection began in what of the table shows.
  bool _begunWithin = false;

  /// What of the table shows, on screen.
  Rect? get _shown {
    final box = scrollable?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    switch (event) {
      case SelectionEdgeUpdateEvent(
            :final globalPosition,
            :final type,
            :final granularity,
          )
          when globalPosition.isFinite && hasSize:
        final shown = _shown;
        if (shown == null) break;
        final isEnd = type == SelectionEventType.endEdgeUpdate;
        if (!isEnd) _begunWithin = shown.contains(globalPosition);
        final table = MatrixUtils.transformRect(
          getTransformTo(null),
          Offset.zero & containerSize,
        );
        final x = globalPosition.dx;
        final besideRow =
            globalPosition.dy >= table.top &&
            globalPosition.dy <= table.bottom &&
            (x < shown.left || x > shown.right);
        if (!besideRow) {
          _lastStep = null;
          break;
        }
        final position = Offset(
          _begunWithin
              ? x.clamp(shown.left, shown.right)
              : (x > shown.right ? table.right + 1 : table.left - 1),
          globalPosition.dy,
        );
        final result = super.dispatchSelectionEvent(
          isEnd
              ? SelectionEdgeUpdateEvent.forEnd(
                  globalPosition: position,
                  granularity: granularity,
                )
              : SelectionEdgeUpdateEvent.forStart(
                  globalPosition: position,
                  granularity: granularity,
                ),
        );
        // Sent again next frame while it scrolls, to select what came in.
        if (_begunWithin && isEnd && _scrollToward(x, shown)) {
          return SelectionResult.pending;
        }
        _lastStep = null;
        return result;
      case SelectWordSelectionEvent(:final globalPosition) ||
          SelectParagraphSelectionEvent(:final globalPosition):
        _begunWithin = _shown?.contains(globalPosition) ?? false;
      case ClearSelectionEvent() || SelectAllSelectionEvent():
        _begunWithin = false;
        _lastStep = null;
    }
    return super.dispatchSelectionEvent(event);
  }

  /// The frame the table last scrolled in toward an edge held past it.
  Duration? _lastStep;

  /// Scrolls the table a step toward [x], past what [shown]: as Flutter's
  /// scroll views do, the further past the faster, up to 600 points a
  /// second. Whether it scrolls on: not at the end.
  bool _scrollToward(double x, Rect shown) {
    final position = scrollable?.position;
    if (position == null || !position.hasPixels) return false;
    final past = x > shown.right ? x - shown.right : x - shown.left;
    if (past > 0
        ? position.pixels >= position.maxScrollExtent
        : position.pixels <= position.minScrollExtent) {
      return false;
    }
    final scheduler = SchedulerBinding.instance;
    final now = scheduler.currentSystemFrameTimeStamp;
    final last = _lastStep;
    _lastStep = now;
    // The first step as long as a frame; none longer than a few.
    final seconds = last == null
        ? 1 / 60
        : math.min((now - last).inMicroseconds / 1e6, 0.05);
    position.jumpTo(
      (position.pixels + past.clamp(-20, 20) * 30 * seconds).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    // The next frame, to send the edge again in.
    scheduler.ensureVisualUpdate();
    return true;
  }

  @override
  SelectedContent? getSelectedContent() {
    if (joinsLines) return super.getSelectedContent();
    final rows = <List<String>>[];
    Rect? previous;
    for (final cell in selectables) {
      final text = cell.getSelectedContent()?.plainText;
      if (text == null) continue;
      final transform = cell.getTransformTo(null);
      final box = cell.boundingBoxes
          .map((rect) => MatrixUtils.transformRect(transform, rect))
          .fold<Rect?>(null, (all, rect) => all?.expandToInclude(rect) ?? rect);
      // A row's cells all begin at its top.
      final sameRow =
          previous != null &&
          box != null &&
          box.top < previous.bottom &&
          previous.top < box.bottom;
      if (sameRow) {
        rows.last.add(text);
      } else {
        rows.add([text]);
      }
      previous = box ?? previous;
    }
    if (rows.isEmpty) return null;
    return SelectedContent(
      plainText: rows.map((cells) => cells.join('\t')).join('\n'),
    );
  }
}

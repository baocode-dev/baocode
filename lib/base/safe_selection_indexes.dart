import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A selection container that does not fail on where Flutter's own leaves
/// its selection's ends.
///
/// Flutter keeps the index of the text each end of the selection is in, and
/// counts on it to be on its list: an end moved starts its search there, or
/// at the other end's when its own is out of view (a scroll view's). Yet the
/// first text taken off the list leaves the start at -1, the end kept, and a
/// Select All with nothing on the list puts the start at 0: the search then
/// starts nowhere, finds nothing, and fails a null check
/// (`_adjustSelection`), every time the selection is updated, until it is
/// cleared. Such an end is found anew here, from the start of the list.
///
/// Flutter also counts on an end's text to know where the end is once
/// selected (Select All); a scroll view the end is out of view in does not.
/// Such an end is not remembered here.
mixin SafeSelectionIndexes on StaticSelectionContainerDelegate {
  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    final isEnd = event.type == SelectionEventType.endEdgeUpdate;
    final count = selectables.length;
    if (currentSelectionStartIndex >= count) currentSelectionStartIndex = -1;
    if (currentSelectionEndIndex >= count) currentSelectionEndIndex = -1;
    final own = isEnd ? currentSelectionEndIndex : currentSelectionStartIndex;
    if (own != -1) {
      // Where Flutter's search for it starts (`_adjustSelection`).
      final opposite = isEnd
          ? currentSelectionStartIndex
          : currentSelectionEndIndex;
      final ownShown = isEnd
          ? value.endSelectionPoint != null
          : value.startSelectionPoint != null;
      final oppositeShown = isEnd
          ? value.startSelectionPoint != null
          : value.endSelectionPoint != null;
      final from = ownShown ? own : (oppositeShown ? opposite : 0);
      if (from < 0 || from >= count) {
        if (isEnd) {
          currentSelectionEndIndex = -1;
        } else {
          currentSelectionStartIndex = -1;
        }
      }
    }
    return super.handleSelectionEdgeUpdate(event);
  }

  @override
  void didReceiveSelectionBoundaryEvents() {
    final count = selectables.length;
    final start = currentSelectionStartIndex;
    final end = currentSelectionEndIndex;
    if (start < 0 || end < 0 || start >= count || end >= count) return;
    final first = start < end ? start : end;
    final last = start < end ? end : start;
    for (var index = first; index <= last; index++) {
      didReceiveSelectionEventFor(selectable: selectables[index]);
    }
    for (final (index, forEnd) in [(start, false), (end, true)]) {
      final selectable = selectables[index];
      final geometry = selectable.value;
      final point = forEnd
          ? geometry.endSelectionPoint
          : geometry.startSelectionPoint;
      if (!geometry.hasSelection || point == null) continue;
      updateLastSelectionEdgeLocation(
        globalSelectionEdgeLocation: MatrixUtils.transformPoint(
          selectable.getTransformTo(null),
          point.localPosition + Offset(0, -point.lineHeight / 2),
        ),
        forEnd: forEnd,
      );
    }
  }
}

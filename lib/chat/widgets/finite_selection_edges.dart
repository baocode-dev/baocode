import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../base/safe_selection_indexes.dart';

/// The content of a scroll view in the conversation: a selection's edge
/// sent to it always at a point its text can place.
///
/// A selection begun outside a scroll view has an edge past the view sent
/// in as [Offset.infinite], "after all of it" (Flutter's scroll views). In
/// a line's own coordinates that is NaN, and a line cut short to fit (a
/// diff's, ellipsized) cannot tell the edge is after it: it answers that it
/// is before it, and the scroll view keeps the edge. A drag on the text
/// below an open diff then selected nothing, for as long as the diff was
/// open and built, however far above. Here such an edge goes just past the
/// content instead, where every line knows it is after it.
class FiniteSelectionEdges extends StatefulWidget {
  const FiniteSelectionEdges({super.key, required this.child});

  final Widget child;

  @override
  State<FiniteSelectionEdges> createState() => _FiniteSelectionEdgesState();
}

class _FiniteSelectionEdgesState extends State<FiniteSelectionEdges> {
  final _delegate = _FiniteEdgesDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);
}

class _FiniteEdgesDelegate extends StaticSelectionContainerDelegate
    with SafeSelectionIndexes {
  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    if (event
        case SelectionEdgeUpdateEvent(
          :final globalPosition,
          :final granularity,
          :final type,
        )
        when !globalPosition.isFinite && hasSize) {
      final bounds = MatrixUtils.transformRect(
        getTransformTo(null),
        Offset.zero & containerSize,
      );
      // Past the content on the side the edge is (NaN: before it).
      double past(double value, double low, double high) =>
          value.isFinite ? value : (value > 0 ? high + 1 : low - 1);
      final position = Offset(
        past(globalPosition.dx, bounds.left, bounds.right),
        past(globalPosition.dy, bounds.top, bounds.bottom),
      );
      event = type == SelectionEventType.startEdgeUpdate
          ? SelectionEdgeUpdateEvent.forStart(
              globalPosition: position,
              granularity: granularity,
            )
          : SelectionEdgeUpdateEvent.forEnd(
              globalPosition: position,
              granularity: granularity,
            );
    }
    return super.dispatchSelectionEvent(event);
  }
}

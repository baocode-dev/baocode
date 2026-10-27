import 'package:baocode/base/safe_selection_indexes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _Plain extends StaticSelectionContainerDelegate {}

class _Safe extends StaticSelectionContainerDelegate
    with SafeSelectionIndexes {}

/// Selected, and its ends nowhere: as a container whose text is under a
/// transform that cannot be inverted (scaled to nothing) has them.
class _NoPoints extends StaticSelectionContainerDelegate {
  @override
  SelectionGeometry getSelectionGeometry() {
    final geometry = super.getSelectionGeometry();
    return SelectionGeometry(
      status: geometry.status,
      hasContent: geometry.hasContent,
      selectionRects: geometry.selectionRects,
    );
  }
}

Future<void> _show(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SelectionArea(child: child)),
  ),
);

void main() {
  for (final safe in [false, true]) {
    final name = safe ? 'is' : 'is not (Flutter alone)';
    testWidgets('an end moved after a Select All of nothing $name found anew', (
      tester,
    ) async {
      final delegate = safe ? _Safe() : _Plain();
      addTearDown(delegate.dispose);
      await _show(
        tester,
        SelectionContainer(delegate: delegate, child: const SizedBox()),
      );
      Object? failed;
      try {
        delegate.dispatchSelectionEvent(const SelectAllSelectionEvent());
        delegate.dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forStart(globalPosition: Offset.zero),
        );
      } catch (error) {
        failed = error;
      }
      expect(failed, safe ? isNull : isNotNull);
    });

    testWidgets('Select All with text first that cannot place its ends '
        '${safe ? 'holds' : 'fails (Flutter alone)'}', (tester) async {
      final delegate = safe ? _Safe() : _Plain();
      addTearDown(delegate.dispose);
      final inner = _NoPoints();
      addTearDown(inner.dispose);
      await _show(
        tester,
        SelectionContainer(
          delegate: delegate,
          child: Column(
            children: [
              SelectionContainer(
                delegate: inner,
                child: const Text('Text of a box shrunk to nothing.'),
              ),
              const Text('The answer below it.'),
            ],
          ),
        ),
      );
      Object? failed;
      try {
        delegate.dispatchSelectionEvent(const SelectAllSelectionEvent());
      } catch (error) {
        failed = error;
      }
      expect(failed, safe ? isNull : isNotNull);
      if (safe) {
        expect(
          delegate.getSelectedContent()?.plainText,
          contains('The answer below it.'),
        );
      }
    });
  }
}

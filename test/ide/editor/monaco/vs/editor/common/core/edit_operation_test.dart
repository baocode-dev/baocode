import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/edit_operation.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/position.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/range.dart';

void main() {
  test('insert collapses the range and moves markers', () {
    final edit = EditOperation.insert(const Position(3, 5), '😀');
    expect(Range.isEmptyRange(edit.range), isTrue);
    expect(edit.range.startLineNumber, 3);
    expect(edit.range.startColumn, 5);
    expect(edit.text, '😀');
    expect(edit.forceMoveMarkers, isTrue);
  });

  test('delete preserves the range and null text', () {
    final range = Range(1, 2, 2, 3);
    final edit = EditOperation.delete(range);
    expect(edit.range, same(range));
    expect(edit.text, isNull);
    expect(edit.forceMoveMarkers, isNull);
  });

  test('replace preserves nullable text and optional move semantics', () {
    final range = Range(1, 1, 1, 4);
    final replacement = EditOperation.replace(range, 'new');
    expect(replacement.range, same(range));
    expect(replacement.text, 'new');
    expect(replacement.forceMoveMarkers, isNull);
    final move = EditOperation.replaceMove(range, null);
    expect(move.range, same(range));
    expect(move.text, isNull);
    expect(move.forceMoveMarkers, isTrue);
  });
}

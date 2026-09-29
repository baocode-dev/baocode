// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// Cross-checked against pinned textModel.test.ts, model.test.ts,
// modelDecorations.test.ts and modelEditOperation.test.ts (6a598d4a).

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/position.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/range.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/model/text_model.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/model/interval_tree.dart'
    show IntervalNodeOptions;
import 'package:monad/ide/editor/monaco/vs/editor/common/text_model_events.dart';
import 'package:monad/ide/editor/monaco/vs/platform/undo_redo/common/undo_redo_service.dart';

void checkRange(Range? actual, Range expected) {
  expect(actual, isNotNull);
  expect(
    [
      actual!.startLineNumber,
      actual.startColumn,
      actual.endLineNumber,
      actual.endColumn,
    ],
    [
      expected.startLineNumber,
      expected.startColumn,
      expected.endLineNumber,
      expected.endColumn,
    ],
  );
}

void main() {
  test('pinned validatePosition/Range: bounds and surrogate pairs', () {
    final model = TextModel('a📚b\nline two');
    expect(model.validatePosition(const Position(0, 0)).toString(), '(1,1)');
    expect(model.validatePosition(const Position(1, 3)).toString(), '(1,2)');
    expect(model.validatePosition(const Position(1, 4)).toString(), '(1,4)');
    expect(model.validatePosition(const Position(40, 10)).toString(), '(2,9)');
    expect(model.getOffsetAt(const Position(1, 3)), 2);
    expect(model.getPositionAt(999).toString(), '(2,9)');
    expect(model.modifyPosition(const Position(1, 2), 2).toString(), '(1,4)');
    expect(model.isValidRange(Range(1, 3, 1, 3)), isFalse);
    checkRange(model.validateRange(Range(1, 3, 1, 3)), Range(1, 2, 1, 2));
    checkRange(model.validateRange(Range(1, 1, 1, 3)), Range(1, 1, 1, 4));
    checkRange(model.validateRange(Range(1, 3, 1, 5)), Range(1, 2, 1, 5));
    model.dispose();
  });

  test('pinned model EOL, length, snapshot BOM and setValue flush', () {
    final model = TextModel('﻿a\r\nb');
    expect(model.getValue(), 'a\r\nb');
    expect(model.getValue(EndOfLinePreference.lf), 'a\nb');
    expect(model.getValueLength(EndOfLinePreference.crlf, true), 5);
    final snapshot = model.createSnapshot(true);
    expect(snapshot.read(), '﻿a\r\nb');
    expect(snapshot.read(), isNull);
    final old = model.createSnapshot();
    final events = <ModelContentChangedEvent>[];
    model.onDidChangeContent(events.add);
    model.setValue('new');
    expect(old.read(), 'a\r\nb');
    expect(model.getVersionId(), 2);
    expect(model.getAlternativeVersionId(), 2);
    expect(events.single.isFlush, isTrue);
    expect(events.single.changes.single.rangeLength, 4);
    expect(model.createSnapshot().read(), 'new');
    final replacement = TextModel('from snapshot');
    model.setValue(replacement.createSnapshot());
    expect(model.getValue(), 'from snapshot');
    replacement.dispose();
    model.dispose();
  });

  test('pinned model edit operations: descending events, inverse edits, overlap and no-op', () {
    final model = TextModel('abcd\nefgh');
    final events = <ModelContentChangedEvent>[];
    model.onDidChangeContent(events.add);
    final undo = model.applyEdits([
      TextModelEditOperation(Range(1, 2, 1, 3), 'X'),
      TextModelEditOperation(Range(2, 2, 2, 3), 'Y'),
    ], computeUndoEdits: true);
    expect(model.getValue(), 'aXcd\neYgh');
    expect(events.single.changes.map((c) => c.rangeOffset).toList(), [6, 1]);
    expect(undo!.map((e) => e.text).toList(), ['b', 'f']);
    expect(model.getVersionId(), 2);
    expect(
      () => model.applyEdits([
        TextModelEditOperation(Range(1, 1, 1, 3), ''),
        TextModelEditOperation(Range(1, 2, 1, 4), ''),
      ]),
      throwsStateError,
    );
    expect(model.getValue(), 'aXcd\neYgh');
    expect(
      model.applyEdits([TextModelEditOperation(Range(1, 1, 1, 1), '')]),
      isNull,
    );
    expect(model.getVersionId(), 2);
    expect(events.length, 1);
    expect(events.single.detailedReasonsChangeLengths, [2]);
    model.dispose();
  });

  test('pinned decorations retain ranges across edit and EOL and respect stickiness', () {
    final model = TextModel('abc\ndef');
    final events = <String>[];
    model.onDidChangeDecorations(() => events.add('decorations'));
    model.onDidChangeContent((_) => events.add('content'));
    final ids = model.deltaDecorations([], [
      ModelDeltaDecoration(
        Range(1, 2, 1, 3),
        options: const IntervalNodeOptions(
          stickiness: TrackedRangeStickiness.neverGrowsWhenTypingAtEdges,
        ),
      ),
      ModelDeltaDecoration(Range(2, 2, 2, 3)),
    ]);
    expect(ids.length, 2);
    events.clear();
    model.applyEdits([TextModelEditOperation(Range(1, 2, 1, 2), 'Z')]);
    expect(events, ['decorations', 'content']);
    checkRange(model.getDecorationRange(ids.first), Range(1, 3, 1, 4));
    checkRange(model.getDecorationRange(ids.last), Range(2, 2, 2, 3));
    events.clear();
    model.setEOL(EndOfLineSequence.crlf);
    expect(events, ['content']);
    checkRange(model.getDecorationRange(ids.last), Range(2, 2, 2, 3));
    expect(model.getDecorationsInRange(Range(2, 1, 2, 4)).length, 1);
    expect(model.getAllDecorations().length, 2);
    model.deltaDecorations(ids, []);
    expect(model.getDecorationRange(ids.first), isNull);
    model.dispose();
  });

  test(
    'grouped multiline edits undo and redo without flushing decorations',
    () {
      final model = TextModel('one\ntwo\nthree');
      final id = model.deltaDecorations([], [
        ModelDeltaDecoration(Range(3, 1, 3, 6)),
      ], ownerId: 7).single;
      model.pushEditOperations(null, [
        TextModelEditOperation(Range(1, 1, 1, 4), 'FIRST'),
        TextModelEditOperation(Range(2, 1, 2, 4), 'SECOND'),
      ], null);
      model.pushEditOperations(null, [
        TextModelEditOperation(Range(2, 7, 2, 7), '\nmore'),
      ], null);
      expect(model.getValue(), 'FIRST\nSECOND\nmore\nthree');
      expect(model.getAllDecorations(ownerId: 7).single.id, id);
      model.undo();
      expect(model.getValue(), 'one\ntwo\nthree');
      expect(model.getAlternativeVersionId(), 1);
      checkRange(model.getDecorationRange(id), Range(3, 1, 3, 6));
      model.redo();
      expect(model.getValue(), 'FIRST\nSECOND\nmore\nthree');
      checkRange(model.getDecorationRange(id), Range(4, 1, 4, 6));
      model.dispose();
    },
  );

  test('auto whitespace is trimmed on next compatible push, but not on direct edit', () {
    final model = TextModel('');
    model.pushEditOperations(null, [
      TextModelEditOperation(
        Range(1, 1, 1, 1),
        '  ',
        isAutoWhitespaceEdit: true,
      ),
    ], null);
    model.pushEditOperations(null, [
      TextModelEditOperation(Range(1, 3, 1, 3), '\nnext'),
    ], null);
    expect(model.getValue(), '\nnext');
    model.undo();
    expect(model.getValue(), '');
    model.dispose();
  });

  test('unbound models reject a resource undo group', () {
    final model = TextModel('a');
    expect(
      () => model.pushEditOperations(
        null,
        [TextModelEditOperation(Range(1, 2, 1, 2), 'b')],
        null,
        group: UndoRedoGroup(),
      ),
      throwsStateError,
    );
    expect(model.getValue(), 'a');
    expect(model.canUndo(), isFalse);
    model.dispose();
  });

  test('options, language, local undo boundaries and alternative version', () {
    final model = TextModel(
      'abc',
      options: const TextModelOptions(indentSize: null),
    );
    final optionChanges = <ModelOptionsChangedEvent>[];
    model.onDidChangeOptions(optionChanges.add);
    model.updateOptions(tabSize: 2);
    expect(model.getOptions().indentSize, 2);
    expect(optionChanges.single.indentSize, true);
    final languages = <String>[];
    model.onDidChangeLanguage(
      (event) => languages.add('${event.oldLanguage}->${event.newLanguage}'),
    );
    model.setLanguage('dart');
    model.setLanguage('dart');
    expect(languages, ['plaintext->dart']);
    final flags = <String>[];
    model.onDidChangeContent((e) {
      if (e.isUndoing) flags.add('undo');
      if (e.isRedoing) flags.add('redo');
    });
    model.pushEditOperations(null, [
      TextModelEditOperation(Range(1, 4, 1, 4), 'd'),
    ], null);
    model.pushStackElement();
    model.pushEditOperations(null, [
      TextModelEditOperation(Range(1, 5, 1, 5), 'e'),
    ], null);
    expect(model.getValue(), 'abcde');
    model.undo();
    expect(model.getValue(), 'abcd');
    expect(model.getAlternativeVersionId(), 2);
    model.undo();
    expect(model.getValue(), 'abc');
    expect(model.getAlternativeVersionId(), 1);
    model.redo();
    model.redo();
    expect(model.getValue(), 'abcde');
    expect(flags, ['undo', 'undo', 'redo', 'redo']);
    model.pushStackElement();
    model.pushEOL(EndOfLineSequence.crlf);
    expect(model.getEndOfLineSequence(), EndOfLineSequence.crlf);
    model.undo();
    expect(model.getEndOfLineSequence(), EndOfLineSequence.lf);
    model.redo();
    expect(model.getEndOfLineSequence(), EndOfLineSequence.crlf);
    model.dispose();
    expect(() => model.getValue(), throwsStateError);
  });
}

/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/editor/contrib/multicursor/browser/multicursor.ts
// (MultiCursorSession: addSelectionToNextFindMatch / selectAll;
// InsertCursorAtEndOfEachLineSelected) at
// 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviations: there is no find widget/state; a session that starts from a
// non-empty selection searches case-insensitively without whole-word, like
// the find widget defaults. Search is injected by the caller.

import '../../../common/core/position.dart';
import '../../../common/core/range.dart';
import '../../../common/core/selection.dart';
import '../../../common/core/word_character_classifier.dart';
import '../../../common/cursor/cursor_common.dart';
import '../../../common/cursor/cursor_word_operations.dart';

/// Finds the next match of [searchText] at or after [start], wrapping around.
typedef FindNextMatch = Range? Function(
  String searchText,
  Position start, {
  required bool matchCase,
  required bool wholeWord,
});

class MultiCursorSession {
  MultiCursorSession._(
    this.searchText,
    this.wholeWord,
    this.matchCase,
    this.currentMatch,
  );

  /// [selections] are in cursor order, primary first; [valueInRange] reads
  /// the model text of a range with '\n' line breaks.
  static MultiCursorSession? create(
    ICursorSimpleModel model,
    WordCharacterClassifier wordSeparators,
    List<Selection> selections,
    String Function(Range range) valueInRange,
  ) {
    // The exception is the find state disassociation case: when beginning
    // with a single, collapsed selection
    final disconnected = selections.length == 1 && selections.first.isEmpty();
    final wholeWord = disconnected;
    final matchCase = disconnected;
    final s = selections.first;
    String searchText;
    Selection? currentMatch;
    if (s.isEmpty()) {
      // selection is empty => expand to current word
      final word = WordOperations.getWordAtPosition(
        model,
        wordSeparators,
        s.getStartPosition(),
      );
      if (word == null) return null;
      searchText = word.word;
      currentMatch = Selection(
        s.startLineNumber,
        word.startColumn,
        s.startLineNumber,
        word.endColumn,
      );
    } else {
      searchText = valueInRange(s);
    }
    return MultiCursorSession._(searchText, wholeWord, matchCase, currentMatch);
  }

  final String searchText;
  final bool wholeWord;
  final bool matchCase;
  Selection? currentMatch;

  /// The selections after adding the next match, or null if none.
  List<Selection>? addSelectionToNextFindMatch(
    List<Selection> allSelections,
    FindNextMatch findNextMatch,
  ) {
    final nextMatch = _getNextMatch(allSelections, findNextMatch);
    if (nextMatch == null) return null;
    return [...allSelections, nextMatch];
  }

  /// Replaces the last added selection with the next match.
  List<Selection>? moveSelectionToNextFindMatch(
    List<Selection> allSelections,
    FindNextMatch findNextMatch,
  ) {
    final nextMatch = _getNextMatch(allSelections, findNextMatch);
    if (nextMatch == null) return null;
    return [...allSelections.take(allSelections.length - 1), nextMatch];
  }

  Selection? _getNextMatch(
    List<Selection> allSelections,
    FindNextMatch findNextMatch,
  ) {
    final result = currentMatch;
    if (result != null) {
      currentMatch = null;
      return result;
    }
    final lastAddedSelection = allSelections.last;
    final nextMatch = findNextMatch(
      searchText,
      lastAddedSelection.getEndPosition(),
      matchCase: matchCase,
      wholeWord: wholeWord,
    );
    if (nextMatch == null) return null;
    return Selection(
      nextMatch.startLineNumber,
      nextMatch.startColumn,
      nextMatch.endLineNumber,
      nextMatch.endColumn,
    );
  }
}

/// editor.action.insertCursorAtEndOfEachLineSelected (upstream
/// `InsertCursorAtEndOfEachLineSelected.getCursorsForSelection`): a cursor
/// at the end of every line each non-empty selection spans, the last line's
/// at the selection's end unless it ends at column 1.
List<Selection> cursorsAtEndOfEachLineSelected(
  ICursorSimpleModel model,
  List<Selection> selections,
) => [
  for (final selection in selections)
    if (!selection.isEmpty()) ...[
      for (var i = selection.startLineNumber; i < selection.endLineNumber; i++)
        Selection(i, model.getLineMaxColumn(i), i, model.getLineMaxColumn(i)),
      if (selection.endColumn > 1)
        Selection(
          selection.endLineNumber,
          selection.endColumn,
          selection.endLineNumber,
          selection.endColumn,
        ),
    ],
];

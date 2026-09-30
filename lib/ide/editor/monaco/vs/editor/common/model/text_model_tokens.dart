/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/model/textModelTokens.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `TokenizerWithStateStore`, the
// line-oriented part of `TokenizerWithStateStoreAndTextModel`
// (`updateTokensUntilLine`, `tokenizeHeuristically`, `guessStartState`),
// `findLikelyRelevantLines`, `TrackingTokenizationStateStore`,
// `TokenizationStateStore`, `RangePriorityQueueImpl` and `safeTokenize`.
// Deviations: states are vscode-textmate [StateStack]s, the only states
// stored here; the text model is the [ITokenizedLines] subset; a
// `ContiguousMultilineTokensBuilder` is a [TokenLinesBuilder] callback;
// `onUnexpectedError` is [onTokenizationError]; `DefaultBackgroundTokenizer`
// (main-thread idle scheduling) is not ported: the background isolate
// drives tokenization instead (text_mate_worker_tokenizer.dart).

import 'dart:typed_data';

import '../../../../../textmate/vscode_textmate/main.dart' show StateStack;
import '../languages/null_tokenize.dart';
import '../tokens/line_tokens.dart';
import 'fixed_array.dart';

/// `ITokenizationSupport`, for encoded tokenization.
abstract interface class ITokenizationSupport {
  StateStack getInitialState();

  EncodedTokenizationResult<StateStack> tokenizeEncoded(
    String line,
    bool hasEOL,
    StateStack state,
  );
}

/// The text model as tokenization reads it.
abstract interface class ITokenizedLines {
  int getLineCount();

  /// [lineNumber] is one-based.
  String getLineContent(int lineNumber);
}

/// `ContiguousMultilineTokensBuilder.add`: a line's end-offset tokens.
typedef TokenLinesBuilder = void Function(int lineNumber, Uint32List tokens);

/// Where `safeTokenize` reports what upstream's `onUnexpectedError` does.
void Function(Object error, StackTrace stack)? onTokenizationError;

class TokenizerWithStateStore {
  TokenizerWithStateStore(int lineCount, this.tokenizationSupport)
    : _initialState = tokenizationSupport.getInitialState(),
      store = TrackingTokenizationStateStore(lineCount);

  final StateStack _initialState;
  final ITokenizationSupport tokenizationSupport;
  final TrackingTokenizationStateStore store;

  StateStack? getStartState(int lineNumber) =>
      store.getStartState(lineNumber, _initialState);

  ({int lineNumber, StateStack startState})? getFirstInvalidLine() =>
      store.getFirstInvalidLine(_initialState);

  void updateTokensUntilLine(
    ITokenizedLines textModel,
    int languageId,
    TokenLinesBuilder builder,
    int lineNumber,
  ) {
    while (true) {
      final lineToTokenize = getFirstInvalidLine();
      if (lineToTokenize == null || lineToTokenize.lineNumber > lineNumber) {
        break;
      }

      final text = textModel.getLineContent(lineToTokenize.lineNumber);

      final r = safeTokenize(
        languageId,
        tokenizationSupport,
        text,
        true,
        lineToTokenize.startState,
      );
      builder(lineToTokenize.lineNumber, r.tokens);
      store.setEndState(lineToTokenize.lineNumber, r.endState);
    }
  }

  /// The result is not cached.
  ({bool heuristicTokens}) tokenizeHeuristically(
    ITokenizedLines textModel,
    int languageId,
    TokenLinesBuilder builder,
    int startLineNumber,
    int endLineNumber,
  ) {
    if (endLineNumber <= store.getFirstInvalidEndStateLineNumberOrMax()) {
      // nothing to do
      return (heuristicTokens: false);
    }

    if (startLineNumber <= store.getFirstInvalidEndStateLineNumberOrMax()) {
      // tokenization has reached the viewport start...
      updateTokensUntilLine(textModel, languageId, builder, endLineNumber);
      return (heuristicTokens: false);
    }

    var state = _guessStartState(textModel, languageId, startLineNumber);

    for (
      var lineNumber = startLineNumber;
      lineNumber <= endLineNumber;
      lineNumber++
    ) {
      final text = textModel.getLineContent(lineNumber);
      final r = safeTokenize(
        languageId,
        tokenizationSupport,
        text,
        true,
        state,
      );
      builder(lineNumber, r.tokens);
      state = r.endState;
    }

    return (heuristicTokens: true);
  }

  StateStack _guessStartState(
    ITokenizedLines textModel,
    int languageId,
    int lineNumber,
  ) {
    final (:likelyRelevantLines, :initialState) = findLikelyRelevantLines(
      textModel,
      lineNumber,
      this,
    );

    var state = initialState ?? tokenizationSupport.getInitialState();
    for (final line in likelyRelevantLines) {
      final r = safeTokenize(
        languageId,
        tokenizationSupport,
        line,
        false,
        state,
      );
      state = r.endState;
    }
    return state;
  }
}

/// `ITextModel.getLineFirstNonWhitespaceColumn`: 0 for a blank line.
int _lineFirstNonWhitespaceColumn(String line) {
  for (var i = 0; i < line.length; i++) {
    final c = line.codeUnitAt(i);
    if (c != 0x20 && c != 0x09) return i + 1;
  }
  return 0;
}

({List<String> likelyRelevantLines, StateStack? initialState})
findLikelyRelevantLines(
  ITokenizedLines model,
  int lineNumber, [
  TokenizerWithStateStore? store,
]) {
  var nonWhitespaceColumn = _lineFirstNonWhitespaceColumn(
    model.getLineContent(lineNumber),
  );
  final likelyRelevantLines = <String>[];
  StateStack? initialState;
  for (var i = lineNumber - 1; nonWhitespaceColumn > 1 && i >= 1; i--) {
    final line = model.getLineContent(i);
    final newNonWhitespaceIndex = _lineFirstNonWhitespaceColumn(line);
    // Ignore lines full of whitespace
    if (newNonWhitespaceIndex == 0) continue;
    if (newNonWhitespaceIndex < nonWhitespaceColumn) {
      likelyRelevantLines.add(line);
      nonWhitespaceColumn = newNonWhitespaceIndex;
      initialState = store?.getStartState(i);
      if (initialState != null) break;
    }
  }

  return (
    likelyRelevantLines: likelyRelevantLines.reversed.toList(),
    initialState: initialState,
  );
}

/// **Invariant:** if the text model is retokenized from line 1 to
/// [getFirstInvalidEndStateLineNumber] - 1, then the recomputed end state for
/// line l will be equal to [getEndState] (l).
class TrackingTokenizationStateStore {
  TrackingTokenizationStateStore(this._lineCount) {
    _invalidEndStatesLineNumbers.addRange(1, _lineCount + 1);
  }

  int _lineCount;
  final TokenizationStateStore _tokenizationStateStore =
      TokenizationStateStore();
  final RangePriorityQueueImpl _invalidEndStatesLineNumbers =
      RangePriorityQueueImpl();

  StateStack? getEndState(int lineNumber) =>
      _tokenizationStateStore.getEndState(lineNumber);

  /// Whether the end state has changed.
  bool setEndState(int lineNumber, StateStack state) {
    _invalidEndStatesLineNumbers.delete(lineNumber);
    final r = _tokenizationStateStore.setEndState(lineNumber, state);
    if (r && lineNumber < _lineCount) {
      // because the state changed, we cannot trust the next state anymore and
      // have to invalidate it.
      _invalidEndStatesLineNumbers.addRange(lineNumber + 1, lineNumber + 2);
    }

    return r;
  }

  /// `acceptChange(range, newLineCount)`, the range being the one-based,
  /// half-open lines `[startLineNumber, endLineNumberExclusive)`.
  void acceptChange(
    int startLineNumber,
    int endLineNumberExclusive,
    int newLineCount,
  ) {
    final length = endLineNumberExclusive - startLineNumber;
    _lineCount += newLineCount - length;
    _tokenizationStateStore.acceptChange(startLineNumber, length, newLineCount);
    _invalidEndStatesLineNumbers.addRangeAndResize(
      startLineNumber,
      endLineNumberExclusive,
      newLineCount,
    );
  }

  void invalidateEndStateRange(
    int startLineNumber,
    int endLineNumberExclusive,
  ) {
    _invalidEndStatesLineNumbers.addRange(
      startLineNumber,
      endLineNumberExclusive,
    );
  }

  int? getFirstInvalidEndStateLineNumber() => _invalidEndStatesLineNumbers.min;

  /// Upstream's `|| Number.MAX_SAFE_INTEGER` (line numbers start at 1).
  int getFirstInvalidEndStateLineNumberOrMax() =>
      getFirstInvalidEndStateLineNumber() ?? 9007199254740991;

  bool allStatesValid() => _invalidEndStatesLineNumbers.min == null;

  StateStack? getStartState(int lineNumber, StateStack initialState) {
    if (lineNumber == 1) return initialState;
    return getEndState(lineNumber - 1);
  }

  ({int lineNumber, StateStack startState})? getFirstInvalidLine(
    StateStack initialState,
  ) {
    final lineNumber = getFirstInvalidEndStateLineNumber();
    if (lineNumber == null) return null;
    final startState = getStartState(lineNumber, initialState);
    if (startState == null) {
      throw StateError('Start state must be defined');
    }

    return (lineNumber: lineNumber, startState: startState);
  }
}

class TokenizationStateStore {
  final FixedArray<StateStack?> _lineEndStates = FixedArray(null);

  StateStack? getEndState(int lineNumber) => _lineEndStates.get(lineNumber);

  bool setEndState(int lineNumber, StateStack state) {
    final oldState = _lineEndStates.get(lineNumber);
    if (oldState != null && oldState.equals(state)) return false;

    _lineEndStates.set(lineNumber, state);
    return true;
  }

  void acceptChange(int startLineNumber, int length, int newLineCount) {
    if (newLineCount > 0 && length > 0) {
      // Keep the last state, even though it is unrelated. But if the new
      // state happens to agree with this last state, then we know we can stop
      // tokenizing.
      length--;
      newLineCount--;
    }

    _lineEndStates.replace(startLineNumber, length, newLineCount);
  }
}

/// Sorted, disjoint, non-touching half-open ranges, as upstream's
/// `OffsetRange[]`: `(start, endExclusive)` pairs.
class RangePriorityQueueImpl {
  final List<(int, int)> _ranges = [];

  List<(int, int)> getRanges() => _ranges;

  int? get min => _ranges.isEmpty ? null : _ranges[0].$1;

  int? removeMin() {
    if (_ranges.isEmpty) return null;
    final range = _ranges[0];
    if (range.$1 + 1 == range.$2) {
      _ranges.removeAt(0);
    } else {
      _ranges[0] = (range.$1 + 1, range.$2);
    }
    return range.$1;
  }

  void delete(int value) {
    final idx = _ranges.indexWhere((r) => r.$1 <= value && value < r.$2);
    if (idx == -1) return;
    final (start, endExclusive) = _ranges[idx];
    if (start == value) {
      if (endExclusive == value + 1) {
        _ranges.removeAt(idx);
      } else {
        _ranges[idx] = (value + 1, endExclusive);
      }
    } else {
      if (endExclusive == value + 1) {
        _ranges[idx] = (start, value);
      } else {
        _ranges.replaceRange(idx, idx + 1, [
          (start, value),
          (value + 1, endExclusive),
        ]);
      }
    }
  }

  /// `OffsetRange.addRange(range, this._ranges)`.
  void addRange(int start, int endExclusive) {
    var i = 0;
    while (i < _ranges.length && _ranges[i].$2 < start) {
      i++;
    }
    var j = i;
    while (j < _ranges.length && _ranges[j].$1 <= endExclusive) {
      j++;
    }
    if (i == j) {
      _ranges.insert(i, (start, endExclusive));
    } else {
      final newStart = start < _ranges[i].$1 ? start : _ranges[i].$1;
      final newEnd = endExclusive > _ranges[j - 1].$2
          ? endExclusive
          : _ranges[j - 1].$2;
      _ranges.replaceRange(i, j, [(newStart, newEnd)]);
    }
  }

  void addRangeAndResize(int start, int endExclusive, int newLength) {
    var idxFirstMightBeIntersecting = 0;
    while (!(idxFirstMightBeIntersecting >= _ranges.length ||
        start <= _ranges[idxFirstMightBeIntersecting].$2)) {
      idxFirstMightBeIntersecting++;
    }
    var idxFirstIsAfter = idxFirstMightBeIntersecting;
    while (!(idxFirstIsAfter >= _ranges.length ||
        endExclusive < _ranges[idxFirstIsAfter].$1)) {
      idxFirstIsAfter++;
    }
    final delta = newLength - (endExclusive - start);

    for (var i = idxFirstIsAfter; i < _ranges.length; i++) {
      _ranges[i] = (_ranges[i].$1 + delta, _ranges[i].$2 + delta);
    }

    if (idxFirstMightBeIntersecting == idxFirstIsAfter) {
      if (newLength != 0) {
        _ranges.insert(idxFirstMightBeIntersecting, (start, start + newLength));
      }
    } else {
      final first = _ranges[idxFirstMightBeIntersecting].$1;
      final last = _ranges[idxFirstIsAfter - 1].$2;
      final newStart = start < first ? start : first;
      final endEx = endExclusive > last ? endExclusive : last;

      if (newStart != endEx + delta) {
        _ranges.replaceRange(idxFirstMightBeIntersecting, idxFirstIsAfter, [
          (newStart, endEx + delta),
        ]);
      } else {
        _ranges.removeRange(idxFirstMightBeIntersecting, idxFirstIsAfter);
      }
    }
  }

  @override
  String toString() => _ranges.map((r) => '[${r.$1}, ${r.$2})').join(' + ');
}

/// Tokenizes [text] from a clone of [state]; the null tokenization when
/// tokenizing throws. The tokens come back in end-offset form.
EncodedTokenizationResult<StateStack> safeTokenize(
  int languageId,
  ITokenizationSupport? tokenizationSupport,
  String text,
  bool hasEOL,
  StateStack state,
) {
  EncodedTokenizationResult<StateStack>? r;

  if (tokenizationSupport != null) {
    try {
      r = tokenizationSupport.tokenizeEncoded(text, hasEOL, state.clone());
    } catch (e, stack) {
      onTokenizationError?.call(e, stack);
    }
  }

  r ??= nullTokenizeEncoded(languageId, state);

  LineTokens.convertToEndOffset(r.tokens, text.length);
  return r;
}

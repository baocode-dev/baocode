/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/workbench/services/textMate/browser/
// backgroundTokenization/worker/textMateWorkerTokenizer.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971, with the line bookkeeping of
// `MirrorTextModel` it extends.
// Deviations:
// - Changes arrive as whole-line replacements ([acceptChange]) rather than
//   `IModelChangedEvent`s; the state store sees the same line ranges.
// - No state deltas go back: this editor keeps no states outside the
//   worker. No font tokens either.
// - [tokenizeViewport] is VS Code's main-thread viewport tokenization
//   (`TokenizerWithStateStoreAndTextModel.tokenizeHeuristically`) moved into
//   the worker, so the UI isolate never tokenizes; its tokens are marked
//   heuristic and replaced when the background pass reaches them.

import 'dart:async';
import 'dart:typed_data';

import '../../../../../../editor/common/model/text_model_tokens.dart';
import '../../../../../../editor/common/tokens/line_tokens.dart';
import '../../../common/tm_grammar_factory.dart';
import '../../tokenization_support/text_mate_tokenization_support.dart';
import '../../tokenization_support/tokenization_support_with_line_limit.dart';

abstract interface class TextMateModelTokenizerHost {
  Future<ICreateGrammarResult?> getOrCreateGrammar(
    String languageId,
    int encodedLanguageId,
  );

  /// End-offset tokens of the lines tokenized at [versionId];
  /// [heuristic] when they were tokenized from a guessed state.
  void setTokens(
    int versionId,
    List<(int lineNumber, Uint32List tokens)> tokens, {
    bool heuristic = false,
  });
}

class TextMateWorkerTokenizer implements ITokenizedLines {
  TextMateWorkerTokenizer(
    List<String> lines,
    this._versionId,
    this._host,
    this._languageId,
    this._encodedLanguageId,
    this._maxTokenizationLineLength,
  ) : _lines = lines {
    unawaited(_resetTokenization());
  }

  final TextMateModelTokenizerHost _host;
  List<String> _lines;
  int _versionId;
  String _languageId;
  int _encodedLanguageId;
  final int _maxTokenizationLineLength;
  TokenizerWithStateStore? _tokenizerWithStateStore;
  bool _isDisposed = false;
  Timer? _tokenizeDebouncer;
  bool _tokenizing = false;
  (int, int)? _viewport;

  int get versionId => _versionId;

  @override
  int getLineCount() => _lines.length;

  @override
  String getLineContent(int lineNumber) => _lines[lineNumber - 1];

  void dispose() {
    _isDisposed = true;
    _tokenizeDebouncer?.cancel();
  }

  void onLanguageId(String languageId, int encodedLanguageId) {
    _languageId = languageId;
    _encodedLanguageId = encodedLanguageId;
    unawaited(_resetTokenization());
  }

  /// Replaces the lines `[startLineNumber, endLineNumberExclusive)` with
  /// [newLines] (at least one), as of [versionId].
  void acceptChange(
    int versionId,
    int startLineNumber,
    int endLineNumberExclusive,
    List<String> newLines,
  ) {
    _versionId = versionId;
    _lines = [
      ..._lines.sublist(0, startLineNumber - 1),
      ...newLines,
      ..._lines.sublist(endLineNumberExclusive - 1),
    ];
    _tokenizerWithStateStore?.store.acceptChange(
      startLineNumber,
      endLineNumberExclusive,
      newLines.length,
    );
    _scheduleTokenize();
  }

  /// Tokenizes `[startLineNumber, endLineNumberExclusive)` again (all lines
  /// after the theme changed), as upstream's `retokenize`.
  void retokenize(int startLineNumber, int endLineNumberExclusive) {
    final tokenizer = _tokenizerWithStateStore;
    if (tokenizer == null) return;
    tokenizer.store.invalidateEndStateRange(
      startLineNumber,
      endLineNumberExclusive,
    );
    _scheduleTokenize();
  }

  /// Tokens for the visible lines before the background pass reaches them
  /// (once the grammar is loaded, when it is not yet).
  void tokenizeViewport(int startLineNumber, int endLineNumber) {
    _viewport = (startLineNumber, endLineNumber);
    final tokenizer = _tokenizerWithStateStore;
    if (tokenizer == null || _isDisposed) return;
    final end = endLineNumber < _lines.length ? endLineNumber : _lines.length;
    if (startLineNumber > end) return;
    final tokens = <(int, Uint32List)>[];
    final r = tokenizer.tokenizeHeuristically(
      this,
      _encodedLanguageId,
      (lineNumber, lineTokens) => tokens.add((lineNumber, lineTokens)),
      startLineNumber,
      end,
    );
    if (tokens.isNotEmpty) {
      _host.setTokens(_versionId, tokens, heuristic: r.heuristicTokens);
    }
  }

  void _scheduleTokenize() {
    _tokenizeDebouncer?.cancel();
    _tokenizeDebouncer = Timer(const Duration(milliseconds: 10), _tokenize);
  }

  Future<void> _resetTokenization() async {
    _tokenizerWithStateStore = null;

    final languageId = _languageId;
    final encodedLanguageId = _encodedLanguageId;

    final r = await _host.getOrCreateGrammar(languageId, encodedLanguageId);

    if (_isDisposed ||
        languageId != _languageId ||
        encodedLanguageId != _encodedLanguageId ||
        r == null) {
      return;
    }

    final grammar = r.grammar;
    if (grammar != null) {
      final tokenizationSupport = TokenizationSupportWithLineLimit(
        _encodedLanguageId,
        TextMateTokenizationSupport(grammar, r.initialState, false),
        _maxTokenizationLineLength,
      );
      _tokenizerWithStateStore = TokenizerWithStateStore(
        _lines.length,
        tokenizationSupport,
      );
    } else {
      _tokenizerWithStateStore = null;
    }
    if (_viewport case (final start, final end)?) tokenizeViewport(start, end);
    _tokenize();
  }

  void _tokenize() {
    if (_tokenizing) return;
    final tokenizer = _tokenizerWithStateStore;
    if (_isDisposed || tokenizer == null) return;

    final watch = Stopwatch()..start();

    while (true) {
      var tokenizedLines = 0;
      final tokenBuilder = <(int, Uint32List)>[];

      while (true) {
        final lineToTokenize = tokenizer.getFirstInvalidLine();
        if (lineToTokenize == null || tokenizedLines > 200) break;

        tokenizedLines++;

        final text = _lines[lineToTokenize.lineNumber - 1];
        final r = tokenizer.tokenizationSupport.tokenizeEncoded(
          text,
          true,
          lineToTokenize.startState,
        );
        tokenizer.store.setEndState(lineToTokenize.lineNumber, r.endState);

        LineTokens.convertToEndOffset(r.tokens, text.length);
        tokenBuilder.add((lineToTokenize.lineNumber, r.tokens));

        if (watch.elapsedMilliseconds > 20) {
          // yield to check for changes
          break;
        }
      }

      if (tokenizedLines == 0) break;

      _host.setTokens(_versionId, tokenBuilder);

      if (watch.elapsedMilliseconds > 20) {
        // yield to check for changes
        _tokenizing = true;
        Timer.run(() {
          _tokenizing = false;
          _tokenize();
        });
        return;
      }
    }
  }
}

import 'dart:collection';

import 'package:flutter/painting.dart';

import '../vs/editor/standalone/common/monarch/monarch_lexer.dart';
import 'document_snapshot.dart';
import 'language_assets.dart';

class TokenizedLine {
  const TokenizedLine(this.lineNumber, this.tokens, this.endState);

  final int lineNumber;
  final List<Token> tokens;
  final IState endState;
}

class TokenizedDocument {
  const TokenizedDocument(this.snapshot, this.languageId, this.lines);

  final DocumentSnapshot snapshot;
  final String languageId;
  final List<TokenizedLine> lines;
}

/// Runs pinned Monarch definitions across document lines with persistent state.
/// Unchanged prefix lines reuse their tokenization. An unchanged suffix can
/// also be reused once the tokenizer's state converges after an edit. Viewport
/// layout/painting are separate work.
class MonacoSyntaxService {
  MonacoSyntaxService({MonacoLanguageAssets? assets})
    : _assets = assets ?? const MonacoLanguageAssets();

  final MonacoLanguageAssets _assets;
  final Map<String, Future<MonarchTokenizer>> _tokenizers = {};

  String _firstLine(DocumentSnapshot document) {
    final line = document.text.substring(0, document.contentEnds.first);
    // The raw file bridge retains the BOM; Monaco's text buffer extracts it.
    return line.startsWith('﻿') ? line.substring(1) : line;
  }

  /// The tokenizer of [languageId]: a language pack's grammar for it when
  /// one registers it, else the bundled grammar or registration.
  Future<MonarchTokenizer> tokenizerFor(String languageId) =>
      _tokenizers.putIfAbsent(languageId, () async {
        final language = await _assets.loadLanguage(languageId);
        return MonarchTokenizer(language.id, language.compile());
      });

  Future<List<TokenizedLine>?> tokenizeFile(
    DocumentSnapshot document,
    String path,
  ) async {
    final language = await _assets.forPath(
      path,
      firstLine: _firstLine(document),
    );
    return language == null ? null : tokenize(document, language.id);
  }

  Future<TokenizedDocument?> tokenizeFileIncremental(
    DocumentSnapshot document,
    String path, {
    TokenizedDocument? previous,
    bool Function()? isCancelled,
  }) async {
    final language = await _assets.forPath(
      path,
      firstLine: _firstLine(document),
    );
    return language == null
        ? null
        : tokenizeIncremental(
            document,
            language.id,
            previous: previous,
            isCancelled: isCancelled,
          );
  }

  Future<List<TokenizedLine>> tokenize(
    DocumentSnapshot document,
    String languageId,
  ) async => (await tokenizeIncremental(document, languageId)).lines;

  /// Tokenizes [document], reusing [previous] lines outside the edited span.
  ///
  /// Work is time-sliced: after [sliceBudget] of synchronous lexing the call
  /// yields to the event loop so typing and painting stay responsive on large
  /// files. When [isCancelled] returns true at a yield point, the call throws
  /// [TokenizationCancelled] instead of finishing stale work.
  Future<TokenizedDocument> tokenizeIncremental(
    DocumentSnapshot document,
    String languageId, {
    TokenizedDocument? previous,
    bool Function()? isCancelled,
    Duration sliceBudget = const Duration(milliseconds: 6),
  }) async {
    final tokenizer = await tokenizerFor(languageId);
    var state = tokenizer.getInitialState();
    final lines = <TokenizedLine>[];
    // What is reused is kept in plain locals, so the loop reads nothing of
    // the nullable [previous]. Guarded by a promoted boolean instead, Dart
    // 3.13.4's AOT compiler hoisted `previous.…` loads out of the loop and
    // read a null `previous`: release builds crashed opening a file.
    var oldLines = const <TokenizedLine>[];
    // An old line's index minus its new index, in the shared suffix.
    var lineShift = 0;
    // No line is reused from here on unless [previous] shares a suffix.
    var suffixStart = document.lineCount;
    if (previous != null && previous.languageId == languageId) {
      oldLines = previous.lines;
      lineShift = previous.snapshot.lineCount - document.lineCount;
      final (prefixLines, suffixLines) = unchangedLines(
        previous.snapshot,
        document,
      );
      for (var i = 0; i < prefixLines; i++) {
        lines.add(oldLines[i]);
      }
      if (lines.isNotEmpty) {
        state = lines.last.endState as MonarchLineState;
      }
      suffixStart = document.lineCount - suffixLines;
    }
    final watch = Stopwatch()..start();
    for (var i = lines.length; i < document.lineCount; i++) {
      if (watch.elapsed >= sliceBudget) {
        await Future<void>.delayed(Duration.zero);
        if (isCancelled?.call() ?? false) throw const TokenizationCancelled();
        watch.reset();
      }
      if (i >= suffixStart) {
        final oldIndex = i + lineShift;
        final oldState = oldIndex == 0
            ? tokenizer.getInitialState()
            : oldLines[oldIndex - 1].endState;
        if (state.equals(oldState)) {
          for (var j = i; j < document.lineCount; j++) {
            final oldLine = oldLines[j + lineShift];
            lines.add(
              oldLine.lineNumber == j + 1
                  ? oldLine
                  : TokenizedLine(j + 1, oldLine.tokens, oldLine.endState),
            );
          }
          break;
        }
      }
      final text = document.text.substring(
        document.lineStarts[i],
        document.contentEnds[i],
      );
      final result = tokenizer.tokenize(
        text,
        document.newlineLengths[i] > 0,
        state,
      );
      state = result.endState as MonarchLineState;
      lines.add(TokenizedLine(i + 1, result.tokens, state));
    }
    return TokenizedDocument(
      document,
      languageId,
      List<TokenizedLine>.unmodifiable(lines),
    );
  }

  /// Counts whole lines (content and newline) shared at the start and end of
  /// two snapshots, comparing code units in place rather than per-line copies.
  /// The counts never overlap in either snapshot.
  static (int, int) unchangedLines(
    DocumentSnapshot old,
    DocumentSnapshot next,
  ) {
    final a = old.text;
    final b = next.text;
    final shortest = a.length < b.length ? a.length : b.length;
    var prefix = 0;
    while (prefix < shortest && a.codeUnitAt(prefix) == b.codeUnitAt(prefix)) {
      prefix++;
    }
    // A line is shared when its content and newline end within the common
    // prefix, or it is the final line of both texts and they are equal.
    var prefixLines = 0;
    final maxLines = old.lineCount < next.lineCount
        ? old.lineCount
        : next.lineCount;
    while (prefixLines < maxLines) {
      final end =
          old.contentEnds[prefixLines] + old.newlineLengths[prefixLines];
      final nextEnd =
          next.contentEnds[prefixLines] + next.newlineLengths[prefixLines];
      final lastOfBoth =
          prefixLines == old.lineCount - 1 && prefixLines == next.lineCount - 1;
      if (end != nextEnd ||
          old.newlineLengths[prefixLines] != next.newlineLengths[prefixLines]) {
        break;
      }
      if (lastOfBoth ? a != b : end > prefix) break;
      // A shared CR followed by a newly inserted LF would change the newline.
      if (!lastOfBoth &&
          end == prefix &&
          a.codeUnitAt(end - 1) == 0x0D &&
          end < b.length &&
          b.codeUnitAt(end) == 0x0A) {
        break;
      }
      prefixLines++;
    }
    var suffix = 0;
    final maxSuffix = shortest;
    while (suffix < maxSuffix &&
        a.codeUnitAt(a.length - suffix - 1) ==
            b.codeUnitAt(b.length - suffix - 1)) {
      suffix++;
    }
    var suffixLines = 0;
    while (suffixLines < old.lineCount - prefixLines &&
        suffixLines < next.lineCount - prefixLines) {
      final oldLine = old.lineCount - 1 - suffixLines;
      final newLine = next.lineCount - 1 - suffixLines;
      final oldLength =
          old.contentEnds[oldLine] +
          old.newlineLengths[oldLine] -
          old.lineStarts[oldLine];
      final newLength =
          next.contentEnds[newLine] +
          next.newlineLengths[newLine] -
          next.lineStarts[newLine];
      if (oldLength != newLength ||
          old.newlineLengths[oldLine] != next.newlineLengths[newLine]) {
        break;
      }
      // The whole line, and the newline ending the line before it, must be
      // within the common suffix so the line really starts a fresh line.
      final fromEnd = a.length - old.lineStarts[oldLine];
      if (fromEnd > suffix) break;
      if (oldLine > 0 && fromEnd == suffix) {
        final before = old.lineStarts[oldLine] - 1;
        final nextBefore = next.lineStarts[newLine] - 1;
        if (nextBefore < 0 ||
            a.codeUnitAt(before) != b.codeUnitAt(nextBefore)) {
          break;
        }
        // A CRLF split differently (e.g. an inserted CR before LF) differs.
        if (a.codeUnitAt(before) == 0x0A &&
            (before > 0 && a.codeUnitAt(before - 1) == 0x0D) !=
                (nextBefore > 0 && b.codeUnitAt(nextBefore - 1) == 0x0D)) {
          break;
        }
      }
      suffixLines++;
    }
    return (prefixLines, suffixLines);
  }

  /// Convert Monaco start-offset tokens into exact-text Flutter spans.
  /// The caller supplies styles from the active editor theme; this service
  /// does not invent colors or substitute for Monaco's token theme service.
  ///
  /// Lines are converted lazily on first lookup, so only painted lines pay for
  /// span construction. Spans are cached per token list and style function,
  /// so lines reused by incremental tokenization keep identical span lists.
  Map<int, List<TextSpan>> styledLines(
    DocumentSnapshot document,
    List<TokenizedLine> lines,
    TextStyle? Function(String tokenType) styleForToken,
  ) {
    for (final line in lines) {
      final index = line.lineNumber - 1;
      if (index < 0 || index >= document.lineCount) {
        throw RangeError.range(index, 0, document.lineCount - 1);
      }
    }
    return _LazyStyledLines(document, lines, styleForToken, _spanCache);
  }

  final Expando<(Object, String, List<TextSpan>)> _spanCache = Expando();

  /// [code] in the language named [language] (an id or alias), styled a
  /// line at a time; null when no grammar has that name. For code blocks
  /// in hovers (`EditorMarkdownCodeBlockRenderer`).
  Future<List<List<TextSpan>>?> colorize(
    String language,
    String code,
    TextStyle? Function(String tokenType) styleForToken,
  ) async {
    final languageId = await _assets.languageIdForName(language);
    if (languageId == null) return null;
    final document = DocumentSnapshot(code);
    final lines = await tokenize(document, languageId);
    final styled = styledLines(document, lines, styleForToken);
    return [
      for (var line = 1; line <= document.lineCount; line++)
        styled[line] ?? const [],
    ];
  }
}

/// Thrown by [MonacoSyntaxService.tokenizeIncremental] when cancelled.
class TokenizationCancelled implements Exception {
  const TokenizationCancelled();

  @override
  String toString() => 'Tokenization cancelled';
}

class _LazyStyledLines extends MapBase<int, List<TextSpan>> {
  _LazyStyledLines(this._document, this._lines, this._style, this._cache) {
    for (var i = 0; i < _lines.length; i++) {
      _indexByLine[_lines[i].lineNumber] = i;
    }
  }

  final DocumentSnapshot _document;
  final List<TokenizedLine> _lines;
  final TextStyle? Function(String tokenType) _style;
  final Expando<(Object, String, List<TextSpan>)> _cache;
  final Map<int, int> _indexByLine = {};

  @override
  List<TextSpan>? operator [](Object? key) {
    final index = _indexByLine[key];
    if (index == null) return null;
    final line = _lines[index];
    final lineIndex = line.lineNumber - 1;
    final text = _document.text.substring(
      _document.lineStarts[lineIndex],
      _document.contentEnds[lineIndex],
    );
    final cached = _cache[line.tokens];
    if (cached != null && identical(cached.$1, _style) && cached.$2 == text) {
      return cached.$3;
    }
    final spans = <TextSpan>[];
    var previous = 0;
    for (var i = 0; i < line.tokens.length; i++) {
      final token = line.tokens[i];
      final start = token.offset;
      final end = i + 1 < line.tokens.length
          ? line.tokens[i + 1].offset
          : text.length;
      if (start < previous || start < 0 || end < start || end > text.length) {
        throw StateError(
          'Monarch token offsets do not match line ${line.lineNumber}',
        );
      }
      if (start > previous) {
        spans.add(TextSpan(text: text.substring(previous, start)));
      }
      if (end > start) {
        spans.add(
          TextSpan(text: text.substring(start, end), style: _style(token.type)),
        );
      }
      previous = end;
    }
    if (previous < text.length) {
      spans.add(TextSpan(text: text.substring(previous)));
    }
    final result = List<TextSpan>.unmodifiable(spans);
    _cache[line.tokens] = (_style, text, result);
    return result;
  }

  @override
  Iterable<int> get keys => _indexByLine.keys;

  @override
  void operator []=(int key, List<TextSpan> value) =>
      throw UnsupportedError('Styled lines are read-only');

  @override
  void clear() => throw UnsupportedError('Styled lines are read-only');

  @override
  List<TextSpan>? remove(Object? key) =>
      throw UnsupportedError('Styled lines are read-only');
}

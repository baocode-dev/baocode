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

  Future<MonarchTokenizer> tokenizerFor(String languageId) =>
      _tokenizers.putIfAbsent(languageId, () async {
        final direct = (await _assets.availableLanguages()).contains(
          languageId,
        );
        final language = direct
            ? await _assets.load(languageId)
            : await _assets.loadRegistered(languageId);
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
  }) async {
    final language = await _assets.forPath(
      path,
      firstLine: _firstLine(document),
    );
    return language == null
        ? null
        : tokenizeIncremental(document, language.id, previous: previous);
  }

  Future<List<TokenizedLine>> tokenize(
    DocumentSnapshot document,
    String languageId,
  ) async => (await tokenizeIncremental(document, languageId)).lines;

  Future<TokenizedDocument> tokenizeIncremental(
    DocumentSnapshot document,
    String languageId, {
    TokenizedDocument? previous,
  }) async {
    final tokenizer = await tokenizerFor(languageId);
    var state = tokenizer.getInitialState();
    final lines = <TokenizedLine>[];
    if (previous != null && previous.languageId == languageId) {
      final old = previous.snapshot;
      final shared = old.lineCount < document.lineCount
          ? old.lineCount
          : document.lineCount;
      for (var i = 0; i < shared; i++) {
        if (old.newlineLengths[i] != document.newlineLengths[i] ||
            old.text.substring(old.lineStarts[i], old.contentEnds[i]) !=
                document.text.substring(
                  document.lineStarts[i],
                  document.contentEnds[i],
                )) {
          break;
        }
        lines.add(previous.lines[i]);
      }
      if (lines.isNotEmpty) {
        state = lines.last.endState as MonarchLineState;
      }
    }
    var suffixStart = document.lineCount;
    if (previous != null && previous.languageId == languageId) {
      var oldIndex = previous.snapshot.lineCount - 1;
      var newIndex = document.lineCount - 1;
      while (oldIndex >= lines.length && newIndex >= lines.length) {
        final old = previous.snapshot;
        if (old.newlineLengths[oldIndex] != document.newlineLengths[newIndex] ||
            old.text.substring(
                  old.lineStarts[oldIndex],
                  old.contentEnds[oldIndex],
                ) !=
                document.text.substring(
                  document.lineStarts[newIndex],
                  document.contentEnds[newIndex],
                )) {
          break;
        }
        suffixStart = newIndex;
        oldIndex--;
        newIndex--;
      }
    }
    for (var i = lines.length; i < document.lineCount; i++) {
      if (previous != null &&
          previous.languageId == languageId &&
          i >= suffixStart) {
        final oldIndex = i + previous.snapshot.lineCount - document.lineCount;
        final oldState = oldIndex == 0
            ? tokenizer.getInitialState()
            : previous.lines[oldIndex - 1].endState;
        if (state.equals(oldState)) {
          for (var j = i; j < document.lineCount; j++) {
            final oldLine = previous
                .lines[j + previous.snapshot.lineCount - document.lineCount];
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

  /// Convert Monaco start-offset tokens into exact-text Flutter spans.
  /// The caller supplies styles from the active editor theme; this service
  /// does not invent colors or substitute for Monaco's token theme service.
  Map<int, List<TextSpan>> styledLines(
    DocumentSnapshot document,
    List<TokenizedLine> lines,
    TextStyle? Function(String tokenType) styleForToken,
  ) {
    final result = <int, List<TextSpan>>{};
    for (final line in lines) {
      final index = line.lineNumber - 1;
      if (index < 0 || index >= document.lineCount) {
        throw RangeError.range(index, 0, document.lineCount - 1);
      }
      final text = document.text.substring(
        document.lineStarts[index],
        document.contentEnds[index],
      );
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
            TextSpan(
              text: text.substring(start, end),
              style: styleForToken(token.type),
            ),
          );
        }
        previous = end;
      }
      if (previous < text.length) {
        spans.add(TextSpan(text: text.substring(previous)));
      }
      result[line.lineNumber] = List<TextSpan>.unmodifiable(spans);
    }
    return Map<int, List<TextSpan>>.unmodifiable(result);
  }
}

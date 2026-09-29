import 'dart:collection';

import 'package:flutter/painting.dart';

import '../editor/monaco/flutter/document_snapshot.dart';
import '../lsp/lsp_protocol.dart';

/// The foreground of a semantic token under Dark Modern: the theme's
/// `semanticTokenColors` plus the TextMate scopes VS Code's
/// `tokenClassificationRegistry` maps each standard type/modifier to,
/// resolved against Dark+ (`dark_plus.json`) colors. Null leaves the syntax
/// color.
Color? ideSemanticTokenColor(String type, Set<String> modifiers) {
  final readonly = modifiers.contains('readonly');
  return switch (type) {
    'namespace' ||
    'type' ||
    'class' ||
    'enum' ||
    'interface' ||
    'struct' ||
    'typeParameter' => const Color(0xFF4EC9B0),
    'parameter' => const Color(0xFF9CDCFE),
    'variable' ||
    'property' => readonly ? const Color(0xFF4FC1FF) : const Color(0xFF9CDCFE),
    'enumMember' => const Color(0xFF4FC1FF),
    'event' => const Color(0xFF9CDCFE),
    'function' || 'method' || 'decorator' => const Color(0xFFDCDCAA),
    'macro' => const Color(0xFF569CD6),
    'label' => const Color(0xFFC8C8C8),
    'comment' => const Color(0xFF6A9955),
    'string' => const Color(0xFFCE9178),
    'keyword' || 'modifier' => const Color(0xFF569CD6),
    'number' => const Color(0xFFB5CEA8),
    'regexp' => const Color(0xFFD16969),
    'operator' => const Color(0xFFD4D4D4),
    // Dark Modern `semanticTokenColors`.
    'newOperator' => const Color(0xFFC586C0),
    'stringLiteral' => const Color(0xFFCE9178),
    'customLiteral' => const Color(0xFFDCDCAA),
    'numberLiteral' => const Color(0xFFB5CEA8),
    _ => null,
  };
}

/// Semantic tokens of one document version, grouped by zero-based line.
class IdeSemanticTokens {
  IdeSemanticTokens(this.snapshot, List<LspSemanticToken> tokens) {
    for (final token in tokens) {
      if (token.length <= 0) continue;
      final color = ideSemanticTokenColor(token.type, token.modifiers);
      if (color == null) continue;
      _byLine.putIfAbsent(token.line, () => []).add((
        token.character,
        token.character + token.length,
        color,
      ));
    }
    for (final list in _byLine.values) {
      list.sort((a, b) => a.$1.compareTo(b.$1));
    }
  }

  /// The text the tokens describe.
  final DocumentSnapshot snapshot;
  final Map<int, List<(int, int, Color)>> _byLine = {};

  bool get isEmpty => _byLine.isEmpty;

  String _lineText(int line) => snapshot.text.substring(
    snapshot.lineStarts[line],
    snapshot.contentEnds[line],
  );

  /// Syntax spans [base] (keyed by one-based line) recolored by the tokens.
  /// A line whose text differs from the tokens' keeps its syntax colors
  /// until newer tokens arrive, so typing never waits for the server.
  Map<int, List<TextSpan>> overlay(Map<int, List<TextSpan>>? base) =>
      _SemanticStyledLines(this, base);
}

class _SemanticStyledLines extends MapBase<int, List<TextSpan>> {
  _SemanticStyledLines(this._tokens, this._base);

  final IdeSemanticTokens _tokens;
  final Map<int, List<TextSpan>>? _base;
  final Map<int, (List<TextSpan>?, List<TextSpan>?)> _cache = {};

  @override
  List<TextSpan>? operator [](Object? key) {
    if (key is! int) return null;
    final base = _base?[key];
    final line = key - 1;
    final tokens = _tokens._byLine[line];
    if (tokens == null || line >= _tokens.snapshot.lineCount) return base;
    final cached = _cache[key];
    if (cached != null && identical(cached.$1, base)) return cached.$2;
    final result = _recolor(base, _tokens._lineText(line), tokens);
    _cache[key] = (base, result);
    return result;
  }

  static List<TextSpan>? _recolor(
    List<TextSpan>? base,
    String text,
    List<(int, int, Color)> tokens,
  ) {
    final spans = base ?? [TextSpan(text: text)];
    final buffer = StringBuffer();
    for (final span in spans) {
      buffer.write(span.text ?? '');
    }
    if (buffer.toString() != text) return base;
    final result = <TextSpan>[];
    var offset = 0;
    var t = 0;
    for (final span in spans) {
      final spanText = span.text ?? '';
      final spanEnd = offset + spanText.length;
      var at = offset;
      while (at < spanEnd) {
        while (t < tokens.length && tokens[t].$2 <= at) {
          t++;
        }
        final (tokenStart, tokenEnd, color) = t < tokens.length
            ? tokens[t]
            : (spanEnd, spanEnd, const Color(0x00000000));
        if (tokenStart > at) {
          final end = tokenStart < spanEnd ? tokenStart : spanEnd;
          result.add(
            TextSpan(
              text: spanText.substring(at - offset, end - offset),
              style: span.style,
            ),
          );
          at = end;
        } else {
          final end = tokenEnd < spanEnd ? tokenEnd : spanEnd;
          result.add(
            TextSpan(
              text: spanText.substring(at - offset, end - offset),
              style: (span.style ?? const TextStyle()).copyWith(color: color),
            ),
          );
          at = end;
        }
      }
      offset = spanEnd;
    }
    return List.unmodifiable(result);
  }

  @override
  Iterable<int> get keys => {
    ...?_base?.keys,
    for (final line in _tokens._byLine.keys) line + 1,
  };

  @override
  void operator []=(int key, List<TextSpan> value) =>
      throw UnsupportedError('read-only');

  @override
  void clear() => throw UnsupportedError('read-only');

  @override
  List<TextSpan>? remove(Object? key) => throw UnsupportedError('read-only');
}

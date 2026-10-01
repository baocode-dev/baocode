import '../vs/editor/common/languages/language_configuration.dart';
import 'language_assets.dart';

/// Converts Monaco's exported `conf` object (`MonacoLanguage.configuration`,
/// with patterns already revived as [RegExp]) into a [LanguageConfiguration].
///
/// Accepts both shapes Monaco allows: `[open, close]` lists or
/// `{open, close, notIn}` maps for pairs, `notIn` as a string or list, and a
/// line comment as a string or `{comment, noIndent}`. Language packs may also
/// write VS Code's `language-configuration.json` forms: patterns as strings
/// or `{pattern, flags}` and `indentAction` by name. Malformed entries are
/// skipped rather than failing the whole configuration.
LanguageConfiguration languageConfigurationFromMonaco(
  Map<String, Object?> conf,
) {
  final comments = conf['comments'];
  final indentation = conf['indentationRules'];
  final folding = conf['folding'];
  return LanguageConfiguration(
    comments: comments is Map ? _comments(comments) : null,
    brackets: _pairs(conf['brackets']),
    wordPattern: _regExp(conf['wordPattern']),
    indentationRules: indentation is Map
        ? _indentationRules(indentation)
        : null,
    onEnterRules: _list(conf['onEnterRules'], _onEnterRule),
    autoClosingPairs: _list(conf['autoClosingPairs'], _autoClosingPair),
    surroundingPairs: _list(conf['surroundingPairs'], _surroundingPair),
    colorizedBracketPairs: _pairs(conf['colorizedBracketPairs']),
    autoCloseBefore: conf['autoCloseBefore'] as String?,
    folding: folding is Map ? _folding(folding) : null,
  );
}

/// The language configuration of [language], or null when it has none.
LanguageConfiguration? languageConfigurationOf(MonacoLanguage? language) {
  final conf = language?.configuration;
  return conf == null ? null : languageConfigurationFromMonaco(conf);
}

/// Loads the configuration for a file [path] (by filename, extension, or
/// [firstLine]); null when no Monaco language matches.
Future<LanguageConfiguration?> languageConfigurationForPath(
  String path, {
  String? firstLine,
  MonacoLanguageAssets assets = const MonacoLanguageAssets(),
}) async =>
    languageConfigurationOf(await assets.forPath(path, firstLine: firstLine));

CommentRule _comments(Map<Object?, Object?> map) {
  final line = map['lineComment'];
  final block = map['blockComment'];
  LineCommentConfig? lineComment;
  if (line is String && line.isNotEmpty) {
    lineComment = LineCommentConfig(line);
  } else if (line is Map && line['comment'] is String) {
    lineComment = LineCommentConfig(
      line['comment'] as String,
      noIndent: line['noIndent'] == true,
    );
  }
  return CommentRule(lineComment: lineComment, blockComment: _pair(block));
}

CharacterPair? _pair(Object? value) {
  if (value is List &&
      value.length == 2 &&
      value[0] is String &&
      value[1] is String) {
    return (value[0] as String, value[1] as String);
  }
  if (value is Map && value['open'] is String && value['close'] is String) {
    return (value['open'] as String, value['close'] as String);
  }
  return null;
}

List<CharacterPair>? _pairs(Object? value) => _list(value, _pair);

List<T>? _list<T>(Object? value, T? Function(Object?) convert) {
  if (value is! List) return null;
  return [for (final item in value) ?convert(item)];
}

AutoClosingPairConditional? _autoClosingPair(Object? value) {
  final pair = _pair(value);
  if (pair == null || pair.$1.isEmpty || pair.$2.isEmpty) return null;
  final notIn = value is Map ? value['notIn'] : null;
  return AutoClosingPairConditional(
    pair.$1,
    pair.$2,
    notIn: switch (notIn) {
      final String scope => [scope],
      final List<Object?> scopes => scopes.whereType<String>().toList(),
      _ => null,
    },
  );
}

AutoClosingPair? _surroundingPair(Object? value) {
  final pair = _pair(value);
  if (pair == null || pair.$1.isEmpty || pair.$2.isEmpty) return null;
  return AutoClosingPair(pair.$1, pair.$2);
}

/// A revived [RegExp], a pattern string, or VS Code's
/// `{ "pattern": …, "flags": … }` (language packs may use either); an
/// invalid pattern reads as none.
RegExp? _regExp(Object? value) {
  try {
    return switch (value) {
      final RegExp regExp => regExp,
      final String pattern => RegExp(pattern),
      {'pattern': final String pattern} => RegExp(
        pattern,
        caseSensitive: !'${value['flags'] ?? ''}'.contains('i'),
        multiLine: '${value['flags'] ?? ''}'.contains('m'),
        unicode: '${value['flags'] ?? ''}'.contains('u'),
        dotAll: '${value['flags'] ?? ''}'.contains('s'),
      ),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

IndentationRule? _indentationRules(Map<Object?, Object?> map) {
  final decrease = _regExp(map['decreaseIndentPattern']);
  final increase = _regExp(map['increaseIndentPattern']);
  if (decrease == null || increase == null) return null;
  return IndentationRule(
    decreaseIndentPattern: decrease,
    increaseIndentPattern: increase,
    indentNextLinePattern: _regExp(map['indentNextLinePattern']),
    unIndentedLinePattern: _regExp(map['unIndentedLinePattern']),
  );
}

OnEnterRule? _onEnterRule(Object? value) {
  if (value is! Map) return null;
  final before = _regExp(value['beforeText']);
  final action = value['action'];
  if (before == null || action is! Map) return null;
  // Monaco's enum value, or VS Code's name for it (`indentOutdent`).
  final indentAction = switch (action['indentAction']) {
    final int indent when indent >= 0 && indent < 4 =>
      IndentAction.values[indent],
    final String name => IndentAction.values.firstWhere(
      (value) => value.name.toLowerCase() == name.toLowerCase(),
      orElse: () => IndentAction.none,
    ),
    _ => IndentAction.none,
  };
  return OnEnterRule(
    beforeText: before,
    afterText: _regExp(value['afterText']),
    previousLineText: _regExp(value['previousLineText']),
    action: EnterAction(
      indentAction,
      appendText: action['appendText'] as String?,
      removeText: action['removeText'] as int?,
    ),
  );
}

FoldingRules _folding(Map<Object?, Object?> map) {
  final markers = map['markers'];
  FoldingMarkers? folding;
  if (markers is Map) {
    final start = _regExp(markers['start']);
    final end = _regExp(markers['end']);
    if (start != null && end != null) folding = FoldingMarkers(start, end);
  }
  return FoldingRules(offSide: map['offSide'] == true, markers: folding);
}

// Every file the bundled TextMate manifest names must load: grammars through
// vscode-textmate's `parseRawGrammar`, language configurations through the
// repository's port of VS Code's JSONC parser and through the editor's
// configuration loader (flutter/language_configuration_assets.dart). The
// loader is checked against what VS Code keeps of each configuration
// (`LanguageConfigurationFileHandler.extractValidConfig`,
// src/vs/workbench/contrib/codeEditor/common/
// languageConfigurationExtensionPoint.ts at 6a598d4); what it loses is listed
// in [_loaderLosses].

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/language_configuration_assets.dart';
import 'package:bao_editor/monaco/vs/base/common/json.dart' as json;
import 'package:bao_editor/monaco/vs/editor/common/languages/language_configuration.dart';
import 'package:bao_editor/textmate/textmate_manifest.dart';
import 'package:bao_editor/textmate/vscode_textmate/main.dart'
    show parseRawGrammar;

/// What the loader does not keep of a bundled configuration that VS Code
/// keeps. The loader reads Monaco's `action.indentAction` where VS Code's
/// files have `action.indent`, so every on-enter rule that indents or
/// outdents reads as `none`; it also drops pairs and line comments with an
/// empty side, which VS Code keeps.
const _loaderLosses = {
  'grammars/cpp/language-configuration.json': [
    'onEnterRules[0].indent: VS Code outdent, loader none',
  ],
  'grammars/handlebars/language-configuration.json': [
    'onEnterRules[0].indent: VS Code indentOutdent, loader none',
    'onEnterRules[1].indent: VS Code indent, loader none',
  ],
  'grammars/html/language-configuration.json': [
    'onEnterRules[0].indent: VS Code indentOutdent, loader none',
    'onEnterRules[1].indent: VS Code indent, loader none',
  ],
  'grammars/java/language-configuration.json': [
    'onEnterRules[0].indent: VS Code indentOutdent, loader none',
    'onEnterRules[5].indent: VS Code indent, loader none',
  ],
  'grammars/javascript/javascript-language-configuration.json': [
    'surroundingPairs: loader drops [\$, ]',
    'onEnterRules[0].indent: VS Code indentOutdent, loader none',
    'onEnterRules[5].indent: VS Code indent, loader none',
    'onEnterRules[6].indent: VS Code outdent, loader none',
    'onEnterRules[7].indent: VS Code indentOutdent, loader none',
    'onEnterRules[8].indent: VS Code indentOutdent, loader none',
    'onEnterRules[9].indent: VS Code indentOutdent, loader none',
  ],
  'grammars/javascript/tags-language-configuration.json': [
    'onEnterRules[0].indent: VS Code indentOutdent, loader none',
    'onEnterRules[1].indent: VS Code indent, loader none',
    'onEnterRules[2].indent: VS Code indentOutdent, loader none',
    'onEnterRules[3].indent: VS Code indent, loader none',
  ],
  'grammars/latex/latex-cpp-embedded-language-configuration.json': [
    'onEnterRules[0].indent: VS Code outdent, loader none',
  ],
  'grammars/php/language-configuration.json': [
    'onEnterRules[0].indent: VS Code indentOutdent, loader none',
    'onEnterRules[5].indent: VS Code outdent, loader none',
  ],
  'grammars/python/language-configuration.json': [
    'onEnterRules[0].indent: VS Code indent, loader none',
  ],
  'grammars/restructuredtext/language-configuration.json': [
    'onEnterRules[0].indent: VS Code indent, loader none',
  ],
  'grammars/typescript-basics/language-configuration.json': [
    'surroundingPairs: loader drops [\$, ]',
    'onEnterRules[0].indent: VS Code indentOutdent, loader none',
    'onEnterRules[5].indent: VS Code indent, loader none',
    'onEnterRules[6].indent: VS Code outdent, loader none',
    'onEnterRules[7].indent: VS Code indentOutdent, loader none',
    'onEnterRules[8].indent: VS Code indentOutdent, loader none',
    'onEnterRules[9].indent: VS Code indentOutdent, loader none',
  ],
  'grammars/vue/languages/vue-language-configuration.json': [
    'onEnterRules[0].indent: VS Code indentOutdent, loader none',
    'onEnterRules[1].indent: VS Code indent, loader none',
  ],
  'grammars/xml/xsl.language-configuration.json': [
    'comments.lineComment: VS Code "", loader none',
  ],
};

void main() {
  final manifest = TextMateManifest.parse(
    File('$textMateAssetDirectory/manifest.json').readAsStringSync(),
  );
  String read(String path) =>
      File('$textMateAssetDirectory/$path').readAsStringSync();

  test('every grammar parses with parseRawGrammar', () {
    final paths = {for (final grammar in manifest.grammars) grammar.path};
    for (final path in paths) {
      final grammar = parseRawGrammar(read(path), path);
      expect(grammar.scopeName, isNotEmpty, reason: path);
    }
    expect(paths, hasLength(89));
  });

  final configurations = {
    for (final language in manifest.languages) ?language.configuration,
  };

  test('every language configuration parses as VS Code parses it', () {
    for (final path in configurations) {
      final errors = <json.ParseError>[];
      final value = json.parse(read(path), errors);
      expect(errors, isEmpty, reason: path);
      expect(json.getNodeType(value), 'object', reason: path);
    }
    expect(configurations, hasLength(57));
  });

  test('the editor configuration loader takes every language '
      'configuration', () {
    final losses = <String, List<String>>{};
    for (final path in configurations) {
      final raw = json.parse(read(path))! as Map<String, Object?>;
      final expected = _vscodeReading(raw);
      final actual = _loaderReading(languageConfigurationFromMonaco(raw));
      final lost = <String>[];
      for (final key in {...expected.keys, ...actual.keys}) {
        final want = expected[key], got = actual[key];
        if (want is List<String> && got is List<String>) {
          final dropped = [...want.where((e) => !got.contains(e))];
          final added = [...got.where((e) => !want.contains(e))];
          if (dropped.isNotEmpty) {
            lost.add('$key: loader drops ${dropped.join(', ')}');
          }
          if (added.isNotEmpty) {
            lost.add('$key: loader adds ${added.join(', ')}');
          }
        } else if (want != got) {
          lost.add('$key: VS Code ${want ?? 'none'}, loader ${got ?? 'none'}');
        }
      }
      if (lost.isNotEmpty) losses[path] = lost;
    }
    expect(losses, _loaderLosses);
  });
}

/// A configuration as VS Code keeps it (`extractValidConfig`), flattened to
/// comparable strings (lists of them where order does not matter).
Map<String, Object> _vscodeReading(Map<String, Object?> conf) {
  final result = <String, Object>{};
  bool isPair(Object? value) =>
      value is List && value.length == 2 && value.every((e) => e is String);
  String pair(Object? value) => '[${(value! as List).join(', ')}]';
  // `_parseRegex`: a string, or `{pattern, flags}`.
  String? regExp(Object? value) => switch (value) {
    final String pattern => '/$pattern/',
    {'pattern': final String pattern}
        when value['flags'] == null || value['flags'] is String =>
      '/$pattern/${_flags('${value['flags'] ?? ''}')}',
    _ => null,
  };

  final comments = conf['comments'];
  if (comments is Map) {
    final line = comments['lineComment'];
    if (line is String) {
      result['comments.lineComment'] = '"$line"';
    } else if (line is Map && line['comment'] is String) {
      result['comments.lineComment'] =
          '"${line['comment']}"${line['noIndent'] == true ? ' noIndent' : ''}';
    }
    if (isPair(comments['blockComment'])) {
      result['comments.blockComment'] = pair(comments['blockComment']);
    }
  }
  for (final key in ['brackets', 'colorizedBracketPairs']) {
    final pairs = conf[key];
    if (pairs is List) {
      result[key] = [
        for (final p in pairs)
          if (isPair(p)) pair(p),
      ];
    }
  }
  for (final key in ['autoClosingPairs', 'surroundingPairs']) {
    final pairs = conf[key];
    if (pairs is! List) continue;
    result[key] = [
      for (final p in pairs)
        if (isPair(p))
          pair(p)
        else if (p is Map && p['open'] is String && p['close'] is String)
          if (key == 'surroundingPairs' || p['notIn'] == null)
            pair([p['open'], p['close']])
          else if (p['notIn'] is List &&
              (p['notIn'] as List).every((e) => e is String))
            '${pair([p['open'], p['close']])} notIn ${p['notIn']}',
    ];
  }
  if (conf['autoCloseBefore'] case final String before) {
    result['autoCloseBefore'] = before;
  }
  if (conf['wordPattern'] case final Object pattern?) {
    if (regExp(pattern) case final String re) result['wordPattern'] = re;
  }
  if (conf['indentationRules'] case final Map indentation) {
    final decrease = regExp(indentation['decreaseIndentPattern']);
    final increase = regExp(indentation['increaseIndentPattern']);
    // `_mapIndentationRules` needs both.
    if (decrease != null && increase != null) {
      result['indentationRules'] = [
        decrease,
        increase,
        regExp(indentation['indentNextLinePattern']),
        regExp(indentation['unIndentedLinePattern']),
      ].join(' ');
    }
  }
  if (conf['folding'] case final Map folding) {
    final markers = folding['markers'];
    final start = markers is Map ? regExp(markers['start']) : null;
    final end = markers is Map ? regExp(markers['end']) : null;
    result['folding'] =
        'offSide=${folding['offSide'] == true} '
        'markers=${start != null && end != null ? '$start $end' : null}';
  }
  if (conf['onEnterRules'] case final List rules) {
    var index = 0;
    for (final rule in rules) {
      if (rule is! Map || rule['action'] is! Map) continue;
      final action = rule['action'] as Map;
      final indent = action['indent'];
      final before = regExp(rule['beforeText']);
      if (!const [
            'none',
            'indent',
            'indentOutdent',
            'outdent',
          ].contains(indent) ||
          before == null) {
        continue;
      }
      _addOnEnterRule(
        result,
        index++,
        before,
        rule['afterText'] == null ? null : regExp(rule['afterText']),
        rule['previousLineText'] == null
            ? null
            : regExp(rule['previousLineText']),
        indent as String,
        action['appendText'],
        action['removeText'],
      );
    }
    result['onEnterRules.length'] = '$index';
  }
  return result;
}

/// The loader's [LanguageConfiguration], flattened as [_vscodeReading].
Map<String, Object> _loaderReading(LanguageConfiguration conf) {
  String? regExp(RegExp? re) => re == null
      ? null
      : '/${re.pattern}/${_flags([if (!re.isCaseSensitive) 'i', if (re.isMultiLine) 'm', if (re.isDotAll) 's', if (re.isUnicode) 'u'].join())}';
  String pair(String open, String close) => '[$open, $close]';
  final result = <String, Object>{};
  if (conf.comments?.lineComment case final line?) {
    result['comments.lineComment'] =
        '"${line.comment}"${line.noIndent ? ' noIndent' : ''}';
  }
  if (conf.comments?.blockComment case final block?) {
    result['comments.blockComment'] = pair(block.$1, block.$2);
  }
  if (conf.brackets case final brackets?) {
    result['brackets'] = [for (final (a, b) in brackets) pair(a, b)];
  }
  if (conf.colorizedBracketPairs case final pairs?) {
    result['colorizedBracketPairs'] = [for (final (a, b) in pairs) pair(a, b)];
  }
  if (conf.autoClosingPairs case final pairs?) {
    result['autoClosingPairs'] = [
      for (final p in pairs)
        '${pair(p.open, p.close)}${p.notIn != null ? ' notIn ${p.notIn}' : ''}',
    ];
  }
  if (conf.surroundingPairs case final pairs?) {
    result['surroundingPairs'] = [for (final p in pairs) pair(p.open, p.close)];
  }
  if (conf.autoCloseBefore case final before?) {
    result['autoCloseBefore'] = before;
  }
  if (regExp(conf.wordPattern) case final re?) result['wordPattern'] = re;
  if (conf.indentationRules case final rules?) {
    result['indentationRules'] = [
      regExp(rules.decreaseIndentPattern),
      regExp(rules.increaseIndentPattern),
      regExp(rules.indentNextLinePattern),
      regExp(rules.unIndentedLinePattern),
    ].join(' ');
  }
  if (conf.folding case final folding?) {
    final markers = folding.markers;
    result['folding'] =
        'offSide=${folding.offSide} '
        'markers=${markers != null ? '${regExp(markers.start)} ${regExp(markers.end)}' : null}';
  }
  if (conf.onEnterRules case final rules?) {
    for (final (index, rule) in rules.indexed) {
      _addOnEnterRule(
        result,
        index,
        regExp(rule.beforeText)!,
        regExp(rule.afterText),
        regExp(rule.previousLineText),
        rule.action.indentAction.name,
        rule.action.appendText,
        rule.action.removeText,
      );
    }
    result['onEnterRules.length'] = '${rules.length}';
  }
  return result;
}

void _addOnEnterRule(
  Map<String, Object> result,
  int index,
  String before,
  String? after,
  String? previous,
  String indent,
  Object? appendText,
  Object? removeText,
) {
  final key = 'onEnterRules[$index]';
  result['$key.beforeText'] = before;
  if (after != null) result['$key.afterText'] = after;
  if (previous != null) result['$key.previousLineText'] = previous;
  result['$key.indent'] = indent;
  // VS Code keeps only a truthy `appendText`/`removeText`.
  if (appendText is String && appendText.isNotEmpty) {
    result['$key.appendText'] = appendText;
  }
  if (removeText is num && removeText != 0) {
    result['$key.removeText'] = '$removeText';
  }
}

/// The flags that change what a pattern matches in both engines, sorted; `g`
/// and `y` only change how VS Code calls the expression.
String _flags(String flags) =>
    (flags.split('').where('imsu'.contains).toSet().toList()..sort()).join();

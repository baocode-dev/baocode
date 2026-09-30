// The whole TextMate pipeline against VS Code: native Oniguruma, the
// vscode-textmate port, the grammar factory and the color theme loader must
// give every token of every sample, in every bundled theme, the language,
// token type, font style, bracket flag and colors that the real
// vscode-textmate 9.3.2 on vscode-oniguruma 1.7.0 gave it, set up as VS Code
// 6a598d4 sets it up (tool/generate_textmate_fixtures.mjs).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/workbench/services/text_mate/browser/text_mate_tokenization_feature_impl.dart';
import 'package:monad/ide/editor/monaco/vs/workbench/services/text_mate/common/tm_grammar_factory.dart';
import 'package:monad/ide/editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:monad/ide/editor/textmate/oniguruma/onig_lib.dart';
import 'package:monad/ide/editor/textmate/textmate_manifest.dart';
import 'package:monad/ide/editor/textmate/vscode_textmate/main.dart';

const _fixtures = 'test/fixtures/textmate';

Future<String> _readAsset(String path) =>
    File('$textMateAssetRoot/$path').readAsString();

class _Host implements ITMGrammarFactoryHost {
  @override
  void logTrace(String msg) {}

  @override
  void logError(String msg, Object? err) => fail('$msg: $err');

  @override
  Future<String> readFile(String resource) => _readAsset(resource);
}

/// strings.ts `splitLines`, as the text model splits.
List<String> _splitLines(String text) => text.split(RegExp(r'\r\n|\r|\n'));

/// `nullTokenizeEncoded` (nullTokenize.ts): one token, default colors.
Uint32List _nullTokenizeEncoded(int languageId) =>
    Uint32List.fromList([0, languageId | (1 << 15) | (2 << 24)]);

/// The editor's per-line loop: `TokenizationSupportWithLineLimit` around
/// `TextMateTokenizationSupport.tokenizeEncoded`.
List<Uint32List> _tokenizeLines(
  IGrammar grammar,
  List<String> lines,
  int languageId,
) {
  var state = INITIAL;
  return [
    for (final line in lines)
      if (line.length >= maxTokenizationLineLength)
        _nullTokenizeEncoded(languageId)
      else
        () {
          final result = grammar.tokenizeLine2(
            line,
            state,
            tokenizationTimeLimitMs,
          );
          if (result.stoppedEarly) {
            fail('Time limit reached tokenizing: ${line.substring(0, 100)}');
          }
          if (!state.equals(result.ruleStack)) state = result.ruleStack;
          return result.tokens;
        }(),
  ];
}

/// A line's tokens as the fixture writes them: seven fields per token.
List<Object?> _decode(Uint32List tokens, List<String> colorMap) => [
  for (var i = 0; i < tokens.length; i += 2) ...[
    tokens[i],
    EncodedTokenAttributes.getLanguageId(tokens[i + 1]),
    EncodedTokenAttributes.getTokenType(tokens[i + 1]),
    EncodedTokenAttributes.getFontStyle(tokens[i + 1]),
    EncodedTokenAttributes.containsBalancedBrackets(tokens[i + 1]) ? 1 : 0,
    colorMap[EncodedTokenAttributes.getForeground(tokens[i + 1])],
    colorMap[EncodedTokenAttributes.getBackground(tokens[i + 1])],
  ],
];

void main() {
  late Map<String, Object?> fixture;
  late Map<String, int> languageIds;
  late TextMateManifest manifest;
  late TMGrammarFactory factory;
  final grammars = <String, IGrammar>{};

  setUpAll(() async {
    fixture = jsonDecode(
      File('$_fixtures/typescript_tokens.json').readAsStringSync(),
    ) as Map<String, Object?>;
    languageIds = (fixture['languageIds']! as Map).cast<String, int>();
    manifest = await TextMateManifest.load(_readAsset);
    final onigLib = loadNativeOnigLib();
    if (onigLib == null) fail('Oniguruma did not load');
    factory = TMGrammarFactory(_Host(), [
      for (final grammar in manifest.grammars)
        ?validateGrammarDefinition(
          grammar,
          isRegisteredLanguageId: languageIds.containsKey,
          encodeLanguageId: (language) => languageIds[language]!,
          sourceExtensionId: 'vscode.${grammar.extension}',
        ),
    ], Future.value(onigLib));
  });

  tearDownAll(() => factory.dispose());

  Future<IGrammar> grammarFor(String language) async => grammars[language] ??=
      (await factory.createGrammar(language, languageIds[language]!)).grammar!;

  /// Sets [themeId] as VS Code's `_updateTheme` does; the color map after.
  Future<List<String>> setTheme(String themeId) async {
    final contribution = manifest.themeById(themeId)!;
    final theme = ColorThemeData.fromExtensionTheme(
      contribution,
      contribution.assetPath,
      extensionId: contribution.extensionId,
    );
    await theme.ensureLoaded(_readAsset);
    factory.setTheme(toRawTheme(theme), theme.tokenColorMap);
    return factory.getColorMap();
  }

  test('every sample in every theme tokenizes as in VS Code', () async {
    final samples = {
      for (final sample in (fixture['samples']! as List).cast<Map>())
        sample['name'] as String: sample,
    };
    final cases = (fixture['cases']! as List).cast<Map<String, Object?>>();
    final byTheme = <String, List<Map<String, Object?>>>{};
    for (final c in cases) {
      (byTheme[c['theme']! as String] ??= []).add(c);
    }

    final mismatches = <String>[];
    var tokens = 0;
    for (final MapEntry(key: themeId, value: themeCases) in byTheme.entries) {
      final colorMap = await setTheme(themeId);
      for (final c in themeCases) {
        final sample = samples[c['sample']]!;
        final language = sample['language']! as String;
        final text = File('$_fixtures/${sample['path']}').readAsStringSync();
        final actual = _tokenizeLines(
          await grammarFor(language),
          _splitLines(text),
          languageIds[language]!,
        );
        final expected = c['sameAs'] != null
            ? cases.firstWhere(
                    (other) =>
                        other['sample'] == c['sample'] &&
                        other['theme'] == c['sameAs'],
                  )['lines']!
                  as List
            : c['lines']! as List;
        expect(actual.length, expected.length, reason: '${c['sample']}');
        for (var line = 0; line < expected.length; line++) {
          final want = expected[line] as List;
          final got = _decode(actual[line], colorMap);
          tokens += want.length ~/ 7;
          if (!_listEquals(want, got) && mismatches.length < 20) {
            mismatches.add(
              '${c['sample']} [$themeId] line ${line + 1}\n'
              '  want $want\n'
              '  got  $got',
            );
          }
        }
      }
    }
    printOnFailure('$tokens tokens compared');
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
    // ignore: avoid_print
    print(
      'TextMate parity: $tokens tokens, ${cases.length} cases, '
      '${byTheme.length} themes',
    );
  });

  test('the benchmark file tokenizes as in VS Code, and how fast', () async {
    final bench = fixture['bench']! as Map<String, Object?>;
    final colorMap = await setTheme(bench['theme']! as String);
    final language = bench['language']! as String;
    final grammar = await grammarFor(language);
    final lines = _splitLines(
      File('$_fixtures/${bench['path']}').readAsStringSync(),
    );

    final timings = <int>[];
    late List<Uint32List> actual;
    for (var run = 0; run < 11; run++) {
      final watch = Stopwatch()..start();
      actual = _tokenizeLines(grammar, lines, languageIds[language]!);
      timings.add(watch.elapsedMicroseconds);
    }

    final expected = bench['lines']! as List;
    expect(actual.length, expected.length);
    for (var line = 0; line < expected.length; line++) {
      expect(
        _decode(actual[line], colorMap),
        expected[line],
        reason: 'line ${line + 1}',
      );
    }

    final first = timings.first;
    final warm = timings.skip(1).toList()..sort();
    // ignore: avoid_print
    print(
      'TextMate ${bench['name']} (${lines.length} lines): '
      'first ${first ~/ 1000} ms, warm best ${warm.first ~/ 1000} ms, '
      'median ${warm[warm.length ~/ 2] ~/ 1000} ms',
    );
  });
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

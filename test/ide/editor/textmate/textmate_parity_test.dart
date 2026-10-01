// The whole TextMate pipeline against VS Code, for every built-in language:
// native Oniguruma, the vscode-textmate port, the grammar factory with every
// bundled grammar and the color theme loader must give every line of every
// colorize sample (and of an extra sample for each language without one) the
// scopes and, in every bundled theme, the binary tokens
// (offsets and metadata: language, token type, font style, bracket flag and
// color indices into an identical color map) that the real vscode-textmate
// 9.3.2 on vscode-oniguruma 1.7.0 gave it, set up as VS Code 6a598d4 sets it
// up (tool/generate_textmate_fixtures.mjs, which also checked those against
// VS Code's own colorize results).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/workbench/services/text_mate/browser/text_mate_tokenization_feature_impl.dart';
import 'package:baocode/ide/editor/monaco/vs/workbench/services/text_mate/common/tm_grammar_factory.dart';
import 'package:baocode/ide/editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:baocode/ide/editor/textmate/oniguruma/onig_lib.dart';
import 'package:baocode/ide/editor/textmate/textmate_manifest.dart';
import 'package:baocode/ide/editor/textmate/vscode_textmate/main.dart';

import 'textmate_fixture.dart';

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
  int maxLineLength,
) {
  var state = INITIAL;
  return [
    for (final line in lines)
      if (line.length >= maxLineLength)
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

/// `tokenizeLine`'s tokens as the fixture writes them.
List<int> _scopes(ITokenizeLineResult result, Map<String, int> scopeIndex) => [
  for (final token in result.tokens) ...[
    token.startIndex,
    token.endIndex,
    scopeIndex[token.scopes.join(' ')] ?? -1,
  ],
];

void main() {
  final fixture = loadTextMateFixture();
  final samples = (fixture['samples']! as List).cast<Map<String, Object?>>();
  final colorMaps = (fixture['colorMaps']! as Map).cast<String, List>();
  late TextMateManifest manifest;
  // LanguageIdCodec: the manifest's languages numbered from 1.
  late Map<String, int> languageIds;
  late TMGrammarFactory factory;
  final grammars = <String, IGrammar>{};

  setUpAll(() async {
    manifest = await TextMateManifest.load(_readAsset);
    languageIds = {
      for (final (index, id) in manifest.languageIds.indexed) id: index + 1,
    };
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
    // vscode-textmate keeps one grammar per scope name, made with the
    // language id of the first request (ini and properties share
    // source.ini): request them in the generator's order.
    for (final language in (fixture['grammarOrder']! as List).cast<String>()) {
      grammars[language] = (await factory.createGrammar(
        language,
        languageIds[language]!,
      )).grammar!;
    }
  });

  tearDownAll(() => factory.dispose());

  String sampleText(Map<String, Object?> sample) =>
      File('$textMateFixtures/${sample['path']}').readAsStringSync();

  /// Sets [themeId] as VS Code's `_updateTheme` does; checks the color map
  /// the tokens' color indices refer to.
  Future<void> setTheme(String themeId) async {
    final contribution = manifest.themeById(themeId)!;
    final theme = ColorThemeData.fromExtensionTheme(
      contribution,
      contribution.assetPath,
      extensionId: contribution.extensionId,
    );
    await theme.ensureLoaded(_readAsset);
    factory.setTheme(toRawTheme(theme), theme.tokenColorMap);
    final expected = colorMaps[themeId]!;
    final actual = factory.getColorMap();
    expect(actual.length, expected.length, reason: '$themeId color map');
    for (var i = 1; i < expected.length; i++) {
      expect(actual[i], expected[i], reason: '$themeId color $i');
    }
  }

  test('language ids follow the manifest registration order', () {
    expect(fixture['revision'], manifest.revision);
    expect(languageIds, fixture['languageIds']);
    expect(languageIds['plaintext'], 1);
    expect(
      fixture['defaultMaxTokenizationLineLength'],
      maxTokenizationLineLength,
    );
    expect(fixture['timeLimitMs'], tokenizationTimeLimitMs);
  });

  group('scopes (tokenizeLine)', () {
    for (final sample in samples) {
      test('${sample['name']} as ${sample['language']}', () {
        final grammar = grammars[sample['language']]!;
        final scopeTable = (sample['scopeTable']! as List).cast<String>();
        final scopeIndex = {
          for (final (index, scopes) in scopeTable.indexed) scopes: index,
        };
        final expected = sample['scopes']! as List;
        final lines = _splitLines(sampleText(sample));
        expect(lines.length, expected.length);
        StateStack? state;
        for (var line = 0; line < lines.length; line++) {
          final result = grammar.tokenizeLine(lines[line], state);
          state = result.ruleStack;
          final actual = _scopes(result, scopeIndex);
          if (!_listEquals(actual, expected[line] as List)) {
            fail(
              'line ${line + 1}\n'
              '  want ${_describeScopes(expected[line] as List, scopeTable)}\n'
              '  got  ${[for (final t in result.tokens) '${t.startIndex}-${t.endIndex} ${t.scopes.join(' ')}']}',
            );
          }
        }
      });
    }
  });

  group('binary tokens (the editor loop)', () {
    // The fixture's themes the assets still bundle.
    final bundled = TextMateManifest.parse(
      File('$textMateAssetRoot/manifest.json').readAsStringSync(),
    );
    for (final themeId in colorMaps.keys) {
      if (bundled.themeById(themeId) == null) continue;
      test(themeId, () async {
        await setTheme(themeId);
        final mismatches = <String>[];
        var tokens = 0;
        var cases = 0;
        for (final sample in samples) {
          final sampleCases = sample['cases']! as Map<String, Object?>;
          var expected = sampleCases[themeId];
          if (expected == null) continue;
          if (expected is Map) expected = sampleCases[expected['sameAs']];
          expected as List;
          final language = sample['language']! as String;
          final maxLineLength =
              manifest.maxTokenizationLineLengthOf(language) ??
              maxTokenizationLineLength;
          expect(sample['maxTokenizationLineLength'], maxLineLength);
          final actual = _tokenizeLines(
            grammars[language]!,
            _splitLines(sampleText(sample)),
            languageIds[language]!,
            maxLineLength,
          );
          cases++;
          expect(actual.length, expected.length, reason: '${sample['name']}');
          for (var line = 0; line < expected.length; line++) {
            final want = expected[line] as List;
            tokens += want.length ~/ 2;
            if (!_listEquals(actual[line], want) && mismatches.length < 20) {
              mismatches.add(
                '${sample['name']} line ${line + 1}\n'
                '  want $want\n'
                '  got  ${actual[line]}',
              );
            }
          }
        }
        expect(mismatches, isEmpty, reason: mismatches.join('\n'));
        // ignore: avoid_print
        print('TextMate parity [$themeId]: $tokens tokens, $cases samples');
      });
    }
  });

  test('the benchmark file tokenizes as in VS Code, and how fast', () async {
    final bench = fixture['bench']! as Map<String, Object?>;
    await setTheme(bench['theme']! as String);
    final language = bench['language']! as String;
    final grammar = grammars[language]!;
    final lines = _splitLines(
      File('$textMateFixtures/${bench['path']}').readAsStringSync(),
    );

    final timings = <int>[];
    late List<Uint32List> actual;
    for (var run = 0; run < 11; run++) {
      final watch = Stopwatch()..start();
      actual = _tokenizeLines(
        grammar,
        lines,
        languageIds[language]!,
        maxTokenizationLineLength,
      );
      timings.add(watch.elapsedMicroseconds);
    }

    final expected = bench['tokens']! as List;
    expect(actual.length, expected.length);
    for (var line = 0; line < expected.length; line++) {
      expect(actual[line], expected[line], reason: 'line ${line + 1}');
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

  test('the colorize-results cross-check found no differences', () {
    final check = fixture['colorizeCheck']! as Map<String, Object?>;
    expect(check['mismatches'], isEmpty);
    expect(check['rejectedGrammars'], isEmpty);
    expect(check['tokens'], greaterThan(0));
  });
}

List<String> _describeScopes(List<Object?> flat, List<String> table) => [
  for (var i = 0; i < flat.length; i += 3)
    '${flat[i]}-${flat[i + 1]} ${table[flat[i + 2]! as int]}',
];

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

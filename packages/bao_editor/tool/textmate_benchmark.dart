// Throughput benchmark for TextMate tokenization: native Oniguruma, the
// vscode-textmate port and VS Code's grammar setup, on the large TypeScript
// file tool/generate_textmate_fixtures.mjs also times on node.
//
// Not part of the test suite. Run with:
//   dart run tool/textmate_benchmark.dart
// or AOT (the native library is bundled beside the executable):
//   dart build cli -t tool/textmate_benchmark.dart -o /tmp/textmate_bench
//   /tmp/textmate_bench/bundle/bin/textmate_benchmark
// from the repository root.

import 'dart:io';

import 'package:bao_editor/monaco/vs/workbench/services/text_mate/browser/text_mate_tokenization_feature_impl.dart';
import 'package:bao_editor/monaco/vs/workbench/services/text_mate/common/tm_grammar_factory.dart';
import 'package:bao_editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:bao_editor/textmate/oniguruma/onig_lib.dart';
import 'package:bao_editor/textmate/textmate_manifest.dart';
import 'package:bao_editor/textmate/vscode_textmate/main.dart';

const _sample = 'test/fixtures/textmate/samples/bench/textModel.ts';
const _theme = 'Dark+';
const _rounds = 10;

Future<String> _readAsset(String path) =>
    File('$textMateAssetDirectory/$path').readAsString();

class _Host implements ITMGrammarFactoryHost {
  @override
  void logTrace(String msg) {}

  @override
  void logError(String msg, Object? err) => stderr.writeln('$msg: $err');

  @override
  Future<String> readFile(String resource) => _readAsset(resource);
}

Future<void> main() async {
  final onigLib = loadNativeOnigLib();
  if (onigLib == null) {
    stderr.writeln('Oniguruma did not load');
    exitCode = 1;
    return;
  }
  const languageIds = {'typescript': 2};
  final manifest = await TextMateManifest.load(_readAsset);
  final factory = TMGrammarFactory(_Host(), [
    for (final grammar in manifest.grammars)
      ?validateGrammarDefinition(
        grammar,
        isRegisteredLanguageId: languageIds.containsKey,
        encodeLanguageId: (language) => languageIds[language]!,
        sourceExtensionId: 'vscode.${grammar.extension}',
      ),
  ], Future.value(onigLib));
  final contribution = manifest.themeById(_theme)!;
  final theme = ColorThemeData.fromExtensionTheme(
    contribution,
    contribution.assetPath,
    extensionId: contribution.extensionId,
  );
  await theme.ensureLoaded(_readAsset);
  factory.setTheme(toRawTheme(theme), theme.tokenColorMap);
  final grammar = (await factory.createGrammar('typescript', 2)).grammar!;

  final lines = File(_sample).readAsStringSync().split(RegExp(r'\r\n|\r|\n'));

  int tokenize() {
    final watch = Stopwatch()..start();
    var state = INITIAL;
    var tokens = 0;
    for (final line in lines) {
      final result = grammar.tokenizeLine2(line, state);
      tokens += result.tokens.length ~/ 2;
      if (!state.equals(result.ruleStack)) state = result.ruleStack;
    }
    if (tokens == 0) throw StateError('No tokens');
    return watch.elapsedMicroseconds;
  }

  final first = tokenize();
  final warm = [for (var i = 0; i < _rounds; i++) tokenize()]..sort();
  stdout.writeln(
    '$_sample (${lines.length} lines, $_theme): first ${first ~/ 1000} ms, '
    'warm best ${warm.first ~/ 1000} ms, median ${warm[_rounds ~/ 2] ~/ 1000} ms',
  );
  factory.dispose();
}

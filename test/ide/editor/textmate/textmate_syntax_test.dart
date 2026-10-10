// The editor's TextMate highlighting through its worker: documents tokenized
// in the background and kept up to date through edits must end up with the
// tokens of tokenizing their text from the start, and the service must pick
// VS Code's language for a file unless a language pack claims it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/vs/editor/common/tokens/contiguous_tokens_store.dart';
import 'package:bao_editor/monaco/vs/editor/common/tokens/line_tokens.dart';
import 'package:bao_editor/textmate/textmate_syntax.dart';
import 'package:bao_editor/textmate/textmate_worker.dart';
import 'package:baocode/theme/workbench_theme.dart';

import '../../../flutter_test_config.dart' show testColorTheme;
import 'textmate_fixture.dart';

class _Codec implements ILanguageIdCodec {
  _Codec(this.id);

  final int id;

  @override
  int encodeLanguageId(String languageId) => id;

  @override
  String decodeLanguageId(int languageId) => 'language';
}

List<String> _lines(DocumentSnapshot snapshot) => [
  for (var i = 0; i < snapshot.lineCount; i++)
    snapshot.text.substring(snapshot.lineStarts[i], snapshot.contentEnds[i]),
];

/// Waits until [document] has had no new tokens for a while.
Future<void> _settle(TextMateDocument document) async {
  var changed = true;
  void listener() => changed = true;
  document.addListener(listener);
  try {
    while (changed) {
      changed = false;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  } finally {
    document.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TextMateSyntax syntax;

  setUp(() {
    syntax = TextMateSyntax(
      themes: WorkbenchThemeService.instance,
      launch: () async => TextMateInProcessWorker.create(),
    );
  });

  tearDown(() => syntax.dispose());

  /// Every line of [document] has the tokens of its text tokenized from the
  /// start, as the text model stores them.
  Future<void> expectTokenizedFromStart(TextMateDocument document) async {
    final lines = _lines(document.snapshot);
    final expected = (await syntax.tokenizeFromStart(
      document.languageId,
      lines,
    ))!;
    final mismatches = <int>[];
    for (final (i, line) in lines.indexed) {
      final store = ContiguousTokensStore(_Codec(expected[i][1] & 0xff))
        ..setTokens('language', 0, line.length, expected[i], false);
      final want = store.getTokens('language', 0, line);
      final got = document.lineTokens(i + 1);
      if (got == null || !listEquals(got, want)) mismatches.add(i + 1);
    }
    expect(mismatches, isEmpty, reason: 'lines with other tokens');
  }

  test('numbers languages as VS Code does', () async {
    final fixture = jsonDecode(
      utf8.decode(
        gzip.decode(
          File('packages/bao_editor/test/fixtures/textmate/tokens.json.gz')
              .readAsBytesSync(),
        ),
      ),
    ) as Map<String, Object?>;
    final codec = (await syntax.languageIdCodec)!;
    final ids = (fixture['languageIds']! as Map).cast<String, int>();
    expect(ids, hasLength(greaterThan(70)));
    for (final MapEntry(key: language, value: id) in ids.entries) {
      expect(codec.encodeLanguageId(language), id, reason: language);
    }
  });

  // textmate_parity_test.dart checks the grammars; this checks the worker's
  // line loop (TokenizationSupportWithLineLimit around
  // TextMateTokenizationSupport) and what it sends back.
  test('the worker tokenizes every sample as VS Code', () async {
    final fixture = loadTextMateFixture();
    // vscode-textmate makes one grammar per scope name, for the first
    // language to ask (ini and properties share source.ini).
    for (final language in (fixture['grammarOrder']! as List).cast<String>()) {
      await syntax.tokenizeFromStart(language, const ['']);
    }
    final samples = (fixture['samples']! as List).cast<Map<String, Object?>>();
    final mismatches = <String>[];
    var checked = 0;
    for (final sample in samples) {
      final cases = sample['cases']! as Map<String, Object?>;
      var expected = cases[testColorTheme];
      if (expected is Map) expected = cases[expected['sameAs']];
      expected as List;
      final lines = File('$textMateFixtures/${sample['path']}')
          .readAsStringSync()
          .split(RegExp(r'\r\n|\r|\n'));
      final actual = (await syntax.tokenizeFromStart(
        sample['language']! as String,
        lines,
      ))!;
      expect(actual, hasLength(expected.length), reason: '${sample['name']}');
      for (final (i, tokens) in actual.indexed) {
        // Back from end offsets (LineTokens.convertToEndOffset).
        final starts = [
          for (var t = 0; t < tokens.length; t += 2) ...[
            t == 0 ? 0 : tokens[t - 2],
            tokens[t + 1],
          ],
        ];
        if (tokens[tokens.length - 2] != lines[i].length ||
            !listEquals(starts, (expected[i] as List).cast<int>())) {
          mismatches.add('${sample['name']} line ${i + 1}');
        }
      }
      checked++;
    }
    expect(checked, samples.length);
    expect(mismatches, isEmpty);
  });

  test('picks VS Code languages with grammars', () async {
    expect(await syntax.languageIdForPath('/w/a.ts'), 'typescript');
    expect(await syntax.languageIdForPath('/w/a.tsx'), 'typescriptreact');
    expect(await syntax.languageIdForPath('/w/run.sh'), 'shellscript');
    expect(await syntax.languageIdForPath('/w/Dockerfile'), 'dockerfile');
    expect(await syntax.languageIdForPath('/w/tsconfig.json'), 'jsonc');
    // An installed extension's grammar (Vue - Official).
    expect(await syntax.languageIdForPath('/w/App.vue'), 'vue');
    expect(
      await syntax.languageIdForPath('/w/run', firstLine: '#!/bin/bash'),
      'shellscript',
    );
    expect(
      await syntax.languageIdForPath(
        '/w/run',
        firstLine: '#!/usr/bin/env python3',
      ),
      'python',
    );
    // No VS Code grammar: Monarch highlights these.
    expect(await syntax.languageIdForPath('/w/a.kt'), isNull);
    expect(await syntax.languageIdForPath('/w/notes'), isNull);
    expect(await syntax.theme, isNotNull);
    expect((await syntax.theme)!.data.settingsId, testColorTheme);
  });

  test('tokenizes a document in the background', () async {
    const source = '''
class A {
  // a comment
  private b = "string";
  method(): number { return 42; }
}
''';
    final document = syntax.open(
      (await syntax.languageIdForPath('/w/a.ts'))!,
      DocumentSnapshot(source),
    )!;
    addTearDown(document.dispose);
    await _settle(document);
    await expectTokenizedFromStart(document);

    final theme = document.theme;
    final keyword = document.styledLines[1]!.first;
    expect(keyword.text, 'class');
    expect(keyword.style!.color, isNot(theme.foreground));
    final comment = document.styledLines[2]!.firstWhere(
      (span) => span.text == '// a comment' || span.text == '//',
    );
    expect(comment.style!.color, isNot(keyword.style!.color));
    // Spans cover each line exactly.
    for (final (i, line) in _lines(document.snapshot).indexed) {
      final spans = document.styledLines[i + 1] ?? const <TextSpan>[];
      expect(spans.map((span) => span.text).join(), line);
    }
  });

  test('edits keep tokens in place and converge', () async {
    await syntax.theme;
    var snapshot = DocumentSnapshot('let a = 1;\nconst b = `x\${a}`;\n');
    final document = syntax.open('typescript', snapshot)!;
    addTearDown(document.dispose);
    await _settle(document);

    // Typing inside a token moves the tokens after it at once.
    final before = document.lineTokens(1)!;
    snapshot = DocumentSnapshot('let abc = 1;\nconst b = `x\${a}`;\n');
    document.update(snapshot);
    final after = document.lineTokens(1)!;
    expect(after.length, before.length);
    expect(after[after.length - 2], 12);
    await _settle(document);
    await expectTokenizedFromStart(document);

    // Opening a block comment changes every line after it.
    snapshot = DocumentSnapshot('/*let abc = 1;\nconst b = `x\${a}`;\n');
    document.update(snapshot);
    await _settle(document);
    await expectTokenizedFromStart(document);
    expect(
      document.styledLines[2]!.single.style!.color,
      document.styledLines[1]!.single.style!.color,
    );
  });

  test('a new color theme recolors open documents', () async {
    final themes = WorkbenchThemeService.instance;
    final document = syntax.open(
      (await syntax.languageIdForPath('/w/a.ts'))!,
      DocumentSnapshot('class A {}\n// note\n'),
    )!;
    addTearDown(document.dispose);
    document.setViewport(1, 2);
    await _settle(document);
    final dark = document.styledLines[1]!.first.style!.color;
    final darkComment = document.styledLines[2]!.first.style!.color;
    // The first tokens come from storage: the loaded theme paints the same.
    await themes.loadedColorTheme();
    expect(syntax.editorTheme.value!.data, same(themes.colorTheme));
    final darkBackground = syntax.editorTheme.value!.background;

    await themes.setColorTheme(ThemeSettingDefaults.colorThemeLight);
    expect(themes.colorThemeId, ThemeSettingDefaults.colorThemeLight);
    final light = syntax.editorTheme.value!;
    expect(light.data.settingsId, ThemeSettingDefaults.colorThemeLight);
    expect(document.theme, same(light));
    // Until new tokens arrive the old colors stay rather than none.
    expect(document.styledLines[1]!.first.style!.color, dark);
    await _settle(document);
    await expectTokenizedFromStart(document);
    final keyword = document.styledLines[1]!.first;
    expect(keyword.text, 'class');
    expect(keyword.style!.color, isNot(dark));
    expect(keyword.style!.color, isNot(light.foreground));
    expect(document.styledLines[2]!.first.style!.color, isNot(darkComment));
    expect(light.background, isNot(darkBackground));
  });

  test('random edits in quick succession converge', () async {
    final random = Random(7);
    var text = List.generate(
      60,
      (i) => switch (i % 6) {
        0 => 'function f$i(a: number) {',
        1 => '  const s = "str$i"; // note',
        2 => '  /* block',
        3 => '     still comment */ return a + $i;',
        4 => '}',
        _ => 'type T$i = { k: `t\${$i}` };',
      },
    ).join('\n');
    await syntax.theme;
    final document = syntax.open('typescript', DocumentSnapshot(text))!;
    addTearDown(document.dispose);
    const pieces = ['/*', '*/', '"', '`', '\n', '\r\n', '{', '}', 'x', ' '];
    for (var round = 0; round < 8; round++) {
      for (var i = 0; i < 12; i++) {
        final start = random.nextInt(text.length + 1);
        final end = min(text.length, start + random.nextInt(8));
        final insert = random.nextBool()
            ? pieces[random.nextInt(pieces.length)]
            : '';
        text = text.replaceRange(start, end, insert);
        document.update(DocumentSnapshot(text));
        // Some edits land before the worker answers the last ones.
        if (random.nextBool()) await Future<void>.delayed(Duration.zero);
      }
      await _settle(document);
      await expectTokenizedFromStart(document);
    }
  });

  test('the viewport is tokenized first in a large document', () async {
    final text = List.generate(
      40000,
      (i) => 'const v$i = { key: "value $i", n: $i }; // $i',
    ).join('\n');
    await syntax.theme;
    final document = syntax.open('typescript', DocumentSnapshot(text))!;
    addTearDown(document.dispose);
    final done = Completer<void>();
    document.addListener(() {
      if (!done.isCompleted && document.lineTokens(30000) != null) {
        done.complete();
      }
    });
    document.setViewport(30000, 30040);
    await done.future.timeout(const Duration(seconds: 5));
    // Long before the background pass would get there.
    expect(document.lineTokens(25000), isNull);
  });

  test('colors code blocks by language name or alias', () async {
    final spans = await syntax.colorize('ts', 'let x = 1;');
    expect(spans, hasLength(1));
    expect(spans!.single.map((s) => s.text).join(), 'let x = 1;');
    expect(spans.single.first.style!.color, isNotNull);
    expect(await syntax.colorize('no-such-language', 'x'), isNull);
  });

  test('is unavailable without a worker', () async {
    final unavailable = TextMateSyntax(
      themes: WorkbenchThemeService.instance,
      launch: () async => null,
    );
    addTearDown(unavailable.dispose);
    expect(await unavailable.languageIdForPath('/w/a.ts'), isNull);
    expect(await unavailable.theme, isNull);
    expect(await unavailable.colorize('typescript', 'let x;'), isNull);
    expect(unavailable.open('typescript', DocumentSnapshot('')), isNull);
  });

  test('a background isolate tokenizes, not this one', () async {
    final created = TextMateWorker.debugCreated;
    final isolated = TextMateSyntax(
      themes: WorkbenchThemeService.instance,
      launch: spawnTextMateWorker,
    );
    addTearDown(isolated.dispose);
    final document = isolated.open(
      (await isolated.languageIdForPath('/w/a.ts'))!,
      DocumentSnapshot('let x = 1;'),
    )!;
    addTearDown(document.dispose);
    final tokens = Completer<void>();
    document.addListener(() {
      if (!tokens.isCompleted) tokens.complete();
    });
    await tokens.future.timeout(const Duration(seconds: 10));
    expect(document.lineTokens(1), isNotNull);
    expect(await isolated.colorize('typescript', 'let x;'), isNotNull);
    expect(TextMateWorker.debugCreated, created);
  });
}

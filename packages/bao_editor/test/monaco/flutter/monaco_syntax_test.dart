import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/flutter/document_snapshot.dart';
import 'package:baocode/ide/editor/monaco/flutter/language_assets.dart';
import 'package:baocode/ide/editor/monaco/flutter/monaco_syntax.dart';
import 'package:baocode/ide/editor/monaco/flutter/viewport_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pinned Dart Monarch grammar retains state across CRLF lines', () async {
    final syntax = MonacoSyntaxService();
    final document = DocumentSnapshot(
      '/* start\r\ninside */\nclass A {\n  String s = "x";\n}\n',
    );
    final lines = await syntax.tokenize(document, 'dart');
    expect(lines, hasLength(document.lineCount));
    expect(lines[0].tokens.first.type, contains('comment'));
    expect(lines[1].tokens.first.type, contains('comment'));
    expect(
      lines[2].tokens.any((token) => token.type.contains('keyword')),
      isTrue,
    );
    expect(
      lines[3].tokens.any((token) => token.type.contains('string')),
      isTrue,
    );
    expect(lines.last.lineNumber, document.lineCount);
    final styled = syntax.styledLines(
      document,
      lines,
      (token) => token.contains('keyword')
          ? const TextStyle(color: Color(0xffaa0000))
          : null,
    );
    for (var i = 0; i < document.lineCount; i++) {
      expect(
        styled[i + 1]!.map((span) => span.toPlainText()).join(),
        document.text.substring(
          document.lineStarts[i],
          document.contentEnds[i],
        ),
      );
    }
    expect(styled[3]!.any((span) => span.style?.color != null), isTrue);
    final layout = ViewportLayout(
      snapshot: document,
      style: const TextStyle(fontSize: 14),
      styledLines: styled,
      viewportSize: const Size(400, 180),
    );
    expect(layout.rows, isNotEmpty);
    layout.dispose();
  });

  test(
    'reuses unchanged prefix tokens and recomputes changed suffix state',
    () async {
      final syntax = MonacoSyntaxService();
      final original = await syntax.tokenizeIncremental(
        DocumentSnapshot('/* open\nclose */\nclass A {}'),
        'dart',
      );
      final suffixEdit = await syntax.tokenizeIncremental(
        DocumentSnapshot('/* open\nclose */\nclass B {}'),
        'dart',
        previous: original,
      );
      expect(suffixEdit.lines[0], same(original.lines[0]));
      expect(suffixEdit.lines[1], same(original.lines[1]));
      expect(suffixEdit.lines[2], isNot(same(original.lines[2])));

      final commentEdit = await syntax.tokenizeIncremental(
        DocumentSnapshot('// open\nclose */\nclass B {}'),
        'dart',
        previous: suffixEdit,
      );
      expect(commentEdit.lines[1], isNot(same(suffixEdit.lines[1])));
      expect(
        commentEdit.lines[1].tokens.first.type,
        isNot(contains('comment')),
      );
    },
  );

  test(
    'reuses unchanged suffix after state converges across line inserts',
    () async {
      final syntax = MonacoSyntaxService();
      final original = await syntax.tokenizeIncremental(
        DocumentSnapshot('class A {}\nclass B {}\nclass C {}'),
        'dart',
      );
      final inserted = await syntax.tokenizeIncremental(
        DocumentSnapshot('class A {}\n// comment\nclass B {}\nclass C {}'),
        'dart',
        previous: original,
      );
      expect(inserted.lines[0], same(original.lines[0]));
      expect(inserted.lines[1].tokens, isNot(same(original.lines[1].tokens)));
      expect(inserted.lines[2].lineNumber, 3);
      expect(inserted.lines[2].tokens, same(original.lines[1].tokens));
      expect(inserted.lines[3].tokens, same(original.lines[2].tokens));

      final recovered = await syntax.tokenizeIncremental(
        DocumentSnapshot('/* open\nclose */\nclass B {}\nclass C {}'),
        'dart',
        previous: original,
      );
      expect(recovered.lines[2].tokens, same(original.lines[1].tokens));
      expect(recovered.lines[3].tokens, same(original.lines[2].tokens));

      final changed = await syntax.tokenizeIncremental(
        DocumentSnapshot('/* open\nclass B {}\nclass C {}'),
        'dart',
        previous: original,
      );
      expect(changed.lines[1].tokens, isNot(same(original.lines[1].tokens)));
      expect(changed.lines[1].tokens.first.type, contains('comment'));
      expect(changed.lines[2].tokens, isNot(same(original.lines[2].tokens)));
    },
  );

  test(
    'incremental tokens match a fresh scan through varied line edits',
    () async {
      final random = math.Random(29);
      final syntax = MonacoSyntaxService();
      const pool = [
        'class A {}',
        '/* open',
        'close */',
        'const s = "x";',
        '// note',
        '😀',
        '',
      ];
      final sourceLines = List<String>.generate(
        12,
        (_) => pool[random.nextInt(pool.length)],
      );
      String text() {
        final result = StringBuffer();
        for (var i = 0; i < sourceLines.length; i++) {
          if (i > 0) result.write(i.isEven ? '\r\n' : '\n');
          result.write(sourceLines[i]);
        }
        return result.toString();
      }

      var previous = await syntax.tokenizeIncremental(
        DocumentSnapshot(text()),
        'dart',
      );
      for (var step = 0; step < 90; step++) {
        final index = random.nextInt(sourceLines.length);
        switch (random.nextInt(3)) {
          case 0:
            sourceLines.insert(index, pool[random.nextInt(pool.length)]);
          case 1:
            if (sourceLines.length > 1) sourceLines.removeAt(index);
          case 2:
            sourceLines[index] = pool[random.nextInt(pool.length)];
        }
        final document = DocumentSnapshot(text());
        final incremental = await syntax.tokenizeIncremental(
          document,
          'dart',
          previous: previous,
        );
        final fresh = await syntax.tokenizeIncremental(document, 'dart');
        expect(
          incremental.lines.length,
          fresh.lines.length,
          reason: 'step $step',
        );
        for (var i = 0; i < fresh.lines.length; i++) {
          final actual = incremental.lines[i];
          final expected = fresh.lines[i];
          expect(
            actual.lineNumber,
            expected.lineNumber,
            reason: 'step $step line $i',
          );
          expect(
            actual.tokens.map(
              (token) => (token.offset, token.type, token.language),
            ),
            expected.tokens.map(
              (token) => (token.offset, token.type, token.language),
            ),
            reason: 'step $step line $i',
          );
          expect(
            actual.endState.equals(expected.endState),
            isTrue,
            reason: 'step $step line $i',
          );
        }
        previous = incremental;
      }
    },
  );

  test('tokenizes registered C grammar via its shared C++ source', () async {
    final syntax = MonacoSyntaxService();
    final lines = await syntax.tokenizeFile(
      DocumentSnapshot('int main() { return 0; }'),
      'example.c',
    );
    expect(lines, isNotNull);
    expect(lines!.single.tokens, isNotEmpty);
    expect(lines.single.tokens.first.language, 'c');
    expect(
      await syntax.tokenizeFile(DocumentSnapshot('plain'), 'x.unknown'),
      isNull,
    );
  });

  test(
    'resolves first-line language registration for extensionless files',
    () async {
      final syntax = MonacoSyntaxService();
      final document = DocumentSnapshot('#!/usr/bin/env python3\r\nprint(1)');
      final lines = await syntax.tokenizeFile(document, 'script');
      expect(lines, isNotNull);
      expect(lines!.first.tokens.first.language, 'python');

      final incremental = await syntax.tokenizeFileIncremental(
        document,
        'script',
      );
      expect(incremental?.languageId, 'python');
      final bomDocument = DocumentSnapshot('﻿#!/usr/bin/env python3\nprint(1)');
      expect(
        (await syntax.tokenizeFileIncremental(
          bomDocument,
          'script',
        ))?.languageId,
        'python',
      );
      expect(
        await syntax.tokenizeFileIncremental(
          DocumentSnapshot('plain text'),
          'script',
          previous: incremental,
        ),
        isNull,
      );
    },
  );

  test(
    'tokenizes a baseline line for every registered Monarch language',
    () async {
      final syntax = MonacoSyntaxService();
      final ids = await const MonacoLanguageAssets().registrations();
      final failures = <String, String>{};
      for (final registered in ids) {
        try {
          final tokenizer = await syntax.tokenizerFor(registered.id);
          tokenizer.tokenize('x = 1;', true, tokenizer.getInitialState());
        } catch (error) {
          failures[registered.id] = '$error';
        }
      }
      expect(failures, isEmpty);
    },
  );

  test(
    'reuses compiler per language while retaining independent line state',
    () async {
      final syntax = MonacoSyntaxService();
      final first = await syntax.tokenizerFor('dart');
      final second = await syntax.tokenizerFor('dart');
      expect(first, same(second));
      final document = DocumentSnapshot('class A {}');
      final a = await syntax.tokenize(document, 'dart');
      final b = await syntax.tokenize(document, 'dart');
      expect(
        a.single.tokens.map((token) => token.type),
        b.single.tokens.map((token) => token.type),
      );
    },
  );
}

// Code blocks in hovers are colored by TextMate in the editor's theme: a
// fence's language by its name or alias, an unnamed fence in the editor's
// language (EditorMarkdownCodeBlockRenderer).

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/textmate/textmate_syntax.dart';
import 'package:monad/ide/editor/textmate/textmate_worker.dart';
import 'package:monad/ide/lsp/lsp_protocol.dart';
import 'package:monad/ide/lsp_ui/language_widgets.dart';

import 'fake_language_features.dart';
import 'lsp_test_helpers.dart';

const _a = 'lib/a.dart';

/// The spans of the rich text showing [text] in the hover.
List<TextSpan> _spansShowing(WidgetTester tester, String text) {
  final rich = tester
      .widgetList<RichText>(
        find.descendant(
          of: find.byType(IdeHoverCard),
          matching: find.byType(RichText),
        ),
      )
      .firstWhere((widget) => widget.text.toPlainText().contains(text));
  final spans = <TextSpan>[];
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text != null) spans.add(span);
    return true;
  });
  return spans;
}

Future<List<TextSpan>> _textMate(
  WidgetTester tester,
  String language,
  String code,
) async {
  final syntax = TextMateSyntax(
    launch: () async => TextMateInProcessWorker.create(),
  );
  try {
    return (await tester.runAsync(() => syntax.colorize(language, code)))!
        .single;
  } finally {
    syntax.dispose();
  }
}

Color? _color(List<TextSpan> spans, String text) =>
    spans.firstWhere((span) => span.text == text).style?.color;

void main() {
  testWidgets('hover code blocks are colored by TextMate', (tester) async {
    final languages = FakeLanguageFeatures()
      ..onHover = (path, position) => const LspHover(
        '```ts\nconst x = 1;\n```\n\n```\nfinal y = 2;\n```',
        range: null,
      );
    await pumpLanguageWorkbench(
      tester,
      const {_a: 'void main() {}\n'},
      languages,
      open: [_a],
    );
    await caretAt(tester, 1);
    await press(tester, LogicalKeyboardKey.keyK, primary: true);
    await press(tester, LogicalKeyboardKey.keyI, primary: true);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(IdeHoverCard), findsOneWidget);

    final typescript = await _textMate(tester, 'typescript', 'const x = 1;');
    final named = _spansShowing(tester, 'const x = 1;');
    expect(_color(named, 'const'), _color(typescript, 'const'));
    expect(_color(named, '1'), _color(typescript, '1'));

    // No language: the editor's (Dart, highlighted by TextMate).
    final dart = await _textMate(tester, 'dart', 'final y = 2;');
    final unnamed = _spansShowing(tester, 'final y = 2;');
    expect(_color(unnamed, 'final'), _color(dart, 'final'));
    expect(_color(dart, 'final'), isNotNull);
  });
}

// The IDE editor highlights with VS Code's TextMate grammars in the
// default color theme where it can, and with Monarch where it cannot: when
// no worker starts (the web, no native Oniguruma).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_surface.dart';
import 'package:monad/ide/editor/textmate/textmate_syntax.dart';
import 'package:monad/ide/editor/textmate/textmate_worker.dart';
import 'package:monad/ide/file_service.dart';
import 'package:monad/ide/ide_editor.dart';
import 'package:monad/ide/ide_workspace.dart';
import 'package:monad/theme/app_theme.dart';
import 'package:path/path.dart' as p;

import '../../workbench/fake_files.dart';

class _MemoryFiles with ReadWriteOnlyFiles implements IdeFileService {
  _MemoryFiles(this.contents);

  final Map<String, String> contents;

  @override
  Future<List<IdeFile>> list(String directory) async => [];

  @override
  Future<String> read(String path, {bool force = false}) async =>
      contents[path]!;

  @override
  Future<void> write(String path, String text, {String? expectedText}) async =>
      contents[path] = text;
}

final _root = p.join(p.separator, 'textmate-project');

/// Opens [name] holding [text] in the native editor.
Future<IdeWorkspace> _open(
  WidgetTester tester,
  String name,
  String text,
) async {
  final path = p.join(_root, name);
  final workspace = IdeWorkspace(_root, files: _MemoryFiles({path: text}));
  addTearDown(workspace.dispose);
  await workspace.open(path);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: IdeEditor(
          workspace: workspace,
          active: workspace.active!,
          nativeEditorEnabled: true,
          onError: (error) => fail('Unexpected editor error: $error'),
          onLspStatus: (_) {},
          onPositionChanged: (_) {},
        ),
      ),
    ),
  );
  return workspace;
}

EditorSurface _surface(WidgetTester tester) =>
    tester.widget<EditorSurface>(find.byType(EditorSurface));

/// The painted spans of one-based [line], once every line has some.
Future<List<TextSpan>> _line(WidgetTester tester, int line) async {
  for (var i = 0; i < 40; i++) {
    final spans = _surface(tester).styledLines?[line];
    if (spans != null && spans.isNotEmpty) return spans;
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Line $line was never highlighted');
}

/// What TextMate makes of [code] outside the editor, in the default theme.
Future<List<List<TextSpan>>> _textMate(
  WidgetTester tester,
  String language,
  String code,
) async {
  final syntax = TextMateSyntax(
    launch: () async => TextMateInProcessWorker.create(),
  );
  try {
    return (await tester.runAsync(() => syntax.colorize(language, code)))!;
  } finally {
    syntax.dispose();
  }
}

Color? _colorOf(List<TextSpan> spans, String text) =>
    spans.firstWhere((span) => span.text == text).style?.color;

void main() {
  testWidgets('TypeScript is highlighted by TextMate in Dark 2026', (
    tester,
  ) async {
    const code = 'class A {\n  s = "text"; // note\n}\n';
    await _open(tester, 'a.ts', code);
    final expected = await _textMate(tester, 'typescript', code);
    for (var line = 1; line <= 3; line++) {
      final spans = await _line(tester, line);
      expect(
        [for (final span in spans) (span.text, span.style?.color)],
        [for (final span in expected[line - 1]) (span.text, span.style?.color)],
        reason: 'line $line',
      );
    }
    final surface = _surface(tester);
    // Dark 2026's `editor.background` and `editor.foreground`.
    expect(surface.backgroundColor, const Color(0xFF121314));
    expect(surface.style.color, const Color(0xFFBBBEBF));
  });

  // Each file as VS Code colors it, embedded languages included.
  const files = {
    'a.py': ('python', 'def f(x):\n    return "s" + str(x)  # c\n'),
    'README.md': (
      'markdown',
      '# Title\n\n```ts\nconst a: number = 1;\n```\n\n*em* `code`\n',
    ),
    'index.html': (
      'html',
      '<style>\nbody { color: red; }\n</style>\n'
          '<script>\nlet x = 1;\n</script>\n<p class="a">t</p>\n',
    ),
    'package.json': ('json', '{\n  "name": "x",\n  "n": 1\n}\n'),
    'main.rs': ('rust', 'fn main() {\n    let s = "x"; // c\n}\n'),
  };
  for (final MapEntry(key: name, value: (language, code)) in files.entries) {
    testWidgets('$name is highlighted by TextMate as $language', (
      tester,
    ) async {
      await _open(tester, name, code);
      final expected = await _textMate(tester, language, code);
      for (final (index, line) in expected.indexed) {
        if (line.isEmpty) continue;
        final spans = await _line(tester, index + 1);
        expect(
          [for (final span in spans) (span.text, span.style)],
          [for (final span in line) (span.text, span.style)],
          reason: '$name line ${index + 1}',
        );
      }
    });
  }

  testWidgets('code blocks in Markdown take their language\'s colors', (
    tester,
  ) async {
    await _open(tester, 'b.md', '```ts\nconst a = 1;\n```\n');
    final typescript = await _textMate(tester, 'typescript', 'const a = 1;');
    final spans = await _line(tester, 2);
    expect(_colorOf(spans, 'const'), _colorOf(typescript.single, 'const'));
    expect(_colorOf(spans, '1'), _colorOf(typescript.single, '1'));
  });

  testWidgets('edits recolor the lines they affect', (tester) async {
    await _open(tester, 'b.ts', 'let a = 1;\nlet b = 2;\n');
    final keyword = _colorOf(await _line(tester, 2), 'let');
    final controller = tester
        .widget<EditorSurface>(find.byType(EditorSurface))
        .controller;
    // Opening a block comment on line 1 turns line 2 into a comment.
    controller
      ..select(0, 0)
      ..replaceSelection('/*');
    await tester.pump();
    // Until the worker answers, the edited line keeps its tokens, stretched
    // over the insertion (`ContiguousTokensEditing.insert`).
    final edited = _surface(tester).styledLines![1]!;
    expect(edited.first.text, '/*let');
    expect(edited.first.style?.color, keyword);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final line2 = await _line(tester, 2);
    expect(line2.map((span) => span.text).join(), 'let b = 2;');
    expect(line2.first.style?.color, isNot(keyword));
    expect(
      line2.map((span) => span.style?.color).toSet(),
      hasLength(1),
      reason: 'all comment',
    );
  });

  testWidgets('without a worker Monarch highlights in the old colors', (
    tester,
  ) async {
    final launcher = textMateWorkerLauncher;
    textMateWorkerLauncher = () async => null;
    addTearDown(() => textMateWorkerLauncher = launcher);
    await _open(tester, 'c.ts', 'class A {}');
    final spans = await _line(tester, 1);
    // Monaco's vs-dark keyword color.
    expect(_colorOf(spans, 'class'), const Color(0xff569cd6));
    expect(_surface(tester).backgroundColor, AppColors.code);
  });
}

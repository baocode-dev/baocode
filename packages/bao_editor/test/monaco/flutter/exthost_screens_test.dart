// Renders the editor features extensions drive (decoration types, inlay
// hints, CodeLens, ghost text) offscreen with real fonts and writes PNGs to
// build/exthost-screens/ at the repository root, for a visual check.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_code_lens.dart';
import 'package:bao_editor/monaco/flutter/editor_decoration_types.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_inlay_hints.dart';
import 'package:bao_editor/monaco/flutter/editor_inline_suggest.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';

const _mono = TextStyle(
  fontFamily: 'ScreenMono',
  fontSize: 14,
  height: 1.4,
  color: Color(0xffd4d4d4),
);

final Directory _out = Directory('../../build/exthost-screens');

Color? _themeColor(String id) => switch (id) {
  'editor.foreground' => const Color(0xffd4d4d4),
  'editorError.foreground' => const Color(0xfff14c4c),
  'editorWarning.foreground' => const Color(0xffcca700),
  'editorCodeLens.foreground' => const Color(0xff999999),
  'editorLink.activeForeground' => const Color(0xff4e94ce),
  'editorInlayHint.foreground' => const Color(0xff969696),
  'editorInlayHint.background' => const Color(0x1a4d4d4d),
  'editorGhostText.foreground' => const Color(0x8cffffff),
  _ => null,
};

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }

  final root = Platform.environment['FLUTTER_ROOT']!;
  final material = '$root/bin/cache/artifacts/material_fonts';
  await load('Roboto', [
    '$material/Roboto-Regular.ttf',
    '$material/Roboto-Italic.ttf',
    '$material/Roboto-Bold.ttf',
  ]);
  await load('ScreenMono', ['/System/Library/Fonts/Monaco.ttf']);
  await load('codicon', ['../../assets/codicons/codicon.ttf']);
}

EditorSurfaceController _controller(String text) {
  final document = EditorDocumentModel(text);
  final controller = EditorSurfaceController(document: document);
  addTearDown(() {
    controller.dispose();
    document.dispose();
  });
  return controller;
}

Widget _frame(GlobalKey key, Widget child, {double height = 300}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: 760, height: height, child: child),
        ),
      ),
    );

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    _out.createSync(recursive: true);
    File('${_out.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// A 32x32 PNG: a red disc with a white bar (an error gutter icon).
Future<Uint8List> _iconPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(
    const Offset(16, 16),
    14,
    Paint()..color = const Color(0xfff14c4c),
  );
  canvas.drawRect(
    const Rect.fromLTWH(14, 7, 4, 12),
    Paint()..color = const Color(0xffffffff),
  );
  canvas.drawRect(
    const Rect.fromLTWH(14, 22, 4, 4),
    Paint()..color = const Color(0xffffffff),
  );
  final image = await recorder.endRecording().toImage(32, 32);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Expects no text of [text] to inherit an underline from around the
/// editor (a view zone's widgets are under the app's text style).
void _expectUndecorated(RichText text) {
  void visit(InlineSpan span, TextDecoration? inherited) {
    final decoration = span.style?.decoration ?? inherited;
    if (span is TextSpan && (span.text ?? '').isNotEmpty) {
      expect(decoration ?? TextDecoration.none, TextDecoration.none);
    }
    span.visitDirectChildren((child) {
      visit(child, decoration);
      return true;
    });
  }

  visit(text.text, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  testWidgets('editor_decorations.png', (tester) async {
    final controller = _controller(
      [
        "import { readFile } from 'fs';",
        '',
        'export async function load(path: string) {',
        '  const unused = 42;',
        "  const text = await readFile(path, 'utf8');",
        "  if (!text) throw new Error('empty');",
        '  return JSON.parse(text);',
        '}',
        '',
        '// TODO: cache results',
      ].join('\n'),
    );
    final registry = EditorDecorationTypeRegistry();
    addTearDown(registry.dispose);
    void type(String key, Map<String, Object?> json) => registry
        .registerDecorationType(key, DecorationRenderOptions.fromJson(json));
    type('error-line', {
      'isWholeLine': true,
      'backgroundColor': 'rgba(241, 76, 76, 0.15)',
      'overviewRulerColor': {'id': 'editorError.foreground'},
      'overviewRulerLane': 4,
      'gutterIconPath': {'scheme': 'file', 'path': '/tmp/error.png'},
      'gutterIconSize': 'contain',
    });
    type('boxed', {
      'border': '1px solid #e2c08d',
      'borderRadius': '3px',
      'backgroundColor': 'rgba(226, 192, 141, 0.12)',
      'overviewRulerColor': '#e2c08d',
      'overviewRulerLane': 1,
    });
    type('outlined', {
      'outline': '1px dashed #4ec9b0',
      'overviewRulerColor': '#4ec9b0',
    });
    type('styled', {
      'color': '#c586c0',
      'fontWeight': 'bold',
      'fontStyle': 'italic',
      'textDecoration': 'underline wavy #f14c4c',
    });
    type('faded', {'opacity': '0.4'});
    type('return-type', {
      'after': {'contentText': ': Promise<any>', 'color': '#6a9955'},
    });
    type('blame', {
      'after': {
        'contentText': 'Alice, 2 days ago',
        'color': {'id': 'editorCodeLens.foreground'},
        'fontStyle': 'italic',
        'margin': '0 0 0 3em',
      },
      'rangeBehavior': 1,
    });
    type('badge', {
      'before': {
        'contentText': 'TODO',
        'color': '#ffffff',
        'backgroundColor': '#007acc',
        'border': '1px solid #3794ff',
        'borderRadius': '3px',
        'padding': '0 4px',
        'margin': '0 6px 0 0',
        'fontWeight': 'bold',
      },
      'overviewRulerColor': '#3794ff',
      'overviewRulerLane': 7,
      'dark': {'color': '#9cdcfe'},
    });
    final decorations = EditorDecorationsController(
      document: controller.document,
      types: registry,
      theme: const EditorDecorationTheme(
        isDark: true,
        colors: _themeColor,
        key: 'dark',
      ),
    );
    addTearDown(decorations.dispose);
    DecorationOptions at(int line, int start, int end) =>
        DecorationOptions(range: Range(line, start, line, end));
    decorations
      ..setDecorations('error-line', [at(6, 1, 1)])
      ..setDecorations('boxed', [at(5, 22, 30)])
      ..setDecorations('outlined', [at(3, 28, 40)])
      ..setDecorations('styled', [at(7, 10, 20)])
      ..setDecorations('faded', [at(4, 3, 21)])
      ..setDecorations('return-type', [at(3, 41, 41)])
      ..setDecorationsFast('blame', [5, 44, 5, 44])
      ..setDecorations('badge', [at(10, 4, 8)]);
    final icon = await tester.runAsync(_iconPng);
    final key = GlobalKey();
    await tester.pumpWidget(
      _frame(
        key,
        EditorSurface(
          controller: controller,
          style: _mono,
          decorationProviders: [decorations],
          gutterIconBuilder: (context, gutterIcon) =>
              Image.memory(icon!, gaplessPlayback: true),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(icon!),
        tester.element(find.byType(EditorSurface)),
      ),
    );
    controller.setSelections([const TextSelection.collapsed(offset: 52)]);
    await tester.pump();
    await tester.pump();
    expect(find.byType(Image), findsOne);
    await _capture(tester, key, 'editor_decorations.png');
  });

  testWidgets('inlay_hints.png', (tester) async {
    final controller = _controller(
      [
        'function area(width: number, height: number) {',
        '  return width * height;',
        '}',
        'const size = area(10, 20);',
        'const items = [1, 2, 3].map(n => n * 2);',
        'const index = buildIndex(items);',
        'const veryLongVariableName = createSomething();',
      ].join('\n'),
    );
    final hints = EditorInlayHintsController(
      controller.document,
      colors: EditorInlayHintColors.from(_themeColor),
      padding: true,
    );
    addTearDown(hints.dispose);
    hints.setHints([
      EditorInlayHint.text(
        Position(1, 46),
        ': number',
        kind: EditorInlayHintKind.type,
      ),
      EditorInlayHint.text(
        Position(4, 11),
        ': number',
        kind: EditorInlayHintKind.type,
      ),
      EditorInlayHint.text(
        Position(4, 19),
        'width:',
        kind: EditorInlayHintKind.parameter,
        paddingRight: true,
      ),
      EditorInlayHint.text(
        Position(4, 23),
        'height:',
        kind: EditorInlayHintKind.parameter,
        paddingRight: true,
      ),
      EditorInlayHint.text(
        Position(5, 12),
        ': number[]',
        kind: EditorInlayHintKind.type,
      ),
      EditorInlayHint.text(
        Position(5, 30),
        ': number',
        kind: EditorInlayHintKind.type,
      ),
      EditorInlayHint(
        position: Position(6, 12),
        label: const [
          EditorInlayHintLabelPart(': Map<string, '),
          EditorInlayHintLabelPart('IndexEntry', location: 'index.ts:12'),
          EditorInlayHintLabelPart('>'),
        ],
        kind: EditorInlayHintKind.type,
      ),
      // Cut at maximumLength (43) with `…`.
      EditorInlayHint.text(
        Position(2, 25),
        ': SomethingWithAVeryLongTypeNameThatGoesOnAndOnAndOn',
        kind: EditorInlayHintKind.type,
      ),
    ]);
    // The pointer over a link part with Cmd/Ctrl down.
    final link =
        hints.decorations.items
                .expand((d) => [?d.before, ?d.after])
                .firstWhere((t) => t.text == 'IndexEntry')
                .data!
            as EditorInlayHintPart;
    link.hover(Rect.zero, modifier: true);
    final key = GlobalKey();
    await tester.pumpWidget(
      _frame(
        key,
        EditorSurface(
          controller: controller,
          style: _mono,
          decorationProviders: [hints],
        ),
        height: 200,
      ),
    );
    controller.setSelections([const TextSelection.collapsed(offset: 95)]);
    await tester.pump();
    await _capture(tester, key, 'inlay_hints.png');
  });

  testWidgets('codelens.png', (tester) async {
    final controller = _controller(
      [
        'class Calculator {',
        '  add(a: number, b: number) {',
        '    return a + b;',
        '  }',
        '',
        '  subtract(a: number, b: number) {',
        '    return a - b;',
        '  }',
        '}',
        '',
        "test('adds', () => {",
        '  expect(new Calculator().add(1, 2)).toBe(3);',
        '});',
      ].join('\n'),
    );
    final lenses = EditorCodeLensController(
      controller.document,
      resolve: (lens) async => lens.withCommand(
        const EditorCommand(title: '0 references', id: 'refs'),
      ),
    );
    addTearDown(lenses.dispose);
    lenses.setLenses([
      EditorCodeLens(
        range: Range(1, 1, 1, 17),
        command: const EditorCommand(title: '2 references', id: 'refs'),
      ),
      EditorCodeLens(
        range: Range(1, 1, 1, 17),
        command: const EditorCommand(title: '1 implementation', id: 'impl'),
      ),
      EditorCodeLens(
        range: Range(2, 3, 2, 6),
        command: const EditorCommand(title: '5 references', id: 'refs'),
      ),
      // Resolved when in view.
      EditorCodeLens(range: Range(6, 3, 6, 11)),
      EditorCodeLens(
        range: Range(11, 1, 11, 5),
        command: const EditorCommand(
          title: r'$(play) Run Test',
          id: 'run',
          tooltip: 'Run this test',
        ),
      ),
      EditorCodeLens(
        range: Range(11, 1, 11, 5),
        command: const EditorCommand(title: r'$(debug) Debug Test', id: 'dbg'),
      ),
      EditorCodeLens(
        range: Range(11, 1, 11, 5),
        command: const EditorCommand(title: 'last run: passed'),
      ),
    ]);
    final key = GlobalKey();
    await tester.pumpWidget(
      _frame(
        key,
        EditorSurface(
          controller: controller,
          style: _mono,
          codeLens: lenses,
          codeLensColors: EditorCodeLensColors.from(_themeColor),
          codeLensIcon: (name) => switch (name) {
            'play' => const IconData(0xeb2c, fontFamily: 'codicon'),
            'debug' => const IconData(0xead8, fontFamily: 'codicon'),
            _ => null,
          },
        ),
        height: 360,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('0 references', findRichText: true), findsOne);
    // No span of a lens line, its indentation included, inherits an
    // underline from around the editor.
    final label = find.textContaining('5 references', findRichText: true);
    final lines = tester.widgetList<RichText>(
      find.ancestor(of: label, matching: find.byType(RichText)),
    );
    expect(lines, isNotEmpty);
    lines.forEach(_expectUndecorated);
    // Hover "Debug Test": the link color.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.textContaining('Debug Test', findRichText: true)),
    );
    await tester.pump();
    await _capture(tester, key, 'codelens.png');
  });

  testWidgets('ghost_text.png', (tester) async {
    Widget editor(
      EditorSurfaceController controller,
      EditorInlineSuggestController suggest,
    ) => SizedBox(
      height: 110,
      child: EditorSurface(
        controller: controller,
        style: _mono,
        inlineSuggest: suggest,
        showMinimap: false,
      ),
    );

    // One line, after the caret.
    final single = _controller(
      'function greet(name: string) {\n  console.log(\n}',
    );
    final singleSuggest = EditorInlineSuggestController(
      single,
      colors: EditorGhostTextColors.from(_themeColor),
    );
    addTearDown(singleSuggest.dispose);
    // Lines below the caret.
    final lines = _controller('function fib(n: number): number {\n  \n}');
    final linesSuggest = EditorInlineSuggestController(
      lines,
      colors: EditorGhostTextColors.from(_themeColor),
    );
    addTearDown(linesSuggest.dispose);
    // Lines in the middle of a line: its rest moves below.
    final middle = _controller('const total = sum();\nlog(total);');
    final middleSuggest = EditorInlineSuggestController(
      middle,
      colors: EditorGhostTextColors.from(_themeColor),
    );
    addTearDown(middleSuggest.dispose);

    final key = GlobalKey();
    await tester.pumpWidget(
      _frame(
        key,
        ColoredBox(
          color: const Color(0xff1e1e1e),
          child: Column(
            children: [
              editor(single, singleSuggest),
              const SizedBox(height: 4),
              editor(lines, linesSuggest),
              const SizedBox(height: 4),
              editor(middle, middleSuggest),
            ],
          ),
        ),
        height: 350,
      ),
    );
    single.setSelections([const TextSelection.collapsed(offset: 45)]);
    singleSuggest.show(
      const EditorInlineSuggestion(
        start: 45,
        end: 45,
        text: r'`Hello, ${name}!`);',
      ),
    );
    lines.setSelections([const TextSelection.collapsed(offset: 36)]);
    linesSuggest.show(
      const EditorInlineSuggestion(
        start: 36,
        end: 36,
        text: 'if (n < 2) return n;\n  return fib(n - 1) + fib(n - 2);',
      ),
    );
    middle.setSelections([const TextSelection.collapsed(offset: 18)]);
    middleSuggest.show(
      const EditorInlineSuggestion(
        start: 18,
        end: 18,
        text: '\n  price * quantity,\n  shipping,\n',
      ),
    );
    await tester.pump();
    expect(singleSuggest.isVisible, isTrue);
    expect(linesSuggest.isVisible, isTrue);
    expect(middleSuggest.isVisible, isTrue);
    for (final line in ['  return fib(n - 1) + fib(n - 2);', '  shipping,']) {
      _expectUndecorated(
        tester.widget<RichText>(find.text(line, findRichText: true)),
      );
    }
    await _capture(tester, key, 'ghost_text.png');
  });
}

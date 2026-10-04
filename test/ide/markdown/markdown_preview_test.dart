import 'dart:convert';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:baocode/ide/markdown/markdown_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

const _path = '/project/docs/guide.md';

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

class FakeHost {
  final reads = <String>[];
  final opened = <(String, String?)>[];
  final external = <Uri>[];
  var edits = 0;

  Future<Uint8List> read(String path) async {
    reads.add(path);
    if (path.endsWith('missing.png')) throw StateError('no such file');
    return _png;
  }
}

Future<FakeHost> pumpPreview(
  WidgetTester tester,
  EditorDocumentModel model, {
  bool readOnly = false,
}) async {
  final host = FakeHost();
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: IdeMarkdownPreview(
          path: _path,
          model: model,
          pathContext: p.posix,
          readOnly: readOnly,
          readBytes: host.read,
          onEdited: () => host.edits++,
          onOpenFile: (path, fragment) => host.opened.add((path, fragment)),
          onOpenExternal: host.external.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return host;
}

IdeMarkdownPreviewState _state(WidgetTester tester) =>
    tester.state(find.byType(IdeMarkdownPreview));

/// The text of the unit whose text is [text].
Finder _unit(String text) => find.byWidgetPredicate(
  (widget) => widget is EditableText && widget.controller.text == text,
);

/// The unit with the caret.
EditableText _active(WidgetTester tester) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .firstWhere((field) => field.focusNode.hasFocus);

/// Clicks [text]'s unit at its [offset].
Future<void> _click(
  WidgetTester tester,
  String text,
  int offset, {
  int count = 1,
}) async {
  final render = tester.state<EditableTextState>(_unit(text)).renderEditable;
  final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
  final at = render.localToGlobal(caret.center + const Offset(0.5, 0));
  for (var i = 0; i < count; i++) {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
  }
  // Past the time a next click would count as another of these.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

/// Types [text] at the caret, as the platform's input does.
Future<void> _type(WidgetTester tester, String text) async {
  for (final character in text.split('')) {
    final value = _active(tester).controller.value;
    final selection = value.selection;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: value.text.replaceRange(
          selection.start,
          selection.end,
          character,
        ),
        selection: TextSelection.collapsed(offset: selection.start + 1),
      ),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool meta = false,
}) async {
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

/// The styles [text]'s unit draws [part] in.
List<TextStyle?> _stylesOf(WidgetTester tester, String text, String part) {
  final field = tester.widget<EditableText>(_unit(text));
  final span = field.controller.buildTextSpan(
    context: tester.element(_unit(text)),
    style: field.style,
    withComposing: false,
  );
  final styles = <TextStyle?>[];
  span.visitChildren((child) {
    if (child is TextSpan && child.text == part) styles.add(child.style);
    return true;
  });
  return styles;
}

bool _hidden(TextStyle? style) => style?.fontSize == 0;

void main() {
  testWidgets('the document shows rendered, its marks hidden, and shown '
      'where the caret is', (tester) async {
    final model = EditorDocumentModel('# Guide\n\nSome **bold** and `code`.');
    await pumpPreview(tester, model);
    // The heading's text, no `#`; the paragraph's marks drawn at no size.
    expect(_unit('Guide'), findsOneWidget);
    const paragraph = 'Some **bold** and `code`.';
    expect(_stylesOf(tester, paragraph, '**').every(_hidden), isTrue);
    expect(_stylesOf(tester, paragraph, '`').every(_hidden), isTrue);
    expect(
      _stylesOf(tester, paragraph, 'bold').single?.fontWeight,
      FontWeight.w700,
    );

    // The caret in `bold`: its marks show; the code's stay hidden.
    await _click(tester, paragraph, 9);
    expect(_active(tester).controller.text, paragraph);
    expect(_stylesOf(tester, paragraph, '**').any(_hidden), isFalse);
    expect(_stylesOf(tester, paragraph, '`').every(_hidden), isTrue);
    expect(_state(tester).caret, (line: 3, column: 10));
  });

  testWidgets('typing goes into the source in place, one undo step', (
    tester,
  ) async {
    const text = '# Guide\r\n\r\nFirst paragraph.\r\n\r\nSecond **one**.\r\n';
    final model = EditorDocumentModel(text);
    final host = await pumpPreview(tester, model);

    await _click(tester, 'Second **one**.', 6);
    await _type(tester, ' new');
    expect(
      model.text,
      '# Guide\r\n\r\nFirst paragraph.\r\n\r\nSecond new **one**.\r\n',
    );
    expect(host.edits, 4);
    expect(_state(tester).caret, (line: 5, column: 11));

    await _key(tester, LogicalKeyboardKey.keyZ, meta: true);
    expect(model.text, text);
    await _key(tester, LogicalKeyboardKey.keyZ, meta: true, shift: true);
    expect(
      model.text,
      '# Guide\r\n\r\nFirst paragraph.\r\n\r\nSecond new **one**.\r\n',
    );
  }, variant: _mac);

  testWidgets('Enter continues a list; Enter on an empty item ends it', (
    tester,
  ) async {
    final model = EditorDocumentModel('- one');
    await pumpPreview(tester, model);
    await _click(tester, 'one', 3);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(model.text, '- one\n- ');
    await _type(tester, 'two');
    expect(model.text, '- one\n- two');
    await _key(tester, LogicalKeyboardKey.enter);
    await _key(tester, LogicalKeyboardKey.enter);
    await _type(tester, 'After.');
    expect(model.text, '- one\n- two\n\nAfter.');
  }, variant: _mac);

  testWidgets('Backspace at a heading\'s start makes it a paragraph', (
    tester,
  ) async {
    final model = EditorDocumentModel('Intro\n\n## Title');
    await pumpPreview(tester, model);
    await _click(tester, 'Title', 0);
    await _key(tester, LogicalKeyboardKey.backspace);
    expect(model.text, 'Intro\n\nTitle');
    // Again: it joins the paragraph before.
    await _key(tester, LogicalKeyboardKey.backspace);
    expect(model.text, 'IntroTitle');
  }, variant: _mac);

  testWidgets('the arrows go from one row to the next, and select across', (
    tester,
  ) async {
    final model = EditorDocumentModel('First\n\nSecond\n\nThird');
    await pumpPreview(tester, model);
    await _click(tester, 'First', 2);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_active(tester).controller.text, 'Second');
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_state(tester).caret?.line, 3);
    await _key(tester, LogicalKeyboardKey.arrowRight, meta: true);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_active(tester).controller.text, 'Third');
    expect(_state(tester).caret, (line: 5, column: 1));
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(_state(tester).caret, (line: 3, column: 7));

    // Shift+Up selects back into the first row; typing replaces it all.
    await _key(tester, LogicalKeyboardKey.arrowUp, shift: true);
    expect(_active(tester).controller.text, 'First');
    await _key(tester, LogicalKeyboardKey.keyX);
    // From the end of `Second` up to the end of `First`.
    expect(model.text, 'Firstx\n\nThird');
  }, variant: _mac);

  testWidgets('a table: cells typed in, Tab to the next', (tester) async {
    final model = EditorDocumentModel('| a | b |\n|---|---|\n| 1 | 2 |');
    await pumpPreview(tester, model);
    expect(find.byType(Table), findsOneWidget);
    await _click(tester, '1', 1);
    await _type(tester, '0');
    expect(model.text, '| a | b |\n|---|---|\n| 10 | 2 |');
    await _key(tester, LogicalKeyboardKey.tab);
    expect(_active(tester).controller.text, '2');
    await _type(tester, 'x');
    expect(model.text, '| a | b |\n|---|---|\n| 10 | x |');
  }, variant: _mac);

  testWidgets('a task box ticks its line', (tester) async {
    final model = EditorDocumentModel('- [ ] write\n- [x] read');
    final host = await pumpPreview(tester, model);
    await tester.tap(find.byIcon(Icons.check_box_outline_blank));
    await tester.pumpAndSettle();
    expect(model.text, '- [x] write\n- [x] read');
    expect(host.edits, 1);
  });

  testWidgets('read-only: shown, not edited; a click opens a link', (
    tester,
  ) async {
    final model = EditorDocumentModel(
      '- [ ] write\n\nText [web](https://a.dev).',
    );
    final host = await pumpPreview(tester, model, readOnly: true);
    await tester.tap(find.byIcon(Icons.check_box_outline_blank));
    await _click(tester, 'Text [web](https://a.dev).', 7);
    expect(host.external, [Uri.parse('https://a.dev')]);
    await _click(tester, 'Text [web](https://a.dev).', 2);
    await _type(tester, 'z');
    expect(model.text, '- [ ] write\n\nText [web](https://a.dev).');
  }, variant: _mac);

  testWidgets('images are read from the project, beside the document', (
    tester,
  ) async {
    final model = EditorDocumentModel(
      '![shot](img/shot%201.png)\n\n![](<../a b.png>)\n\n![gone](missing.png)',
    );
    final host = await pumpPreview(tester, model);
    expect(host.reads, [
      '/project/docs/img/shot 1.png',
      '/project/a b.png',
      '/project/docs/missing.png',
    ]);
    expect(find.byType(Image), findsNWidgets(2));
    // One that cannot be read shows its alt text.
    expect(find.text('gone'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('links: ⌘-click; anchors go to their heading, files open', (
    tester,
  ) async {
    final filler = [for (var i = 0; i < 60; i++) 'Paragraph $i.'].join('\n\n');
    const links = '[Go](#the-end) [Other](../README.md#Usage)';
    final model = EditorDocumentModel(
      '$links\n\n$filler\n\n## The End\n\n$filler',
    );
    final host = await pumpPreview(tester, model);
    expect(_unit('The End'), findsNothing);

    // A plain click puts the caret in the link.
    await _click(tester, links, 2);
    expect(_unit('The End'), findsNothing);
    expect(_state(tester).caret, (line: 1, column: 3));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await _click(tester, links, 2);
    expect(_unit('The End'), findsOneWidget);
    expect(tester.getTopLeft(_unit('The End')).dy, lessThan(100));

    _state(tester).revealLine(1);
    await tester.pumpAndSettle();
    await _click(tester, links, 18);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(host.opened, [('/project/README.md', 'Usage')]);
  }, variant: _mac);

  testWidgets('the line at the top, and a line revealed', (tester) async {
    final model = EditorDocumentModel(
      [for (var i = 0; i < 60; i++) 'Paragraph $i.'].join('\n\n'),
    );
    await pumpPreview(tester, model);
    final state = _state(tester);
    expect(state.topLine, 1);
    state.revealLine(81);
    await tester.pumpAndSettle();
    expect(state.topLine, 81);
    expect(tester.getTopLeft(_unit('Paragraph 40.')).dy, lessThan(60));
    expect(state.caret, (line: 81, column: 1));
  });

  testWidgets('another\'s edit keeps the caret where it was', (tester) async {
    final model = EditorDocumentModel('Alpha\n\nBeta');
    await pumpPreview(tester, model);
    await _click(tester, 'Beta', 2);
    model.applyOffsetEdits([const EditorOffsetEdit(0, 0, 'New\n\n')]);
    await tester.pumpAndSettle();
    expect(_state(tester).caret, (line: 5, column: 3));
    expect(_active(tester).controller.text, 'Beta');
  });

  testWidgets('a double click selects a word, a triple its row; copy and '
      'paste carry the source', (tester) async {
    final model = EditorDocumentModel('Some **bold** words\n\n- item');
    await pumpPreview(tester, model);
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': 'one\r\ntwo'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _click(tester, 'Some **bold** words', 15, count: 2);
    expect(
      _active(tester).controller.selection,
      const TextSelection(baseOffset: 14, extentOffset: 19),
    );
    await _key(tester, LogicalKeyboardKey.keyC, meta: true);
    expect(clipboard, ['words']);

    // Across rows: the marks between them too.
    await _key(tester, LogicalKeyboardKey.arrowDown, shift: true);
    await _key(tester, LogicalKeyboardKey.keyC, meta: true);
    expect(clipboard.last, startsWith('words\n\n- '));

    await _click(tester, 'item', 4, count: 3);
    await _key(tester, LogicalKeyboardKey.keyV, meta: true);
    expect(model.text, 'Some **bold** words\n\n- one\n  two');
  }, variant: _mac);

  testWidgets('code blocks keep their indent on Enter; Tab nests an item', (
    tester,
  ) async {
    final model = EditorDocumentModel('```js\n  let a;\n```\n\n- a\n- b');
    await pumpPreview(tester, model);
    await _click(tester, '  let a;', 8);
    await _key(tester, LogicalKeyboardKey.enter);
    await _type(tester, 'b');
    expect(model.text, '```js\n  let a;\n  b\n```\n\n- a\n- b');

    await _click(tester, 'b', 1);
    await _key(tester, LogicalKeyboardKey.tab);
    expect(model.text, '```js\n  let a;\n  b\n```\n\n- a\n  - b');
    await _key(tester, LogicalKeyboardKey.tab, shift: true);
    expect(model.text, '```js\n  let a;\n  b\n```\n\n- a\n- b');
  }, variant: _mac);

  testWidgets('formatting: bold over the selection, a heading, a list', (
    tester,
  ) async {
    final model = EditorDocumentModel('Make this bold');
    await pumpPreview(tester, model);
    await _click(tester, 'Make this bold', 11, count: 2);
    final state = _state(tester);
    state.toggleInline('**');
    await tester.pumpAndSettle();
    expect(model.text, 'Make this **bold**');
    state.setHeading(2);
    await tester.pumpAndSettle();
    expect(model.text, '## Make this **bold**');
    state.setHeading(0);
    state.toggleList(task: true);
    await tester.pumpAndSettle();
    expect(model.text, '- [ ] Make this **bold**');
  }, variant: _mac);

  testWidgets('typing at the end of a list starts a paragraph after it', (
    tester,
  ) async {
    final model = EditorDocumentModel('- a\n');
    await pumpPreview(tester, model);
    // The empty row after the list.
    final rows = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .toList();
    expect(rows.map((field) => field.controller.text), ['a', '']);
    final render = tester
        .stateList<EditableTextState>(find.byType(EditableText))
        .last
        .renderEditable;
    await tester.tapAt(render.localToGlobal(const Offset(2, 4)));
    await tester.pumpAndSettle();
    await _type(tester, 'Text');
    expect(model.text, '- a\n\nText');
  }, variant: _mac);
}

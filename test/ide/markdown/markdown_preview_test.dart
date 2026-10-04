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

class FakeHost {
  final reads = <String>[];
  final opened = <(String, String?)>[];
  final messages = <String>[];
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
          onMessage: host.messages.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return host;
}

Finder _text(String text) => find.text(text, findRichText: true);
final _field = find.byKey(const ValueKey('markdown-block-field'));

IdeMarkdownPreviewState _state(WidgetTester tester) =>
    tester.state(find.byType(IdeMarkdownPreview));

void main() {
  testWidgets('a click edits a block in place; done, it alone changes, '
      'as one undo step', (tester) async {
    const text = '# Guide\r\n\r\nFirst paragraph.\r\n\r\nSecond paragraph.\r\n';
    final model = EditorDocumentModel(text);
    final host = await pumpPreview(tester, model);
    expect(_text('Guide'), findsOneWidget);
    expect(_text('Second paragraph.'), findsOneWidget);

    await tester.tap(_text('Second paragraph.'));
    await tester.pumpAndSettle();
    expect(_field, findsOneWidget);
    expect(
      tester.widget<TextField>(_field).controller!.text,
      'Second paragraph.',
    );
    await tester.enterText(_field, 'Second paragraph,\nnow two lines.');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_field, findsNothing);
    expect(
      model.text,
      '# Guide\r\n\r\nFirst paragraph.\r\n\r\n'
      'Second paragraph,\r\nnow two lines.\r\n',
    );
    expect(host.edits, 1);
    expect(
      find.textContaining('now two lines.', findRichText: true),
      findsOneWidget,
    );

    // Undo, in the preview, takes the block's edit back whole.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(model.text, text);
    expect(host.edits, 2);
  });

  testWidgets('the same text, or the edit given up, changes nothing', (
    tester,
  ) async {
    final model = EditorDocumentModel('One.\n\nTwo.');
    final host = await pumpPreview(tester, model);
    await tester.tap(_text('One.'));
    await tester.pumpAndSettle();
    // Ctrl+Enter is done too.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(_field, findsNothing);
    expect(model.canUndo, isFalse);
    expect(host.edits, 0);
  });

  testWidgets('a change to the block while it is edited ends the edit, '
      'which puts nothing in', (tester) async {
    final model = EditorDocumentModel('One.\n\nTwo.');
    final host = await pumpPreview(tester, model);
    await tester.tap(_text('Two.'));
    await tester.pumpAndSettle();
    await tester.enterText(_field, 'Mine.');
    // Another editor (or the agent) changes the block meanwhile.
    model.applyOffsetEdits([const EditorOffsetEdit(6, 10, 'Theirs.')]);
    await tester.pumpAndSettle();
    expect(_field, findsNothing);
    expect(model.text, 'One.\n\nTheirs.');
    expect(host.messages, hasLength(1));
    expect(_text('Theirs.'), findsOneWidget);
  });

  testWidgets('a change elsewhere leaves the edit going', (tester) async {
    final model = EditorDocumentModel('One.\n\nTwo.');
    await pumpPreview(tester, model);
    await tester.tap(_text('Two.'));
    await tester.pumpAndSettle();
    await tester.enterText(_field, 'Mine.');
    model.applyOffsetEdits([const EditorOffsetEdit(0, 4, 'First.')]);
    await tester.pumpAndSettle();
    expect(_field, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(model.text, 'First.\n\nMine.');
  });

  testWidgets('the preview going puts the block edited in', (tester) async {
    final model = EditorDocumentModel('One.\n\nTwo.');
    final host = await pumpPreview(tester, model);
    await tester.tap(_text('Two.'));
    await tester.pumpAndSettle();
    await tester.enterText(_field, 'Kept.');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(model.text, 'One.\n\nKept.');
    expect(host.edits, 1);
  });

  testWidgets('the room after the last block starts a new one', (tester) async {
    final model = EditorDocumentModel('One.\n');
    await pumpPreview(tester, model);
    await tester.tap(find.text('Click to add content'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field).controller!.text, isEmpty);
    await tester.enterText(_field, '- new');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(model.text, 'One.\n\n- new');
  });

  testWidgets('a task box ticks its line', (tester) async {
    final model = EditorDocumentModel('- [ ] write\n- [x] read');
    final host = await pumpPreview(tester, model);
    await tester.tap(find.byIcon(Icons.check_box_outline_blank));
    await tester.pumpAndSettle();
    expect(model.text, '- [x] write\n- [x] read');
    expect(host.edits, 1);
    // The box, not the block: no field.
    expect(_field, findsNothing);
  });

  testWidgets('read-only: shown, not edited', (tester) async {
    final model = EditorDocumentModel('- [ ] write\n\nText.');
    await pumpPreview(tester, model, readOnly: true);
    await tester.tap(_text('Text.'));
    await tester.tap(find.byIcon(Icons.check_box_outline_blank));
    await tester.pumpAndSettle();
    expect(_field, findsNothing);
    expect(find.text('Click to add content'), findsNothing);
    expect(model.text, '- [ ] write\n\nText.');
  });

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

  testWidgets('links: anchors scroll to their heading, files open', (
    tester,
  ) async {
    final filler = [for (var i = 0; i < 60; i++) 'Paragraph $i.'].join('\n\n');
    final model = EditorDocumentModel(
      '[Go](#the-end) [Other](../README.md#Usage) [Line](src/a.dart#L3)\n\n'
      '$filler\n\n## The End\n\n$filler',
    );
    final host = await pumpPreview(tester, model);
    expect(_text('The End'), findsNothing);
    await tester.tapOnText(find.textRange.ofSubstring('Go'));
    await tester.pumpAndSettle();
    expect(_text('The End'), findsOneWidget);
    expect(tester.getTopLeft(_text('The End')).dy, lessThan(100));
    // A link's click is the link's: no block is edited.
    expect(_field, findsNothing);

    _state(tester).revealLine(1);
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('Other'));
    await tester.tapOnText(find.textRange.ofSubstring('Line'));
    expect(host.opened, [
      ('/project/README.md', 'Usage'),
      ('/project/docs/src/a.dart', 'L3'),
    ]);
  });

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
    expect(tester.getTopLeft(_text('Paragraph 40.')).dy, lessThan(60));
  });
}

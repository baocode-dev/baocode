import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_markdown/bao_markdown.dart';
import 'package:baocode/ide/markdown/markdown_preview.dart';
import 'package:baocode/ide/markdown/markdown_task_box.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/ui_zoom.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

late Uint8List _png;

Future<Uint8List> _createPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(Colors.red, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(160, 80);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

final _svg = Uint8List.fromList(
  utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
    '<rect width="24" height="24" fill="red"/></svg>',
  ),
);

const _path = '/project/docs/guide.md';

class FakeHost {
  final reads = <String>[];
  final opened = <(String, String?)>[];
  final revealed = <String>[];
  var edits = 0;

  Future<Uint8List> read(String path) async {
    reads.add(path);
    if (path.endsWith('missing.png')) throw StateError('no such file');
    return path.endsWith('.svg') ? _svg : _png;
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
          onReveal: host.revealed.add,
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => precacheImage(
      MemoryImage(_png),
      tester.element(find.byType(IdeMarkdownPreview)),
    ),
  );
  await tester.pumpAndSettle();
  return host;
}

/// The line shown as [text] (its marks hidden).
Finder _text(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is RichText &&
      widget.text
              .toPlainText(includeSemanticsLabels: false)
              .replaceAll('\u200B', '') ==
          text,
);

IdeMarkdownPreviewState _state(WidgetTester tester) =>
    tester.state(find.byType(IdeMarkdownPreview));

MarkdownController _controller(WidgetTester tester) =>
    tester.state<MarkdownEditorState>(find.byType(MarkdownEditor)).controller;

/// Where [index] of [text] is, in the line shown as [within].
Offset _at(WidgetTester tester, String text, {String? within, int index = 0}) {
  final paragraph = tester.renderObject<RenderParagraph>(_text(within ?? text));
  final start =
      paragraph.text.toPlainText(includeSemanticsLabels: false).indexOf(text) +
      index;
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + 1),
      )
      .first
      .toRect();
  // Just after its left edge: the caret goes before it.
  return paragraph.localToGlobal(box.centerLeft + const Offset(1, 0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => _png = await _createPng());

  testWidgets('heading rules use the sidebar divider color', (tester) async {
    await pumpPreview(tester, EditorDocumentModel('# Title\n\n## Section'));
    final separator = AppColors.partBorder;
    for (final title in ['Title', 'Section']) {
      final containers = tester.widgetList<Container>(
        find.ancestor(of: _text(title), matching: find.byType(Container)),
      );
      final borders = containers
          .map((container) => (container.decoration as BoxDecoration?)?.border)
          .whereType<Border>();
      expect(borders.first.bottom.color, separator);
    }
  });

  testWidgets('a click puts the caret at the text clicked: where the '
      'source opens', (tester) async {
    const text =
        '# Guide\r\n\r\nSome **bold** and `code`, then bold.\r\n\r\n'
        '- one\r\n- two words\r\n';
    final model = EditorDocumentModel(text);
    final host = await pumpPreview(tester, model);
    final state = _state(tester);
    // Nowhere yet: the source opens where it was.
    expect(state.caret, isNull);

    await tester.tapAt(_at(tester, 'words', within: 'two words'));
    await tester.pumpAndSettle();
    expect(state.caret, (line: 6, column: 7));
    await tester.tapAt(_at(tester, 'Guide'));
    await tester.pumpAndSettle();
    expect(state.caret, (line: 1, column: 3));
    // The second `bold`, not the first.
    await tester.tapAt(
      _at(tester, 'bold.', within: 'Some bold and code, then bold.'),
    );
    await tester.pumpAndSettle();
    expect(state.caret, (line: 3, column: 32));
    // Nothing changed.
    expect(model.text, text);
    expect(host.edits, 0);
  });

  testWidgets('a task box ticks its line', (tester) async {
    final model = EditorDocumentModel('- [ ] write\n- [x] read');
    final host = await pumpPreview(tester, model);
    await tester.tap(find.byType(MarkdownTaskBox).first);
    await tester.pumpAndSettle();
    expect(model.text, '- [x] write\n- [x] read');
    expect(host.edits, 1);
  });

  testWidgets('read-only: its task boxes do not tick', (tester) async {
    final model = EditorDocumentModel('- [ ] write\n\nText.');
    await pumpPreview(tester, model, readOnly: true);
    await tester.tap(find.byType(MarkdownTaskBox).first);
    await tester.pumpAndSettle();
    expect(model.text, '- [ ] write\n\nText.');
  });

  testWidgets('a file dropped goes after the block it is let go on', (
    tester,
  ) async {
    final model = EditorDocumentModel('# Title\n\nText.\n');
    final host = await pumpPreview(tester, model);
    _state(tester)
        .insert('![](shot.png)', position: tester.getCenter(_text('Title')));
    await tester.pumpAndSettle();
    expect(model.text, '# Title\n\n![](shot.png)\n\nText.\n');
    _state(tester).insert('[a](a.md)');
    expect(model.text, '# Title\n\n![](shot.png)\n\nText.\n\n[a](a.md)');
    // Told once each is made.
    await tester.pump();
    expect(host.edits, 2);
  });

  testWidgets('clicking an image opens a zoomable preview', (tester) async {
    final model = EditorDocumentModel('![shot](img/shot.png)');
    final host = await pumpPreview(tester, model);
    final image = find.byType(Image).first;
    await tester.tap(image);
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    expect(model.text, '![shot](img/shot.png)');
    expect(host.edits, 0);
    final viewer = find.byType(InteractiveViewer);
    final enlarged = find.descendant(of: viewer, matching: find.byType(Image));
    expect(tester.getSize(enlarged).width, greaterThan(160));
    final transform = find
        .descendant(of: viewer, matching: find.byType(Transform))
        .first;
    final before = tester.widget<Transform>(transform).transform.clone();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(viewer),
        scrollDelta: const Offset(0, -200),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Transform>(transform).transform, isNot(before));
    final zoomed = tester.widget<Transform>(transform).transform.clone();
    await tester.drag(viewer, const Offset(60, 30));
    await tester.pumpAndSettle();
    expect(tester.widget<Transform>(transform).transform, isNot(zoomed));

    await tester.tap(find.byIcon(Codicons.close));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(host.reads, ['/project/docs/img/shot.png']);
  });

  testWidgets('an image double click opens it, and edits nothing', (
    tester,
  ) async {
    final model = EditorDocumentModel('![shot](shot.png)');
    final host = await pumpPreview(tester, model);
    final at = tester.getCenter(find.byType(Image));
    // Both clicks reach the document before the dialog's first frame.
    await tester.tapAt(at);
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(model.text, '![shot](shot.png)');
    expect(host.edits, 0);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('network images reuse the loaded image in the preview', (
    tester,
  ) async {
    const provider = NetworkImage('https://example.test/shot.png');
    // Seed Flutter's image cache with a deterministic response; no external I/O.
    final codec = (await tester.runAsync(
      () => ui.instantiateImageCodec(_png),
    ))!;
    final frame = (await tester.runAsync(codec.getNextFrame))!;
    codec.dispose();
    PaintingBinding.instance.imageCache.putIfAbsent(
      provider,
      () => OneFrameImageStreamCompleter(
        Future.value(ImageInfo(image: frame.image)),
      ),
    );
    addTearDown(provider.evict);
    final host = await pumpPreview(
      tester,
      EditorDocumentModel('![web](${provider.url})'),
    );
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byType(Image),
      ),
    );
    expect(image.image, provider);
    expect(host.reads, isEmpty);
    await tester.tapAt(const Offset(10, 350));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('SVG images can be opened in the preview', (tester) async {
    final model = EditorDocumentModel('![icon](icon.svg)');
    await pumpPreview(tester, model);
    await tester.tap(find.byType(SvgPicture));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(SvgPicture), findsNWidgets(2));
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
    await tester.tap(find.byIcon(Icons.broken_image_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('links: clicked, the caret in them and their bubble (none of '
      'their marks); from it, or ⌘-clicked, they open', (tester) async {
    final filler = [for (var i = 0; i < 60; i++) 'Paragraph $i.'].join('\n\n');
    final model = EditorDocumentModel(
      '[Go](#the-end) [Other](../README.md#Usage) [Line](src/a.dart#L3)\n\n'
      '$filler\n\n## The End\n\n$filler',
    );
    final host = await pumpPreview(tester, model);
    expect(_text('The End'), findsNothing);
    await tester.tapAt(_at(tester, 'Go', within: 'Go Other Line', index: 1));
    await tester.pumpAndSettle();
    // Not gone to; shown as it was, the caret in it.
    expect(_text('The End'), findsNothing);
    expect(_text('Go Other Line'), findsOneWidget);
    expect(
      _controller(tester).selection,
      const TextSelection.collapsed(offset: 2),
    );
    await tester.tap(find.text('#the-end'));
    await tester.pumpAndSettle();
    // There, and left there.
    expect(_text('The End'), findsOneWidget);
    expect(tester.getTopLeft(_text('The End')).dy, lessThan(100));

    // ⌘-clicked, gone to at once, and left there as the click ends (not
    // brought back to the caret, where it was).
    _state(tester).revealLine(1);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    final click = await tester.startGesture(
      _at(tester, 'Go', within: 'Go Other Line', index: 1),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await click.up();
    await tester.pumpAndSettle();
    expect(_text('The End'), findsOneWidget);
    expect(tester.getTopLeft(_text('The End')).dy, lessThan(100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    _state(tester).revealLine(1);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tapOnText(find.textRange.ofSubstring('Other'));
    await tester.tapOnText(find.textRange.ofSubstring('Line'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(host.opened, [
      ('/project/README.md', 'Usage'),
      ('/project/docs/src/a.dart', 'L3'),
    ]);

    // Right-clicked: its link's menu, and the rest.
    await tester.tapAt(
      _at(tester, 'Go', within: 'Go Other Line', index: 1),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy link address'), findsOneWidget);
    expect(find.text('Select All'), findsOneWidget);
    await tester.tap(find.text('Remove link'));
    await tester.pumpAndSettle();
    expect(model.text, startsWith('Go [Other]'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('taken away, it tells the line at its top', (tester) async {
    final model = EditorDocumentModel(
      [for (var i = 0; i < 60; i++) 'Paragraph $i.'].join('\n\n'),
    );
    int? left;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeMarkdownPreview(
            path: _path,
            model: model,
            pathContext: p.posix,
            readBytes: (_) async => _png,
            initialLine: 41,
            onLeave: (line) => left = line,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(left, 41);
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

  testWidgets('zoomed and scrolled far down, a drag selects under the '
      'pointer', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final model = EditorDocumentModel(
      '${[for (var i = 0; i < 80; i++) 'Paragraph $i.'].join('\n\n')}\n\n'
      '- **必要性检查**：\n'
      '  - 申请人必须在系统中存在且已设置工号\n'
      '  - 报表必须设置负责人\n'
      '  - 如果不满足以上条件，申请将直接失败\n',
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => UiZoom(scale: 1.25, child: child),
        home: Scaffold(
          body: IdeMarkdownPreview(
            path: _path,
            model: model,
            pathContext: p.posix,
            readBytes: (_) async => _png,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _state(tester).revealLine(161);
    await tester.pumpAndSettle();

    Offset at(String text, {bool end = false}) {
      final paragraph = tester.renderObject<RenderParagraph>(_text(text));
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: text.length),
          )
          .first
          .toRect();
      return paragraph.localToGlobal(
        end
            ? box.centerRight - const Offset(1, 0)
            : box.centerLeft + const Offset(1, 0),
      );
    }

    final gesture = await tester.startGesture(
      at('必要性检查：'),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(at('报表必须设置负责人'));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(at('如果不满足以上条件，申请将直接失败', end: true));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    final editor = tester.state<MarkdownEditorState>(
      find.byType(MarkdownEditor),
    );
    final selection = _controller(tester).selection;
    final selected = editor.plainText(selection.start, selection.end);
    expect(selected.split('\n').map((line) => line.trim()), [
      '必要性检查：',
      '申请人必须在系统中存在且已设置工号',
      '报表必须设置负责人',
      '如果不满足以上条件，申请将直接失败',
    ]);
  });

  testWidgets('selected, the stash\'s bar is over it: its marks, a link '
      'typed in it, ⌘B; read-only, none', (tester) async {
    final model = EditorDocumentModel('Some text here.');
    final host = await pumpPreview(tester, model);
    await tester.tapAt(_at(tester, 'text', within: 'Some text here.'));
    await tester.pump();
    final controller = _controller(tester);
    controller.selection = const TextSelection(baseOffset: 5, extentOffset: 9);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Codicons.bold));
    await tester.pumpAndSettle();
    expect(model.text, 'Some **text** here.');
    expect(host.edits, greaterThan(0));

    // ⌘B takes it back.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(model.text, 'Some text here.');

    await tester.tap(find.byIcon(Codicons.link));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(model.text, 'Some [text](https://example.com) here.');

    // Shown only: no bar.
    await pumpPreview(
      tester,
      EditorDocumentModel('Some text.'),
      readOnly: true,
    );
    _controller(tester).selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Codicons.bold), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('selected in code, the bar only proofreads; ⌘B marks nothing', (
    tester,
  ) async {
    const text = 'Text.\n\n```js\nconst a = 1;\n```\n';
    final model = EditorDocumentModel(text);
    await pumpPreview(tester, model);
    await tester.tapAt(_at(tester, 'Text.'));
    await tester.pump();
    final controller = _controller(tester);
    // In the code block: its fences shown, its text selected.
    controller.selection = const TextSelection(
      baseOffset: 13,
      extentOffset: 18,
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Codicons.sparkle), findsOneWidget);
    expect(find.byIcon(Codicons.bold), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(model.text, text);

    // In text, all of it.
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pumpAndSettle();
    expect(find.byIcon(Codicons.bold), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('right-clicked, a file shown in the file manager: a link\'s '
      'where it goes, else the document', (tester) async {
    final model = EditorDocumentModel('See [the guide](../README.md) here.');
    final host = await pumpPreview(tester, model);
    Future<void> reveal(String text) async {
      await tester.tapAt(
        _at(tester, text, within: 'See the guide here.', index: 1),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reveal in Finder'));
      await tester.pumpAndSettle();
    }

    await reveal('guide');
    await reveal('here');
    expect(host.revealed, ['/project/README.md', _path]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('scrolled, the bar goes with the selection at once; out of '
      'view, none until it is back', (tester) async {
    final text = [for (var i = 0; i < 80; i++) 'Line $i here.'].join('\n\n');
    final model = EditorDocumentModel(text);
    await pumpPreview(tester, model);
    await tester.tapAt(_at(tester, 'Line 6 here.'));
    await tester.pump();
    final start = text.indexOf('Line 6');
    _controller(tester).selection = TextSelection(
      baseOffset: start,
      extentOffset: start + 6,
    );
    await tester.pumpAndSettle();
    final bold = find.byIcon(Codicons.bold);
    double gap() =>
        tester.getRect(_text('Line 6 here.')).top - tester.getRect(bold).top;
    final before = tester.getRect(bold).top;
    final over = gap();
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(MarkdownEditor),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    position.jumpTo(position.pixels + 60);
    await tester.pump();
    expect(tester.getRect(bold).top, closeTo(before - 60, 0.5));
    await tester.pumpAndSettle();
    expect(gap(), closeTo(over, 0.5));

    position.jumpTo(position.pixels + 1500);
    await tester.pumpAndSettle();
    expect(bold, findsNothing);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getRect(bold).top, closeTo(before, 0.5));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a table is edited in its cells, its rows put in from its '
      'handle\'s menu', (tester) async {
    final model = EditorDocumentModel('| x | y |\n|---|---|\n| 1 | 2 |\n');
    await pumpPreview(tester, model);
    await tester.tapAt(tester.getCenter(find.text('1')));
    await tester.pumpAndSettle();
    final editors = find.byType(MarkdownEditor);
    expect(editors, findsNWidgets(2));
    final cell = tester.state<MarkdownEditorState>(editors.last).controller;
    expect(cell.text, '1');
    cell.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '12',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pumpAndSettle();
    expect(model.text, '| x | y |\n|---|---|\n| 12 | 2 |\n');

    // Its row's handle, on its left edge while the pointer is over it.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final row = tester.getRect(find.text('2'));
    await mouse.moveTo(row.center);
    await tester.pumpAndSettle();
    final table = tester.getRect(find.byType(Table));
    await tester.tapAt(Offset(table.left + 2, row.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert row below'));
    await tester.pumpAndSettle();
    expect(model.text, '| x | y |\n| --- | --- |\n| 12 | 2 |\n|  |  |\n');

    // A column's, on its top edge: moved, aligned.
    await mouse.moveTo(tester.getCenter(find.text('x')));
    await tester.pumpAndSettle();
    final head = tester.getRect(find.byType(Table));
    await tester.tapAt(
      Offset(tester.getCenter(find.text('x')).dx, head.top + 2),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move column right'));
    await tester.pumpAndSettle();
    expect(model.text, '| y | x |\n| --- | --- |\n| 2 | 12 |\n|  |  |\n');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a link in a table\'s cell: the caret in it, its bubble over '
      'it (none of its marks); its address edited and taken off there', (
    tester,
  ) async {
    final model = EditorDocumentModel(
      '| x | y |\n|---|---|\n| [Docs](a.md) | 2 |\n',
    );
    await pumpPreview(tester, model);
    await tester.tapAt(tester.getCenter(find.text('Docs')));
    await tester.pumpAndSettle();
    final editors = find.byType(MarkdownEditor);
    expect(editors, findsNWidgets(2));
    final text = tester.state<MarkdownEditorState>(editors.last).controller;
    expect(text.text, '[Docs](a.md)');
    text.selection = const TextSelection.collapsed(offset: 3);
    await tester.pumpAndSettle();
    expect(_text('Docs'), findsOneWidget);
    expect(find.text('a.md'), findsOneWidget);

    await tester.tap(find.byIcon(Codicons.edit));
    await tester.pumpAndSettle();
    // Still typed in, its link's text picked while the address is typed.
    expect(find.byType(MarkdownEditor), findsNWidgets(2));
    await tester.enterText(find.byType(EditableText).last, 'b.md');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(model.text, '| x | y |\n|---|---|\n| [Docs](b.md) | 2 |\n');

    final again = tester.state<MarkdownEditorState>(editors.last).controller;
    again.selection = const TextSelection.collapsed(offset: 3);
    await tester.pumpAndSettle();
    expect(find.text('b.md'), findsOneWidget);
    await tester.tap(find.byIcon(Codicons.close));
    await tester.pumpAndSettle();
    expect(model.text, '| x | y |\n|---|---|\n| Docs | 2 |\n');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

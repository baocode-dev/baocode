import 'dart:io';

import 'package:bao_markdown/bao_markdown.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = MarkdownEditorStyle(
  text: TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF000000)),
);

/// What the editors copied ([written]), and what a paste finds ([held]).
class _FakeClipboard extends MdClipboard {
  MdClip? written;
  ({String? text, MdClip? clip}) held = (text: null, clip: null);

  @override
  Future<void> write(MdClip clip) async {
    written = clip;
    held = (text: clip.plain, clip: clip);
  }

  @override
  Future<({String? text, MdClip? clip})> read() async => held;
}

Future<MarkdownEditorState> _pump(
  WidgetTester tester,
  MarkdownController controller, {
  double height = 400,
  ScrollController? scroll,
  MarkdownEditorStyle style = _style,
  MarkdownEmbeds embeds = const MarkdownEmbeds(),
}) async {
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFFFFFFFF),
      builder: (context, _) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: height,
          child: MarkdownEditor(
            controller: controller,
            style: style,
            scrollController: scroll,
            embeds: embeds,
            padding: const EdgeInsets.all(10),
          ),
        ),
      ),
    ),
  );
  return tester.state<MarkdownEditorState>(find.byType(MarkdownEditor));
}

/// What the rows show, line by line.
List<String> _shown(WidgetTester tester) => [
  for (final element in find.byType(RichText).evaluate())
    if (_inLineBox(element))
      (element.widget as RichText).text.toPlainText(
        includeSemanticsLabels: false,
      ),
];

bool _inLineBox(Element element) {
  var parent = false;
  element.visitAncestorElements((ancestor) {
    parent = ancestor.widget is MdLineBox;
    return false;
  });
  return parent;
}

Future<void> _tapAt(
  WidgetTester tester,
  MarkdownEditorState state,
  int offset,
) async {
  final rect = state.caretRect(offset)!;
  await tester.tapAt(rect.center + const Offset(0.5, 0));
  await tester.pump();
}

/// Typed in, as the platform's input sends it: [text] where the caret is.
Future<void> _type(WidgetTester tester, String text) async {
  final value = tester.testTextInput.editingState!;
  final old = value['text'] as String;
  final start = value['selectionBase'] as int;
  final end = value['selectionExtent'] as int;
  final (a, b) = start <= end ? (start, end) : (end, start);
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: old.replaceRange(a, b, text),
      selection: TextSelection.collapsed(offset: a + text.length),
    ),
  );
  await tester.pump();
}

void main() {
  test('text set from elsewhere replaces only what differs', () {
    final controller = MarkdownController(text: 'a\nb\nc\nd');
    final ids = [for (var i = 0; i < 4; i++) controller.lines.idOf(i)];
    controller.text = 'a\nB\nc\nd';
    expect(controller.text, 'a\nB\nc\nd');
    expect(controller.lines.idOf(0), ids[0]);
    expect(controller.lines.idOf(2), ids[2]);
    expect(controller.lines.idOf(3), ids[3]);
    expect(controller.undo(), isTrue);
    expect(controller.text, 'a\nb\nc\nd');
  });

  testWidgets('marks show only where the caret is', (tester) async {
    final controller = MarkdownController(text: 'a **bold** b\n# Head\n- item');
    final state = await _pump(tester, controller);
    expect(_shown(tester), ['a bold b', 'Head', 'item']);
    state.requestFocus();
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    expect(_shown(tester), ['a **bold** b', 'Head', 'item']);
    controller.selection = TextSelection.collapsed(
      offset: controller.lineStart(1) + 3,
    );
    await tester.pump();
    expect(_shown(tester), ['a bold b', '# Head', 'item']);
  });

  testWidgets('a click puts the caret where it is in the markdown', (
    tester,
  ) async {
    final controller = MarkdownController(text: 'one **two** three');
    final state = await _pump(tester, controller);
    // "three"'s t: after the marks, as shown.
    await _tapAt(tester, state, 12);
    expect(controller.selection, const TextSelection.collapsed(offset: 12));
    await _type(tester, 'X');
    expect(controller.text, 'one **two** Xthree');
  });

  testWidgets('a click on the next line soon after one is a click of its '
      'own; on the same place, a double click', (tester) async {
    final controller = MarkdownController(text: 'one two three\nfour five');
    final state = await _pump(tester, controller);
    final word = state.caretRect(5)!.center + const Offset(0.5, 0);
    final below = state.caretRect(17)!.center + const Offset(0.5, 0);
    Future<void> click(Offset at) async {
      final mouse = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 50));
    }

    await click(word);
    await click(below);
    // Not "two" (the first click's word) selected.
    expect(controller.selection, const TextSelection.collapsed(offset: 17));
    await tester.pump(const Duration(seconds: 1));

    await click(word);
    await click(word);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 4, extentOffset: 7),
    );
    await tester.pump(const Duration(seconds: 1));

    // Clicked again elsewhere, then twice there: that word.
    await click(word);
    await click(below);
    await click(below);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 14, extentOffset: 18),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  // The system's font, where it is: an empty paragraph's height is
  // rounded unlike a line's of text in it.
  const system = '/System/Library/Fonts/SFNS.ttf';
  testWidgets('a line emptied keeps its height: those under it stay', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = File(system).readAsBytesSync();
      final loader = FontLoader('System')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    });
    final controller = MarkdownController(text: 'one\ntwo\nthree');
    // A height whose line is not a whole number of pixels.
    final state = await _pump(
      tester,
      controller,
      style: const MarkdownEditorStyle(
        text: TextStyle(
          fontFamily: 'System',
          fontSize: 14,
          height: 1.65,
          leadingDistribution: TextLeadingDistribution.even,
          color: Color(0xFF000000),
        ),
      ),
    );
    final before = state.caretRect(controller.lineStart(2))!;
    controller.replace(4, 7, '');
    await tester.pump();
    expect(controller.text, 'one\n\nthree');
    expect(state.caretRect(controller.lineStart(2)), before);
    // Its caret where a line's is.
    expect(state.caretRect(4)!.height, moreOrLessEquals(before.height));
  }, skip: !File(system).existsSync());

  testWidgets('code\'s ground is painted under the selection, not with its '
      'text (which would cover the selection)', (tester) async {
    final controller = MarkdownController(text: 'a `code` b');
    final state = await _pump(tester, controller);
    state.requestFocus();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 10);
    await tester.pump();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    paragraph.text.visitChildren((span) {
      expect(span.style?.backgroundColor, isNull);
      return true;
    });
    final line = tester.renderObject<RenderMdLine>(find.byType(MdLineBox));
    expect(
      line,
      paints
        ..rrect(color: _style.codeBackground)
        ..rect(color: _style.selection),
    );
    // Shown only (a table's cell): on its text's.
    final span = buildInlineSpan(
      '`code`',
      style: _style,
      textStyle: _style.text,
    );
    expect(
      span.children!.whereType<TextSpan>().single.style!.backgroundColor,
      _style.codeBackground,
    );
  });

  testWidgets('a selection moving builds no row again', (tester) async {
    final controller = MarkdownController(
      text: List.generate(30, (i) => 'line $i of text').join('\n'),
    );
    final state = await _pump(tester, controller);
    state.requestFocus();
    await tester.pump();
    final before = tester.widgetList<RichText>(find.byType(RichText)).toList();
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 60);
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 90);
    await tester.pump();
    final after = tester.widgetList<RichText>(find.byType(RichText)).toList();
    expect(after.length, before.length);
    for (var i = 0; i < after.length; i++) {
      expect(identical(after[i], before[i]), isTrue, reason: 'row $i');
    }
  });

  testWidgets('only the lines in view are built', (tester) async {
    final controller = MarkdownController(
      text: List.generate(5000, (i) => 'line $i').join('\n'),
    );
    await _pump(tester, controller);
    expect(find.byType(RichText).evaluate().length, lessThan(60));
  });

  testWidgets('Enter goes on with a list; on an empty item, out of it', (
    tester,
  ) async {
    final controller = MarkdownController(text: '- one\n1. first');
    final state = await _pump(tester, controller);
    state.requestFocus();
    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, '- one\n- \n1. first');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, '- one\n\n1. first');
    controller.selection = TextSelection.collapsed(offset: controller.length);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, '- one\n\n1. first\n2. ');
  });

  testWidgets('Backspace at an item\'s text takes its bullet away', (
    tester,
  ) async {
    final controller = MarkdownController(text: 'a\n- [ ] task');
    final state = await _pump(tester, controller);
    state.requestFocus();
    controller.selection = const TextSelection.collapsed(offset: 8);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.text, 'a\ntask');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.text, 'atask');
    expect(controller.undo(), isTrue);
    expect(controller.text, 'a\ntask');
  });

  testWidgets('Tab nests an item under the one before it', (tester) async {
    final controller = MarkdownController(text: '- a\n- b');
    final state = await _pump(tester, controller);
    state.requestFocus();
    controller.selection = TextSelection.collapsed(offset: controller.length);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.text, '- a\n  - b');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(controller.text, '- a\n  - b', reason: 'no item to nest under');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    expect(controller.text, '- a\n- b');
  });

  testWidgets('arrows move over what shows, a line at a time', (tester) async {
    final controller = MarkdownController(text: '- ab\n- cd');
    final state = await _pump(tester, controller);
    state.requestFocus();
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.selection.extentOffset, 7, reason: 'past the bullet');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.extentOffset, 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controller.selection.extentOffset, 9);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(controller.selection.extentOffset, 4);
  });

  testWidgets('composed text is typed in as it is composed', (tester) async {
    final controller = MarkdownController(text: 'ab');
    final state = await _pump(tester, controller);
    state.requestFocus();
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'anib',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 1, end: 3),
      ),
    );
    await tester.pump();
    expect(controller.text, 'anib');
    expect(controller.isComposing, isTrue);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'a你b',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    expect(controller.text, 'a你b');
    expect(controller.isComposing, isFalse);
    expect(controller.undo(), isTrue);
    expect(controller.text, 'ab');
  });

  testWidgets('the input it opens names its view, which Windows asks for', (
    tester,
  ) async {
    final controller = MarkdownController(text: 'ab');
    final state = await _pump(tester, controller);
    tester.testTextInput.log.clear();
    state.requestFocus();
    await tester.pump();
    final setClient = tester.testTextInput.log.firstWhere(
      (call) => call.method == 'TextInput.setClient',
    );
    final configuration =
        (setClient.arguments as List<Object?>)[1]! as Map<String, Object?>;
    expect(configuration['viewId'], tester.view.viewId);
  });

  testWidgets('what Windows composes is not told back to it as it composes', (
    tester,
  ) async {
    final controller = MarkdownController();
    final state = await _pump(tester, controller);
    state.requestFocus();
    await tester.pump();
    tester.testTextInput.log.clear();
    // As Windows' input method sends it: composing starts with a region of
    // no length, grows, is committed, and the next word starts after it.
    void compose(String old, int at, List<String> steps, String done) {
      state.updateEditingValueWithDeltas([
        TextEditingDeltaNonTextUpdate(
          oldText: old,
          selection: TextSelection.collapsed(offset: at),
          composing: TextRange.collapsed(at),
        ),
      ]);
      var text = old;
      var end = at;
      for (final step in [...steps, done]) {
        state.updateEditingValueWithDeltas([
          TextEditingDeltaReplacement(
            oldText: text,
            replacementText: step,
            replacedRange: TextRange(start: at, end: end),
            selection: TextSelection.collapsed(offset: at + step.length),
            composing: TextRange(start: at, end: at + step.length),
          ),
        ]);
        text = text.replaceRange(at, end, step);
        end = at + step.length;
      }
      state.updateEditingValueWithDeltas([
        TextEditingDeltaNonTextUpdate(
          oldText: text,
          selection: TextSelection.collapsed(offset: end),
          composing: TextRange.empty,
        ),
      ]);
    }

    compose('', 0, ['z', 'zh', 'zhi', "zhi'j", "zhi'jie"], '直接');
    compose('直接', 2, ['z', 'zu', 'zuo'], '做');
    await tester.pump();
    expect(controller.text, '直接做');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    expect(
      tester.testTextInput.log.where(
        (call) => call.method == 'TextInput.setEditingState',
      ),
      isEmpty,
    );
  });

  testWidgets('what Windows composes over a selection replaces it', (
    tester,
  ) async {
    final controller = MarkdownController(text: 'abcd');
    final state = await _pump(tester, controller);
    state.requestFocus();
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    await tester.pump();
    tester.testTextInput.log.clear();
    // #325: as Windows' engine sends it, the first of what is composed put
    // in where the selection starts, though it deleted the selection.
    state.updateEditingValueWithDeltas([
      const TextEditingDeltaNonTextUpdate(
        oldText: 'abcd',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
        composing: TextRange.collapsed(1),
      ),
    ]);
    state.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: 'abcd',
        textInserted: 'n',
        insertionOffset: 1,
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 2),
      ),
    ]);
    expect(controller.text, 'and');
    for (final (old, step) in [('and', 'ni'), ('anid', '你')]) {
      state.updateEditingValueWithDeltas([
        TextEditingDeltaReplacement(
          oldText: old,
          replacementText: step,
          replacedRange: TextRange(start: 1, end: old.length - 1),
          selection: TextSelection.collapsed(offset: 1 + step.length),
          composing: TextRange(start: 1, end: 1 + step.length),
        ),
      ]);
    }
    state.updateEditingValueWithDeltas([
      const TextEditingDeltaNonTextUpdate(
        oldText: 'a你d',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();
    expect(controller.text, 'a你d');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    expect(
      tester.testTextInput.log.where(
        (call) => call.method == 'TextInput.setEditingState',
      ),
      isEmpty,
    );
  });

  testWidgets('copied as it shows, pasted back as its markdown', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': clipboard};
        }
        return null;
      },
    );
    final controller = MarkdownController(text: 'x **b** y\n- item');
    final state = await _pump(tester, controller);
    state.requestFocus();
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.length,
    );
    await state.copy();
    expect(clipboard, 'x b y\nitem');
    controller.selection = TextSelection.collapsed(offset: controller.length);
    await state.paste();
    expect(controller.text, 'x **b** y\n- itemx **b** y\n- item');
  });

  testWidgets('copies and pastes through MdClipboard.instance: its copy as '
      'its markdown, of the other kind or none as the text', (tester) async {
    final clipboard = _FakeClipboard();
    MdClipboard.instance = clipboard;
    addTearDown(() => MdClipboard.instance = const MdClipboard());
    final controller = MarkdownController(text: 'x **b** y');
    final state = await _pump(tester, controller);
    state.requestFocus();
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.length,
    );
    await state.copy();
    expect(
      clipboard.written,
      const MdClip(plain: 'x b y', markdown: 'x **b** y', fromPlain: false),
    );

    // Its copy: pasted as it was, though the text is not the copy's.
    controller.selection = TextSelection.collapsed(offset: controller.length);
    clipboard.held = (
      text: 'something else',
      clip: const MdClip(plain: 'x b y', markdown: ' *i*', fromPlain: false),
    );
    await state.paste();
    expect(controller.text, 'x **b** y *i*');

    // Another app's copy: its text.
    clipboard.held = (text: ' t', clip: null);
    await state.paste();
    expect(controller.text, 'x **b** y *i* t');

    // A plain text's copy: its text, not its markdown.
    clipboard.held = (
      text: ' p',
      clip: const MdClip(plain: ' p', markdown: ' **p**', fromPlain: true),
    );
    await state.paste();
    expect(controller.text, 'x **b** y *i* t p');
  });

  testWidgets('MdClipboard pastes its copy back while the clipboard has its '
      'text', (tester) async {
    String? text;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.setData' => () {
          text = (call.arguments as Map)['text'] as String;
          return null;
        }(),
        'Clipboard.getData' => {'text': text},
        _ => null,
      },
    );
    addTearDown(MdClipboard.reset);
    const clipboard = MdClipboard();
    const clip = MdClip(plain: 'b', markdown: '**b**', fromPlain: false);
    await clipboard.write(clip);
    expect(text, 'b');
    expect((await clipboard.read()).clip, clip);
    // Copied elsewhere since.
    text = 'c';
    expect(await clipboard.read(), (text: 'c', clip: null));
  });

  testWidgets('a drag selects, past the bottom it scrolls on', (tester) async {
    final controller = MarkdownController(
      text: List.generate(200, (i) => 'line $i').join('\n'),
    );
    final scroll = ScrollController();
    final state = await _pump(tester, controller, height: 300, scroll: scroll);
    final start = state.caretRect(0)!.center;
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(start + const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(const Offset(100, 340));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.offset, greaterThan(50));
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, greaterThan(100));
    await gesture.up();
    await tester.pump();
  });

  testWidgets('a code block\'s fences show where the caret is in it', (
    tester,
  ) async {
    final controller = MarkdownController(text: 'a\n```js\ncode\n```\nb');
    final state = await _pump(tester, controller);
    expect(_shown(tester), ['a', 'code', 'b']);
    state.requestFocus();
    controller.selection = TextSelection.collapsed(
      offset: controller.lineStart(2),
    );
    await tester.pump();
    expect(_shown(tester), ['a', '```js', 'code', '```', 'b']);
  });

  testWidgets('a point over a table is before it, or after it past its '
      'middle', (tester) async {
    final controller = MarkdownController(
      text: 'a\n| x | y |\n|---|---|\n| 1 | 2 |\n\nb',
    );
    final state = await _pump(tester, controller);
    final table = tester.getRect(find.byType(MdTable));
    expect(
      state.offsetAt(table.topCenter + const Offset(0, 2)),
      controller.lineStart(1),
    );
    expect(
      state.offsetAt(table.bottomCenter - const Offset(0, 2)),
      controller.lineEnd(3),
    );
  });

  // A Latin font and, for the Chinese, a fallback of other metrics: the
  // system's own, where they are.
  const latin = '/System/Library/Fonts/Supplemental/Arial.ttf';
  const han = '/System/Library/Fonts/Hiragino Sans GB.ttc';
  testWidgets(
    'the caret is as high as its line, beside a space as beside a Chinese '
    'character',
    (tester) async {
      await tester.runAsync(() async {
        for (final (family, path) in [('Latin', latin), ('Han', han)]) {
          final bytes = File(path).readAsBytesSync();
          final loader = FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
        }
      });
      final controller = MarkdownController(text: '空白符号 a', plain: true);
      final state = await _pump(
        tester,
        controller,
        style: const MarkdownEditorStyle(
          text: TextStyle(
            fontFamily: 'Latin',
            fontFamilyFallback: ['Han'],
            fontSize: 14,
            height: 1.55,
            leadingDistribution: TextLeadingDistribution.even,
            color: Color(0xFF000000),
          ),
        ),
      );
      final first = state.caretRect(0)!;
      for (var offset = 1; offset <= controller.length; offset++) {
        final rect = state.caretRect(offset)!;
        expect(rect.top, moreOrLessEquals(first.top), reason: '$offset');
        expect(rect.height, moreOrLessEquals(first.height), reason: '$offset');
      }
    },
    skip: !File(latin).existsSync() || !File(han).existsSync(),
  );

  testWidgets(
    'a line above the view growing (an image read) leaves the view still',
    (tester) async {
      final height = ValueNotifier(10.0);
      final controller = MarkdownController(
        text: [
          'a',
          '',
          '![x](x.png)',
          '',
          for (var i = 0; i < 60; i++) 'line $i',
        ].join('\n'),
      );
      final scroll = ScrollController();
      final state = await _pump(
        tester,
        controller,
        scroll: scroll,
        embeds: _GrowingImage(height),
      );
      scroll.jumpTo(80);
      await tester.pump();
      final line = controller.lineStart(12);
      final before = state.caretRect(line)!.top;
      final image = state.caretRect(controller.lineStart(2));
      // In the cache area above the view, laid out.
      expect(image, isNotNull);
      expect(image!.top, lessThan(0));

      height.value = 300;
      await tester.pump();
      expect(state.caretRect(line)!.top, moreOrLessEquals(before));
      // By as much as the line grew.
      expect(scroll.offset, greaterThan(80 + 250));
      scroll.dispose();
    },
  );
}

/// Images as tall as [height] says.
class _GrowingImage extends MarkdownEmbeds {
  const _GrowingImage(this.height);

  final ValueListenable<double> height;

  @override
  InlineSpan inline(BuildContext context, MdEmbed embed) => WidgetSpan(
    child: ValueListenableBuilder<double>(
      valueListenable: height,
      builder: (context, height, _) => SizedBox(width: 50, height: height),
    ),
  );
}

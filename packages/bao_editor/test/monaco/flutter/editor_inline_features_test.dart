import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_code_lens.dart';
import 'package:bao_editor/monaco/flutter/editor_decorations.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_inlay_hints.dart';
import 'package:bao_editor/monaco/flutter/editor_inline_suggest.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';

EditorSurfaceController _controller(String text) {
  final document = EditorDocumentModel(text);
  final controller = EditorSurfaceController(document: document);
  addTearDown(() {
    controller.dispose();
    document.dispose();
  });
  return controller;
}

Future<FocusNode> _mount(
  WidgetTester tester,
  EditorSurfaceController controller, {
  List<EditorDecorationProvider> providers = const [],
  EditorInlineSuggestController? inlineSuggest,
  EditorCodeLensController? codeLens,
}) async {
  final focus = FocusNode();
  addTearDown(focus.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 600,
          height: 300,
          child: EditorSurface(
            controller: controller,
            focusNode: focus,
            decorationProviders: providers,
            inlineSuggest: inlineSuggest,
            codeLens: codeLens,
          ),
        ),
      ),
    ),
  );
  focus.requestFocus();
  await tester.pump();
  return focus;
}

void main() {
  group('ghost text', () {
    test('computeGhostText places insertions', () {
      final snapshot = DocumentSnapshot('print(fo\nab');
      // Completing a word: one part at the end.
      final word = computeGhostText(snapshot, 6, 8, 'foo(bar)')!;
      expect(word.lineNumber, 1);
      expect(word.parts.single.column, 9);
      expect(word.parts.single.text, 'o(bar)');
      expect(word.render('print(fo'), 'print(foo(bar)');
      // Insertions inside the replaced text.
      final inner = computeGhostText(snapshot, 9, 11, 'aXbY')!;
      expect(inner.parts.map((p) => (p.column, p.text)), [(2, 'X'), (3, 'Y')]);
      expect(computeGhostText(snapshot, 9, 11, 'aXbY', mode: 'prefix'), isNull);
      expect(
        computeGhostText(
          snapshot,
          9,
          11,
          'aXbY',
          mode: 'subwordSmart',
          cursorOffset: 11,
        ),
        isNull,
      );
      // Deleting is not ghost text.
      expect(computeGhostText(snapshot, 9, 11, 'a'), isNull);
      // Lines below.
      final lines = computeGhostText(snapshot, 8, 8, '\n    return 1')!;
      expect(lines.parts.single.lines, ['', '    return 1']);
    });

    testWidgets('shows, follows typing, accepts with Tab', (tester) async {
      final controller = _controller('print(fo)\n');
      final suggest = EditorInlineSuggestController(controller);
      addTearDown(suggest.dispose);
      await _mount(tester, controller, inlineSuggest: suggest);
      controller.setSelections([const TextSelection.collapsed(offset: 8)]);
      suggest.show(
        const EditorInlineSuggestion(start: 6, end: 8, text: 'foobar'),
      );
      await tester.pump();
      expect(suggest.isVisible, isTrue);
      expect(suggest.ghostText!.parts.single.text, 'obar');
      final ghost = suggest.decorations.items.single;
      expect(ghost.after!.text, 'obar');
      expect(ghost.after!.style!.fontStyle, FontStyle.italic);
      expect(ghost.after!.cursorStops, InjectedTextCursorStops.left);

      // Typing what it suggests keeps it, shorter.
      controller.type('o');
      await tester.pump();
      expect(suggest.ghostText!.parts.single.text, 'bar');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(controller.document.text, 'print(foobar)\n');
      expect(controller.value.selection.extentOffset, 12);
      expect(suggest.isVisible, isFalse);
    });

    testWidgets('typing something else or Escape hides it', (tester) async {
      final controller = _controller('ab');
      final suggest = EditorInlineSuggestController(controller);
      addTearDown(suggest.dispose);
      var dismissed = 0;
      suggest.onDismissed = (_) => dismissed++;
      await _mount(tester, controller, inlineSuggest: suggest);
      controller.setSelections([const TextSelection.collapsed(offset: 2)]);
      suggest.show(const EditorInlineSuggestion(start: 0, end: 2, text: 'abc'));
      await tester.pump();
      controller.type('x');
      await tester.pump();
      expect(suggest.isVisible, isFalse);
      expect(dismissed, 1);

      suggest.show(
        const EditorInlineSuggestion(start: 0, end: 3, text: 'abxyz'),
      );
      await tester.pump();
      expect(suggest.isVisible, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(suggest.isVisible, isFalse);
      expect(dismissed, 2);
      // Tab indents again.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(controller.document.text, isNot('abx'));
    });

    testWidgets('multi-line ghost text: a zone, the rest of the line moved', (
      tester,
    ) async {
      final controller = _controller('f(x)\nnext');
      final suggest = EditorInlineSuggestController(controller);
      addTearDown(suggest.dispose);
      await _mount(tester, controller, inlineSuggest: suggest);
      controller.setSelections([const TextSelection.collapsed(offset: 2)]);
      suggest.show(
        const EditorInlineSuggestion(start: 2, end: 2, text: 'a,\n  b,\n  '),
      );
      await tester.pump();
      final zones = suggest.zones(const TextStyle(fontSize: 14));
      expect(zones.single.afterLineNumber, 1);
      expect(zones.single.heightInLines, 2);
      final decorations = suggest.decorations.items.toList();
      expect(decorations.first.after!.text, 'a,');
      // `x)` is hidden on the line and shown after the last ghost line.
      expect(decorations.last.opacity, 0);
      expect((decorations.last.start, decorations.last.end), (2, 4));

      // acceptNextWord takes `a`, then `,`.
      expect(suggest.acceptNextWord(), isTrue);
      expect(controller.document.text, 'f(ax)\nnext');
      expect(suggest.isVisible, isTrue);
      expect(suggest.ghostText!.parts.single.text, ',\n  b,\n  ');
      expect(suggest.accept(), isTrue);
      expect(controller.document.text, 'f(a,\n  b,\n  x)\nnext');
      expect(controller.value.selection.extentOffset, 12);
    });
  });

  group('inlay hints', () {
    test('anchors to words, renders parts, paddings and kinds', () {
      final document = EditorDocumentModel('let x = 1;\nfoo(a, b);');
      addTearDown(document.dispose);
      final hints = EditorInlayHintsController(
        document,
        colors: const EditorInlayHintColors(
          typeForeground: Color(0xff00ff00),
          parameterBackground: Color(0xff0000ff),
        ),
      );
      addTearDown(hints.dispose);
      hints.setHints([
        EditorInlayHint(
          position: Position(2, 5),
          label: const [EditorInlayHintLabelPart('value:')],
          kind: EditorInlayHintKind.parameter,
          paddingRight: true,
        ),
        EditorInlayHint(
          position: Position(1, 6),
          label: const [
            EditorInlayHintLabelPart(': '),
            EditorInlayHintLabelPart('Map<K, V>', location: 'def'),
          ],
          kind: EditorInlayHintKind.type,
        ),
      ]);
      final items = hints.decorations.items.toList();
      // After `x`: the word starts before the position.
      final type = items.where((d) => d.after != null).toList();
      expect(type.map((d) => d.after!.text), [': ', 'Map<K, V>']);
      expect(type.first.start, 4);
      expect(type.first.end, 5);
      expect(type.first.after!.style!.color, const Color(0xff00ff00));
      expect(type.first.after!.cursorStops, InjectedTextCursorStops.none);
      expect(type.last.after!.cursorStops, InjectedTextCursorStops.right);
      // Before `a`: the word starts at the position.
      final parameter = items.where((d) => d.before != null).toList();
      expect(parameter.map((d) => d.before!.text), ['value:', ' ']);
      expect(parameter.first.start, 15);
      expect(parameter.first.end, 16);
      expect(parameter.first.before!.backgroundColor, const Color(0xff0000ff));
      expect(parameter.first.before!.cursorStops, InjectedTextCursorStops.none);
      expect(parameter.last.before!.cursorStops, InjectedTextCursorStops.right);
      expect(
        parameter.last.before!.width,
        const EditorCssLength(1 / 3, EditorCssUnit.em),
      );

      // Hints move with their words.
      document.applyOffsetEdits([const EditorOffsetEdit(0, 0, '  ')]);
      final moved = hints.decorations.items.firstWhere((d) => d.after != null);
      expect(moved.start, 6);
    });

    test('long labels are cut per line', () {
      final document = EditorDocumentModel('a b');
      addTearDown(document.dispose);
      final hints = EditorInlayHintsController(document, maximumLength: 5);
      addTearDown(hints.dispose);
      hints.setHints([
        EditorInlayHint.text(Position(1, 2), 'abcd'),
        EditorInlayHint.text(Position(1, 4), 'efgh'),
        EditorInlayHint.text(Position(1, 4), 'never'),
      ]);
      expect(hints.decorations.items.map((d) => (d.after ?? d.before)!.text), [
        'abcd',
        'e…',
      ]);
    });

    test('parts are links with the modifier, hovers underline', () {
      final document = EditorDocumentModel('let x = 1;');
      addTearDown(document.dispose);
      final hints = EditorInlayHintsController(document);
      addTearDown(hints.dispose);
      final activated = <EditorInlayHintPart>[];
      final hovered = <EditorInlayHintPart?>[];
      hints
        ..onActivate = activated.add
        ..onHover = (part, _) => hovered.add(part);
      hints.setHints([
        EditorInlayHint(
          position: Position(1, 6),
          label: const [
            EditorInlayHintLabelPart(': '),
            EditorInlayHintLabelPart(
              'number',
              command: EditorCommand(title: 'go', id: 'go.def'),
              tooltip: 'the type',
            ),
          ],
        ),
      ]);
      EditorInlayHintPart target(int index) =>
          hints.decorations.items.toList()[index].after!.data!
              as EditorInlayHintPart;
      final link = target(1);
      expect(link.part.label, 'number');
      expect(link.cursor(modifier: false), isNull);
      expect(link.cursor(modifier: true), SystemMouseCursors.click);
      const down = PointerDownEvent();
      expect(link.pointerDown(down, modifier: false), isFalse);
      expect(link.pointerDown(down, modifier: true), isTrue);
      expect(activated.single.index, 1);
      expect(target(0).pointerDown(down, modifier: true), isFalse);

      link.hover(Rect.zero, modifier: true);
      final active = hints.decorations.items.toList()[1].after!.style!;
      expect(active.decoration, TextDecoration.underline);
      expect(active.color, const EditorInlayHintColors().linkForeground);
      expect(hovered.single!.part.tooltip, 'the type');
      link.hover(null, modifier: false);
      expect(
        hints.decorations.items.toList()[1].after!.style!.decoration,
        isNull,
      );
    });
  });

  group('CodeLens', () {
    test('zones above lines, sized like upstream, follow edits', () {
      final document = EditorDocumentModel('a\n  fun f()\n  fun g()');
      addTearDown(document.dispose);
      final lenses = EditorCodeLensController(document);
      addTearDown(lenses.dispose);
      lenses.setLenses([
        EditorCodeLens(
          range: Range(2, 3, 2, 10),
          command: const EditorCommand(title: '2 references', id: 'refs'),
        ),
        EditorCodeLens(
          range: Range(2, 3, 2, 10),
          command: const EditorCommand(title: 'Run', id: 'run'),
        ),
        EditorCodeLens(range: Range(3, 3, 3, 10)),
      ]);
      final zones = lenses.zones(
        style: const TextStyle(fontSize: 14),
        lineHeight: 19,
      );
      expect(zones.map((z) => z.afterLineNumber), [1, 2]);
      // font (14 * 0.9) | 0 = 12, height (12 * max(1.3, 19 / 12)) | 0 = 19.
      expect(zones.first.heightInLines, 1);
      expect(zones.first.interactive, isTrue);
      document.applyOffsetEdits([const EditorOffsetEdit(0, 0, 'x\n')]);
      expect(
        lenses
            .zones(style: const TextStyle(fontSize: 14), lineHeight: 19)
            .map((z) => z.afterLineNumber),
        [2, 3],
      );
    });

    testWidgets('resolves in view and runs clicked commands', (tester) async {
      final controller = _controller('a\nfun f()\nfun g()');
      final resolved = Completer<void>();
      final lenses = EditorCodeLensController(
        controller.document,
        resolve: (lens) async {
          resolved.complete();
          return lens.withCommand(
            const EditorCommand(title: 'resolved', id: 'r'),
          );
        },
      );
      addTearDown(lenses.dispose);
      final ran = <String>[];
      lenses.onCommand = (lens, command) => ran.add(command.id);
      lenses.setLenses([
        EditorCodeLens(
          range: Range(2, 1, 2, 4),
          command: const EditorCommand(title: '1 reference', id: 'refs'),
        ),
        EditorCodeLens(
          range: Range(2, 1, 2, 4),
          command: const EditorCommand(title: 'not a link'),
        ),
        EditorCodeLens(range: Range(3, 1, 3, 4)),
      ]);
      await _mount(tester, controller, codeLens: lenses);
      await tester.pump(const Duration(milliseconds: 300));
      expect(resolved.isCompleted, isTrue);
      await tester.pump();
      expect(find.textContaining('resolved', findRichText: true), findsOne);
      expect(
        find.textContaining('\u00a0|\u00a0not a link', findRichText: true),
        findsOne,
      );
      final title = find.text('1 reference', findRichText: true);
      expect(title, findsOne);
      controller.setSelections([const TextSelection.collapsed(offset: 1)]);
      await tester.tapAt(tester.getCenter(title));
      expect(ran, ['refs']);
      // The caret did not move into the text.
      expect(controller.value.selection.extentOffset, 1);
    });
  });
}

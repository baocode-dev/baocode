import 'dart:async';

import 'package:bao_markdown/bao_markdown.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/ide_spinning.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/stash/stash_ai.dart' show StashAiException;
import 'package:baocode/stash/stash_disk.dart';
import 'package:baocode/stash/stash_editor.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/stash/stash_store.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/models/model_providers.dart';

void main() {
  testWidgets(
    'the bar\'s polish, clicked, keeps the bar and replaces the text',
    (tester) async {
      // Its model picked already: no menu first.
      final previous = ModelProviders.current;
      addTearDown(() => ModelProviders.current = previous);
      await (ModelProviders.current = ModelProviders.memory()).setActionsModel(
        ModelProviders.followAuxiliary,
      );
      final controller = StashEditor.controllerFor('321321\n321\n3123');
      final focus = FocusNode();
      final answer = Completer<String?>();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: StashEditor(
              controller: controller,
              store: StashStore(MemoryStashDisk()),
              ensureNote: () async => 1,
              focusNode: focus,
              autofocus: true,
              onPolish: (text, {cancel}) => answer.future,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      focus.requestFocus();
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.length,
      );
      await tester.pumpAndSettle();
      expect(find.text('Polish'), findsOneWidget);
      // Clicked with the mouse, hovered first: the bar stays, the editor
      // keeps its focus and selection.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Polish')));
      await tester.pump(const Duration(milliseconds: 700));
      await mouse.down(tester.getCenter(find.text('Polish')));
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await mouse.up();
      await tester.pump();
      expect(find.text('Polishing…'), findsOneWidget);

      answer.complete('Better text');
      await tester.pumpAndSettle();
      expect(controller.text, 'Better text');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 11),
      );
      expect(find.text('Polish'), findsOneWidget);
      await mouse.removePointer();
      await tester.pumpAndSettle(const Duration(seconds: 1));
    },
  );

  testWidgets('clicking Polishing… in the bar cancels at once and allows an '
      'immediate retry', (tester) async {
    final previous = ModelProviders.current;
    addTearDown(() => ModelProviders.current = previous);
    await (ModelProviders.current = ModelProviders.memory()).setActionsModel(
      ModelProviders.followAuxiliary,
    );
    final controller = StashEditor.controllerFor('321321\n321\n3123');
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final first = Completer<String?>();
    final second = Completer<String?>();
    var calls = 0;
    var firstCancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: StashEditor(
            controller: controller,
            store: StashStore(MemoryStashDisk()),
            ensureNote: () async => 1,
            focusNode: focus,
            autofocus: true,
            onPolish: (text, {cancel}) {
              final call = ++calls;
              if (call == 1) {
                unawaited(cancel?.then((_) => firstCancelled = true));
                return first.future;
              }
              return second.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.length,
    );
    await tester.pumpAndSettle();
    expect(find.text('Polish'), findsOneWidget);

    await tester.tap(find.text('Polish'));
    await tester.pump();
    expect(find.text('Polishing…'), findsOneWidget);
    expect(find.byType(IdeStopSpinner), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is IdeHover &&
            widget.message == englishLocalizations.stashCancelPolish,
      ),
      findsOneWidget,
    );

    // Click while polishing: cancels immediately without losing selection.
    await tester.tap(find.text('Polishing…'));
    await tester.pump();
    expect(firstCancelled, isTrue);
    expect(find.text('Polish'), findsOneWidget);
    expect(find.byType(IdeStopSpinner), findsNothing);
    expect(focus.hasFocus, isTrue);
    expect(controller.selection.isCollapsed, isFalse);

    // Immediately retry while the first request has not settled yet.
    await tester.tap(find.text('Polish'));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Polishing…'), findsOneWidget);

    // Late error from the cancelled first request must not show an error
    // dialog or clear the retry's busy state.
    first.completeError(const StashAiException('stale error'));
    await tester.pump();
    expect(find.text('Polishing…'), findsOneWidget);
    expect(find.textContaining('stale error'), findsNothing);

    second.complete('Better text');
    await tester.pumpAndSettle();
    expect(controller.text, 'Better text');
    expect(find.text('Polish'), findsOneWidget);
  });

  testWidgets('disposing the editor cancels an in-flight bar polish', (
    tester,
  ) async {
    final previous = ModelProviders.current;
    addTearDown(() => ModelProviders.current = previous);
    await (ModelProviders.current = ModelProviders.memory()).setActionsModel(
      ModelProviders.followAuxiliary,
    );
    final controller = StashEditor.controllerFor('hello world');
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final answer = Completer<String?>();
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: StashEditor(
            controller: controller,
            store: StashStore(MemoryStashDisk()),
            ensureNote: () async => 1,
            focusNode: focus,
            autofocus: true,
            onPolish: (text, {cancel}) {
              unawaited(cancel?.then((_) => cancelled = true));
              return answer.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.length,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polish'));
    await tester.pump();
    expect(cancelled, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cancelled, isTrue);
  });

  testWidgets('the bar\'s model menu, open, keeps the bar where it stands', (
    tester,
  ) async {
    // None picked: the polish opens the menu that picks one.
    final previous = ModelProviders.current;
    addTearDown(() => ModelProviders.current = previous);
    ModelProviders.current = ModelProviders.memory();
    final controller = StashEditor.controllerFor('321321\n321\n3123');
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: StashEditor(
            controller: controller,
            store: StashStore(MemoryStashDisk()),
            ensureNote: () async => 1,
            focusNode: focus,
            autofocus: true,
            onPolish: (text, {cancel}) async => 'POLISHED',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.length,
    );
    await tester.pumpAndSettle();
    expect(find.text('Polish'), findsOneWidget);

    // Polish, clicked with the mouse: no model picked yet, so the menu
    // that picks one opens. It takes the keyboard; the bar stays over
    // the selection all the same.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Polish')));
    await tester.pump(const Duration(milliseconds: 700));
    await mouse.down(tester.getCenter(find.text('Polish')));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text(englishLocalizations.aiModelFirst), findsOneWidget);
    expect(find.text('Polish'), findsOneWidget);

    // Picked from it: the polish goes on with the text selected, the bar
    // still there.
    await tester.tap(find.text(englishLocalizations.aiModelAuxiliary));
    await tester.pumpAndSettle();
    expect(ModelProviders.current.actionsModel, ModelProviders.followAuxiliary);
    expect(controller.text, 'POLISHED');
    expect(find.text('Polish'), findsOneWidget);
    await mouse.removePointer();
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('text selected by a drag, the editor not focused before, is '
      'deleted by Backspace', (tester) async {
    final controller = StashEditor.controllerFor('hello world');
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: StashEditor(
            controller: controller,
            store: StashStore(MemoryStashDisk()),
            ensureNote: () async => 1,
            focusNode: focus,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    final start = _editor(tester).caretRect(0)!.center;
    final mouse = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var x = 10.0; x <= 300; x += 10) {
      await mouse.moveTo(start + Offset(x, 0));
      await tester.pump();
    }
    await mouse.up();
    await tester.pumpAndSettle();
    expect(controller.selection.isCollapsed, isFalse);
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(controller.text, isNot(contains('hello')));
  });

  testWidgets('a triple click selects the paragraph', (tester) async {
    final controller = StashEditor.controllerFor(
      'export function tokens(input: number) {\nsecond line',
    );
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: StashEditor(
            controller: controller,
            store: StashStore(MemoryStashDisk()),
            ensureNote: () async => 1,
            focusNode: focus,
            onPolish: (text, {cancel}) async => text,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final at = _editor(tester).caretRect(2)!.center;
    Future<void> clicks(int count) async {
      for (var i = 0; i < count; i++) {
        final mouse = await tester.startGesture(
          at,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 20));
        await mouse.up();
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await clicks(2);
    await tester.pump(const Duration(milliseconds: 600));
    final text = controller.text;
    expect(controller.selection.textInside(text), 'export');
    await clicks(3);
    await tester.pumpAndSettle();
    expect(
      controller.selection.textInside(text),
      'export function tokens(input: number) {',
    );
  });

  testWidgets('a drag held past the bottom keeps scrolling, the selection '
      'with it', (tester) async {
    final controller = StashEditor.controllerFor(
      [for (var i = 0; i < 200; i++) 'line $i'].join('\n'),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 300,
              child: StashEditor(
                controller: controller,
                store: StashStore(MemoryStashDisk()),
                ensureNote: () async => 1,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Its own scrolling, as the stashes' page has it.
    final scroll = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(MarkdownEditor),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    final mouse = await tester.startGesture(
      const Offset(30, 100),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var y = 110.0; y <= 320; y += 10) {
      await mouse.moveTo(Offset(60, y));
      await tester.pump(const Duration(milliseconds: 8));
    }
    // Held still past the bottom for a second.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final scrolled = scroll.pixels;
    final extent = controller.selection.extentOffset;
    await mouse.up();
    await tester.pumpAndSettle();
    expect(scrolled, greaterThan(300));
    expect(
      tester.getRect(find.byType(StashEditor)).bottom,
      300,
      reason: 'the editor as tall as its box',
    );
    expect(extent, greaterThan(controller.text.indexOf('line 20')));
  });

  testWidgets('the color menu keeps focus and applies and clears both colors', (
    tester,
  ) async {
    final controller = StashEditor.controllerFor('hello world');
    final focus = await _edit(tester, controller);
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);

    Future<void> pick(Finder swatch) async {
      final selection = controller.selection;
      await tester.tap(find.byIcon(Codicons.symbolColor));
      await tester.pumpAndSettle();
      final position = tester.getCenter(swatch);
      await mouse.moveTo(position);
      await mouse.down(position);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(controller.selection, selection);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('A'), findsNothing);
      expect(find.byIcon(Codicons.symbolColor), findsOneWidget);
      // Still on the same text.
      expect(controller.selectedText, 'ello');
    }

    await pick(find.text('A').first);
    expect(controller.text, 'h<span style="color:red">ello</span> world');
    await pick(find.text('A').at(StashColors.text.length));
    expect(
      controller.text,
      'h<span style="color:red;background-color:mistyrose">ello</span> world',
    );
    await pick(find.text('∅').first);
    expect(
      controller.text,
      'h<span style="background-color:mistyrose">ello</span> world',
    );
    await pick(find.text('∅').last);
    expect(controller.text, 'hello world');
    await mouse.removePointer();
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('a link is typed in the bar, not a dialog', (tester) async {
    final controller = StashEditor.controllerFor('see the docs');
    await _edit(tester, controller);
    controller.selection = const TextSelection(baseOffset: 8, extentOffset: 12);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Codicons.link));
    await tester.pumpAndSettle();
    // The field in the bar (the text is the editor's own, no EditableText).
    expect(find.byType(EditableText), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'https://x.dev');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.text, 'see the [docs](https://x.dev)');
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('pictures and links are tags in the line, code a block', (
    tester,
  ) async {
    final controller = StashEditor.controllerFor(
      'a ![](1/a.png) b [X](https://x.dev "card")\n```dart\nx\ny\n```',
    );
    await _edit(tester, controller);
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();
    expect(find.text('Image 1'), findsOneWidget);
    expect(find.text('X'), findsOneWidget);
    // All on the one line.
    final y = tester.getCenter(find.text('Image 1')).dy;
    expect(tester.getCenter(find.text('X')).dy, closeTo(y, 2));
    // Code on lines of its own, its fences hidden.
    final code = find.text('x', findRichText: true);
    expect(code, findsOneWidget);
    expect(tester.getTopLeft(code).dy, greaterThan(y));
    expect(find.text('```dart', findRichText: true), findsNothing);
  });

  testWidgets('a task box is at the left edge of the text, centered on its '
      'line, and checks it', (tester) async {
    final controller = StashEditor.controllerFor('plain\n- [ ] task');
    await _edit(tester, controller);
    final box = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.checked != null,
    );
    expect(box, findsOneWidget);
    final plain = tester.getRect(find.text('plain', findRichText: true));
    final task = tester.getRect(find.text('task', findRichText: true));
    final square = tester.getRect(box);
    expect(square.left, closeTo(plain.left, 0.5));
    expect(square.center.dy, closeTo(task.center.dy, 1));
    expect(task.left, closeTo(square.right + 8, 0.5));

    await tester.tap(box);
    await tester.pump();
    expect(controller.text, 'plain\n- [x] task');
  });

  testWidgets('said clearly, its text is replaced in one step Undo takes '
      'back; its pictures and a requirement written before stay', (
    tester,
  ) async {
    final controller = StashEditor.controllerFor(
      'btn hidden ![](1/a.png) sidebar\n\n## 需求\n\nold one',
    );
    await _edit(tester, controller);
    final state = tester.state<StashEditorState>(find.byType(StashEditor));
    final asked = state.textPart!.text;
    expect(asked, isNot(contains('需求')));
    expect(asked, contains('1/a.png]'));
    // Changed meanwhile: not replaced.
    expect(state.rewrite('$asked!', 'whatever'), isFalse);
    expect(
      state.rewrite(
        asked,
        asked.replaceFirst('btn hidden', 'The button is hidden by'),
      ),
      isTrue,
    );
    await tester.pump();
    expect(
      controller.text,
      'The button is hidden by ![](1/a.png) sidebar\n\n## 需求\n\nold one',
    );

    controller.undo();
    expect(
      controller.text,
      'btn hidden ![](1/a.png) sidebar\n\n## 需求\n\nold one',
    );
  });

  testWidgets('a tag at a line\'s end: the caret goes after it, the text '
      'as it was', (tester) async {
    const text = 'see [X](https://x.dev "card")';
    final controller = StashEditor.controllerFor(text);
    await _edit(tester, controller);
    expect(controller.text, text);
    final editor = _editor(tester);
    final tag = tester.getRect(find.text('X'));
    expect(editor.caretRect(text.length)!.left, greaterThan(tag.right));
    expect(editor.caretRect(4)!.left, lessThan(tag.left));
  });

  testWidgets('the caret in a web link: a bar over it opens or edits it, '
      'the text typed on', (tester) async {
    final controller = StashEditor.controllerFor(
      'see [docs](https://x.dev/guide) now',
    );
    final focus = await _edit(tester, controller);
    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.pumpAndSettle();
    expect(find.text('x.dev/guide'), findsOneWidget);
    // Typing goes on in the text: the bar takes no focus.
    expect(focus.hasFocus, isTrue);
    // Beside the link, not in it: no bar.
    controller.selection = const TextSelection.collapsed(offset: 33);
    await tester.pumpAndSettle();
    expect(find.text('x.dev/guide'), findsNothing);
    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Codicons.edit));
    await tester.pumpAndSettle();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 5, extentOffset: 9),
    );
    // The link field, with the link in it.
    expect(find.byType(EditableText), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'https://x.dev/guide',
    );
  });

  testWidgets('another stash shown closes the link field', (tester) async {
    final first = StashEditor.controllerFor('see docs');
    final focus = FocusNode();
    final store = StashStore(MemoryStashDisk());
    Widget editor(MarkdownController controller) => MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        body: StashEditor(
          controller: controller,
          store: store,
          ensureNote: () async => 1,
          focusNode: focus,
          autofocus: true,
        ),
      ),
    );
    await tester.pumpWidget(editor(first));
    focus.requestFocus();
    await tester.pumpAndSettle();
    first.selection = const TextSelection(baseOffset: 4, extentOffset: 8);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Codicons.link));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    await tester.pumpWidget(editor(StashEditor.controllerFor('other')));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('code pasted amid a line goes on lines of its own', (
    tester,
  ) async {
    final controller = StashEditor.controllerFor('abc def');
    await _edit(tester, controller);
    controller.selection = const TextSelection.collapsed(offset: 3);
    tester
        .state<StashEditorState>(find.byType(StashEditor))
        .insertMarkdown('```\nx = 1\n```');
    await tester.pumpAndSettle();
    expect(controller.text, 'abc\n```\nx = 1\n```\n def');
    expect(controller.infoOf(2).kind, MdLineKind.fence);
    // The caret after it.
    expect(controller.selection.baseOffset, 18);
  });

  testWidgets('a code block: started with ```lang and Enter, typed in, '
      'left with Enter on its empty last line, written as a fence', (
    tester,
  ) async {
    final controller = StashEditor.controllerFor('note\n```dart');
    await _edit(tester, controller);
    controller.selection = TextSelection.collapsed(offset: controller.length);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await _type(tester, 'var a = 1;');
    // A new line, as the system's text input types it.
    await _type(tester, '\n');
    expect(
      controller
          .infoOf(controller.lineAt(controller.selection.baseOffset))
          .kind,
      MdLineKind.fence,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await _type(tester, 'after');
    await tester.pumpAndSettle();
    expect(controller.text, 'note\n```dart\nvar a = 1;\n```\nafter');
  });

  testWidgets('[[ offers the other stashes; picked, one goes in as a link', (
    tester,
  ) async {
    final controller = StashEditor.controllerFor('see ');
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: StashEditor(
            controller: controller,
            store: StashStore(MemoryStashDisk()),
            ensureNote: () async => 1,
            focusNode: focus,
            autofocus: true,
            refs: StashRefs(
              stashes: () => const [
                (id: 3, title: 'Login bug'),
                (id: 4, title: 'Sidebar'),
              ],
              projects: () => const [],
              open: opened.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    await _type(tester, '[[side');
    await tester.pumpAndSettle();
    expect(find.text('Sidebar'), findsOneWidget);
    expect(find.text('Login bug'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, 'see [Sidebar](stash:4) ');
    expect(find.text('#4'), findsNothing, reason: 'the menu closed');
  });

  testWidgets('⌘B and ⌘I mark the selection', (tester) async {
    final controller = StashEditor.controllerFor('make it bold');
    await _edit(tester, controller);
    controller.selection = const TextSelection(baseOffset: 8, extentOffset: 12);
    await tester.pump();
    final command = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control;
    await tester.sendKeyDownEvent(command);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(command);
    await tester.pump();
    expect(controller.text, 'make it **bold**');
    await tester.sendKeyDownEvent(command);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(command);
    await tester.pump();
    expect(controller.text, 'make it ***bold***');
  });

  test('code is told from prose and markdown', () {
    expect(
      StashEditorState.looksLikeCode('for the record I think\nwe ship'),
      isFalse,
    );
    expect(
      StashEditorState.looksLikeCode(
        '- item\n  - nested a\n  - nested b\n- two',
      ),
      isFalse,
    );
    expect(
      StashEditorState.looksLikeCode('const a = 1;\nconsole.log(a);'),
      isTrue,
    );
    expect(
      StashEditorState.looksLikeCode('def f(x):\n    return x * 2'),
      isTrue,
    );
    expect(
      StashEditorState.looksLikeCode('if (ready) {\n  start();\n}'),
      isTrue,
    );
  });

  testWidgets('a card put in is undone at once, the space after it too', (
    tester,
  ) async {
    // As read from the file: nothing to undo of it.
    final controller = StashEditor.controllerFor('see');
    await _edit(tester, controller);
    final state = tester.state<StashEditorState>(find.byType(StashEditor));
    controller.selection = const TextSelection.collapsed(offset: 3);
    state.insertCard('https://x.dev');
    await tester.pumpAndSettle();
    const card = '[https://x.dev](https://x.dev "card")';
    expect(controller.text, 'see$card ');
    // The caret after it, typing on.
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: 3 + card.length + 1),
    );
    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, 'see');
    expect(controller.canUndo, isFalse);
  });

  testWidgets('a click in a code block puts the caret in its code', (
    tester,
  ) async {
    final controller = StashEditor.controllerFor('before\n```\na\nb\nc\n```');
    await _edit(tester, controller);
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();
    final b = find.text('b', findRichText: true);
    await tester.tapAt(tester.getCenter(b));
    await tester.pumpAndSettle();
    final offset = controller.selection.baseOffset;
    expect(controller.lineAt(offset), 3);
    await _type(tester, 'X');
    expect(controller.lines.content(3), anyOf('Xb', 'bX'));
  });

  testWidgets('files dragged in go where the pointer is, shown as they '
      'come', (tester) async {
    final controller = StashEditor.controllerFor('hello world');
    await _edit(tester, controller);
    controller.selection = const TextSelection.collapsed(offset: 0);
    final editor = tester.state<StashEditorState>(find.byType(StashEditor));
    // Past the text's end, on its line.
    final over = _editor(tester).caretRect(0)!.center + const Offset(300, 0);
    editor.fileDragOver(over, const []);
    await tester.pump();
    expect(find.byType(ColoredBox), findsWidgets);
    editor.fileDrop(over, const []);
    await tester.pumpAndSettle();
    expect(controller.selection, const TextSelection.collapsed(offset: 11));
  });

  testWidgets('the caret follows the text after the panel shows another '
      'stash (a new controller)', (tester) async {
    final focus = FocusNode();
    final store = StashStore(MemoryStashDisk());
    Widget editor(MarkdownController controller) => MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        body: StashEditor(
          controller: controller,
          store: store,
          ensureNote: () async => 1,
          focusNode: focus,
          autofocus: true,
        ),
      ),
    );
    await tester.pumpWidget(editor(StashEditor.controllerFor('')));
    await tester.pumpAndSettle();
    final next = StashEditor.controllerFor('');
    await tester.pumpWidget(editor(next));
    focus.requestFocus();
    await tester.pumpAndSettle();
    final start = _editor(tester).caretRect()!.left;
    next.replace(
      0,
      0,
      '321321',
      selection: const TextSelection.collapsed(offset: 6),
    );
    await tester.pump();
    expect(_editor(tester).caretRect()!.left, greaterThan(start + 40));
    next.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    expect(_editor(tester).caretRect()!.left, lessThan(start + 60));
    expect(_editor(tester).caretRect()!.left, greaterThan(start + 20));
  });

  testWidgets('pictures and files show above the text, each once', (
    tester,
  ) async {
    const text = 'a![](1/a.png) b[x.pdf](1/x.pdf) c![](1/a.png) d';
    final controller = StashEditor.controllerFor(text);
    expect(StashAttachment.of(text), const [
      StashAttachment.picture('1/a.png'),
      StashAttachment.file('1/x.pdf', 'x.pdf'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StashAttachments(
            controller: controller,
            store: StashStore(MemoryStashDisk()),
          ),
        ),
      ),
    );
    expect(find.text('x.pdf'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    // Another put in: shown at once; all gone, nothing shows.
    controller.replace(0, 0, '![](1/b.png)');
    await tester.pump();
    expect(find.byType(Image), findsNWidgets(2));
    controller.replace(0, controller.length, '');
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('x.pdf'), findsNothing);
  });

  test('polished, pictures and files go as their paths and come back', () {
    const slice = 'see **this** ![](1/a.png) and [b.pdf](1/b.pdf)';
    final asked = stashTextForModel(slice, (path) => '/stash/$path');
    expect(asked.text, 'see **this** [/stash/1/a.png] and [/stash/1/b.pdf]');

    // Put elsewhere, one left out: in its new place, the other after it.
    final back = stashTextFromModel(
      'Look at [/stash/1/a.png]: **this**.',
      asked.attachments,
      endsLine: false,
    );
    expect(back, 'Look at ![](1/a.png): **this**. [b.pdf](1/b.pdf)');
    expect(
      stashTextFromModel('x', const [], endsLine: true),
      'x\n',
      reason: 'the line goes on after it, as it did',
    );
  });

  testWidgets('copied and pasted in a stash, pictures stay pictures; as '
      'text, their paths', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        } else if (call.method == 'Clipboard.getData') {
          return {'text': clipboard};
        } else if (call.method == 'Clipboard.hasStrings') {
          return {'value': clipboard != null};
        }
        return null;
      },
    );
    final controller = StashEditor.controllerFor('a ![](/pics/a.png) b');
    await _edit(tester, controller);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.length,
    );
    await _editor(tester).copy();
    expect(clipboard, 'a @/pics/a.png b');

    controller.selection = TextSelection.collapsed(offset: controller.length);
    await _editor(tester).paste();
    await tester.pumpAndSettle();
    expect(controller.text, 'a ![](/pics/a.png) ba ![](/pics/a.png) b');
  });
}

MarkdownEditorState _editor(WidgetTester tester) =>
    tester.state<MarkdownEditorState>(find.byType(MarkdownEditor));

/// Typed in, as the platform's input sends it: [text] where the caret is.
/// What was typed last is what the input has, until the editor tells it
/// otherwise.
Future<void> _type(WidgetTester tester, String text) async {
  final told = tester.testTextInput.editingState!;
  final value = identical(told, _told) ? _typed! : _valueOf(told);
  _told = told;
  final (a, b) = (value.selection.start, value.selection.end);
  _typed = TextEditingValue(
    text: value.text.replaceRange(a, b, text),
    selection: TextSelection.collapsed(offset: a + text.length),
  );
  tester.testTextInput.updateEditingValue(_typed!);
  await tester.pump();
}

Map<String, dynamic>? _told;
TextEditingValue? _typed;

TextEditingValue _valueOf(Map<String, dynamic> state) {
  final base = state['selectionBase'] as int;
  final extent = state['selectionExtent'] as int;
  return TextEditingValue(
    text: state['text'] as String,
    selection: TextSelection(baseOffset: base, extentOffset: extent),
  );
}

/// [controller] in an editor, focused.
Future<FocusNode> _edit(
  WidgetTester tester,
  MarkdownController controller,
) async {
  final focus = FocusNode();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        body: StashEditor(
          controller: controller,
          store: StashStore(MemoryStashDisk()),
          ensureNote: () async => 1,
          focusNode: focus,
          autofocus: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  focus.requestFocus();
  await tester.pump();
  return focus;
}

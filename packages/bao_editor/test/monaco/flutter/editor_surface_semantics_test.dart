import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';

final _textSemanticsFinder = find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.textField == true,
);

EditorSurfaceController _controller(String text) {
  final controller = EditorSurfaceController()
    ..value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  addTearDown(controller.dispose);
  return controller;
}

FocusNode _focusNode({bool canRequestFocus = true}) {
  final focus = FocusNode(canRequestFocus: canRequestFocus);
  addTearDown(focus.dispose);
  return focus;
}

Future<void> _mount(
  WidgetTester tester,
  EditorSurfaceController controller,
  FocusNode focus, {
  bool readOnly = false,
  bool wrap = false,
  TextDirection direction = TextDirection.ltr,
}) => tester.pumpWidget(
  MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          height: 60,
          child: EditorSurface(
            controller: controller,
            focusNode: focus,
            readOnly: readOnly,
            wrap: wrap,
          ),
        ),
      ),
    ),
  ),
);

SemanticsNode _node(WidgetTester tester) =>
    tester.getSemantics(_textSemanticsFinder);

void _perform(WidgetTester tester, SemanticsAction action, [Object? args]) {
  final node = _node(tester);
  node.owner!.performAction(node.id, action, args);
}

BuildContext _actionContext(WidgetTester tester) => tester.element(
  find.descendant(of: find.byType(EditorSurface), matching: find.byType(Focus)),
);

void main() {
  testWidgets(
    'one stable document node exposes raw text and oriented selection',
    (tester) async {
      final text = 'a\t😀\r\nאב é\r${List.filled(20, 'line').join('\n')}';
      final controller = _controller(text);
      final editingValue = TextEditingValue(
        text: text,
        selection: const TextSelection(baseOffset: 4, extentOffset: 1),
        composing: const TextRange(start: 1, end: 4),
      );
      controller.value = editingValue;
      final focus = _focusNode();
      await _mount(tester, controller, focus, direction: TextDirection.rtl);
      final id = _node(tester).id;
      expect(
        _node(tester),
        isSemantics(
          value: text,
          textDirection: TextDirection.rtl,
          isTextField: true,
          isMultiline: true,
          isReadOnly: false,
          isFocusable: true,
          isFocused: false,
          hasFocusAction: true,
          hasTapAction: true,
          hasSetTextAction: false,
          hasSetSelectionAction: false,
          children: const [],
        ),
      );
      expect(
        _node(tester).getSemanticsData().textSelection,
        editingValue.selection,
      );
      expect(controller.value, editingValue);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);

      _perform(tester, SemanticsAction.focus);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(_node(tester).id, id);
      expect(_node(tester), isSemantics(isFocused: true));
      expect(
        controller.value,
        editingValue,
      ); // Semantics/focus must not commit IME.

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(EditorSurface)),
          scrollDelta: const Offset(0, 40),
        ),
      );
      await tester.pump();
      expect(_node(tester).id, id);
      expect(_node(tester).getSemanticsData().value, text);
      expect(controller.value, editingValue);

      controller.value = editingValue.copyWith(
        text: '$text\r\nend',
        selection: TextSelection(baseOffset: text.length, extentOffset: 1),
      );
      await tester.pump();
      await _mount(tester, controller, focus, wrap: true);
      expect(_node(tester).id, id);
      expect(_node(tester).getSemanticsData().value, controller.value.text);
      expect(
        _node(tester).getSemanticsData().textSelection,
        controller.value.selection,
      );
      final textNodes = <SemanticsNode>[];
      void collect(SemanticsNode node) {
        if (node.getSemanticsData().flagsCollection.isTextField) {
          textNodes.add(node);
        }
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      collect(_node(tester).owner!.rootSemanticsNode!);
      expect(textNodes.map((node) => node.id), [id]);
      expect(_node(tester), isSemantics(children: const []));
    },
  );

  testWidgets('setText needs focus and commits composition with raw UTF-16', (
    tester,
  ) async {
    final controller = _controller('漢');
    controller.value = controller.value.copyWith(
      composing: const TextRange(start: 0, end: 1),
    );
    final focus = _focusNode();
    await _mount(tester, controller, focus);
    _perform(tester, SemanticsAction.setText, 'ignored');
    expect(controller.value.text, '漢');
    _perform(tester, SemanticsAction.tap);
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);

    const replacement = 'A\r\n😀\t漢\rz';
    _perform(tester, SemanticsAction.setText, replacement);
    await tester.pump();
    expect(controller.document.text, replacement);
    expect(
      controller.value,
      const TextEditingValue(
        text: replacement,
        selection: TextSelection.collapsed(offset: replacement.length),
      ),
    );
    expect(_node(tester).getSemanticsData().value, replacement);
    expect(tester.testTextInput.editingState?['text'], replacement);
    expect(controller.undo(), isTrue);
    expect(controller.value.text, '漢');
  });

  testWidgets('setSelection preserves raw base/extent without rewriting text', (
    tester,
  ) async {
    final controller = _controller('a😀\r\nb漢');
    controller.value = controller.value.copyWith(
      composing: const TextRange(start: 6, end: 7),
    );
    final focus = _focusNode();
    await _mount(tester, controller, focus);
    focus.requestFocus();
    await tester.pump();
    _perform(tester, SemanticsAction.setSelection, {'base': 7, 'extent': 1});
    await tester.pump();
    expect(controller.value.text, 'a😀\r\nb漢');
    expect(controller.document.text, 'a😀\r\nb漢');
    expect(controller.value.composing, TextRange.empty);
    expect(
      controller.value.selection,
      const TextSelection(baseOffset: 7, extentOffset: 1),
    );
    expect(
      _node(tester).getSemanticsData().textSelection,
      controller.value.selection,
    );
    _perform(tester, SemanticsAction.setSelection, {'base': 4, 'extent': 2});
    expect(
      controller.value.selection,
      const TextSelection(baseOffset: 4, extentOffset: 2),
    ); // Raw offsets may address the interior of a CRLF or surrogate pair.
    _perform(tester, SemanticsAction.setSelection, {'base': 100, 'extent': 1});
    expect(controller.value.selection.baseOffset, 7);
    final before = controller.value;
    _perform(tester, SemanticsAction.setSelection, {'base': -1, 'extent': -1});
    expect(controller.value, before);

    final stale = tester.widget<Semantics>(_textSemanticsFinder).properties;
    focus.unfocus();
    await tester.pump();
    stale.onSetSelection!(const TextSelection.collapsed(offset: 0));
    stale.onSetText!('ignored after blur');
    expect(controller.value, before);
    expect(
      _node(tester),
      isSemantics(
        isFocused: false,
        hasSetSelectionAction: false,
        hasSetTextAction: false,
        hasMoveCursorForwardByCharacterAction: false,
        hasMoveCursorBackwardByCharacterAction: false,
      ),
    );
  });

  testWidgets('cursor actions move the extent and keep controller boundaries', (
    tester,
  ) async {
    final controller = _controller('a😀\r\né');
    controller.select(0, 0);
    final focus = _focusNode();
    await _mount(tester, controller, focus);
    focus.requestFocus();
    await tester.pump();
    expect(
      _node(tester),
      isSemantics(hasMoveCursorBackwardByCharacterAction: false),
    );
    _perform(tester, SemanticsAction.moveCursorForwardByCharacter, false);
    await tester.pump();
    expect(
      controller.value.selection,
      const TextSelection.collapsed(offset: 1),
    );
    controller.select(0, 1);
    await tester.pump();
    _perform(tester, SemanticsAction.moveCursorForwardByCharacter, false);
    await tester.pump();
    expect(
      controller.value.selection,
      const TextSelection.collapsed(offset: 3),
    );
    _perform(tester, SemanticsAction.moveCursorForwardByCharacter, true);
    await tester.pump();
    expect(
      controller.value.selection,
      const TextSelection(baseOffset: 3, extentOffset: 5),
    );
    _perform(tester, SemanticsAction.moveCursorForwardByCharacter, true);
    await tester.pump();
    expect(
      controller.value.selection,
      const TextSelection(baseOffset: 3, extentOffset: 7),
    );
    expect(
      _node(tester),
      isSemantics(hasMoveCursorForwardByCharacterAction: false),
    );
    for (var step = 0; step < 3; step++) {
      _perform(tester, SemanticsAction.moveCursorBackwardByCharacter, true);
      await tester.pump();
    }
    expect(
      controller.value.selection,
      const TextSelection(baseOffset: 3, extentOffset: 1),
    );
    expect(
      _node(tester).getSemanticsData().textSelection,
      controller.value.selection,
    );
    expect(controller.value.text, 'a😀\r\né');
  });

  testWidgets('clipboard and custom select-all use public Flutter actions', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    String? clipboard;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      } else if (call.method == 'Clipboard.getData') {
        return {'text': clipboard};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final controller = _controller('a😀b');
    controller.value = controller.value.copyWith(
      selection: const TextSelection(baseOffset: 3, extentOffset: 1),
      composing: const TextRange(start: 1, end: 3),
    );
    final focus = _focusNode();
    await _mount(tester, controller, focus);
    focus.requestFocus();
    await tester.pump();
    _perform(tester, SemanticsAction.copy);
    await tester.pump();
    expect(clipboard, '😀');
    expect(controller.value.composing, const TextRange(start: 1, end: 3));
    _perform(tester, SemanticsAction.cut);
    await tester.pump();
    expect(controller.value.text, 'ab');
    expect(controller.value.composing, TextRange.empty);
    clipboard = '😀\r\n';
    _perform(tester, SemanticsAction.paste);
    await tester.pump();
    expect(controller.value.text, 'a😀\r\nb');
    final actionIds = _node(tester)
        .getSemanticsData()
        .customSemanticsActionIds!;
    expect(actionIds, hasLength(1));
    _perform(tester, SemanticsAction.customAction, actionIds.single);
    await tester.pump();
    expect(
      controller.value.selection,
      TextSelection(baseOffset: 0, extentOffset: controller.value.text.length),
    );

    final context = _actionContext(tester);
    await (Actions.invoke(context, CopySelectionTextIntent.copy)
        as Future<void>);
    expect(clipboard, controller.value.text);
    await (Actions.invoke(
      context,
      const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
    ) as Future<void>);
    expect(controller.value.text, isEmpty);
    await (Actions.invoke(
      context,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    ) as Future<void>);
    expect(controller.value.text, 'a😀\r\nb');
    Actions.invoke(
      context,
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
    );
    expect(controller.value.selection.start, 0);
    expect(controller.value.selection.end, controller.value.text.length);
    await tester.pump();
    focus.unfocus();
    await tester.pump();
    expect(
      Actions.find<CopySelectionTextIntent>(_actionContext(tester))
          .isEnabled(CopySelectionTextIntent.copy),
      isFalse,
    );
  });

  testWidgets(
    'readOnly blocks all mutation routes but allows selection and copy',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      String? clipboard;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        } else if (call.method == 'Clipboard.getData') {
          return {'text': clipboard};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final controller = _controller('a😀b');
      controller.select(1, 3);
      final focus = _focusNode();
      await _mount(tester, controller, focus);
      focus.requestFocus();
      await tester.pump();
      final id = _node(tester).id;
      final stale = tester.widget<Semantics>(_textSemanticsFinder).properties;
      final inputClient =
          tester.state(find.byType(EditorSurface)) as TextInputClient;
      await _mount(tester, controller, focus, readOnly: true);
      expect(_node(tester).id, id);
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(
        _node(tester),
        isSemantics(
          isFocused: true,
          isReadOnly: true,
          hasSetTextAction: false,
          hasSetSelectionAction: true,
          hasCopyAction: true,
          hasCutAction: false,
          hasPasteAction: false,
        ),
      );
      final before = controller.value;
      stale.onSetText!('blocked');
      stale.onCut!();
      stale.onPaste!();
      inputClient.updateEditingValue(const TextEditingValue(text: 'blocked'));
      inputClient.performAction(TextInputAction.newline);
      for (final selector in [
        'deleteBackward:',
        'deleteForward:',
        'cut:',
        'paste:',
        'undo:',
        'redo:',
      ]) {
        inputClient.performSelector(selector);
      }
      for (final key in [
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.delete,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.tab,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      for (final key in [
        LogicalKeyboardKey.keyX,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyZ,
        LogicalKeyboardKey.keyY,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.value, before);
      final context = _actionContext(tester);
      expect(
        Actions.find<CopySelectionTextIntent>(context).isEnabled(
          const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
        ),
        isFalse,
      );
      expect(
        Actions.find<PasteTextIntent>(context)
            .isEnabled(const PasteTextIntent(SelectionChangedCause.keyboard)),
        isFalse,
      );
      expect(
        Actions.find<CopySelectionTextIntent>(context)
            .isEnabled(CopySelectionTextIntent.copy),
        isTrue,
      );
      _perform(tester, SemanticsAction.setSelection, {'base': 4, 'extent': 0});
      await tester.pump();
      expect(
        controller.value.selection,
        const TextSelection(baseOffset: 4, extentOffset: 0),
      );
      _perform(tester, SemanticsAction.copy);
      await tester.pump();
      expect(clipboard, 'a😀b');
      controller.value = const TextEditingValue(
        text: 'external',
        selection: TextSelection.collapsed(offset: 8),
      );
      await tester.pump();
      expect(_node(tester).getSemanticsData().value, 'external');
      await _mount(tester, controller, focus);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      _perform(tester, SemanticsAction.setText, 'editable again');
      await tester.pump();
      expect(controller.value.text, 'editable again');
    },
  );

  for (final action in [SemanticsAction.cut, SemanticsAction.paste]) {
    for (final transition in ['readOnly', 'blur', 'controller', 'dispose']) {
      testWidgets('${action.name} cancels pending mutation after $transition', (
        tester,
      ) async {
        final messenger = tester.binding.defaultBinaryMessenger;
        final pending = Completer<Object?>();
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.getData' ||
              call.method == 'Clipboard.setData') {
            return pending.future;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final controller = _controller('original');
        controller.selectAll();
        final before = controller.value;
        final focus = _focusNode();
        await _mount(tester, controller, focus);
        focus.requestFocus();
        await tester.pump();
        _perform(tester, action);
        await tester.pump();
        switch (transition) {
          case 'readOnly':
            await _mount(tester, controller, focus, readOnly: true);
          case 'blur':
            focus.unfocus();
            await tester.pump();
          case 'controller':
            await _mount(tester, _controller('replacement controller'), focus);
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
        }
        pending.complete(
          action == SemanticsAction.paste ? {'text': 'changed'} : null,
        );
        await tester.pump();
        expect(controller.value, before);
      });
    }
  }

  testWidgets(
    'nonfocusable and empty editors have truthful action availability',
    (tester) async {
      final controller = _controller('');
      final focus = _focusNode(canRequestFocus: false);
      await _mount(tester, controller, focus);
      expect(
        _node(tester),
        isSemantics(
          value: '',
          isTextField: true,
          isMultiline: true,
          isFocusable: false,
          hasFocusAction: false,
          hasTapAction: false,
          hasSetTextAction: false,
          hasCopyAction: false,
          hasCutAction: false,
          hasPasteAction: false,
        ),
      );
      expect(tester.testTextInput.hasAnyClients, isFalse);
      focus.canRequestFocus = true;
      focus.requestFocus();
      await tester.pump();
      expect(
        _node(tester),
        isSemantics(
          isFocused: true,
          hasSetTextAction: true,
          hasSetSelectionAction: true,
          hasPasteAction: true,
          hasCopyAction: false,
          hasCutAction: false,
          hasMoveCursorForwardByCharacterAction: false,
          hasMoveCursorBackwardByCharacterAction: false,
          customActions: const [],
        ),
      );
      controller.value = const TextEditingValue(text: 'invalid selection');
      await tester.pump();
      expect(_node(tester).getSemanticsData().textSelection, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}

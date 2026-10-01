import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show PointerScrollEvent;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_document_model.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_surface_controller.dart';

void main() {
  test('revealSelection notifies without changing value or undo history', () {
    final document = EditorDocumentModel('é');
    final controller = EditorSurfaceController(document: document);
    addTearDown(() {
      controller.dispose();
      document.dispose();
    });
    const composing = TextEditingValue(
      text: 'é',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    controller.value = composing;
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.revealSelection();
    controller.revealSelection();
    expect(notifications, 2);
    expect(controller.value, composing);
    expect(document.text, composing.text);
    expect(document.canUndo, isFalse);
    controller.dispose();
    controller.revealSelection();
    expect(notifications, 2);
  });

  test(
    'controller keeps raw UTF-16 input and atomically preserves composing',
    () {
      final document = EditorDocumentModel('A\r\n😀\rZ');
      final controller = EditorSurfaceController(document: document);
      addTearDown(() {
        controller.dispose();
        document.dispose();
      });
      final values = <TextEditingValue>[];
      controller.addListener(() => values.add(controller.value));
      const first = TextEditingValue(
        text: 'A\r\n😀漢\rZ',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 5, end: 6),
      );
      controller.value = first;
      expect(document.text, first.text);
      expect(values, [first]);
      const commit = TextEditingValue(
        text: 'A\r\n😀字\rZ',
        selection: TextSelection.collapsed(offset: 6),
      );
      controller.value = commit;
      expect(document.text, commit.text);
      expect(controller.value.composing, TextRange.empty);
      // The composition and its commit are one undo step.
      controller.undo();
      expect(controller.value.text, 'A\r\n😀\rZ');
      controller.redo();
      expect(controller.value.text, commit.text);
    },
  );

  test(
    'IME can replace one CRLF code unit without normalized line endings',
    () {
      final controller = EditorSurfaceController(
        document: EditorDocumentModel('x\r\ny'),
      );
      addTearDown(() {
        controller.dispose();
        controller.document.dispose();
      });
      controller.value = const TextEditingValue(
        text: 'x\ny',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(controller.document.text, 'x\ny');
      controller.undo();
      expect(controller.document.text, 'x\r\ny');
    },
  );

  test('selection, deletion, and insertion respect UTF-16 offsets', () {
    final controller = EditorSurfaceController(
      document: EditorDocumentModel('a😀b'),
    );
    addTearDown(() {
      controller.dispose();
      controller.document.dispose();
    });
    controller.select(3, 1);
    expect(controller.value.selection.baseOffset, 3);
    expect(controller.value.selection.extentOffset, 1);
    controller.replaceSelection('中');
    expect(controller.value.text, 'a中b');
    expect(controller.value.selection.extentOffset, 2);
    controller.deleteBackward();
    expect(controller.value.text, 'ab');
    controller.selectAll();
    expect(
      controller.value.selection,
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
  });

  group('pinned grapheme navigation and deletion', () {
    const clusters = <String, String>{
      'combining marks': 'ȩ́',
      'ZWJ family': '👨‍👩‍👧‍👦',
      'skin tone': '👍🏽',
      'emoji variation selector': '✈️',
      'keycap': '1️⃣',
      'Hangul jamo': '각',
      'flag': '🇨🇦',
      // The pinned VS Code helper merges the full regional-indicator run.
      'pinned adjacent flags': '🇺🇸🇨🇦',
      'CRLF': '\r\n',
    };

    for (final entry in clusters.entries) {
      test('${entry.key} is one movement and deletion unit', () {
        final cluster = entry.value;
        final text = 'a${cluster}z';
        final document = EditorDocumentModel(text);
        final controller = EditorSurfaceController(document: document);
        addTearDown(() {
          controller.dispose();
          document.dispose();
        });
        final start = 1;
        final end = 1 + cluster.length;

        controller.select(start, start);
        controller.moveHorizontal(1);
        expect(controller.value.selection.extentOffset, end);
        controller.moveHorizontal(-1);
        expect(controller.value.selection.extentOffset, start);
        controller.moveHorizontal(1, extend: true);
        expect(
          controller.value.selection,
          TextSelection(baseOffset: start, extentOffset: end),
        );
        controller.select(end, end);
        controller.moveHorizontal(-1, extend: true);
        expect(
          controller.value.selection,
          TextSelection(baseOffset: end, extentOffset: start),
        );

        controller.select(end, end);
        final notifications = <TextEditingValue>[];
        controller.addListener(() => notifications.add(controller.value));
        controller.deleteBackward();
        expect(controller.value.text, 'az');
        expect(document.text, 'az');
        expect(controller.value.selection.extentOffset, start);
        expect(notifications, hasLength(1));
        controller.undo();
        expect(controller.value.text, text);
        controller.select(start, start);
        controller.deleteForward();
        expect(controller.value.text, 'az');
        controller.undo();
        expect(controller.value.text, text);

        // IMEs may deliver any raw UTF-16 offset, even inside surrogate pairs.
        // Preserve it on assignment, then snap a user command to the cluster.
        for (var interior = start + 1; interior < end; interior++) {
          final raw = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: interior),
            composing: TextRange(start: start, end: end),
          );
          controller.value = raw;
          expect(controller.value, raw);
          controller.moveHorizontal(1);
          expect(controller.value.selection.extentOffset, end);
          controller.value = raw;
          controller.moveHorizontal(-1);
          expect(controller.value.selection.extentOffset, start);
          controller.value = raw;
          controller.deleteForward();
          expect(
            controller.value.text,
            'az',
            reason: 'forward offset $interior',
          );
          controller.undo();
          controller.value = raw;
          controller.deleteBackward();
          expect(
            controller.value.text,
            'az',
            reason: 'backward offset $interior',
          );
          controller.undo();
          expect(controller.value.text, text);
        }
      });
    }

    test(
      'movement is bounded, and extent movement does not collapse to edge',
      () {
        final document = EditorDocumentModel('é😀z');
        final controller = EditorSurfaceController(document: document);
        addTearDown(() {
          controller.dispose();
          document.dispose();
        });
        controller.select(0, 0);
        controller.moveHorizontal(-1);
        controller.deleteBackward();
        expect(controller.value.selection.extentOffset, 0);
        expect(controller.value.text, document.savedText);
        controller.select(document.text.length, document.text.length);
        controller.moveHorizontal(1);
        controller.deleteForward();
        expect(controller.value.selection.extentOffset, document.text.length);
        expect(controller.value.text, document.savedText);
        controller.select(0, 2);
        controller.moveHorizontal(
          1,
        ); // Keyboard collapses without another step.
        expect(controller.value.selection.extentOffset, 2);
        controller.select(0, 2);
        controller.moveHorizontal(1, collapseSelection: false);
        expect(
          controller.value.selection,
          const TextSelection.collapsed(offset: 4),
        );
        controller.select(4, 2);
        controller.moveHorizontal(-1, collapseSelection: false);
        expect(
          controller.value.selection,
          const TextSelection.collapsed(offset: 0),
        );
      },
    );

    test(
      'explicit selection deletion preserves raw offsets and mixed endings',
      () {
        final document = EditorDocumentModel('﻿é\r\nA\rB\n');
        final controller = EditorSurfaceController(document: document);
        addTearDown(() {
          controller.dispose();
          document.dispose();
        });
        controller.select(2, 3); // Only the explicitly selected combining mark.
        controller.deleteForward();
        expect(controller.value.text, '﻿e\r\nA\rB\n');
        controller.undo();
        expect(controller.value.text, document.savedText);
        controller.select(
          4,
          4,
        ); // Inside CRLF: command deletes the full newline.
        controller.deleteBackward();
        expect(controller.value.text, '﻿éA\rB\n');
        controller.undo();
        expect(controller.value.text, document.savedText);
      },
    );
  });

  testWidgets('attaches only on focus, paints without TextField, handles IME', (
    tester,
  ) async {
    final controller = EditorSurfaceController(
      document: EditorDocumentModel('iW中😀'),
    );
    addTearDown(() {
      controller.dispose();
      controller.document.dispose();
    });
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 100,
            child: EditorSurface(controller: controller, focusNode: focus),
          ),
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(EditableText), findsNothing);
    expect(tester.testTextInput.hasAnyClients, isFalse);
    focus.requestFocus();
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(
      tester.testTextInput.setClientArgs?['inputType']?['name'],
      'TextInputType.multiline',
    );
    const composing = TextEditingValue(
      text: 'iW中😀漢',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 5, end: 6),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    expect(controller.value, composing);
    expect(controller.document.text, composing.text);
    expect(
      tester.testTextInput.log.map((call) => call.method),
      containsAll([
        'TextInput.setEditableSizeAndTransform',
        'TextInput.setCaretRect',
        'TextInput.setMarkedTextRect',
      ]),
    );
    final caretCall = tester.testTextInput.log.lastWhere(
      (call) => call.method == 'TextInput.setCaretRect',
    );
    final x = (caretCall.arguments as Map<String, dynamic>)['x'] as num;
    expect(x, greaterThan(10)); // Measured glyph position, not column * width.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'iW中😀字',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();
    expect(controller.value.composing, TextRange.empty);
    expect(controller.document.text, 'iW中😀字');
    final clientId =
        (tester.testTextInput.log
                        .firstWhere(
                          (call) => call.method == 'TextInput.setClient',
                        )
                        .arguments
                    as List<dynamic>)
                .first
            as int;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SystemChannels.textInput.name,
          SystemChannels.textInput.codec.encodeMethodCall(
            MethodCall('TextInputClient.performSelectors', <dynamic>[
              clientId,
              <String>['moveLeft:', 'deleteBackward:'],
            ]),
          ),
          (_) {},
        );
    await tester.pump();
    expect(controller.document.text, 'iW中字');
    focus.unfocus();
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(tester.testTextInput.hasAnyClients, isFalse);
  });

  testWidgets('copy, cut, paste, and selectAll use the platform clipboard', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? clipboard;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map<String, dynamic>)['text'] as String?;
      } else if (call.method == 'Clipboard.getData') {
        return <String, String?>{'text': clipboard};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final document = EditorDocumentModel('a😀b');
    final controller = EditorSurfaceController(document: document);
    addTearDown(() {
      controller.dispose();
      document.dispose();
    });
    controller.select(1, 3);
    await controller.copy();
    expect(clipboard, '😀');
    await controller.cut();
    expect(controller.value.text, 'ab');
    controller.select(1, 1);
    await controller.paste();
    expect(controller.value.text, 'a😀b');
    controller.selectAll();
    expect(controller.value.selection.start, 0);
    expect(controller.value.selection.end, 4);
  });

  for (final change in ['selection', 'text', 'disposed', 'editability']) {
    testWidgets('pending paste is cancelled after $change changes', (
      tester,
    ) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final clipboard = Completer<Object?>();
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) {
        if (call.method == 'Clipboard.getData') return clipboard.future;
        return Future<Object?>.value();
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final document = EditorDocumentModel('abc');
      final controller = EditorSurfaceController(document: document);
      addTearDown(() {
        controller.dispose();
        document.dispose();
      });
      var canEdit = true;
      controller.select(1, 1);
      final pending = controller.paste(canEdit: () => canEdit);
      switch (change) {
        case 'selection':
          controller.select(2, 2);
        case 'text':
          controller.value = const TextEditingValue(
            text: 'aXbc',
            selection: TextSelection.collapsed(offset: 1),
          );
        case 'disposed':
          controller.dispose();
        case 'editability':
          canEdit = false;
      }
      final before = controller.value;
      clipboard.complete(<String, String>{'text': '😀\r\n'});
      await pending;
      expect(controller.value, before);
      expect(document.text, before.text);
    });
  }

  testWidgets('cut checks editability again after clipboard write', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final write = Completer<Object?>();
    var calls = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) {
      calls++;
      return write.future;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final document = EditorDocumentModel('abc');
    final controller = EditorSurfaceController(document: document);
    addTearDown(() {
      controller.dispose();
      document.dispose();
    });
    controller.selectAll();
    var canEdit = true;
    final pending = controller.cut(canEdit: () => canEdit);
    canEdit = false;
    write.complete(null);
    await pending;
    expect(controller.value.text, 'abc');
    expect(calls, 1);
    await controller.cut(canEdit: () => false);
    await controller.paste(canEdit: () => false);
    expect(calls, 1);
  });

  testWidgets('wheel scrolling does not snap back to the focused caret', (
    tester,
  ) async {
    final document = EditorDocumentModel(List.filled(25, 'WWW').join('\n'));
    final controller = EditorSurfaceController(document: document);
    addTearDown(() {
      controller.dispose();
      document.dispose();
    });
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 120,
            height: 50,
            child: EditorSurface(controller: controller, focusNode: focus),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.pump();
    double lastCaretTop() {
      final call = tester.testTextInput.log.lastWhere(
        (call) => call.method == 'TextInput.setCaretRect',
      );
      return (call.arguments as Map<String, dynamic>)['y'] as double;
    }

    final before = lastCaretTop();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(EditorSurface)),
        scrollDelta: const Offset(0, -40),
      ),
    );
    await tester.pump();
    expect(lastCaretTop(), greaterThan(before));
  });

  testWidgets(
    'mouse drag selects and focused surface receives keyboard edits',
    (tester) async {
      final controller = EditorSurfaceController(
        document: EditorDocumentModel('iiiWWW'),
      );
      addTearDown(() {
        controller.dispose();
        controller.document.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 80,
              child: EditorSurface(controller: controller),
            ),
          ),
        ),
      );
      final topLeft = tester.getTopLeft(find.byType(EditorSurface));
      final mouse = await tester.startGesture(
        topLeft + const Offset(3, 15),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveTo(topLeft + const Offset(90, 15));
      await tester.pump();
      expect(controller.value.selection.start, 0);
      expect(controller.value.selection.end, greaterThan(1));
      await mouse.up();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(controller.value.text.length, lessThan(6));
    },
  );
}

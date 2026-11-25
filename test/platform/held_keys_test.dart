import 'dart:async';

import 'package:baocode/chat/panels/reply_suggestion_bar.dart';
import 'package:baocode/platform/held_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('baocode/window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// The system's answer: [held] the modifiers held, the others not.
  void system(Set<String> held, {Future<void>? after}) =>
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'heldModifiers');
        await after;
        return {
          for (final name in ['shift', 'control', 'alt', 'meta'])
            name: held.contains(name),
        };
      });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('a modifier the app missed going up is let go', (tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    // Up where the app did not hear: still held for it.
    system({'shift'});
    expect(await HeldKeys.commandOrControl(), isFalse);
    expect(HardwareKeyboard.instance.isMetaPressed, isFalse);
    // One the system has held stays.
    expect(HardwareKeyboard.instance.isShiftPressed, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('one held for both stays held', (tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    system({'control'});
    expect(await HeldKeys.commandOrControl(), isTrue);
    expect(HardwareKeyboard.instance.isControlPressed, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('the system not answering: as the app has it', (tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await HeldKeys.commandOrControl(), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    // Nothing held: not asked.
    var asked = false;
    messenger.setMockMethodCallHandler(channel, (_) async => asked = true);
    expect(await HeldKeys.commandOrControl(), isFalse);
    expect(asked, isFalse);
  });

  testWidgets('a key meanwhile: the answer left, maybe old', (tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    final answer = Completer<void>();
    system(const {}, after: answer.future);
    final held = HeldKeys.commandOrControl();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    answer.complete();
    expect(await held, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });

  testWidgets('a suggested reply clicked with ⌘ held only for the app: '
      'put in, not picked beside the others', (tester) async {
    final picked = <String>[];
    final toggled = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReplySuggestionBar(
            suggestions: const ['one', 'two'],
            onPick: picked.add,
            onToggle: toggled.add,
            onSend: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    system(const {});
    await tester.tap(find.text('one'));
    await tester.pump();
    expect(picked, ['one']);
    expect(toggled, isEmpty);

    // Held for both: picked beside them.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    system({'meta'});
    await tester.tap(find.text('two'));
    await tester.pump();
    expect(toggled, ['two']);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  });
}

import 'dart:io';

import 'package:baocode/diagnostics/key_watch.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/platform/event_log.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  setUp(() {
    folder = Directory.systemTemp.createTempSync('key_watch');
    EventLog.current = EventLog(folder.path);
    KeyWatch.debugReset();
  });
  tearDown(() {
    EventLog.current = null;
    folder.deleteSync(recursive: true);
  });

  List<String> lines() {
    final file = File(EventLog.current!.path);
    if (!file.existsSync()) return const [];
    return [
      for (final line in file.readAsLinesSync())
        if (line.contains(' [keys] ')) line,
    ];
  }

  /// A focused field under [take], which says whether a key down is taken.
  Future<void> field(
    WidgetTester tester,
    bool Function(KeyEvent event) take,
  ) async {
    KeyWatch.start();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Focus(
            onKeyEvent: (_, event) => event is KeyDownEvent && take(event)
                ? KeyEventResult.handled
                : KeyEventResult.ignored,
            child: TextField(controller: controller, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a typing key taken from a text field is written, once a '
      'minute; one let through is not', (tester) async {
    await field(
      tester,
      (event) => event.logicalKey == LogicalKeyboardKey.digit1,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2, platform: 'windows');
    expect(lines(), isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, platform: 'windows');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, platform: 'windows');
    expect(lines(), [
      contains(
        'a text field did not get 1 (0x7001e): '
        'no keybinding, a widget of its own; held none',
      ),
    ]);
  });

  testWidgets('a shortcut with Control is not written', (tester) async {
    await field(tester, (event) => true);
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'windows',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, platform: 'windows');
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'windows',
    );
    expect(lines(), isEmpty);
  });

  testWidgets('the keybinding the key was resolved to is named', (
    tester,
  ) async {
    await field(tester, (event) {
      KeybindingService.onResolved?.call(
        event,
        const [],
        KeybindingFound(
          KeybindingItem(
            entry: const KeybindingEntry(key: '1', command: 'some.command'),
            source: KeybindingSource.user,
            platform: KeybindingPlatform.windows,
          ),
        ),
      );
      return true;
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, platform: 'windows');
    expect(lines(), [
      contains('keybinding 1 -> some.command (user); held none'),
    ]);
  });

  test('what is held is said at the upload', () {
    expect(KeyWatch.describe(), 'held none');
  });
}

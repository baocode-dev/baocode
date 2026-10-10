import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_tab_bar.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/language/language_types.dart';

import 'fake_files.dart';

/// Go Back and Go Forward, off macOS (the tests' platform is Linux's):
/// Ctrl+Alt+- and Ctrl+Shift+-.
Future<void> _back(WidgetTester tester) async {
  await chord(tester, LogicalKeyboardKey.minus, control: true, alt: true);
  await tester.pumpAndSettle();
}

Future<void> _forward(WidgetTester tester) async {
  await chord(tester, LogicalKeyboardKey.minus, control: true, shift: true);
  await tester.pumpAndSettle();
}

/// Puts the caret on (1-based) [line] of the active editor.
Future<void> _caretTo(WidgetTester tester, int line) async {
  final position = LspPosition(line - 1, 0);
  tester
      .state<IdeEditorState>(find.byType(IdeEditor))
      .revealRange(LspRange(position, position));
  await tester.pumpAndSettle();
}

String _status(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.textContaining(RegExp(r'^Ln \d+, Col')),
  );
  return text.data ?? text.textSpan!.toPlainText();
}

Finder _tab(String name) =>
    find.descendant(of: find.byType(IdeTabBar), matching: find.text(name));

Object? _context(WidgetTester tester, String key) =>
    tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench)).keyContext(key);

void main() {
  final long = [for (var i = 1; i <= 60; i++) 'line $i'].join('\n');
  final files = {'a.dart': long, 'b.dart': long, 'c.dart': 'c'};

  testWidgets('switching files is recorded; back and forward return', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['a.dart', 'b.dart', 'c.dart'],
      nativeEditor: true,
    );
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('c.dart'));
    expect(_context(tester, 'canNavigateBack'), isFalse);

    // A tab, from the keyboard.
    await chord(tester, LogicalKeyboardKey.digit1, alt: true);
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('a.dart'));
    // And one clicked.
    await tester.tap(
      find.descendant(
        of: find.byType(IdeTabBar),
        matching: find.text('b.dart'),
      ),
    );
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('b.dart'));
    expect(_context(tester, 'canNavigateBack'), isTrue);
    expect(_context(tester, 'canNavigateForward'), isFalse);

    await _back(tester);
    expect(workspace.active!.path, inRoot('a.dart'));
    await _back(tester);
    expect(workspace.active!.path, inRoot('c.dart'));
    expect(_context(tester, 'canNavigateBack'), isFalse);
    // Nothing further back: the key does nothing.
    await _back(tester);
    expect(workspace.active!.path, inRoot('c.dart'));

    await _forward(tester);
    expect(workspace.active!.path, inRoot('a.dart'));
    await _forward(tester);
    expect(workspace.active!.path, inRoot('b.dart'));
    expect(_context(tester, 'canNavigateForward'), isFalse);
  });

  testWidgets('a jump of more than 10 lines is recorded, a shorter move is '
      'not', (tester) async {
    await pumpWorkbench(tester, files, open: ['a.dart'], nativeEditor: true);
    await tester.pumpAndSettle();
    // A file opens with the caret at its end: a few lines up is no
    // navigation.
    expect(_status(tester), startsWith('Ln 60,'));
    await _caretTo(tester, 55);
    expect(_context(tester, 'canNavigateBack'), isFalse);
    await _caretTo(tester, 20);
    expect(_status(tester), startsWith('Ln 20,'));
    expect(_context(tester, 'canNavigateBack'), isTrue);

    await _back(tester);
    expect(_status(tester), startsWith('Ln 55,'));
    await _forward(tester);
    expect(_status(tester), startsWith('Ln 20,'));
    // A jump after going back drops what Go Forward had.
    await _back(tester);
    expect(_context(tester, 'canNavigateForward'), isTrue);
    await _caretTo(tester, 5);
    expect(_context(tester, 'canNavigateForward'), isFalse);
  });

  testWidgets('a file closed is dropped from the history', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['a.dart', 'b.dart', 'c.dart'],
      nativeEditor: true,
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.digit1, alt: true);
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.digit2, alt: true);
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('b.dart'));
    // History: c, a. Closing c leaves a.
    await tester.tap(_tab('c.dart'), buttons: kMiddleMouseButton);
    await tester.pumpAndSettle();
    await _back(tester);
    expect(workspace.active!.path, inRoot('a.dart'));
    expect(_context(tester, 'canNavigateBack'), isFalse);
    // Closing the active file records nothing of it.
    await tester.tap(_tab('a.dart'), buttons: kMiddleMouseButton);
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('b.dart'));
    expect(_context(tester, 'canNavigateBack'), isFalse);
  });

  testWidgets("the mouse's back and forward buttons", (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['a.dart', 'c.dart'],
      nativeEditor: true,
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.digit1, alt: true);
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('a.dart'));
    final editor = tester.getCenter(find.byType(IdeEditor));
    await tester.tapAt(editor, buttons: kBackMouseButton);
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('c.dart'));
    await tester.tapAt(editor, buttons: kForwardMouseButton);
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('a.dart'));
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_quick_input.dart';

import 'fake_files.dart';

Finder get _input => find.descendant(
  of: find.byType(IdeQuickInput),
  matching: find.byType(TextField),
);

String _inputText(WidgetTester tester) =>
    tester.widget<TextField>(_input).controller!.text;

Finder _row(String label) =>
    find.descendant(of: find.byType(IdeQuickInput), matching: find.text(label));

bool _chatShown(WidgetTester tester) => !tester
    .widget<Offstage>(
      find
          .ancestor(
            of: find.byKey(chatKey, skipOffstage: false),
            matching: find.byType(Offstage, skipOffstage: false),
          )
          .first,
    )
    .offstage;

void main() {
  const files = {
    'lib/main.dart': 'void main() {}\n',
    'lib/src/other.dart': 'one\ntwo\nthree\nfour\n',
    'test/other_test.dart': '',
    'README.md': '# Readme\n',
    'build/generated.dart': '',
  };

  testWidgets('command palette filters, highlights, runs and remembers', (
    tester,
  ) async {
    await pumpWorkbench(tester, files, open: ['lib/main.dart']);
    expect(_chatShown(tester), isTrue);

    await chord(tester, LogicalKeyboardKey.keyP, control: true, shift: true);
    expect(find.byType(IdeQuickInput), findsOneWidget);
    expect(_inputText(tester), '>');
    // Keybinding labels are listed with the commands.
    await tester.enterText(_input, '>show all com');
    await tester.pump();
    expect(_row('Show All Commands'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(IdeQuickInput),
        matching: find.text('Ctrl+Shift+P'),
      ),
      findsOneWidget,
    );

    await tester.enterText(_input, '>tgl chat');
    await tester.pump();
    final text = tester.widget<Text>(_row('View: Toggle Chat'));
    final highlighted = <String>[];
    text.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.style?.fontWeight == FontWeight.w600) {
        highlighted.add(span.text!);
      }
      return true;
    });
    expect(highlighted.join(), 'Tgl Chat');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(_chatShown(tester), isFalse);

    // F1 opens the palette too, with the last command listed first.
    await chord(tester, LogicalKeyboardKey.f1);
    expect(_inputText(tester), '>');
    final first = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(IdeQuickInput),
            matching: find.byType(Text),
          ),
        )
        .firstWhere((text) => text.textSpan != null);
    expect(first.textSpan!.toPlainText(), 'View: Toggle Chat');
    expect(_row('recently used'), findsOneWidget);

    // Arrows move the selection; Escape closes without running anything.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(_chatShown(tester), isFalse);

    // Ctrl+J toggles the chat back from the editor.
    await chord(tester, LogicalKeyboardKey.keyJ, control: true);
    expect(_chatShown(tester), isTrue);
  });

  testWidgets('palette runs editor-independent commands from the welcome', (
    tester,
  ) async {
    await pumpWorkbench(tester, files);
    expect(find.text('Show All Commands'), findsOneWidget);
    expect(find.text('Ctrl+P'), findsOneWidget);
    expect(find.text('Ctrl+G'), findsOneWidget);
    await tester.tap(find.text('Go to File…'));
    await tester.pump();
    expect(_inputText(tester), '');
  });

  testWidgets('the welcome labels shortcuts with macOS glyphs there', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpWorkbench(tester, files);
    expect(find.text('⇧⌘P'), findsOneWidget);
    expect(find.text('⌘P'), findsOneWidget);
    expect(find.text('⌃G'), findsOneWidget);
    expect(find.text('⌘B'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('quick open lists, filters and opens files; > and : switch', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(tester, files, open: ['README.md']);
    await chord(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pump();
    expect(_inputText(tester), '');
    // Recently opened first, then the indexed files (build/ is skipped).
    expect(_row('README.md'), findsOneWidget);
    expect(_row('recently opened'), findsOneWidget);
    expect(_row('main.dart  lib'), findsOneWidget);
    expect(_row('generated.dart  build'), findsNothing);

    await tester.enterText(_input, 'other');
    await tester.pump();
    final labels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(IdeQuickInput),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.textSpan?.toPlainText() ?? text.data)
        .where((label) => !label!.startsWith('Search files'))
        .toList();
    expect(labels.take(2), ['other.dart  lib/src', 'other_test.dart  test']);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(workspace.active!.path, inRoot('lib/src/other.dart'));
    expect(find.byType(IdeQuickInput), findsNothing);

    // path:line opens at the line.
    await chord(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.enterText(_input, 'main.dart:1:5');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(workspace.active!.path, inRoot('lib/main.dart'));
    expect(find.text('Ln 1, Col 5'), findsOneWidget);

    // Typing > switches to commands, : to go to line.
    await chord(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.enterText(_input, '>save');
    await tester.pump();
    expect(_row('File: Save'), findsOneWidget);
    await tester.enterText(_input, ':');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(IdeQuickInput),
        matching: find.textContaining('Type a line number between 1 and 2'),
      ),
      findsOneWidget,
    );
    await tester.enterText(_input, 'nothing-matches-this');
    await tester.pump();
    expect(_row('No matching results'), findsOneWidget);
    // Clicking outside dismisses.
    await tester.tapAt(const Offset(700, 700));
    await tester.pump();
    expect(find.byType(IdeQuickInput), findsNothing);
  });

  testWidgets('go to line (Ctrl+G) and the status bar Ln/Col entry', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['lib/src/other.dart'],
    );
    await chord(tester, LogicalKeyboardKey.keyG, control: true);
    expect(_inputText(tester), ':');
    await tester.enterText(_input, ':3:2');
    await tester.pump();
    expect(_row('Go to line 3 and character 2.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(find.text('Ln 3, Col 2'), findsOneWidget);
    final editor = tester.state<IdeEditorState>(find.byType(IdeEditor));
    expect(editor.mounted, isTrue);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(IdeEditor),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.selection.baseOffset, 'one\ntwo\n'.length + 1);
    expect(field.focusNode!.hasFocus, isTrue);

    // Clicking Ln/Col opens the same input.
    await tester.tap(find.text('Ln 3, Col 2'));
    await tester.pump();
    expect(_inputText(tester), ':');
    await tester.enterText(_input, ':1');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(find.text('Ln 1, Col 1'), findsOneWidget);
    expect(workspace.active!.path, inRoot('lib/src/other.dart'));
  });
}

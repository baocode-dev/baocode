import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_editor.dart';
import 'package:monad/ide/ide_find_widget.dart';

import 'fake_files.dart';

TextField _editorField(WidgetTester tester) => tester.widget<TextField>(
  find
      .descendant(of: find.byType(IdeEditor), matching: find.byType(TextField))
      .first,
);

Finder get _findInputs => find.descendant(
  of: find.byType(IdeFindWidget),
  matching: find.byType(TextField),
);

bool _toggled(WidgetTester tester, String tooltip) => tester
    .widgetList<Semantics>(
      find.descendant(
        of: find.byTooltip(tooltip),
        matching: find.byType(Semantics),
      ),
    )
    .firstWhere((semantics) => semantics.properties.toggled != null)
    .properties
    .toggled!;

void main() {
  testWidgets('find widget: seeding, toggles, counter, replace, escape', (
    tester,
  ) async {
    await pumpWorkbench(
      tester,
      {'main.dart': 'Alpha alpha alphabet\nAlpha'},
      open: ['main.dart'],
    );
    final editor = tester.state<IdeEditorState>(find.byType(IdeEditor));
    final field = _editorField(tester);
    field.controller!.selection = const TextSelection(
      baseOffset: 6,
      extentOffset: 11,
    );
    field.focusNode!.requestFocus();
    await tester.pump();

    await chord(tester, LogicalKeyboardKey.keyF, control: true);
    expect(find.byType(IdeFindWidget), findsOneWidget);
    expect(_findInputs, findsOneWidget);
    expect(tester.widget<TextField>(_findInputs).controller!.text, 'alpha');
    expect(find.text('? of 4'), findsOneWidget);
    expect(editor.findMatches, hasLength(4));
    expect(editor.findIndex, -1);

    // Enter goes to the next match after the selection, as in Monaco.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('3 of 4'), findsOneWidget);
    expect(editor.findIndex, 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('2 of 4'), findsOneWidget);

    expect(_toggled(tester, 'Match case'), isFalse);
    await tester.tap(find.byTooltip('Match case'));
    await tester.pump();
    expect(_toggled(tester, 'Match case'), isTrue);
    expect(find.text('? of 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Whole word'));
    await tester.pump();
    expect(_toggled(tester, 'Whole word'), isTrue);
    expect(find.text('? of 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Regular expression'));
    await tester.pump();
    expect(_toggled(tester, 'Regular expression'), isTrue);

    await tester.enterText(_findInputs, 'zzz');
    await tester.pump();
    final counter = tester.widget<Text>(find.text('No results'));
    expect(counter.style!.color, isNot(Colors.white));
    expect(editor.findMatches, isEmpty);

    // Escape closes and returns focus to the text.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(IdeFindWidget), findsNothing);
    expect(editor.findMatches, isEmpty);
    expect(_editorField(tester).focusNode!.hasFocus, isTrue);

    // Ctrl+H opens with the replace row.
    await chord(tester, LogicalKeyboardKey.keyH, control: true);
    expect(_findInputs, findsNWidgets(2));
    expect(editor.replaceVisible, isTrue);
    await tester.tap(find.byTooltip('Toggle replace'));
    await tester.pump();
    expect(_findInputs, findsOneWidget);
  });

  testWidgets('status bar: selection, encoding, line endings, language', (
    tester,
  ) async {
    await pumpWorkbench(
      tester,
      {'crlf.dart': '\uFEFFone\r\ntwo\r\n', 'mixed.txt': 'a\nb\r\n'},
      open: ['mixed.txt', 'crlf.dart'],
    );
    // The caret starts at the end of a newly shown file.
    expect(find.text('Ln 3, Col 1'), findsOneWidget);
    expect(find.text('Spaces: 4'), findsOneWidget);
    expect(find.text('UTF-8 with BOM'), findsOneWidget);
    expect(find.text('CRLF'), findsOneWidget);
    expect(find.text('Dart'), findsOneWidget);

    _editorField(tester).controller!.selection = const TextSelection(
      baseOffset: 5,
      extentOffset: 7,
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Ln 2, Col 2 (2 selected)'), findsOneWidget);

    await chord(tester, LogicalKeyboardKey.tab, control: true);
    await tester.pump();
    expect(find.text('Mixed'), findsOneWidget);
    expect(find.text('UTF-8'), findsOneWidget);
    expect(find.text('Plain Text'), findsOneWidget);
  });
}

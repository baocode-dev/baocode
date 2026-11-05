import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/ide/ide_columns.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_find_widget.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/workspace/back_to_chat_button.dart';
import 'package:baocode/workspace/pin_window_button.dart';

import '../../debug/support/fake_debug_adapter.dart';
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

    expect(_toggled(tester, 'Match case (Alt+C)'), isFalse);
    await tester.tap(find.byTooltip('Match case (Alt+C)'));
    await tester.pump();
    expect(_toggled(tester, 'Match case (Alt+C)'), isTrue);
    expect(find.text('? of 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Whole word (Alt+W)'));
    await tester.pump();
    expect(_toggled(tester, 'Whole word (Alt+W)'), isTrue);
    expect(find.text('? of 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Regular expression (Alt+R)'));
    await tester.pump();
    expect(_toggled(tester, 'Regular expression (Alt+R)'), isTrue);

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
    // From between the first line's CR and LF: over two lines.
    expect(find.text('Ln 2, Col 2 (2 lines, 2 selected)'), findsOneWidget);

    await chord(tester, LogicalKeyboardKey.tab, control: true);
    await tester.pump();
    expect(find.text('Mixed'), findsOneWidget);
    expect(find.text('UTF-8'), findsOneWidget);
    expect(find.text('Plain Text'), findsOneWidget);
  });

  testWidgets('status bar: its right items after the chat\'s branch, '
      'against the window\'s right edge, however few', (tester) async {
    await pumpWorkbench(tester, const {'a.dart': 'a'});
    final window = tester.view.physicalSize / tester.view.devicePixelRatio;
    // No editor: the notifications bell alone, under the chat, as far from
    // the edge as the bar's items, as high as the row under its line.
    final bell = tester.getRect(find.byTooltip('No Notifications'));
    expect(bell.right, closeTo(window.width - 6, 1));
    expect(bell.bottom, closeTo(window.height, 1));
    // Not in the bar under the rest.
    expect(
      find.descendant(
        of: find.byType(IdeStatusBar),
        matching: find.byTooltip('No Notifications'),
      ),
      findsNothing,
    );
  });

  testWidgets('status bar: as many right items under the chat as fit '
      'there, the others at the end of the bar under the rest', (tester) async {
    await pumpWorkbench(
      tester,
      {'crlf.dart': '﻿one\r\ntwo\r\n'},
      open: ['crlf.dart'],
    );
    final window = tester.view.physicalSize / tester.view.devicePixelRatio;
    final chatLeft = window.width - IdeColumns.defaultChat;
    final items = [
      'Ln 3, Col 1',
      'Spaces: 4',
      'UTF-8 with BOM',
      'CRLF',
      'Dart',
    ].map(find.text).toList();
    for (final item in items) {
      expect(item, findsOneWidget);
    }
    final inBar = [
      for (final item in items)
        find
            .descendant(of: find.byType(IdeStatusBar), matching: item)
            .evaluate()
            .isNotEmpty,
    ];
    // Under the chat, the last ones, after those in the bar.
    expect(inBar.last, isFalse);
    expect(inBar.skipWhile((it) => it).every((it) => !it), isTrue);
    for (final (i, item) in items.indexed) {
      final rect = tester.getRect(item);
      expect(rect.left >= chatLeft, !inBar[i], reason: '$i');
      expect(rect.bottom, closeTo(window.height - 3, 4));
    }
    // In order, apart.
    for (var i = 1; i < items.length; i++) {
      expect(
        tester.getRect(items[i]).left,
        greaterThan(tester.getRect(items[i - 1]).right),
      );
    }
    final bell = tester.getRect(find.byTooltip('No Notifications'));
    expect(bell.right, closeTo(window.width - 6, 1));
  });

  testWidgets('status bar: a mark of the debugging colors while a session '
      'is debugged, the bar on the window\'s color', (tester) async {
    late DebugService service;
    await tester.runAsync(() async {
      final fake = await createFakeDebugService();
      service = fake.service;
      await service.startDebugging(
        service.configurationManager.getLaunches().first,
        {
          'type': 'fake',
          'request': 'launch',
          'name': 'Launch main.js',
          'program': r'${workspaceFolder}/main.js',
        },
      );
    });
    addTearDown(service.dispose);
    await pumpWorkbench(tester, const {'a.dart': 'a'}, debugService: service);
    final mark = find.descendant(
      of: find.byType(IdeStatusBar),
      matching: find.text('Launch main.js'),
    );
    expect(mark, findsOneWidget);
    final box = tester.widget<Container>(
      find.ancestor(of: mark, matching: find.byType(Container)).first,
    );
    expect(
      (box.decoration! as BoxDecoration).color,
      themeColors['statusBar.debuggingBackground'],
    );
  });

  testWidgets('title bar: the window pin beside the way back to the chat', (
    tester,
  ) async {
    final pins = <bool>[];
    await pumpWorkbench(tester, const {
      'a.dart': 'a',
    }, onPinnedChanged: pins.add);
    final pin = find.byType(PinWindowButton);
    expect(pin, findsOneWidget);
    expect(
      tester.getRect(pin).right,
      lessThan(tester.getRect(find.byType(BackToChatButton)).left),
    );
    expect(tester.widget<PinWindowButton>(pin).onChanged, pins.add);
  });

  testWidgets('title bar: the side bar\'s toggle right after the traffic '
      'lights, no name there; the activity bar has no way back to the chat', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(tester, const {'a.dart': 'a'});
    expect(find.text('Fast Ide'), findsNothing);
    final toggle = find.byTooltip('Toggle Primary Side Bar (Ctrl+B)');
    expect(tester.getRect(toggle).left, AppMetrics.trafficLightsWidth + 8);
    IconData icon() => tester
        .widget<Icon>(find.descendant(of: toggle, matching: find.byType(Icon)))
        .icon!;
    expect(icon(), Codicons.layoutSidebarLeft);
    expect(find.text('Explorer'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    expect(workspace.layout.sidebar, isFalse);
    expect(icon(), Codicons.layoutSidebarLeftOff);
    expect(find.text('Explorer'), findsNothing);

    // Shown from elsewhere (the header Windows draws).
    workspace.layout.sidebar = true;
    await tester.pump();
    expect(icon(), Codicons.layoutSidebarLeft);
    expect(find.text('Explorer'), findsOneWidget);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.runtimeType.toString() == '_ActivityItem' &&
            (widget as dynamic).label == 'Back to chat',
      ),
      findsNothing,
    );
  });
}

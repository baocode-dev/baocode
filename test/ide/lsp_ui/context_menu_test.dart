import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';

import 'fake_language_features.dart';
import 'lsp_test_helpers.dart';

const _a = 'lib/a.dart';

const _source =
    'class Greeter {\n'
    '  void greet() {\n'
    '    print(1);\n'
    '  }\n'
    '}\n';

/// Right-clicks just after the left edge of the character at [offset],
/// and lets the menu fade in.
Future<void> _rightClick(WidgetTester tester, int offset) async {
  final rect = surfaceView(tester).rangeRectAt(offset, offset + 1)!;
  await tester.tapAt(
    tester.getTopLeft(find.byType(EditorSurface)) +
        rect.centerLeft +
        const Offset(1, 0),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

List<String> _menuLabels(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_MenuPanel',
      ),
      matching: find.byType(Text),
    ),
  ))
    text.data!,
];

void main() {
  testWidgets('without a language server: editing, the clipboard and the '
      'palette', (tester) async {
    final languages = FakeLanguageFeatures(supported: {});
    await pumpLanguageWorkbench(tester, {_a: _source}, languages, open: [_a]);
    final greet = offsetOf(tester, 'greet');
    await _rightClick(tester, greet + 2);
    // The caret moved to the click.
    expect(surfaceController(tester).value.selection.baseOffset, greet + 2);
    expect(find.text('Go to Definition'), findsNothing);
    expect(find.text('Rename Symbol'), findsNothing);
    for (final label in [
      'Change All Occurrences',
      'Cut',
      'Copy',
      'Paste',
      'Command Palette...',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Command Palette...'));
    await tester.pumpAndSettle();
    expect(find.text('Cut'), findsNothing);
    // Open, and focused once the menu has given the focus back.
    final input = tester.widget<TextField>(
      find.descendant(
        of: find.byType(IdeQuickInput),
        matching: find.byType(TextField),
      ),
    );
    expect(input.controller!.text, '>');
    expect(input.focusNode!.hasFocus, isTrue);
  });

  testWidgets('a click in the selection keeps it; Copy copies it', (
    tester,
  ) async {
    final languages = FakeLanguageFeatures(supported: {});
    await pumpLanguageWorkbench(tester, {_a: _source}, languages, open: [_a]);
    final greeter = offsetOf(tester, 'Greeter');
    surfaceController(tester).select(greeter, greeter + 'Greeter'.length);
    await settle(tester);
    await _rightClick(tester, greeter + 3);
    final selection = surfaceController(tester).value.selection;
    expect((selection.start, selection.end), (greeter, greeter + 7));

    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, ['Greeter']);
  });

  testWidgets('language items follow what the server provides', (tester) async {
    final languages = FakeLanguageFeatures(
      supported: {
        LanguageRequest.definition,
        LanguageRequest.references,
        LanguageRequest.rename,
        LanguageRequest.codeActions,
      },
    );
    languages.onCodeActions = (path, range, diagnostics) => const [
      LspCodeAction(title: 'Extract method', kind: 'refactor.extract'),
      LspCodeAction(title: 'Organize imports', kind: 'source.organizeImports'),
      LspCodeAction(title: 'Fix it', kind: 'quickfix'),
    ];
    await pumpLanguageWorkbench(tester, {_a: _source}, languages, open: [_a]);
    await _rightClick(tester, offsetOf(tester, 'greet'));
    expect(_menuLabels(tester), [
      'Go to Definition',
      'F12',
      'Go to References',
      isNotEmpty,
      'Rename Symbol',
      'F2',
      'Change All Occurrences',
      isNotEmpty,
      'Refactor...',
      isNotEmpty,
      'Source Action...',
      'Cut',
      isNotEmpty,
      'Copy',
      isNotEmpty,
      'Paste',
      isNotEmpty,
      'Command Palette...',
      isNotEmpty,
    ]);

    // Refactor... lists only refactorings.
    await tester.tap(find.text('Refactor...'));
    await settle(tester);
    expect(find.text('Extract method'), findsOneWidget);
    expect(find.text('Organize imports'), findsNothing);
    expect(find.text('Fix it'), findsNothing);
  });
}

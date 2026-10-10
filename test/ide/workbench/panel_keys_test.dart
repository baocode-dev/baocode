import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/keybindings/keybinding_service.dart';

import '../lsp_ui/fake_language_features.dart';
import '../lsp_ui/lsp_test_helpers.dart';
import 'fake_files.dart';

const _a = 'lib/a.dart';
const _b = 'lib/b.dart';

const _files = {
  _a: 'void main() {\n  foo();\n  bar();\n}\n',
  _b: 'int foo() => 1;\nint bar() => 2;\n',
};

/// The panel's lists as VS Code's Problems view and references view take
/// the keyboard (markers.contribution.ts, the references view's
/// Navigation, listCommands.ts).
void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  List<String> clipboard(WidgetTester tester) {
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
    return copied;
  }

  testWidgets('Ctrl+Shift+M focuses Problems, whose tree the arrows walk; '
      'Enter opens a problem, Ctrl+C copies it; again, it hides', (
    tester,
  ) async {
    final copied = clipboard(tester);
    final languages = FakeLanguageFeatures();
    languages.diagnostics[inRoot(_a)] = [
      LspDiagnostic(range: lspRange(2, 2, 5), message: 'Prefer final'),
      LspDiagnostic(
        range: lspRange(1, 2, 5),
        message: "Undefined name 'foo'",
        severity: LspDiagnosticSeverity.error,
      ),
    ];
    languages.diagnostics[inRoot(_b)] = [
      LspDiagnostic(
        range: lspRange(0, 4, 7),
        message: 'Info in b',
        severity: LspDiagnosticSeverity.information,
        source: 'dart',
      ),
    ];
    final workspace = await pumpLanguageWorkbench(
      tester,
      _files,
      languages,
      open: [_a, _b],
    );
    final state = workbenchState(tester);

    await press(tester, LogicalKeyboardKey.keyM, primary: true, shift: true);
    expect(state.keyContext('panelVisible'), isTrue);
    expect(state.keyContext('focusedView'), 'workbench.panel.markers.view');
    expect(state.keyContext('listFocus'), isTrue);
    // The first file's first problem (the error, by severity).
    expect(state.keyContext('problemFocus'), isTrue);
    expect(state.keyContext('treeElementHasParent'), isTrue);

    // Left: its file; Left again collapses it.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(state.keyContext('problemFocus'), isFalse);
    expect(state.keyContext('treeElementCanCollapse'), isTrue);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(state.keyContext('treeElementCanExpand'), isTrue);
    expect(find.textContaining('Prefer final'), findsNothing);
    // Right expands it and then goes into it.
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.textContaining('Prefer final'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(state.keyContext('problemFocus'), isTrue);
    // End: b's problem, which Enter opens, its range selected.
    await press(tester, LogicalKeyboardKey.end);
    await press(tester, LogicalKeyboardKey.enter);
    await settle(tester);
    expect(workspace.active!.path, inRoot(_b));
    final selection = surfaceController(tester).value.selection;
    expect((selection.start, selection.end), (4, 7));
    expect(state.keyContext('editorTextFocus'), isTrue);

    // Again from the editor: the list, where it was; Ctrl+C copies it.
    await press(tester, LogicalKeyboardKey.keyM, primary: true, shift: true);
    expect(state.keyContext('problemFocus'), isTrue);
    await press(tester, LogicalKeyboardKey.keyC, primary: true);
    expect(copied, hasLength(1));
    expect(copied.single, startsWith('[{\n\t"resource": "${inRoot(_b)}"'));
    expect(copied.single, contains('"message": "Info in b"'));
    expect(copied.single, contains('"severity": 2'));
    expect(copied.single, contains('"startColumn": 5'));
    // Focused, Ctrl+Shift+M hides the panel.
    await press(tester, LogicalKeyboardKey.keyM, primary: true, shift: true);
    expect(state.keyContext('panelVisible'), isFalse);
  });

  testWidgets('F4 / Shift+F4 go to the next and previous reference from the '
      'nearest; Clear ends them', (tester) async {
    final languages = FakeLanguageFeatures()
      ..onReferences = (path, position) => [
        LspLocation(uriOf(_a), lspRange(1, 2, 5)),
        LspLocation(uriOf(_b), lspRange(0, 4, 7)),
      ];
    final workspace = await pumpLanguageWorkbench(
      tester,
      _files,
      languages,
      open: [_a],
    );
    final state = workbenchState(tester);
    final foo = offsetOf(tester, 'foo');
    await caretAt(tester, foo);
    expect(state.keyContext('reference-list.hasResult'), isFalse);
    await press(tester, LogicalKeyboardKey.f12, shift: true);
    await settle(tester);
    expect(state.keyContext('reference-list.hasResult'), isTrue);

    // The caret is in a.dart's: the next is b.dart's.
    await press(tester, LogicalKeyboardKey.f4);
    await settle(tester);
    expect(workspace.active!.path, inRoot(_b));
    expect(surfaceController(tester).value.selection.baseOffset, 4);
    expect(surfaceController(tester).value.selection.isCollapsed, isTrue);
    expect(state.keyContext('editorTextFocus'), isTrue);
    // Around the end, and back.
    await press(tester, LogicalKeyboardKey.f4);
    await settle(tester);
    expect(workspace.active!.path, inRoot(_a));
    expect(surfaceController(tester).value.selection.baseOffset, foo);
    await press(tester, LogicalKeyboardKey.f4, shift: true);
    await settle(tester);
    expect(workspace.active!.path, inRoot(_b));

    runCommand(tester, 'references-view.clear');
    await settle(tester);
    expect(state.keyContext('reference-list.hasResult'), isFalse);
    await press(tester, LogicalKeyboardKey.f4);
    await settle(tester);
    expect(workspace.active!.path, inRoot(_b));
  });
}

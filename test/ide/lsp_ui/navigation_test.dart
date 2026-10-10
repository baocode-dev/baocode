import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp_ui/language_widgets.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart';
import 'package:baocode/theme/workbench_theme.dart';

import '../workbench/fake_files.dart';
import 'fake_language_features.dart';
import 'lsp_test_helpers.dart';

const _a = 'lib/a.dart';
const _b = 'lib/b.dart';

const _files = {
  _a: 'void main() {\n  foo();\n  bar();\n}\n',
  _b: 'int foo() => 1;\nint bar() => 2;\n',
};

void main() {
  testWidgets('diagnostics squiggle, count in the status bar and list in '
      'the problems panel', (tester) async {
    final languages = FakeLanguageFeatures();
    languages.diagnostics[inRoot(_a)] = [
      LspDiagnostic(
        range: lspRange(1, 2, 5),
        message: "Undefined name 'foo'",
        source: 'dart',
      ),
      LspDiagnostic(
        range: lspRange(2, 2, 5),
        message: 'Unused bar',
        severity: LspDiagnosticSeverity.hint,
        unnecessary: true,
      ),
    ];
    languages.diagnostics[inRoot(_b)] = [
      LspDiagnostic(
        range: lspRange(1, 4, 7),
        message: 'Prefer final',
        severity: LspDiagnosticSeverity.warning,
      ),
    ];
    await pumpLanguageWorkbench(tester, _files, languages, open: [_a]);

    final surface = tester.widget<EditorSurface>(find.byType(EditorSurface));
    final foo = offsetOf(tester, 'foo');
    expect(
      surface.decorations.where(
        (d) =>
            d.kind == EditorDecorationKind.error &&
            d.start == foo &&
            d.end == foo + 3,
      ),
      hasLength(1),
    );
    // The unnecessary hint fades instead of squiggling: the text at the
    // theme's `editorUnnecessaryCode.opacity`, where it has one.
    final bar = offsetOf(tester, 'bar');
    expect(
      surface.decorations.where(
        (d) => d.start == bar && d.kind == EditorDecorationKind.hint,
      ),
      isEmpty,
    );
    final opacity = themeColors.get('editorUnnecessaryCode.opacity');
    expect(
      surface.decorations
          .where((d) => d.start == bar && d.overlayColor != null)
          .map((d) => d.overlayColor),
      [
        if (opacity != null)
          themeColors['editor.background'].withValues(alpha: 1 - opacity.a),
      ],
    );

    // `$(error) 1 $(warning) 1`: each icon a placeholder in the text.
    expect(find.text('\uFFFC 1 \uFFFC 1'), findsOneWidget);
    await tester.tap(find.text('\uFFFC 1 \uFFFC 1'));
    await settle(tester);
    expect(find.byType(IdeBottomPanel), findsOneWidget);
    expect(find.textContaining("Undefined name 'foo'"), findsOneWidget);
    expect(find.textContaining('Prefer final'), findsOneWidget);
    // Hints are not problems.
    expect(find.textContaining('Unused bar'), findsNothing);

    await tester.tap(find.textContaining('Prefer final'));
    await settle(tester);
    await settle(tester);
    expect(surfaceController(tester).value.text, _files[_b]);
    final selection = surfaceController(tester).value.selection;
    expect(selection.start, offsetOf(tester, 'bar'));
    expect(selection.end, offsetOf(tester, 'bar') + 3);

    // New diagnostics update the count.
    languages.setDiagnostics(inRoot(_b), const []);
    await settle(tester);
    expect(find.text('\uFFFC 1 \uFFFC 0'), findsOneWidget);
  });

  testWidgets('F8 walks problems across files and shows them in a hover', (
    tester,
  ) async {
    final languages = FakeLanguageFeatures();
    languages.diagnostics[inRoot(_a)] = [
      LspDiagnostic(range: lspRange(2, 2, 5), message: 'Problem in a'),
    ];
    languages.diagnostics[inRoot(_b)] = [
      LspDiagnostic(
        range: lspRange(0, 4, 7),
        message: 'Problem in b',
        severity: LspDiagnosticSeverity.warning,
      ),
    ];
    final workspace = await pumpLanguageWorkbench(
      tester,
      _files,
      languages,
      open: [_a],
    );

    await press(tester, LogicalKeyboardKey.f8);
    await settle(tester);
    expect(workspace.active!.path, inRoot(_a));
    expect(
      surfaceController(tester).value.selection.extentOffset,
      offsetOf(tester, 'bar'),
    );
    expect(find.byType(IdeHoverCard), findsOneWidget);
    expect(find.textContaining('Problem in a'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.f8);
    await settle(tester);
    await settle(tester);
    expect(workspace.active!.path, inRoot(_b));
    expect(surfaceController(tester).value.selection.extentOffset, 4);
    expect(find.textContaining('Problem in b'), findsOneWidget);
  });

  testWidgets('mouse hover shows the hover card after a delay; Escape and '
      'typing hide it; Cmd/Ctrl+K Cmd/Ctrl+I shows it at the caret', (
    tester,
  ) async {
    final languages = FakeLanguageFeatures()
      ..onHover = (path, position) =>
          const LspHover('**foo** returns an int', range: null);
    languages.diagnostics[inRoot(_a)] = [
      LspDiagnostic(range: lspRange(2, 2, 5), message: 'Bar is deprecated'),
    ];
    await pumpLanguageWorkbench(tester, _files, languages, open: [_a]);

    final foo = offsetOf(tester, 'foo');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(globalAt(tester, foo + 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(IdeHoverCard), findsNothing);
    await settle(tester, const Duration(milliseconds: 300));
    expect(find.byType(IdeHoverCard), findsOneWidget);
    expect(find.textContaining('returns an int'), findsOneWidget);
    expect(languages.requests.last, matches(r'^hover .*a\.dart 1:[2-5]$'));

    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(IdeHoverCard), findsNothing);

    // Keyboard hover at the caret, with the diagnostic there.
    await mouse.moveTo(Offset.zero);
    await caretAt(tester, offsetOf(tester, 'bar') + 1);
    await press(tester, LogicalKeyboardKey.keyK, primary: true);
    await press(tester, LogicalKeyboardKey.keyI, primary: true);
    expect(find.byType(IdeHoverCard), findsOneWidget);
    expect(find.textContaining('Bar is deprecated'), findsOneWidget);

    surfaceController(tester).type('x');
    await settle(tester);
    expect(find.byType(IdeHoverCard), findsNothing);
  });

  testWidgets('F12 opens a definition in another file and Go Back returns', (
    tester,
  ) async {
    final languages = FakeLanguageFeatures()
      ..onDefinition = (path, position) => [
        LspLocation(uriOf(_b), lspRange(0, 4, 7)),
      ];
    final workspace = await pumpLanguageWorkbench(
      tester,
      _files,
      languages,
      open: [_a],
    );
    final foo = offsetOf(tester, 'foo');
    await caretAt(tester, foo + 1);

    await press(tester, LogicalKeyboardKey.f12);
    await settle(tester);
    await settle(tester);
    expect(languages.requests, contains('definition ${inRoot(_a)} 1:3'));
    expect(workspace.active!.path, inRoot(_b));
    expect(surfaceController(tester).value.selection.extentOffset, 4);

    runCommand(tester, 'workbench.action.navigateBack');
    await settle(tester);
    await settle(tester);
    expect(workspace.active!.path, inRoot(_a));
    expect(surfaceController(tester).value.selection.extentOffset, foo + 1);

    runCommand(tester, 'workbench.action.navigateForward');
    await settle(tester);
    await settle(tester);
    expect(workspace.active!.path, inRoot(_b));
  });

  testWidgets('Ctrl/Cmd+click goes to the definition under the pointer and '
      'underlines it as a link while hovering', (tester) async {
    final languages = FakeLanguageFeatures()
      ..onDefinition = (path, position) => [
        LspLocation(uriOf(_a), lspRange(2, 2, 5)),
      ];
    await pumpLanguageWorkbench(tester, _files, languages, open: [_a]);
    final foo = offsetOf(tester, 'foo');
    final modifier = LogicalKeyboardKey.controlLeft;

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.sendKeyDownEvent(modifier);
    await mouse.moveTo(globalAt(tester, foo + 1));
    await settle(tester);
    expect(languageSession(tester).link, (foo, foo + 3));
    final surface = tester.widget<EditorSurface>(find.byType(EditorSurface));
    expect(surface.contentCursor, SystemMouseCursors.click);
    expect(
      surface.decorations.where(
        (d) => d.start == foo && d.underlineStyle == EditorUnderlineStyle.solid,
      ),
      hasLength(1),
    );

    await mouse.down(globalAt(tester, foo + 1));
    await mouse.up();
    await tester.sendKeyUpEvent(modifier);
    await settle(tester);
    expect(
      languages.requests,
      contains(matches(r'^definition .*a\.dart 1:[2-5]$')),
    );
    expect(
      surfaceController(tester).value.selection.extentOffset,
      offsetOf(tester, 'bar'),
    );
  });

  testWidgets('Shift+F12 lists references grouped by file; a row opens it', (
    tester,
  ) async {
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
    await caretAt(tester, offsetOf(tester, 'foo'));

    await press(tester, LogicalKeyboardKey.f12, shift: true);
    await settle(tester);
    expect(find.byType(IdeBottomPanel), findsOneWidget);
    expect(
      find.textContaining("References to 'foo' — 2 results in 2 files"),
      findsOneWidget,
    );
    expect(find.text('a.dart'), findsWidgets);
    expect(find.text('b.dart'), findsWidgets);

    await tester.tap(find.textContaining('Ln 1, Col 5'));
    await settle(tester);
    await settle(tester);
    expect(workspace.active!.path, inRoot(_b));
    final selection = surfaceController(tester).value.selection;
    expect((selection.start, selection.end), (4, 7));
  });

  testWidgets('no definition shows a message instead', (tester) async {
    final languages = FakeLanguageFeatures();
    await pumpLanguageWorkbench(tester, _files, languages, open: [_a]);
    await caretAt(tester, offsetOf(tester, 'foo'));
    await press(tester, LogicalKeyboardKey.f12);
    expect(find.text("No definition found for 'foo'"), findsOneWidget);
    await settle(tester, const Duration(seconds: 3));
    expect(find.text("No definition found for 'foo'"), findsNothing);
  });
}

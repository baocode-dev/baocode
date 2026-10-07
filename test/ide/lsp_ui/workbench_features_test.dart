import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/ide_breadcrumbs.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp_ui/document_symbols.dart';
import 'package:baocode/ide/lsp_ui/semantic_tokens.dart';
import 'package:baocode/theme/codicons.dart';

import '../../flutter_test_config.dart' show testColorTheme;
import '../workbench/fake_files.dart';
import 'fake_language_features.dart';
import 'lsp_test_helpers.dart';
import 'semantic_token_fixture.dart';

const _a = 'lib/a.dart';

const _source =
    'class Greeter {\n'
    '  void greet() {\n'
    '    print(1);\n'
    '  }\n'
    '}\n'
    'void main() {}\n';

List<LspDocumentSymbol> _symbols(String path) => [
  LspDocumentSymbol(
    name: 'Greeter',
    kind: LspSymbolKind.klass,
    range: lspRange(0, 0, 1, endLine: 4),
    selectionRange: lspRange(0, 6, 13),
    children: [
      LspDocumentSymbol(
        name: 'greet',
        kind: LspSymbolKind.method,
        range: lspRange(1, 2, 3, endLine: 3),
        selectionRange: lspRange(1, 7, 12),
      ),
    ],
  ),
  LspDocumentSymbol(
    name: 'main',
    kind: LspSymbolKind.function,
    range: lspRange(5, 0, 14),
    selectionRange: lspRange(5, 5, 9),
  ),
];

void main() {
  testWidgets('the outline lists symbols, follows the caret and reveals '
      'them; breadcrumbs show the symbol path', (tester) async {
    final languages = FakeLanguageFeatures()..onDocumentSymbols = _symbols;
    await pumpLanguageWorkbench(tester, {_a: _source}, languages, open: [_a]);
    await settle(tester);

    runCommand(tester, 'outline.focus');
    await settle(tester);
    // Past the pane's opening (0.15s from the frame after).
    await settle(tester, const Duration(milliseconds: 200));
    expect(find.byType(IdeOutlineView), findsOneWidget);
    final outline = find.byType(IdeOutlineView);
    expect(
      find.descendant(of: outline, matching: find.text('Greeter')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: outline, matching: find.text('greet')),
      findsOneWidget,
    );

    await caretAt(tester, _source.indexOf('print'));
    final crumbs = find.byType(IdeBreadcrumbs);
    expect(tester.widget<IdeBreadcrumbs>(crumbs).symbols.map((s) => s.name), [
      'Greeter',
      'greet',
    ]);
    expect(
      find.descendant(of: crumbs, matching: find.text('greet')),
      findsOneWidget,
    );

    await tester.tap(find.descendant(of: outline, matching: find.text('main')));
    await settle(tester);
    expect(
      surfaceController(tester).value.selection.extentOffset,
      _source.indexOf('main'),
    );

    // Edits ask again after a pause.
    final before = languages.count('documentSymbols');
    surfaceController(tester).type('x');
    await settle(tester, const Duration(milliseconds: 400));
    expect(languages.count('documentSymbols'), before + 1);
  });

  testWidgets('Go to Symbol (@) filters symbols and reveals the pick', (
    tester,
  ) async {
    final languages = FakeLanguageFeatures()..onDocumentSymbols = _symbols;
    await pumpLanguageWorkbench(tester, {_a: _source}, languages, open: [_a]);
    await settle(tester);

    runCommand(tester, 'workbench.action.gotoSymbol');
    await settle(tester);
    expect(find.byType(IdeQuickInput), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(IdeQuickInput),
        matching: find.byType(TextField),
      ),
      '@gre',
    );
    await settle(tester);
    expect(
      find.descendant(
        of: find.byType(IdeQuickInput),
        matching: find.textContaining('Greeter'),
      ),
      findsWidgets,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(find.byType(IdeQuickInput), findsNothing);
    final caret = surfaceController(tester).value.selection.extentOffset;
    expect(
      caret == _source.indexOf('Greeter') || caret == _source.indexOf('greet('),
      isTrue,
    );
  });

  testWidgets('semantic tokens restyle the painted spans in the theme', (
    tester,
  ) async {
    final languages = FakeLanguageFeatures()
      ..onSemanticTokens = (path) => const [
        LspSemanticToken(0, 6, 7, 'class', {}),
        LspSemanticToken(1, 7, 5, 'method', {'declaration'}),
      ];
    await pumpLanguageWorkbench(tester, {_a: _source}, languages, open: [_a]);
    await settle(tester, const Duration(milliseconds: 350));

    // In the workbench's theme (Dark 2026 under test); Dart has no
    // language-specific rules, so it styles as plaintext.
    final fixture = SemanticTokenFixture.instance;
    final classStyle = fixture.style(
      testColorTheme,
      'class',
      {},
      'plaintext',
    )!;
    final methodStyle = fixture.style(testColorTheme, 'method', {
      'declaration',
    }, 'plaintext')!;
    expect(classStyle.foreground, isNotNull);
    expect(methodStyle.foreground, isNot(classStyle.foreground));

    final styled = tester
        .widget<EditorSurface>(find.byType(EditorSurface))
        .styledLines!;
    final line1 = styled[1]!;
    expect(line1.map((s) => s.text).join(), 'class Greeter {');
    final greeter = line1.firstWhere((s) => s.text == 'Greeter');
    expect(greeter.style!.color, classStyle.foreground);
    final greet = styled[2]!.firstWhere((s) => s.text == 'greet');
    expect(greet.style!.color, methodStyle.foreground);
    // Lines without tokens keep the syntax spans.
    final line3 = [const TextSpan(text: '    print(1);')];
    expect(languageSession(tester).styledLines({3: line3})![3], same(line3));
  });

  testWidgets('the session restyles its tokens for a new theme or language', (
    tester,
  ) async {
    final languages = FakeLanguageFeatures()
      ..onSemanticTokens = (path) => const [
        LspSemanticToken(0, 6, 7, 'property', {'readonly', 'defaultLibrary'}),
      ];
    await pumpLanguageWorkbench(tester, {_a: _source}, languages, open: [_a]);
    await settle(tester, const Duration(milliseconds: 350));
    // Null too when no span covers exactly 'Greeter'.
    Color? greeterColor() {
      final line = tester
          .widget<EditorSurface>(find.byType(EditorSurface))
          .styledLines?[1];
      for (final span in line ?? const <TextSpan>[]) {
        if (span.text == 'Greeter') return span.style?.color;
      }
      return null;
    }

    final fixture = SemanticTokenFixture.instance;
    const modifiers = {'readonly', 'defaultLibrary'};
    final session = languageSession(tester);
    // The editor gives the session the document's TextMate language.
    expect(session.languageId, 'dart');
    expect(
      greeterColor(),
      fixture
          .style(testColorTheme, 'property', modifiers, 'plaintext')!
          .foreground,
    );

    // Dark+ has TypeScript's own rule for this token.
    final darkPlus = await tester.runAsync(() => fixture.loadTheme('Dark+'));
    session.semanticTokenStyler = ideSemanticTokenStyler(darkPlus!);
    await settle(tester);
    final plain = fixture.style('Dark+', 'property', modifiers, 'plaintext')!;
    expect(greeterColor(), plain.foreground);

    session.languageId = 'typescript';
    await settle(tester);
    final typescript = fixture.style(
      'Dark+',
      'property',
      modifiers,
      'typescript',
    )!;
    expect(typescript.foreground, isNot(plain.foreground));
    expect(greeterColor(), typescript.foreground);

    // A theme without semantic highlighting leaves the syntax spans.
    final noSemantic = await tester.runAsync(
      () => fixture.loadTheme('Default High Contrast Light'),
    );
    expect(noSemantic!.semanticHighlighting, isFalse);
    session.semanticTokenStyler = ideSemanticTokenStyler(noSemantic);
    await settle(tester);
    final syntax = {
      1: const [TextSpan(text: 'class Greeter {')],
    };
    expect(session.styledLines(syntax), same(syntax));
    expect(greeterColor(), isNot(typescript.foreground));
  });

  testWidgets('status bar: a missing server offers to install it, a failed '
      'one retries', (tester) async {
    final languages = FakeLanguageFeatures();
    languages.statuses[inRoot(_a)] = const [
      LanguageServerStatus(
        serverId: 'dart-analyzer',
        state: LanguageServerState.missing,
        installable: true,
      ),
      LanguageServerStatus(
        serverId: 'lint',
        state: LanguageServerState.failed,
        message: 'crashed',
      ),
    ];
    await pumpLanguageWorkbench(tester, {_a: _source}, languages, open: [_a]);

    expect(find.text('dart-analyzer not installed'), findsOneWidget);
    // Opening the file recommends the server only in the notification
    // center, without a toast.
    const recommendation =
        "Do you want to install the recommended 'dart-analyzer' language "
        'server for the Dart language?';
    await _toastIn(tester);
    expect(find.text(recommendation), findsNothing);
    expect(find.byIcon(Codicons.bellDot), findsOneWidget);
    // The status bar entry recommends it in a toast.
    await tester.tap(find.text('dart-analyzer not installed'));
    await _toastIn(tester);
    expect(find.text(recommendation), findsOneWidget);
    await tester.tap(find.text('Install'));
    await settle(tester);
    expect(languages.installed, ['dart-analyzer']);
    expect(find.text(recommendation), findsNothing);

    languages.setStatus(inRoot(_a), const [
      LanguageServerStatus(
        serverId: 'dart-analyzer',
        state: LanguageServerState.running,
        progress: 'Indexing 3/10',
      ),
      LanguageServerStatus(
        serverId: 'lint',
        state: LanguageServerState.failed,
        message: 'crashed',
      ),
    ]);
    await settle(tester);
    expect(find.text('dart-analyzer: Indexing 3/10'), findsOneWidget);
    await tester.tap(find.text('lint failed'));
    await settle(tester);
    expect(languages.retried, ['lint']);
  });

  testWidgets('a missing runtime explains instead of installing', (
    tester,
  ) async {
    final languages = FakeLanguageFeatures();
    languages.statuses[inRoot(_a)] = const [
      LanguageServerStatus(
        serverId: 'pyright',
        state: LanguageServerState.missing,
        installable: true,
        missingRuntime: 'node',
      ),
    ];
    await pumpLanguageWorkbench(tester, {_a: _source}, languages, open: [_a]);
    // Not recommended: it cannot be installed.
    expect(find.text('Install'), findsNothing);
    await tester.tap(find.text('pyright not installed'));
    await _toastIn(tester);
    expect(find.textContaining('needs node'), findsOneWidget);
    expect(find.text('Install'), findsNothing);
    await tester.tap(find.byTooltip('Clear Notification'));
    await settle(tester);
    expect(find.textContaining('needs node'), findsNothing);
    expect(languages.installed, isEmpty);
  });

  testWidgets('a recommendation can be ignored for good', (tester) async {
    final languages = FakeLanguageFeatures();
    languages.statuses[inRoot(_a)] = const [
      LanguageServerStatus(
        serverId: 'dart-analyzer',
        state: LanguageServerState.missing,
        installable: true,
      ),
    ];
    final ignored = <String>[];
    await pumpLanguageWorkbench(
      tester,
      {_a: _source},
      languages,
      open: [_a],
      onIgnoreRecommendation: ignored.add,
    );
    await _toastIn(tester);
    // In the notification center, under its gear, as VS Code's "Don't Show
    // Again for this Extension".
    await tester.tap(find.byIcon(Codicons.bellDot));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More Actions...'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't Show Again for this Language Server"));
    await tester.pumpAndSettle();
    expect(ignored, ['dart-analyzer']);
    expect(find.textContaining('recommended'), findsNothing);
    expect(languages.installed, isEmpty);
  });

  testWidgets('an ignored server is not recommended', (tester) async {
    final languages = FakeLanguageFeatures();
    languages.statuses[inRoot(_a)] = const [
      LanguageServerStatus(
        serverId: 'dart-analyzer',
        state: LanguageServerState.missing,
        installable: true,
      ),
    ];
    await pumpLanguageWorkbench(
      tester,
      {_a: _source},
      languages,
      open: [_a],
      ignoredRecommendations: const {'dart-analyzer'},
    );
    await _toastIn(tester);
    expect(find.textContaining('recommended'), findsNothing);
    // The status bar still offers it.
    await tester.tap(find.text('dart-analyzer not installed'));
    await _toastIn(tester);
    expect(find.textContaining('recommended'), findsOneWidget);
  });

  testWidgets('language commands are in the palette with their keybindings', (
    tester,
  ) async {
    final languages = FakeLanguageFeatures(
      supported: {LanguageRequest.definition},
    );
    await pumpLanguageWorkbench(tester, {_a: _source}, languages, open: [_a]);
    final commands = {
      for (final command in workbenchState(tester).commands)
        command.id: command,
    };
    expect(commands['editor.action.revealDefinition']!.shortcutLabel(), 'F12');
    expect(commands['editor.action.revealDefinition']!.enabled, isTrue);
    expect(commands['editor.action.rename']!.enabled, isFalse);
    expect(
      commands['editor.action.formatSelection']!.shortcutLabel(),
      'Ctrl+K Ctrl+F',
    );
    expect(commands['editor.action.marker.nextInFiles']!.shortcutLabel(), 'F8');
    expect(
      commands['workbench.action.gotoSymbol']!.shortcutLabel(),
      'Ctrl+Shift+O',
    );
    expect(
      commands['workbench.actions.view.problems']!.shortcutLabel(),
      'Ctrl+Shift+M',
    );
  });
}

/// Lets a toast shown by the last action slide in.
Future<void> _toastIn(WidgetTester tester) async {
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 300));
}

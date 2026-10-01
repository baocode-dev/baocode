import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/lsp/lsp_protocol.dart';
import 'package:monad/ide/lsp_ui/language_widgets.dart';

import '../workbench/fake_files.dart';
import 'fake_language_features.dart';
import 'lsp_test_helpers.dart';

const _a = 'lib/a.dart';
const _b = 'lib/b.dart';

void main() {
  group('completion', () {
    const source = 'void main() {\n  pri\n}\n';

    FakeLanguageFeatures languages() =>
        FakeLanguageFeatures()
          ..onCompletion = (path, position, trigger) => LspCompletionList([
            const LspCompletionItem(
              label: 'print',
              kind: LspCompletionKind.function,
              detail: 'void print(Object? object)',
            ),
            const LspCompletionItem(label: 'printError'),
            const LspCompletionItem(
              label: 'private',
              kind: LspCompletionKind.keyword,
            ),
            const LspCompletionItem(label: 'other'),
          ]);

    testWidgets('Ctrl+Space filters by the word, arrows move, Enter accepts', (
      tester,
    ) async {
      final fake = languages();
      await pumpLanguageWorkbench(tester, {_a: source}, fake, open: [_a]);
      await caretAt(tester, offsetOf(tester, 'pri') + 3);

      await press(tester, LogicalKeyboardKey.space, primary: true);
      expect(find.byType(IdeSuggestWidget), findsOneWidget);
      final session = languageSession(tester).suggest;
      expect(
        [for (final item in session.items) item.completion.label],
        ['print', 'printError', 'private'],
      );
      expect(session.selectedIndex, 0);
      // The focused item's detail shows beside the list.
      expect(find.text('void print(Object? object)'), findsWidgets);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(session.selectedIndex, 1);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(session.selectedIndex, 2);

      // Typing refilters.
      surfaceController(tester).type('n');
      await settle(tester);
      expect(
        [for (final item in session.items) item.completion.label],
        ['print', 'printError'],
      );

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(IdeSuggestWidget), findsNothing);
      expect(
        surfaceController(tester).value.text,
        'void main() {\n  printError\n}\n',
      );
    });

    testWidgets('a trigger character opens it; Escape closes it', (
      tester,
    ) async {
      final fake = languages();
      await pumpLanguageWorkbench(
        tester,
        {_a: 'void main() {\n  x\n}\n'},
        fake,
        open: [_a],
      );
      await caretAt(tester, offsetOf(tester, 'x') + 1);
      surfaceController(tester).type('.');
      await settle(tester);
      expect(find.byType(IdeSuggestWidget), findsOneWidget);
      expect(fake.count('completion'), 1);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(IdeSuggestWidget), findsNothing);

      // Quick suggestions while typing a word.
      surfaceController(tester).type('p');
      await settle(tester, const Duration(milliseconds: 20));
      expect(fake.count('completion'), 2);
      expect(find.byType(IdeSuggestWidget), findsOneWidget);
    });

    testWidgets('textEdit and additionalTextEdits apply as one undo step', (
      tester,
    ) async {
      final fake = FakeLanguageFeatures()
        ..onCompletion = (path, position, trigger) => LspCompletionList([
          LspCompletionItem(
            label: 'Foo',
            kind: LspCompletionKind.klass,
            textEdit: LspTextEdit(lspRange(1, 2, 5), 'Foo()'),
            additionalTextEdits: [
              LspTextEdit(lspRange(0, 0, 0), "import 'foo.dart';\n"),
            ],
            command: const LspCommand('Log', 'log.accept'),
            serverId: 'dart',
          ),
        ]);
      final workspace = await pumpLanguageWorkbench(
        tester,
        {_a: 'void main() {\n  Fxx\n}\n'},
        fake,
        open: [_a],
      );
      await caretAt(tester, offsetOf(tester, 'Fxx') + 1);
      await press(tester, LogicalKeyboardKey.space, primary: true);
      expect(languageSession(tester).suggest.items, hasLength(1));
      await press(tester, LogicalKeyboardKey.tab);
      expect(
        surfaceController(tester).value.text,
        "import 'foo.dart';\nvoid main() {\n  Foo()\n}\n",
      );
      expect(fake.executed.single.$1.command, 'log.accept');
      expect(fake.executed.single.$2, 'dart');

      expect(workspace.undo(inRoot(_a)), isTrue);
      await settle(tester);
      expect(surfaceController(tester).value.text, 'void main() {\n  Fxx\n}\n');
    });

    testWidgets('snippet completions insert tabstops: Tab moves, mirrors '
        'follow, the final tabstop ends the session', (tester) async {
      final fake = FakeLanguageFeatures()
        ..onCompletion = (path, position, trigger) => const LspCompletionList([
          LspCompletionItem(
            label: 'for',
            kind: LspCompletionKind.snippet,
            insertText: r'for (var ${1:i} = 0; $1 < ${2:n}; $1++) {$0}',
            isSnippet: true,
          ),
        ]);
      await pumpLanguageWorkbench(
        tester,
        {_a: 'void main() {\n  fo\n}\n'},
        fake,
        open: [_a],
      );
      await caretAt(tester, offsetOf(tester, 'fo') + 2);
      await press(tester, LogicalKeyboardKey.space, primary: true);
      await press(tester, LogicalKeyboardKey.enter);

      final controller = surfaceController(tester);
      expect(
        controller.value.text,
        'void main() {\n  for (var i = 0; i < n; i++) {}\n}\n',
      );
      expect(controller.inSnippetMode, isTrue);
      var selection = controller.value.selection;
      expect(
        controller.value.text.substring(selection.start, selection.end),
        'i',
      );

      controller.type('j');
      await settle(tester);
      expect(
        controller.value.text,
        'void main() {\n  for (var j = 0; j < n; j++) {}\n}\n',
      );

      await press(tester, LogicalKeyboardKey.tab);
      selection = controller.value.selection;
      expect(
        controller.value.text.substring(selection.start, selection.end),
        'n',
      );
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      selection = controller.value.selection;
      expect(
        controller.value.text.substring(selection.start, selection.end),
        'j',
      );
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      expect(controller.inSnippetMode, isFalse);
      expect(
        controller.value.selection.extentOffset,
        controller.value.text.indexOf('{}') + 1,
      );
    });

    testWidgets('resolving the focused item fills its documentation', (
      tester,
    ) async {
      final fake = languages()
        ..onResolveCompletion = (item) => LspCompletionItem(
          label: item.label,
          detail: item.detail,
          documentation: 'Prints **${item.label}**',
        );
      await pumpLanguageWorkbench(tester, {_a: source}, fake, open: [_a]);
      await caretAt(tester, offsetOf(tester, 'pri') + 3);
      await press(tester, LogicalKeyboardKey.space, primary: true);
      await settle(tester);
      expect(fake.count('resolveCompletion'), 1);
      expect(find.textContaining('Prints'), findsOneWidget);
    });
  });

  testWidgets('signature help opens on "(", highlights the active parameter '
      'and closes on Escape', (tester) async {
    final fake = FakeLanguageFeatures()
      ..onSignatureHelp = (path, position) => const LspSignatureHelp([
        LspSignature(
          'add(int a, int b)',
          parameters: [
            LspParameterInformation('int a'),
            LspParameterInformation('int b', documentation: 'The addend'),
          ],
        ),
        LspSignature('add(double a)'),
      ], activeParameter: 1);
    await pumpLanguageWorkbench(
      tester,
      {_a: 'void main() {\n  add\n}\n'},
      fake,
      open: [_a],
    );
    await caretAt(tester, offsetOf(tester, 'add') + 3);
    surfaceController(tester).type('(');
    await settle(tester);
    expect(find.byType(IdeParameterHints), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.textContaining('The addend'), findsOneWidget);
    final signature = languageSession(tester).signature!;
    expect(
      IdeParameterHints.activeParameterRange(
        signature.signature,
        signature.activeParameter,
      ),
      ('add(int a, '.length, 'add(int a, int b'.length),
    );

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.text('2/2'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(IdeParameterHints), findsNothing);
  });

  testWidgets('F2 renames across two files with one undo step per document', (
    tester,
  ) async {
    final fake = FakeLanguageFeatures()
      ..onPrepareRename = ((path, position) =>
          (range: lspRange(0, 4, 7), placeholder: 'foo'))
      ..onRename = (path, position, newName) => LspWorkspaceEdit({
        uriOf(_a): [
          LspTextEdit(lspRange(0, 4, 7), newName),
          LspTextEdit(lspRange(1, 14, 17), newName),
        ],
        uriOf(_b): [LspTextEdit(lspRange(0, 0, 3), newName)],
      });
    final workspace = await pumpLanguageWorkbench(
      tester,
      {_a: 'int foo = 1;\nvoid main() { foo; }\n', _b: 'foo + 1;\n'},
      fake,
      open: [_a],
    );
    await caretAt(tester, 5);

    await press(tester, LogicalKeyboardKey.f2);
    expect(find.byType(IdeRenameInput), findsOneWidget);
    final field = find.byKey(const ValueKey('ide-rename-field'));
    expect(tester.widget<TextField>(field).controller!.text, 'foo');
    await tester.enterText(field, 'bar');
    // Enter runs acceptRenameInput (the input's submit action does not).
    await press(tester, LogicalKeyboardKey.enter);
    await settle(tester);
    await settle(tester);

    expect(find.byType(IdeRenameInput), findsNothing);
    expect(workspace.active!.path, inRoot(_a));
    final a = workspace.documents.firstWhere((d) => d.path == inRoot(_a));
    final b = workspace.documents.firstWhere((d) => d.path == inRoot(_b));
    expect(a.text, 'int bar = 1;\nvoid main() { bar; }\n');
    // The unopened file opened as a dirty tab.
    expect(b.text, 'bar + 1;\n');
    expect(b.dirty, isTrue);
    // The caret stayed on the renamed symbol.
    expect(surfaceController(tester).value.selection.extentOffset, 5);

    expect(workspace.undo(a.path), isTrue);
    expect(a.text, 'int foo = 1;\nvoid main() { foo; }\n');
    expect(workspace.undo(b.path), isTrue);
    expect(b.text, 'foo + 1;\n');
  });

  testWidgets('Escape cancels the rename input', (tester) async {
    final fake = FakeLanguageFeatures();
    await pumpLanguageWorkbench(
      tester,
      {_a: 'int foo = 1;\n'},
      fake,
      open: [_a],
    );
    await caretAt(tester, 5);
    await press(tester, LogicalKeyboardKey.f2);
    expect(find.byType(IdeRenameInput), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(IdeRenameInput), findsNothing);
    expect(fake.count('rename'), 0);
  });

  testWidgets('Format Document applies the edits as one undo step and keeps '
      'the caret', (tester) async {
    const before = 'void main(){\nprint( 1 );\n  var x=2;\n}\n';
    const after = 'void main() {\n  print(1);\n  var x = 2;\n}\n';
    final fake = FakeLanguageFeatures()
      ..onFormat = (path, range) => [
        LspTextEdit(lspRange(0, 0, 0, endLine: 4), after),
      ];
    final workspace = await pumpLanguageWorkbench(
      tester,
      {_a: before},
      fake,
      open: [_a],
    );
    await caretAt(tester, before.indexOf('x=2'));

    await press(tester, LogicalKeyboardKey.keyF, shift: true, alt: true);
    await settle(tester);
    final controller = surfaceController(tester);
    expect(controller.value.text, after);
    expect(controller.value.selection.extentOffset, after.indexOf('x = 2'));

    expect(workspace.undo(inRoot(_a)), isTrue);
    expect(workspace.active!.text, before);
  });

  testWidgets('Quick Fix (Ctrl/Cmd+.) lists actions, preferred first, and '
      'applies the chosen edit; the lightbulb appears', (tester) async {
    final diagnostic = LspDiagnostic(
      range: lspRange(0, 0, 3),
      message: 'Unknown type',
    );
    final fake = FakeLanguageFeatures()
      ..onCodeActions = (path, range, diagnostics) => [
        const LspCodeAction(title: 'Extract method', kind: 'refactor.extract'),
        LspCodeAction(
          title: "Import 'dart:math'",
          kind: 'quickfix',
          isPreferred: true,
          diagnostics: diagnostics,
          edit: LspWorkspaceEdit({
            uriOf(_a): [
              LspTextEdit(lspRange(0, 0, 0), "import 'dart:math';\n"),
            ],
          }),
          command: const LspCommand('Organize', 'organize'),
        ),
      ];
    fake.diagnostics[inRoot(_a)] = [diagnostic];
    await pumpLanguageWorkbench(tester, {_a: 'Rnd r;\n'}, fake, open: [_a]);
    await caretAt(tester, 1);
    await settle(tester, const Duration(milliseconds: 300));
    expect(find.byType(IdeLightbulb), findsOneWidget);

    await press(tester, LogicalKeyboardKey.period, primary: true);
    expect(find.byType(IdeCodeActionMenuWidget), findsOneWidget);
    final menu = languageSession(tester).codeActionMenu!;
    expect(menu.actions.first.action.title, "Import 'dart:math'");
    expect(find.text('Quick Fix'), findsOneWidget);
    expect(find.text('Extract'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.enter);
    await settle(tester);
    expect(find.byType(IdeCodeActionMenuWidget), findsNothing);
    expect(
      surfaceController(tester).value.text,
      "import 'dart:math';\nRnd r;\n",
    );
    expect(fake.executed.single.$1.command, 'organize');
  });

  testWidgets('workspace/applyEdit requests apply and answer', (tester) async {
    final fake = FakeLanguageFeatures();
    final workspace = await pumpLanguageWorkbench(
      tester,
      {_a: 'one\n', _b: 'two\n'},
      fake,
      open: [_a],
    );

    late bool applied;
    fake
        .requestApplyEdit(
          LspWorkspaceEdit({
            uriOf(_a): [LspTextEdit(lspRange(0, 0, 3), 'ONE')],
          }),
        )
        .then((value) => applied = value);
    await settle(tester);
    expect(applied, isTrue);
    expect(workspace.active!.text, 'ONE\n');

    fake
        .requestApplyEdit(
          const LspWorkspaceEdit(
            {},
            resourceOperations: [
              {'kind': 'delete', 'uri': 'file:///project/lib/b.dart'},
            ],
          ),
        )
        .then((value) => applied = value);
    await settle(tester);
    expect(applied, isFalse);
  });
}

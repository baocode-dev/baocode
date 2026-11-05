import 'dart:async';

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_layout.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp_ui/lsp_convert.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart';
import 'package:baocode/ide/services/language.dart';
import 'package:baocode/ide/services/problems.dart';
import 'package:baocode/ide/services/references.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/context_keys.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/contributions/language.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/statusbar.dart';
import 'package:baocode/l10n/app_localizations.dart';

import '../../lsp_ui/fake_language_features.dart';
import '../fake_files.dart';
import 'fake_host.dart';

LspRange _at(int line, int start, int end) =>
    LspRange(LspPosition(line, start), LspPosition(line, end));

/// The language servers' services alone, over a workspace with scripted
/// servers: the servers' edits, the problems stepped through and counted,
/// the references stepped through, and their context keys.
void main() {
  late FakeLanguageFeatures languages;
  late IdeWorkspace workspace;
  late FakeWorkbenchHost host;
  late IdeLayout layout;
  late LanguageService language;
  late ProblemsService problems;
  late ReferencesService references;
  late WorkbenchServices services;
  var caret = const Position(1, 1);
  final applied = <LspWorkspaceEdit>[];
  var hovers = 0;

  Future<void> setUpServices(WidgetTester tester) async {
    languages = FakeLanguageFeatures();
    workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles({inRoot('a.dart'): 'a\nb\nc', inRoot('b.dart'): 'b'}),
      languages: languages,
    );
    host = FakeWorkbenchHost();
    layout = IdeLayout();
    caret = const Position(1, 1);
    applied.clear();
    hovers = 0;
    language = LanguageService(
      host: host,
      caret: () => caret,
      applyEdit: (edit) async {
        applied.add(edit);
        return true;
      },
      ignored: () => const {},
    );
    problems = ProblemsService(
      host: host,
      language: language,
      layout: () => layout,
      caret: () => caret,
      activePath: () => workspace.active?.path,
      showHover: () => hovers++,
    );
    references = ReferencesService(
      host: host,
      layout: () => layout,
      caret: () => caret,
      activePath: () => workspace.active?.path,
    );
    services = WorkbenchServices()
      ..add(ActionRegistry())
      ..add(ContextKeyService())
      ..add(StatusbarService())
      ..add<WorkbenchHost>(host)
      ..add(workspace)
      ..add(language)
      ..add(problems)
      ..add(references);
    final contribution = LanguageContribution(services);
    language.attach(workspace);
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) {
            host.context = context;
            return const SizedBox();
          },
        ),
      ),
    );
    addTearDown(() {
      contribution.dispose();
      services.remove<IdeWorkspace>(owned: false);
      services.dispose();
      workspace.dispose();
      languages.dispose();
    });
  }

  testWidgets('a server\'s edits are applied, and answered', (tester) async {
    await setUpServices(tester);
    final edit = LspWorkspaceEdit(const {});
    // Heard in the test's zone, as the window's are.
    bool? answer;
    unawaited(languages.requestApplyEdit(edit).then((a) => answer = a));
    await tester.pump();
    expect(answer, isTrue);
    expect(applied, [same(edit)]);
  });

  testWidgets('problems: counted, stepped through across files, with the '
      'hover', (tester) async {
    await setUpServices(tester);
    final keys = services.get<ContextKeyService>();
    final statusbar = services.get<StatusbarService>();
    String counts() =>
        statusbar.items(host.context!, StatusbarAlignment.left).first.text;
    expect(counts(), r'$(error) 0 $(warning) 0');
    languages
      ..setDiagnostics(inRoot('a.dart'), [
        LspDiagnostic(range: _at(1, 0, 1), message: 'one'),
      ])
      ..setDiagnostics(inRoot('b.dart'), [
        LspDiagnostic(
          range: _at(0, 0, 1),
          message: 'two',
          severity: LspDiagnosticSeverity.warning,
        ),
      ]);
    expect(counts(), r'$(error) 1 $(warning) 1');

    await workspace.open(inRoot('a.dart'));
    problems.go(next: true);
    await tester.pump();
    expect(host.calls, ['openLocation ${inRoot('a.dart')}']);
    expect(hovers, 1);
    problems.go(next: true);
    expect(host.calls.last, 'openLocation ${inRoot('b.dart')}');

    // Toggle Problems: shown with the keyboard; the status bar's toggles.
    expect(keys.getValue('problemsVisibility'), isFalse);
    services
        .get<ActionRegistry>()
        .byId('workbench.actions.view.problems')!
        .run(services, null);
    expect(layout.panel, IdePanelTab.problems);
    expect(keys.getValue('problemsVisibility'), isTrue);
    expect(keys.getValue('problemFocus'), isFalse);
    problems.togglePanel();
    expect(layout.panel, isNull);
  });

  testWidgets('references: shown in the panel, stepped through from the '
      'nearest', (tester) async {
    await setUpServices(tester);
    final keys = services.get<ContextKeyService>();
    final actions = services.get<ActionRegistry>();
    bool enabled(String id) => actions.byId(id)!.precondition!(services);
    expect(keys.getValue('reference-list.isActive'), isFalse);
    expect(enabled('references-view.next'), isFalse);

    await workspace.open(inRoot('a.dart'));
    references.show('References', [
      IdeLocation(inRoot('a.dart'), _at(0, 0, 1)),
      IdeLocation(inRoot('a.dart'), _at(2, 0, 1)),
      IdeLocation(inRoot('b.dart'), _at(0, 0, 1)),
    ]);
    expect(layout.panel, IdePanelTab.references);
    expect(keys.getValue('reference-list.hasResult'), isTrue);
    expect(enabled('references-view.next'), isTrue);

    // From the caret's (line 2: the first after it is line 3's), on.
    caret = const Position(2, 1);
    references.go(next: true);
    await tester.pump();
    expect(host.calls, ['openLocation ${inRoot('b.dart')}', 'focusEditor']);
    expect(references.list.focused, isA<IdeLocation>());

    actions.byId('references-view.clear')!.run(services, null);
    expect(references.references, isNull);
    expect(keys.getValue('reference-list.isActive'), isFalse);
  });
}

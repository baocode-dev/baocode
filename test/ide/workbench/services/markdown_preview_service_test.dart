import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/markdown/markdown_paste.dart';
import 'package:baocode/ide/services/markdown_preview.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/contributions/editor_panes.dart';
import 'package:baocode/ide/workbench/contributions/markdown.dart';
import 'package:baocode/ide/workbench/editor_panes.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/storage.dart';

import '../fake_files.dart';
import 'fake_host.dart';

/// The markdown previews alone, over a workspace: which documents show as
/// one, switching them, what the window keeps, and their pane and commands.
void main() {
  late IdeWorkspace workspace;
  late FakeWorkbenchHost host;
  late WorkbenchStorage storage;
  late MarkdownPreviewService markdown;
  var kept = 0;
  final inserted = <String>[];

  Future<void> setUpPreview(WidgetTester tester) async {
    workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles({
        inRoot('README.md'): '# Title\n\ntext\n',
        inRoot('notes.md'): 'notes',
        inRoot('a.txt'): 'a',
      }),
    );
    host = FakeWorkbenchHost();
    kept = 0;
    inserted.clear();
    storage = WorkbenchStorage(onChanged: () => kept++);
    markdown = MarkdownPreviewService(
      host: host,
      storage: storage,
      workspace: () => workspace,
      caret: () => const Position(3, 1),
      clipboard: () => const SystemMarkdownClipboard(),
      insertInEditor: inserted.add,
    );
    storage.register(markdown);
    // A window to switch in.
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          host.context = context;
          return const SizedBox();
        },
      ),
    );
    addTearDown(() {
      markdown.dispose();
      workspace.dispose();
    });
  }

  testWidgets('markdown files show as their preview until switched', (
    tester,
  ) async {
    await setUpPreview(tester);
    await workspace.open(inRoot('a.txt'));
    expect(markdown.hasPreview(workspace.active!), isFalse);
    expect(markdown.previewing(workspace.active), isFalse);

    await workspace.open(inRoot('README.md'));
    final readme = workspace.active!;
    expect(markdown.hasPreview(readme), isTrue);
    expect(markdown.previewing(readme), isTrue);

    var changes = 0;
    markdown.addListener(() => changes++);
    await markdown.setPreview(false);
    expect(markdown.previewing(readme), isFalse);
    expect(changes, 1);
    expect(kept, 1);
    // Already the source: nothing.
    await markdown.setPreview(false);
    expect(changes, 1);

    // The source at a place: there, focused, once the frame is drawn.
    await markdown.setPreview(true);
    expect(markdown.previewing(readme), isTrue);
    // The preview starts at the source's caret.
    expect(workspace.viewStateOf(readme).previewLine, 3);
    tester.binding.scheduleFrame();
    await tester.pump();
    host.calls.clear();
    await markdown.setPreview(false, at: (line: 2, column: 4));
    // The frame the window's rebuild draws.
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(host.calls, ['revealLine 2:4', 'focusEditor']);
  });

  testWidgets('the files shown as their source are kept with the window', (
    tester,
  ) async {
    await setUpPreview(tester);
    storage.restore({
      'markdownSource': [inRoot('notes.md'), 7],
    });
    await workspace.open(inRoot('notes.md'));
    expect(markdown.previewing(workspace.active), isFalse);
    await workspace.open(inRoot('README.md'));
    await markdown.setPreview(false);
    expect(storage.collect()['markdownSource'], [
      inRoot('notes.md'),
      inRoot('README.md'),
    ]);
    // None: no key.
    await markdown.setPreview(true);
    await workspace.open(inRoot('notes.md'));
    await markdown.setPreview(true);
    expect(storage.collect().containsKey('markdownSource'), isFalse);
  });

  testWidgets('a link to a line opens its file there', (tester) async {
    await setUpPreview(tester);
    await markdown.openLinked(inRoot('a.txt'), 'L12');
    expect(host.calls, ['openFile ${inRoot('a.txt')}:12']);
  });

  testWidgets('the panes: a preview for markdown, the editor otherwise', (
    tester,
  ) async {
    await setUpPreview(tester);
    final services = WorkbenchServices()
      ..add(ActionRegistry())
      ..add(EditorPaneRegistry())
      ..add<WorkbenchHost>(host)
      ..add(workspace)
      ..add(markdown);
    final contributions = [
      EditorPanesContribution(services),
      MarkdownContribution(services),
    ];
    addTearDown(() => disposeContributions(contributions));
    final panes = services.get<EditorPaneRegistry>();
    final actions = services.get<ActionRegistry>();
    bool enabled(String id) => actions.byId(id)!.precondition!(services);

    await workspace.open(inRoot('a.txt'));
    expect(panes.paneFor(workspace.active!), isNull);
    expect(enabled('markdown.showPreview'), isFalse);
    expect(enabled('markdown.showSource'), isFalse);

    await workspace.open(inRoot('README.md'));
    expect(
      panes.paneFor(workspace.active!)?.id,
      'workbench.editor.markdownPreview',
    );
    expect(enabled('markdown.showPreview'), isFalse);
    expect(enabled('markdown.showSource'), isTrue);

    actions.byId('markdown.showSource')!.run(services, null);
    await tester.pump();
    expect(panes.paneFor(workspace.active!), isNull);
    expect(enabled('markdown.showPreview'), isTrue);
  });

  test('a pane of greater priority shows the document', () {
    final panes = EditorPaneRegistry();
    final doc = IdeDocument.untitled('Untitled-1');
    EditorPane pane(String id) => EditorPane(
      id: id,
      accepts: (_) => true,
      build: (_, _) => const SizedBox(),
    );
    final low = panes.register(pane('low'), priority: 1);
    panes.register(pane('first'), priority: 5);
    panes.register(pane('second'), priority: 5);
    expect(panes.paneFor(doc)?.id, 'first');
    low();
    expect(panes.paneFor(doc)?.id, 'first');
  });
}

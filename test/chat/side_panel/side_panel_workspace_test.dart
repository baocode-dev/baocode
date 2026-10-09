// The side panel of a conversation in a multi-folder workspace, as the
// IDE's: each folder a root of the files page, a repository of the changes
// page's to pick from; the files the agent names found in its folders.

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/side_panel/file_link.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/git/repository_scan.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../ide/git/fake_git.dart';

/// Files in memory.
class _Files implements IdeFileService {
  _Files(this.texts);

  final Map<String, String> texts;

  @override
  Future<String> read(String path, {bool force = false}) async =>
      texts[path] ?? (throw IdeFileNotFoundException(path));

  @override
  Future<List<IdeFile>> list(String directory) async {
    final entries = <String, bool>{};
    for (final path in texts.keys) {
      if (!p.isWithin(directory, path)) continue;
      final relative = p.split(p.relative(path, from: directory));
      entries[p.join(directory, relative.first)] = relative.length > 1;
    }
    return [
      for (final MapEntry(key: path, value: isDirectory) in entries.entries)
        IdeFile(path, p.basename(path), isDirectory: isDirectory),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _workspace = '/data/workspaces/w1';
const _site = '/code/site';
const _api = '/code/api';

final _files = _Files({
  '$_site/index.html': '<html>',
  '$_api/main.go': 'package main',
  '$_api/new.go': 'package main',
});

/// A conversation in the workspace `web` of [roots], its side panel shown
/// at [section].
Future<({AgentSidePanel panel, ChatSession session})> _pump(
  WidgetTester tester, {
  required SidePanelSection section,
  List<String> roots = const [_site, _api],
  List<(String, IdeGitRepository)> repositories = const [],
  String? workspaceName = 'web',
  IdeGitRepository? git,
  VoidCallback? onAddFolder,
  ValueChanged<String>? onRemoveFolder,
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = ChatSession(
    kernelContext: const KernelContext(cwd: _workspace),
    openReview: (root, {session}) async => null,
  );
  addTearDown(session.dispose);
  final panel = AgentSidePanel();
  addTearDown(panel.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: Material(
        child: AgentSidePanelArea(
          panel: panel,
          builder: (context) => AgentSidePanelView(
            panel: panel,
            session: session,
            files: _files,
            watchDirectory: (_) => const Stream.empty(),
            workspaceName: workspaceName,
            git: git,
            roots: roots,
            repositories: repositories,
            onAddFolder: onAddFolder,
            onRemoveFolder: onRemoveFolder,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
  panel.showSection(session, section);
  await tester.pumpAndSettle();
  return (panel: panel, session: session);
}

Finder get _list => find.byKey(const ValueKey('side-panel-list'));

Finder _inList(String text) =>
    find.descendant(of: _list, matching: find.text(text));

void main() {
  testWidgets('the files page has each folder a root, under the '
      'workspace\'s name; a root is taken out from its menu', (tester) async {
    final removed = <String>[];
    final (:panel, :session) = await _pump(
      tester,
      section: SidePanelSection.files,
      onAddFolder: () {},
      onRemoveFolder: removed.add,
    );
    expect(_inList('web (Workspace)'), findsOneWidget);
    final site = tester.getTopLeft(_inList('site')).dy;
    final api = tester.getTopLeft(_inList('api')).dy;
    expect(site, lessThan(api));
    expect(tester.getTopLeft(_inList('index.html')).dy, greaterThan(site));
    expect(tester.getTopLeft(_inList('main.go')).dy, greaterThan(api));

    // A file of either opens beside the tree.
    await tester.tap(_inList('main.go'));
    await tester.pumpAndSettle();
    expect(panel.tabsOf(session).active?.path, '$_api/main.go');

    await tester.tap(
      find.ancestor(of: _inList('api'), matching: find.byType(IdeListRow)),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    await tester.tap(find.text('Remove Folder from Workspace'));
    await tester.pumpAndSettle();
    expect(removed, [_api]);

    // The workspace takes it out: the tree follows.
    panel.setRoots(_workspace, [_site]);
    await tester.pumpAndSettle();
    expect(_inList('main.go'), findsNothing);
    expect(
      find.descendant(of: _list, matching: find.byType(IdeExplorer)),
      findsOneWidget,
    );
  });

  testWidgets('a workspace with no folders asks for one', (tester) async {
    var added = 0;
    await _pump(
      tester,
      section: SidePanelSection.files,
      roots: const [],
      onAddFolder: () => added++,
    );
    expect(_inList('This workspace has no folders yet.'), findsOneWidget);
    await tester.tap(_inList('Add Folder to Workspace…'));
    expect(added, 1);
  });

  testWidgets('the changes page lists each folder\'s repository, counts '
      'them all, and shows the one picked', (tester) async {
    final site = FakeGit(_site)..status = '## main\x00 M index.html\x00';
    final api = FakeGit(_api)..status = '## dev\x00 M main.go\x00?? new.go\x00';
    final repositories = [(_site, site.repository()), (_api, api.repository())];
    for (final (_, git) in repositories) {
      addTearDown(git.dispose);
    }
    final (:panel, :session) = await _pump(
      tester,
      section: SidePanelSection.changes,
      repositories: repositories,
    );
    // Each with its branch and changes.
    expect(_inList('site'), findsOneWidget);
    expect(_inList('api'), findsOneWidget);
    expect(_inList('main'), findsOneWidget);
    expect(_inList('dev'), findsOneWidget);
    // The page's tab counts every repository's.
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_SectionBar',
        ),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    // The first's changes until another is picked.
    expect(_inList('index.html'), findsOneWidget);
    expect(_inList('new.go'), findsNothing);

    await tester.tap(_inList('dev'));
    await tester.pumpAndSettle();
    expect(panel.repositoryOf(session.root!), _api);
    expect(_inList('new.go'), findsOneWidget);
    expect(_inList('index.html'), findsNothing);
  });

  testWidgets('a folder\'s project lists the repositories found in its '
      'subfolders, its own left out once known not to be one', (tester) async {
    final own = FakeGit(_workspace)..isRepository = false;
    final nested = FakeGit(_api)..status = '## dev\x00?? new.go\x00';
    final (ownGit, nestedGit) = (own.repository(), nested.repository());
    addTearDown(ownGit.dispose);
    addTearDown(nestedGit.dispose);
    await ownGit.refresh();
    await nestedGit.refresh();
    await _pump(
      tester,
      section: SidePanelSection.changes,
      workspaceName: null,
      roots: const [],
      git: ownGit,
      repositories: ideFolderRepositories(_workspace, ownGit, [
        (_api, nestedGit),
      ]),
    );
    expect(_inList('new.go'), findsOneWidget);
    expect(find.textContaining('doesn\'t have a Git repository'), findsNothing);
  });

  group('the files the chat names', () {
    /// The scope of a conversation in the workspace, the files there as
    /// [_files] has them.
    FileOpenScope scope(List<FileOpenRequest> opened) => FileOpenScope(
      root: _workspace,
      roots: const [_site, _api],
      onOpen: opened.add,
      existence: FileExistence(fileExistsIn(_files)),
      child: const SizedBox(),
    );

    test('a relative path is found in the folder that has it', () async {
      final opened = <FileOpenRequest>[];
      final files = scope(opened);
      // Not known yet: the first folder's, while each is asked.
      expect(files.resolve('main.go'), '$_site/main.go');
      await pumpEventQueue();
      expect(files.resolve('main.go'), '$_api/main.go');
      expect(files.resolve('index.html'), '$_site/index.html');
      // An absolute path in any folder; none outside them.
      expect(files.resolve('$_api/new.go'), '$_api/new.go');
      expect(files.resolve('/elsewhere/a.go'), isNull);
    });

    test('a link opens where it is found, though not known before', () async {
      final opened = <FileOpenRequest>[];
      expect(
        scope(opened).openLink(FileLink('new.go', FileLineRange(3))),
        isTrue,
      );
      await pumpEventQueue();
      expect(opened.single.path, '$_api/new.go');
      expect(opened.single.range, FileLineRange(3));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/search/text_search.dart';
import 'package:baocode/ide/services/editors.dart';
import 'package:baocode/ide/services/layout.dart';
import 'package:baocode/ide/services/search_view.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/context_keys.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/contributions/search.dart';
import 'package:baocode/ide/workbench/editor_panes.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/storage.dart';
import 'package:baocode/ide/workbench/views.dart';

import '../fake_files.dart';
import 'fake_host.dart';

/// The Search view alone, over a workspace and no window: Find in Files'
/// options, Find in Folder, its context keys and commands, what it keeps
/// of the view state.
void main() {
  late IdeWorkspace workspace;
  late FakeWorkbenchHost host;
  late LayoutService layout;
  late SearchViewService search;
  late WorkbenchServices services;
  late SearchContribution contribution;
  var kept = 0;
  final queries = <String>[];

  setUp(() {
    workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles({inRoot('src/a.dart'): 'a'}),
    );
    host = FakeWorkbenchHost();
    kept = 0;
    queries.clear();
    layout = LayoutService(host: host, layout: () => workspace.layout)
      ..attach(workspace.layout);
    final storage = WorkbenchStorage(onChanged: () => kept++);
    final panes = EditorPaneRegistry();
    final editors = EditorService(
      host: host,
      panes: panes,
      workspace: () => workspace,
      layout: () => workspace.layout,
      history: () => null,
      focusWorkbench: () {},
    );
    search = SearchViewService(
      host: host,
      layout: layout,
      editors: editors,
      workspace: () => workspace,
      textSearch: () => (root, query) {
        queries.add('$root ${query.pattern}');
        return Stream.value(const IdeTextSearchComplete(limitHit: false));
      },
      storage: storage,
    );
    storage.register(search);
    services = WorkbenchServices()
      ..add(ActionRegistry())
      ..add(ContextKeyService())
      ..add<WorkbenchHost>(host)
      ..add(layout)
      ..add(panes)
      ..add(editors)
      ..add(search);
    contribution = SearchContribution(services);
    addTearDown(() {
      contribution.dispose();
      services.dispose();
      workspace.dispose();
    });
  });

  Object? key(String key) => services.get<ContextKeyService>().getValue(key);
  WorkbenchAction action(String id) => services.get<ActionRegistry>().byId(id)!;
  bool enabled(String id) => action(id).precondition?.call(services) ?? true;

  test('Find in Files: its options, the view shown, searched', () {
    workspace.layout.sidebar = false;
    action('workbench.action.findInFiles').run(services, {
      'query': 'needle',
      'replace': 'thread',
      'isRegex': true,
      'filesToInclude': 'src',
      'triggerSearch': true,
    });
    final session = search.session;
    expect(session.query.text, 'needle');
    expect(session.replace.text, 'thread');
    expect(session.replaceShown, isTrue);
    expect(session.useRegExp, isTrue);
    expect(session.includes.text, 'src');
    // Files to include: shown, not to be missed.
    expect(session.detailsShown, isTrue);
    expect(layout.view, IdeSideView.search);
    expect(workspace.layout.sidebar, isTrue);
    expect(queries, ['$testRoot needle']);

    expect(key('searchViewletVisible'), isTrue);
    expect(key('replaceActive'), isTrue);
    expect(key('viewHasSearchPattern'), isTrue);
    expect(key('viewHasFilePattern'), isTrue);
    expect(key('searchInputBoxFocus'), isFalse);
    expect(key('someoneElses'), isNull);
    expect(enabled('search.action.refreshSearchResults'), isTrue);
    expect(enabled('search.action.clearSearchResults'), isTrue);
    // Not showing (no widget): the view's own commands wait.
    expect(enabled('search.action.openResult'), isFalse);
    expect(enabled('toggleSearchRegex'), isFalse);

    action('search.action.clearSearchResults').run(services, null);
    expect(session.query.text, isEmpty);
  });

  test('Find in Folder: the folder relative to the root', () {
    layout.view = IdeSideView.explorer;
    search.findInFolder(inRoot('src'));
    expect(search.session.includes.text, './src');
    expect(layout.view, IdeSideView.search);
    search.findInFolder(testRoot);
    expect(search.session.includes.text, isEmpty);
  });

  test('kept with the view state, a change told', () {
    search.session
      ..matchCase = true
      ..includes.text = 'lib';
    expect(kept, isPositive);
    final into = <String, Object?>{};
    search.saveState(into);
    expect(into['search'], {'includes': 'lib', 'matchCase': true});

    search.session.clear();
    search.restoreState({
      'search': {'excludes': 'build', 'wholeWord': true},
    });
    expect(search.session.excludes.text, 'build');
    expect(search.session.wholeWord, isTrue);
    expect(search.session.matchCase, isFalse);
  });
}

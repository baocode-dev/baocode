import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/services/git_changes.dart';
import 'package:baocode/ide/services/scm_service.dart';
import 'package:baocode/ide/workbench/storage.dart';
import 'package:baocode/ide/workbench/views.dart';
import 'package:baocode/l10n/l10n.dart';

import '../../git/fake_git.dart';
import '../fake_files.dart';
import 'fake_host.dart';

void main() {
  late FakeWorkbenchHost host;
  late WorkbenchStorage storage;
  var kept = 0;

  setUp(() {
    host = FakeWorkbenchHost();
    kept = 0;
    storage = WorkbenchStorage(onChanged: () => kept++);
  });

  testWidgets('follows the repository: its changes and branch', (tester) async {
    final git = FakeGit(testRoot)
      ..status =
          '## feature\x00'
          ' M a.txt\x00'
          '?? b.txt\x00';
    final repository = git.repository();
    final workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles({inRoot('a.txt'): 'a', inRoot('b.txt'): 'b'}),
      git: repository,
    );
    final scm = ScmService(host: host, storage: storage);
    addTearDown(() {
      scm.dispose();
      workspace.dispose();
    });
    var changes = 0;
    scm.addListener(() => changes++);
    scm.attach(workspace);
    await tester.runAsync(repository.refresh);
    expect(scm.git, same(repository));
    expect(scm.count, 2);
    expect(scm.branch, 'feature');
    expect(changes, greaterThan(0));

    // Show History: the log, filtered to the file.
    scm.showHistory(inRoot('a.txt'));
    expect(host.shown, IdeSideView.sourceControl);
    expect(repository.graphFilter.paths, [inRoot('a.txt')]);
    // The log left for the editor: the explorer back.
    scm.leaveGitLog();
    expect(host.shown, IdeSideView.explorer);

    scm.detach();
    expect(scm.git, isNull);
  });

  test('keeps the favorite branches and changelists with the window', () {
    final scm = ScmService(host: host, storage: storage);
    addTearDown(scm.dispose);
    final into = <String, Object?>{};
    scm.saveState(into);
    expect(into, isEmpty);
    scm.favoriteBranches.toggle(testRoot, 'refs/heads/main');
    expect(kept, 1);
    scm.saveState(into);
    expect(into.keys, ['gitFavoriteBranches']);

    final other = ScmService(
      host: FakeWorkbenchHost(),
      storage: WorkbenchStorage(),
    );
    addTearDown(other.dispose);
    other.restoreState(into);
    expect(other.favoriteBranches.isEmpty, isFalse);
  });

  testWidgets('the diffs of local changes write into open documents', (
    tester,
  ) async {
    final files = TreeFiles({inRoot('a.txt'): 'a'});
    final workspace = IdeWorkspace(testRoot, files: files);
    addTearDown(workspace.dispose);
    await workspace.open(inRoot('a.txt'));
    final notifications = IdeNotifications();
    final changes = GitChangesService(
      files: files,
      notifications: notifications,
      workspace: workspace,
    );
    await tester.runAsync(() => changes.write(inRoot('a.txt'), 'edited'));
    expect(workspace.documents.single.text, 'edited');
    expect(workspace.documents.single.dirty, isFalse);
    expect(files.contents[inRoot('a.txt')], 'edited');

    // Without the IDE's documents (the side panel's), into the file.
    final panel = GitChangesService(files: files, notifications: notifications);
    await tester.runAsync(() => panel.write(inRoot('b.txt'), 'new'));
    expect(files.contents[inRoot('b.txt')], 'new');

    final git = FakeGit(testRoot)..status = '## main\x00 M a.txt\x00';
    final repository = git.repository();
    await tester.runAsync(repository.refresh);
    final state = repository.state!;
    final opened = <String>[];
    final diffs = changes.localDiffs(
      repository,
      state,
      state.group(IdeGitGroup.workingTree),
      lookupAppLocalizations(const Locale('en')),
      onOpenInEditor: (change) => opened.add(change.path),
    );
    expect(diffs.single.path, inRoot('a.txt'));
    diffs.single.onOpenInEditor!();
    expect(opened, [inRoot('a.txt')]);
  });
}

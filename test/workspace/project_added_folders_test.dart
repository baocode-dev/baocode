// Folders added to a project's own: the project stays as it is (its
// agents start in its folder, its conversations stay), its agents work in
// those folders too, and its IDE and side panel show each as a root.

import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:baocode/workspace/workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'project_workspace_test.dart' show FakeWorkspaceDirectories;

Future<Workspace> _loaded({PreferenceStore? preferences}) async {
  final workspace = Workspace(
    projects: const [Project('site', '/code/site')],
    kernels: [MockKernels.claudeCode],
    preferences: preferences,
    workspaceDirectories: FakeWorkspaceDirectories(),
  );
  addTearDown(workspace.dispose);
  await workspace.load();
  return workspace;
}

void main() {
  test('added and taken out, the project stays a folder\'s, its own '
      'first of its folders', () async {
    final workspace = await _loaded();
    expect(workspace.multiRootAt('/code/site'), isNull);

    workspace
      ..addFolder('/code/site', '/code/api')
      ..addFolder('/code/site', '/code/api')
      // Its own is no folder added to it.
      ..addFolder('/code/site', '/code/site')
      ..addFolder('/code/site', '/code/docs');
    final multi = workspace.multiRootAt('/code/site')!;
    expect(multi.inProject, isTrue);
    expect(multi.name, 'site');
    expect(multi.folders, ['/code/site', '/code/api', '/code/docs']);
    expect(multi.added, ['/code/api', '/code/docs']);
    expect(workspace.workspaceOf(workspace.projectAt('/code/site')), isNull);
    expect(workspace.workspaces, isEmpty);

    workspace
      ..removeFolder('/code/site', '/code/site')
      ..removeFolder('/code/site', '/code/api');
    expect(workspace.multiRootAt('/code/site')!.added, ['/code/docs']);
    workspace.removeFolder('/code/site', '/code/docs');
    expect(workspace.multiRootAt('/code/site'), isNull);
  });

  test('none to a remote project', () async {
    final workspace = await _loaded();
    const remote = 'ssh://box/srv/app';
    expect(workspace.canAddFolders(remote), isFalse);
    workspace.addFolder(remote, '/code/api');
    expect(workspace.multiRootAt(remote), isNull);
  });

  test('kept between runs', () async {
    final preferences = MemoryPreferenceStore();
    final first = await _loaded(preferences: preferences);
    first.addFolder('/code/site', '/code/api');

    final next = await _loaded(preferences: preferences);
    expect(next.multiRootAt('/code/site')!.added, ['/code/api']);
  });

  test('an agent there starts in the project\'s folder, given those added '
      'as they are when it starts, and told of them', () async {
    final workspace = await _loaded();
    final thread = workspace.create(project: workspace.projectAt('/code/site'));
    final context = thread.session.kernelContext;
    expect(context.cwd, '/code/site');
    expect(context.workspace!(), isNull);

    workspace.addFolder('/code/site', '/code/api');
    final given = context.workspace!()!;
    expect(given.folders, ['/code/api']);
    expect(given.instructions, contains('"site"'));
    expect(given.instructions, contains('- api: /code/api'));
    expect(given.instructions, isNot(contains('- site:')));
  });

  test('they go along with the project moved to another folder', () async {
    final workspace = await _loaded();
    workspace.addFolder('/code/site', '/code/api');

    final moved = await workspace.relocateProject(
      workspace.projectAt('/code/site'),
      '/code/site-v2',
    );

    expect(moved, ProjectRelocation.moved);
    expect(workspace.multiRootAt('/code/site'), isNull);
    expect(workspace.multiRootAt('/code/site-v2')!.folders, [
      '/code/site-v2',
      '/code/api',
    ]);
  });

  testWidgets('Edit Project… adds folders to it, its own staying', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pick = WorkspaceDialog.pickDirectory;
    final canPick = WorkspaceDialog.canPickDirectory;
    WorkspaceDialog.pickDirectory = () async => '/code/api';
    WorkspaceDialog.canPickDirectory = () => true;
    addTearDown(() {
      WorkspaceDialog.pickDirectory = pick;
      WorkspaceDialog.canPickDirectory = canPick;
    });
    final workspace = Workspace(
      projects: const [Project('site', '/code/site')],
      kernels: [MockKernels.claudeCode],
    );
    await tester.pumpWidget(BaoCodeApp(workspace: workspace));
    workspace.create(project: workspace.projects.first);
    await tester.pump();

    Future<void> open() async {
      showProjectDialog(
        tester.element(find.byType(Sidebar)),
        workspace: workspace,
        project: workspace.projectAt('/code/site'),
      );
      await tester.pumpAndSettle();
    }

    Finder inDialog(Finder finder) =>
        find.descendant(of: find.byType(ProjectDialog), matching: finder);

    await open();
    // Its own listed, with no × to take it out.
    expect(inDialog(find.text('/code/site')), findsWidgets);
    expect(inDialog(find.byTooltip('Remove site')), findsNothing);
    await tester.tap(inDialog(find.text('Add from Finder…')));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('/code/api')), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(workspace.multiRootAt('/code/site')!.added, ['/code/api']);

    await open();
    await tester.tap(inDialog(find.byTooltip('Remove api')));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(workspace.multiRootAt('/code/site'), isNull);
  });
}

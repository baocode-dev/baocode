// Multi-folder workspaces: made, kept between runs, renamed and deleted;
// and what an agent started in one is given of its folders.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/project_workspace.dart';
import 'package:baocode/workspace/workspace.dart';

/// Workspaces' folders under [root], nothing written.
class FakeWorkspaceDirectories extends ProjectWorkspaceDirectories {
  FakeWorkspaceDirectories([this.root = '/data/workspaces']);

  @override
  final String? root;

  final List<ProjectWorkspace> written = [];

  @override
  void write(ProjectWorkspace workspace) => written.add(workspace);
}

Workspace _workspace({
  PreferenceStore? preferences,
  ProjectWorkspaceDirectories? directories,
}) => Workspace(
  kernels: [MockKernels.claudeCode],
  preferences: preferences,
  workspaceDirectories: directories ?? FakeWorkspaceDirectories(),
);

void main() {
  group('Workspace', () {
    test('makes one in a folder of its own, listed first', () async {
      final directories = FakeWorkspaceDirectories();
      final workspace = _workspace(directories: directories);
      await workspace.load();
      final made = workspace.createWorkspace('  web  ', [
        '/code/site',
        '/code/api',
        '/code/site',
      ])!;
      expect(made.name, 'web');
      expect(made.folders, ['/code/site', '/code/api']);
      expect(made.path, startsWith('/data/workspaces/'));
      expect(directories.written, [made]);
      final project = workspace.sidebarProjects.first;
      expect(project.path, made.path);
      expect(project.name, 'web');
      expect(workspace.workspaceOf(project), made);
      expect(workspace.projectAt(made.path).name, 'web');
    });

    test('none where workspaces cannot be kept', () async {
      final workspace = _workspace(directories: FakeWorkspaceDirectories(null));
      await workspace.load();
      expect(workspace.createWorkspace('web', ['/code/site']), isNull);
    });

    test('is kept between runs, listed though nothing was asked there '
        '(its folder in the data directory as it is then)', () async {
      final store = MemoryPreferenceStore();
      final first = _workspace(preferences: store);
      await first.load();
      final made = first.createWorkspace('web', ['/code/site', '/code/api'])!;
      first.dispose();

      final next = _workspace(
        preferences: store,
        directories: FakeWorkspaceDirectories('/moved/workspaces'),
      );
      await next.load();
      final kept = next.workspaces.single;
      expect(kept.id, made.id);
      expect(kept.name, 'web');
      expect(kept.folders, ['/code/site', '/code/api']);
      expect(kept.path, '/moved/workspaces/${made.id}');
      expect(
        next.sidebarProjects.map((project) => (project.name, project.path)),
        contains(('web', kept.path)),
      );
    });

    test('renamed, its agents are listed under the new name', () async {
      final workspace = _workspace();
      await workspace.load();
      final made = workspace.createWorkspace('web', ['/code/site'])!;
      final thread = workspace.create(project: workspace.projectAt(made.path));
      workspace.updateWorkspace(made, name: 'frontend');
      expect(workspace.workspaceAt(made.path)!.name, 'frontend');
      expect(thread.project.name, 'frontend');
      expect(workspace.sidebarProjects.first.name, 'frontend');
    });

    test('folders are added and taken out', () async {
      final workspace = _workspace();
      await workspace.load();
      final made = workspace.createWorkspace('web', ['/code/site'])!;
      workspace.addWorkspaceFolder(made, '/code/api');
      workspace.addWorkspaceFolder(made, '/code/api');
      expect(workspace.workspaceAt(made.path)!.folders, [
        '/code/site',
        '/code/api',
      ]);
      workspace.removeWorkspaceFolder(made, '/code/site');
      expect(workspace.workspaceAt(made.path)!.folders, ['/code/api']);
    });

    test('deleted, it is forgotten and off the sidebar', () async {
      final store = MemoryPreferenceStore();
      final workspace = _workspace(preferences: store);
      await workspace.load();
      final made = workspace.createWorkspace('web', ['/code/site'])!;
      workspace.deleteWorkspace(made);
      expect(workspace.workspaces, isEmpty);
      expect(
        workspace.sidebarProjects.where((p) => p.path == made.path),
        isEmpty,
      );
      expect(store.preferences['workspaces'], isEmpty);
    });

    test('an agent there is given its folders as they are when it starts, '
        'and what it is told of them', () async {
      final workspace = _workspace();
      await workspace.load();
      final made = workspace.createWorkspace('web', ['/code/site'])!;
      final thread = workspace.create(project: workspace.projectAt(made.path));
      final context = thread.session.kernelContext;
      expect(context.cwd, made.path);
      expect(context.workspace!()!.folders, ['/code/site']);
      workspace.addWorkspaceFolder(made, '/code/api');
      final given = context.workspace!()!;
      expect(given.folders, ['/code/site', '/code/api']);
      expect(given.instructions, contains('"web"'));
      expect(given.instructions, contains('- api: /code/api'));

      final folder = workspace.create(
        project: workspace.projectAt('/code/site'),
      );
      expect(folder.session.kernelContext.workspace!(), isNull);
    });
  });

  group('Claude Code in a workspace', () {
    test('each folder is an --add-dir, their CLAUDE.md read, and the agent '
        'told of them after the chat\'s own prompt', () {
      const launch = ClaudeLaunch(
        cwd: '/data/workspaces/w1',
        directories: ['/code/site', '/code/api'],
        instructions: '<workspace>web</workspace>',
      );
      final arguments = launch.arguments;
      expect(
        [
          for (var i = 0; i < arguments.length - 1; i++)
            if (arguments[i] == '--add-dir') arguments[i + 1],
        ],
        ['/code/site', '/code/api'],
      );
      final prompt = arguments[arguments.indexOf('--append-system-prompt') + 1];
      expect(
        prompt,
        '${ClaudeLaunch.appendedSystemPrompt}\n\n<workspace>web</workspace>',
      );
      expect(launch.settings['env'], {
        'CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD': '1',
      });
      expect(launch.copyWith(cwd: '/remote').directories, [
        '/code/site',
        '/code/api',
      ]);
    });

    test('a folder\'s project has none of them', () {
      const launch = ClaudeLaunch(cwd: '/code/site');
      expect(launch.arguments, isNot(contains('--add-dir')));
      expect(
        launch.arguments[launch.arguments.indexOf('--append-system-prompt') +
            1],
        ClaudeLaunch.appendedSystemPrompt,
      );
      expect(launch.settings.containsKey('env'), isFalse);
    });

    test('the kernel launches with the workspace as it is then', () async {
      final launches = <ClaudeLaunch>[];
      var folders = ['/code/site'];
      final kernel = ClaudeCodeKernel(
        MockKernels.claudeCode,
        KernelContext(
          cwd: '/data/workspaces/w1',
          workspace: () =>
              KernelWorkspace(folders: folders, instructions: 'told'),
        ),
        start: (launch) async {
          launches.add(launch);
          return MockClaudeCodeTransport.start(launch);
        },
      );
      folders = ['/code/site', '/code/api'];
      kernel.prepare();
      await pumpEventQueue();
      expect(launches.single.directories, ['/code/site', '/code/api']);
      expect(launches.single.instructions, 'told');
      kernel.dispose();
    });
  });
}

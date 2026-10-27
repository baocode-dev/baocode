import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/icons/project_icon.dart';
import 'package:baocode/main.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/remote/remote_files.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

import 'workspace_test.dart' show claude;

Future<Workspace> pumpLoaded(
  WidgetTester tester, {
  PreferenceStore? preferences,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final workspace = Workspace(kernels: [claude], preferences: preferences);
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.runAsync(workspace.load);
  await tester.pump();
  return workspace;
}

Finder inSidebar(Finder finder) =>
    find.descendant(of: find.byType(Sidebar), matching: finder);

/// The sidebar lists this machine's projects, or an SSH host's: switched
/// between under its heading once there is a host.
void main() {
  testWidgets('no host: the heading is as it was', (tester) async {
    final workspace = await pumpLoaded(tester);
    expect(workspace.sshHosts, isEmpty);
    expect(inSidebar(find.text('Agents')), findsOneWidget);
    expect(inSidebar(find.text('This Computer')), findsNothing);
  });

  testWidgets('a project is opened from under New Chat, on this machine or '
      'the host listed', (tester) async {
    final workspace = await pumpLoaded(tester);
    double top(String label) =>
        tester.getTopLeft(inSidebar(find.text(label)).first).dy;
    expect(top('Open Project'), greaterThan(top('New Chat')));
    expect(top('Open Project'), lessThan(top('Search')));

    workspace.addSshHost('box');
    workspace.sidebarHost = 'box';
    await tester.pump();
    expect(inSidebar(find.text('Open Project')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a folder opened on a host: the sidebar lists that host, and '
      'this machine once switched back', (tester) async {
    final workspace = await pumpLoaded(tester);
    await workspace.openFolder('ssh://dev/srv/app');
    await tester.pump();
    expect(workspace.sshHosts, ['dev']);
    // Where the agent picked is.
    expect(workspace.sidebarHost, 'dev');
    expect(inSidebar(find.text('Agents')), findsNothing);
    expect(inSidebar(find.text('dev')), findsOneWidget);
    expect(inSidebar(find.text('app')), findsOneWidget);
    expect(inSidebar(find.text('project')), findsNothing);

    workspace.sidebarHost = null;
    await tester.pump();
    expect(inSidebar(find.text('This Computer')), findsOneWidget);
    expect(inSidebar(find.text('project')), findsOneWidget);
    expect(inSidebar(find.text('app')), findsNothing);

    // A new agent is where the sidebar lists.
    expect(workspace.create().project.path, '/tmp/project');
  });

  testWidgets('the menu switches; a host with no project offers a folder '
      'there', (tester) async {
    final workspace = await pumpLoaded(tester);
    workspace.addSshHost('box');
    await tester.pump();
    expect(workspace.sidebarHost, isNull);

    await tester.tap(inSidebar(find.text('This Computer')));
    await tester.pump();
    expect(find.text('box'), findsOneWidget);
    await tester.tap(find.text('box'));
    await tester.pump();
    expect(workspace.sidebarHost, 'box');
    expect(inSidebar(find.text('No projects on box yet.')), findsOneWidget);
  });

  testWidgets("a host's connection edited from its menu, kept between "
      "runs; not one of ~/.ssh/config's", (tester) async {
    final configHosts = defaultRemoteConfigHosts;
    final secrets = SecretStore.instance;
    defaultRemoteConfigHosts = () async => ['dev'];
    SecretStore.instance = MemorySecretStore();
    addTearDown(() {
      defaultRemoteConfigHosts = configHosts;
      SecretStore.instance = secrets;
    });
    final store = MemoryPreferenceStore();
    var workspace = await pumpLoaded(tester, preferences: store);
    workspace.addSshHost('dev');
    workspace.addSshHost('root@box');
    workspace.sidebarHost = 'dev';
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.tap(inSidebar(find.text('dev')));
    await tester.pump();
    expect(find.text('Edit Connection...'), findsNothing);
    await tester.tap(find.text('root@box').last);
    await tester.pump();

    // The heading's.
    await tester.tap(inSidebar(find.text('root@box')).first);
    await tester.pump();
    await tester.tap(find.text('Edit Connection...'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Edit root@box'), findsOneWidget);
    await tester.enterText(find.text('box'), '10.0.0.7');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(workspace.sshServers['root@box']?.address, 'root@10.0.0.7');

    await tester.pumpWidget(const SizedBox());
    workspace = await pumpLoaded(tester, preferences: store);
    expect(workspace.sshServers['root@box']?.hostName, '10.0.0.7');
  });

  testWidgets('All lists every host\'s projects together, and is kept '
      'between runs', (tester) async {
    final store = MemoryPreferenceStore();
    var workspace = await pumpLoaded(tester, preferences: store);
    await workspace.openFolder('ssh://dev/srv/app');
    await tester.pump();
    expect(inSidebar(find.text('project')), findsNothing);

    await tester.tap(inSidebar(find.text('dev')));
    await tester.pump();
    await tester.tap(find.text('All'));
    await tester.pump();
    expect(workspace.sidebarAllHosts, isTrue);
    expect(workspace.sidebarHost, isNull);
    expect(inSidebar(find.text('All')), findsWidgets);
    expect(inSidebar(find.text('project')), findsOneWidget);
    expect(inSidebar(find.text('app · dev')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    workspace = await pumpLoaded(tester, preferences: store);
    expect(workspace.sidebarAllHosts, isTrue);

    // A host picked: that one alone again.
    workspace.sidebarHost = 'dev';
    await tester.pump();
    expect(workspace.sidebarAllHosts, isFalse);
    expect(inSidebar(find.text('project')), findsNothing);
  });

  testWidgets('hosts and the one switched to are kept between runs; a host '
      'removed takes its projects off the sidebar', (tester) async {
    final store = MemoryPreferenceStore();
    var workspace = await pumpLoaded(tester, preferences: store);
    await workspace.openFolder('ssh://dev/srv/app');
    workspace.addSshHost('box');
    workspace.sidebarHost = 'box';
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    workspace = await pumpLoaded(tester, preferences: store);
    expect(workspace.sshHosts, ['dev', 'box']);

    workspace.sidebarHost = 'dev';
    workspace.removeSshHost('dev');
    await tester.pump();
    expect(workspace.sshHosts, ['box']);
    expect(workspace.sidebarHost, isNull);
    final app = workspace.projects.firstWhere((p) => p.host == 'dev');
    expect(workspace.isHidden(app), isTrue);

    // Added again: its projects back.
    workspace.addSshHost('dev');
    expect(workspace.isHidden(app), isFalse);
    expect(workspace.sshHosts, ['box', 'dev']);
  });

  testWidgets('a project taken off a host stays off as the host is '
      'connected to again; and as the host is removed and added back', (
    tester,
  ) async {
    final workspace = await pumpLoaded(tester);
    await workspace.openFolder('ssh://wsl+Ubuntu/home/me/app');
    await workspace.openFolder('ssh://wsl+Ubuntu/home/me/lib');
    final app = workspace.projects.firstWhere((p) => p.name == 'app');
    final lib = workspace.projects.firstWhere((p) => p.name == 'lib');
    workspace.hideProject(app);

    // Another project there opened: connected again.
    workspace.addSshHost('wsl+Ubuntu');
    expect(workspace.isHidden(app), isTrue);

    workspace.removeSshHost('wsl+Ubuntu');
    expect(workspace.isHidden(lib), isTrue);
    workspace.addSshHost('wsl+Ubuntu');
    expect(workspace.isHidden(lib), isFalse);
    expect(workspace.isHidden(app), isTrue);
  });

  testWidgets('a host is renamed in the heading, given an icon; both kept '
      'between runs', (tester) async {
    final store = MemoryPreferenceStore();
    var workspace = await pumpLoaded(tester, preferences: store);
    workspace
      ..addSshHost('dev@localhost:2222')
      ..sidebarHost = 'dev@localhost:2222';
    await tester.pump();

    await tester.tap(inSidebar(find.text('dev@localhost:2222')));
    await tester.pump();
    await tester.tap(find.text('Rename Host'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(inSidebar(find.byType(EditableText)), 'Ubuntu');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(workspace.hostLabel('dev@localhost:2222'), 'Ubuntu');
    expect(inSidebar(find.text('Ubuntu')), findsOneWidget);

    workspace.setIcon(
      workspace.hostIconProject('dev@localhost:2222'),
      const EmojiIcon('🐧'),
    );

    await tester.pumpWidget(const SizedBox());
    workspace = await pumpLoaded(tester, preferences: store);
    expect(workspace.hostLabel('dev@localhost:2222'), 'Ubuntu');
    expect(
      workspace.iconOf(workspace.hostIconProject('dev@localhost:2222')),
      const EmojiIcon('🐧'),
    );

    // Its own name again.
    workspace.renameHost('dev@localhost:2222', '  ');
    expect(workspace.hostLabel('dev@localhost:2222'), 'dev@localhost:2222');
  });

  testWidgets('archived agents are counted where the sidebar lists', (
    tester,
  ) async {
    final workspace = await pumpLoaded(tester);
    final local = workspace.threads.firstWhere(
      (thread) => thread.record != null,
    );
    workspace.setArchived(local, true);
    await workspace.openFolder('ssh://dev/srv/app');
    await tester.pump();
    expect(workspace.sidebarHost, 'dev');
    expect(inSidebar(find.textContaining('Archived')), findsNothing);

    workspace.sidebarHost = null;
    await tester.pump();
    expect(inSidebar(find.textContaining('Archived')), findsOneWidget);
  });
}

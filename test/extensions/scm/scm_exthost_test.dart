// Source control against a real extension host: the built-in Git extension
// runs, its API sees the workspace's repository (as GitLens uses it), and
// its provider is received but not shown; an extension's own source
// control is shown with its groups and resources, a resource's command and
// inline action run, and the input box's text reaches its accept input
// command (goal 五.12).
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:baocode/extensions/host/extension_host_manager.dart';
import 'package:baocode/extensions/menus/menu_service.dart';
import 'package:baocode/extensions/scm/scm_view.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../host/exthost_runtime.dart';

final class _Settings extends ChangeNotifier implements SettingsFile {
  @override
  final Map<String, Object?> values = {};

  @override
  Future<void> write(List<String> path, Object? value) async {}
}

Future<T> _eventually<T>(
  FutureOr<T?> Function() read, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    final value = await read();
    if (value != null) return value;
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Nothing after $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runtime = exthostRuntimeDir();

  test(
    "SCM: the Git extension's API and hidden provider; an extension's "
    'source control shown, its commands and input (五.12)',
    () => _body(runtime!),
    timeout: const Timeout(Duration(minutes: 4)),
    skip: runtime == null ? 'No runtime: set BAOCODE_EXTHOST_DIR' : false,
  );
}

Future<void> _git(String cwd, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: cwd);
  if (result.exitCode != 0) fail('git $args: ${result.stderr}');
}

Future<void> _body(String runtime) async {
  final temp = await Directory.systemTemp.createTemp('exthost-scm');
  addTearDown(() => temp.delete(recursive: true));
  final root = temp.resolveSymbolicLinksSync();
  final project = await Directory(p.join(root, 'proj')).create();
  File(p.join(project.path, 'tracked.txt')).writeAsStringSync('one\n');
  await _git(project.path, ['init', '-q', '-b', 'main']);
  await _git(project.path, ['add', '.']);
  await _git(project.path, [
    '-c',
    'user.name=Bao',
    '-c',
    'user.email=bao@example.com',
    'commit',
    '-q',
    '-m',
    'first',
  ]);
  File(p.join(project.path, 'tracked.txt')).writeAsStringSync('two\n');

  final unsupported = <String>{};
  final parity = ExtHostParity.instance.onUnsupportedCall.listen(
    (call) => unsupported.add(call.name),
  );
  addTearDown(parity.cancel);

  final app = ExtensionsApp(
    userSettings: _Settings(),
    dataDirectory: p.join(root, 'data'),
    loadRuntime: () => ExtHostRuntime.load(runtime),
    coreConfiguration: () async => CoreConfiguration.fromJson(
      (jsonDecode(
        File('assets/exthost/core_configuration.json').readAsStringSync(),
      ) as Map).cast(),
      platform: CoreConfiguration.currentPlatform,
    ),
  );
  addTearDown(app.dispose);
  final extensions = WorkspaceExtensions(app: app, root: project.path);
  final workspace = IdeWorkspace(
    project.path,
    languages: extensions.languages,
    extensionLanguageId: extensions.languageIdFor,
  );
  addTearDown(() {
    extensions.dispose();
    workspace.dispose();
  });
  await extensions.attach(workspace, start: false);
  await extensions.trust!.setWorkspaceTrust(true);
  extensions.host!.developmentLocations = [
    VsUri.file(p.absolute('test/fixtures/extensions/scm-fixture')),
  ];
  await extensions.startHost().timeout(const Duration(seconds: 90));
  expect(
    extensions.host!.manager.state,
    ExtensionHostState.running,
    reason: '${extensions.host!.manager.error}',
  );
  final commands = extensions.commands;
  await _eventually(
    () => commands.hasCommand('scmFixture.state') ? true : null,
  );
  final scm = extensions.scm;

  // The Git extension's API: the repository, its branch and its change.
  final state = await _eventually(() async {
    final state = (await commands.executeCommand('scmFixture.state', []) as Map)
        .cast<String, Object?>();
    final repositories = state['repositories']! as List;
    return repositories.isNotEmpty &&
            ((repositories.first as Map)['changes'] as List).isNotEmpty
        ? state
        : null;
  });
  expect(state['gitState'], 'initialized');
  final repository = ((state['repositories']! as List).single as Map);
  expect(repository['root'], project.path);
  expect(repository['head'], 'main');
  expect(repository['changes'], ['tracked.txt']);

  // Git's provider received, not shown; the fixture's shown.
  final git = await _eventually(
    () => scm.providers.where((p) => p.providerId == 'git').firstOrNull,
  );
  expect(git.shown, isFalse);
  expect(git.rootUri?.fsPath(), project.path);
  final fixture = await _eventually(
    () =>
        scm.shownProviders.where((p) => p.providerId == 'fixture').firstOrNull,
  );
  expect(scm.shownProviders, [fixture]);
  final changes = await _eventually(
    () => fixture.groups
        .where((g) => g.id == 'changes' && g.resources.length == 2)
        .firstOrNull,
  );
  expect(changes.label, 'Fixture Changes');
  expect(fixture.count, 2);
  expect(fixture.input.placeholder, 'Fixture message');
  expect(changes.resources.first.decorations.strikeThrough, isTrue);
  expect(changes.resources.first.decorations.tooltip, 'Changed');

  // A resource's command, its inline action (the resource as the
  // argument), and the input box's text to the accept input command.
  await changes.resources.first.open();
  final ui = ExtensionScmUi(
    service: scm,
    menus: extensions.menus,
    contextKeys: extensions.contextKeys,
    executeCommand: commands.executeCommand,
  );
  final inline = extensions.menus
      .menuItems(
        'scm/resourceState/context',
        ui.resourceContext(changes.resources.last),
        args: [changes.resources.last.toArgument()],
      )
      .single;
  expect(inline.id, 'inline');
  await (inline.actions.single as MenuCommandAction).run();
  fixture.input.setValue('my message', fromView: true);
  await _eventually(() async {
    final state = (await commands.executeCommand('scmFixture.state', []) as Map)
        .cast<String, Object?>();
    return state['input'] == 'my message' ? true : null;
  });
  await ui.run(fixture.acceptInputCommand!);
  final after = (await commands.executeCommand('scmFixture.state', []) as Map)
      .cast<String, Object?>();
  expect(after['opened'], ['one.txt']);
  expect(after['staged'], ['two.txt']);
  expect(after['commits'], ['my message']);
  // The extension cleared its input: so does the view's.
  await _eventually(() => fixture.input.value.isEmpty ? true : null);

  // What the Git extension asked for that is not implemented (printed for
  // the parity record).
  debugPrint('Unsupported calls: ${unsupported.toList()..sort()}');
}

// The Testing API against a real extension host running
// test/fixtures/extensions/testing-fixture: its controller's tests found
// through the resolve handler, a Run of all of them (a pass, a failure with
// its expected and actual values at a location, output), a Debug run with
// the Debug profile, and a run the extension starts itself (goal 五.14).
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
import 'package:baocode/extensions/testing/test_service.dart';
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
    "Testing: a controller's tests, Run and Debug, results with a failure's "
    'location, output, and an extension-started run (五.14)',
    () => _body(runtime!),
    timeout: const Timeout(Duration(minutes: 4)),
    skip: runtime == null ? 'No runtime: set BAOCODE_EXTHOST_DIR' : false,
  );
}

Future<void> _body(String runtime) async {
  final temp = await Directory.systemTemp.createTemp('exthost-testing');
  addTearDown(() => temp.delete(recursive: true));
  final root = temp.resolveSymbolicLinksSync();
  final project = await Directory(p.join(root, 'proj')).create();
  final file = p.join(project.path, 'math.test.js');
  File(file).writeAsStringSync('// tests\n' * 10);

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
    VsUri.file(p.absolute('test/fixtures/extensions/testing-fixture')),
  ];
  await extensions.startHost().timeout(const Duration(seconds: 90));
  expect(
    extensions.host!.manager.state,
    ExtensionHostState.running,
    reason: '${extensions.host!.manager.error}',
  );
  final unsupported = <String>{};
  final parity = ExtHostParity.instance.onUnsupportedCall.listen(
    (call) => unsupported.add(call.name),
  );
  addTearDown(parity.cancel);
  addTearDown(() => debugPrint('Unsupported calls: $unsupported'));
  final testing = extensions.testing!;
  final commands = extensions.commands;

  // The controller, then its tests once the view expands its root.
  final controller = await _eventually(
    () => testing.controller('fixtureTests'),
  );
  expect(controller.label, 'Fixture Tests');
  await _eventually(
    () => testing.profilesOf('fixtureTests').length == 2 ? true : null,
  );
  // The view expands a root as it shows (`TreeProjection.expandElement`).
  await _eventually(() => testing.item('fixtureTests'));
  await testing.expand('fixtureTests', 0);
  final suite = await _eventually(
    () => testing.item('fixtureTests${TestIds.delimiter}suite'),
  );
  expect(testing.childrenOf(suite).map((c) => c.item.label), [
    'adds',
    'subtracts',
  ]);
  final subtracts = testing.childrenOf(suite).last;
  expect(subtracts.item.uri?.fsPath(), file);
  expect(subtracts.item.range?.startLineNumber, 6);

  // Run all: one pass, one failure with its message at its location.
  final run = (await testing.runAll(TestRunGroup.run))!;
  await run.done;
  final addsState = run.getStateById(
    'fixtureTests${TestIds.delimiter}suite${TestIds.delimiter}adds',
  )!;
  final subtractsState = run.getStateById(subtracts.item.extId)!;
  expect(addsState.ownComputedState, TestResultState.passed);
  expect(subtractsState.ownComputedState, TestResultState.failed);
  expect(subtractsState.ownDuration, 12);
  expect(
    run.getStateById(suite.item.extId)!.computedState,
    TestResultState.failed,
  );
  final failure = testing.failures().single.$2;
  expect(failure.message, '2 - 1 should be 1');
  expect(failure.expected, '1');
  expect(failure.actual, '3');
  expect(failure.location?.uri.fsPath(), file);
  expect(failure.location?.range.startLineNumber, 7);
  expect(run.tasks.single.output.toString(), contains('running adds'));
  expect(
    extensions.output.channel(testResultsOutputChannelId)?.text.text,
    contains('running subtracts'),
  );

  // Debug: the Debug profile runs them.
  final debugRun = (await testing.runTests(TestRunGroup.debug, [
    subtracts.item.extId,
  ]))!;
  await debugRun.done;
  final log = (await commands.executeCommand('testingFixture.log', []) as List)
      .cast<String>();
  expect(log, containsAllInOrder(['resolved', 'run:adds', 'run:subtracts']));
  expect(log, contains('debug:subtracts'));
  expect(log, isNot(contains('debug:adds')));

  // A run the extension started: its result too.
  await commands.executeCommand('testingFixture.selfRun', []);
  final self = await _eventually(
    () =>
        testing.results.first.isComplete &&
            testing.results.first.id != debugRun.id
        ? testing.results.first
        : null,
  );
  expect(
    self
        .getStateById(
          'fixtureTests${TestIds.delimiter}suite${TestIds.delimiter}adds',
        )
        ?.ownComputedState,
    TestResultState.skipped,
  );
}

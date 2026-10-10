// Goal sections 9.3/9.4: debug workspace assembly, persistence and trust.

import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:baocode/extensions/host/extension_host_manager.dart';
import 'package:baocode/extensions/files/disk_file_system_provider_io.dart';
import 'package:baocode/extensions/files/file_types.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../debug/support/fake_debug_adapter.dart';
import '../support/main_thread_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String root;
  late ExtensionsApp app;
  late TestSettings settings;
  late WorkspaceExtensions extensions;
  late IdeWorkspace workspace;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workspace-debug-assembly-');
    root = p.join(temp.path, 'project');
    await Directory(p.join(root, '.vscode')).create(recursive: true);
    await File(p.join(root, '.vscode', 'launch.json')).writeAsString(
      jsonEncode({
        'version': '0.2.0',
        'configurations': [
          {'type': 'fake', 'request': 'launch', 'name': 'Initial'},
        ],
      }),
    );
    settings = TestSettings({
      'security.workspace.trust.startupPrompt': 'never',
    });
    app = ExtensionsApp(
      userSettings: settings,
      dataDirectory: p.join(temp.path, 'data'),
      loadRuntime: () async =>
          throw StateError('This test must not start a runtime'),
      coreConfiguration: () async => CoreConfiguration.fromJson(
        (jsonDecode(
          await File('assets/exthost/core_configuration.json').readAsString(),
        ) as Map).cast(),
        platform: CoreConfiguration.currentPlatform,
      ),
    );
    extensions = app.workspace(root);
    workspace = IdeWorkspace(
      root,
      extensionLanguageId: extensions.languageIdFor,
    );
    await extensions.attach(workspace, start: false);
  });

  tearDown(() async {
    extensions.dispose();
    await extensions.debugShutdown;
    workspace.dispose();
    await app.dispose();
    settings.dispose();
    await temp.delete(recursive: true);
  });

  test(
    'debug service loads launch.json without downloading or starting a host',
    () {
      expect(extensions.debug, isNotNull);
      expect(
        extensions.debugHost!.workspaceFolders.single.uri,
        VsUri.file(root),
      );
      expect(
        extensions.debug!.configurationManager
            .getLaunch(VsUri.file(root))!
            .getConfigurationNames(),
        ['Initial'],
      );
      expect(extensions.host!.manager.state, ExtensionHostState.stopped);
      expect(
        extensions.host!.services[extensions.debug.runtimeType],
        same(extensions.debug),
      );
      expect(
        extensions.host!.customers,
        contains(MainContext.mainThreadDebugService.nid),
      );
    },
  );

  test('breakpoints and watches are restored before construction on the next attach', () async {
    final uri = VsUri.file(p.join(root, 'main.js'));
    await extensions.debug!.addBreakpoints(uri, [
      const BreakpointData(lineNumber: 3, condition: 'count > 1'),
    ]);
    extensions.debug!.addWatchExpression('count');
    extensions.dispose();
    await extensions.debugShutdown;
    workspace.dispose();
    extensions = app.workspace(root);
    workspace = IdeWorkspace(root);
    await extensions.attach(workspace, start: false);
    final breakpoint = extensions.debug!.model.getBreakpoints().single;
    expect(breakpoint.uri, uri);
    expect(breakpoint.lineNumber, 3);
    expect(breakpoint.condition, 'count > 1');
    expect(extensions.debug!.model.getWatchExpressions().single.name, 'count');
    expect(extensions.host!.manager.starts, 0);
  });

  test('launch file writes/deletes reload configurations and deleted files lose breakpoints', () async {
    final uri = VsUri.file(p.join(root, 'main.js'));
    await File(uri.fsPath()).writeAsString('const count = 1;');
    await extensions.debug!.addBreakpoints(uri, [
      const BreakpointData(lineNumber: 1),
    ]);
    final launch = VsUri.file(p.join(root, '.vscode', 'launch.json'));
    await extensions.files.writeFile(
      launch,
      utf8.encode(
        jsonEncode({
          'version': '0.2.0',
          'configurations': [
            {'name': 'Updated', 'type': 'fake', 'request': 'launch'},
          ],
        }),
      ),
    );
    await until(
      () => extensions.debug!.configurationManager
          .getLaunch(VsUri.file(root))!
          .getConfigurationNames()
          .contains('Updated'),
    );
    final provider =
        extensions.files.getProvider('file')! as DiskFileSystemProvider;
    final deletedBreakpoint = extensions.debug!.model.onDidChangeBreakpoints(
      (_) {},
    );
    await File(uri.fsPath()).delete();
    provider.fireChanges([FileChange(uri, FileChangeType.deleted)]);
    await until(() => extensions.debug!.model.getBreakpoints().isEmpty);
    deletedBreakpoint.dispose();
    await File(launch.fsPath()).delete();
    provider.fireChanges([FileChange(launch, FileChangeType.deleted)]);
    await until(
      () => extensions.debug!.configurationManager
          .getLaunch(VsUri.file(root))!
          .getConfigurationNames()
          .isEmpty,
    );
  });

  test('headless workspaces remain restricted; only consent enables executable extensions', () async {
    final host = extensions.host!;
    final description = <String, Object?>{
      'identifier': {'value': 'acme.debug'},
      'publisher': 'acme',
      'name': 'debug',
      'main': './extension.js',
    };
    expect(extensions.trust!.isWorkspaceTrusted, isFalse);
    expect(host.trusted, isFalse);
    expect(host.includeExtension!(description), isFalse);
    expect(
      await extensions.debugHost!.requestWorkspaceTrust('Debug this project?'),
      isFalse,
    );
    expect(
      extensions.contextKeys.getContextKeyValue('isWorkspaceTrusted'),
      isFalse,
    );
    await app.trustStore.setUrisTrust([VsUri.file(root)], true);
    expect(host.trusted, isTrue);
    expect(host.includeExtension!(description), isTrue);
    expect(
      extensions.contextKeys.getContextKeyValue('isWorkspaceTrusted'),
      isTrue,
    );
    await app.trustStore.setUrisTrust([VsUri.file(root)], false);
    expect(host.trusted, isFalse);
    expect(host.includeExtension!(description), isFalse);
    final limited = {
      ...description,
      'capabilities': {
        'untrustedWorkspaces': {'supported': 'limited'},
      },
    };
    expect(host.includeExtension!(limited), isTrue);
    expect(host.manager.starts, 0);
  });
}

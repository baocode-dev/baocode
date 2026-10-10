// Goal 9.4: run the bundled js-debug through the real REH and Dart main thread.
@Tags(['exthost'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../host/exthost_runtime.dart';

final class _Settings extends ChangeNotifier implements SettingsFile {
  @override
  final Map<String, Object?> values = {
    'security.workspace.trust.startupPrompt': 'never',
  };

  @override
  Future<void> write(List<String> path, Object? value) async {}
}

Future<T> _eventually<T>(FutureOr<T?> Function() read) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (true) {
    final value = await read();
    if (value != null) return value;
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Debug state did not arrive in 30 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<
  ({WorkspaceExtensions extensions, IdeWorkspace workspace, String source})
>
_startWorkspace(String runtime, String fileName, String program) async {
  final temp = await Directory.systemTemp.createTemp('exthost-debug-');
  final project = await Directory(
    p.join(await temp.resolveSymbolicLinks(), 'project'),
  ).create();
  final source = p.join(project.path, fileName);
  await File(source).writeAsString(program);
  final settings = _Settings();
  final app = ExtensionsApp(
    userSettings: settings,
    dataDirectory: p.join(temp.path, 'data'),
    loadRuntime: () => ExtHostRuntime.load(runtime),
    coreConfiguration: () async => CoreConfiguration.fromJson(
      (jsonDecode(
        await File('assets/exthost/core_configuration.json').readAsString(),
      ) as Map).cast(),
      platform: CoreConfiguration.currentPlatform,
    ),
  );
  await app.load();
  await app.trustStore.setUrisTrust([VsUri.file(project.path)], true);
  final extensions = app.workspace(project.path);
  final workspace = IdeWorkspace(project.path);
  addTearDown(() async {
    await extensions.debug?.stopSession(null);
    extensions.dispose();
    await extensions.debugShutdown;
    workspace.dispose();
    await app.dispose();
    settings.dispose();
    await temp.delete(recursive: true);
  });
  await extensions.attach(workspace, start: false);
  expect(extensions.trust!.isWorkspaceTrusted, isTrue);
  await extensions.startHost().timeout(const Duration(seconds: 90));
  return (extensions: extensions, workspace: workspace, source: source);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runtime = exthostRuntimeDir();
  final node = runtime == null
      ? null
      : p.join(runtime, Platform.isWindows ? 'node.exe' : 'node');

  test(
    'bundled js-debug launches Node, hits a breakpoint and exposes locals (9.4)',
    () async {
      final scenario = await _startWorkspace(
        runtime!,
        'main.js',
        'function add(a, b) {\n'
            '  const sum = a + b;\n'
            '  console.log(sum);\n'
            '  return sum;\n'
            '}\n'
            'add(40, 2);\n',
      );
      final extensions = scenario.extensions;
      final workspace = scenario.workspace;
      final source = scenario.source;
      final project = Directory(p.dirname(source));
      final debug = extensions.debug!;
      expect(
        extensions.host!.extensions.value.any(
          (description) =>
              (description['identifier'] as Map?)?['value'] ==
              'ms-vscode.js-debug',
        ),
        isTrue,
      );
      expect(debug.registry.getDebugger('pwa-node'), isNotNull);
      await debug.addBreakpoints(VsUri.file(source), [
        const BreakpointData(lineNumber: 2),
      ]);
      final launch = debug.configurationManager.getLaunch(
        VsUri.file(project.path),
      );
      final started = await debug
          .startDebugging(launch, {
            'type': 'pwa-node',
            'request': 'launch',
            'name': 'Node launch',
            'program': source,
            'cwd': project.path,
            'runtimeExecutable': node,
            'console': 'internalConsole',
            'autoAttachChildProcesses': false,
          })
          .timeout(const Duration(seconds: 90));
      expect(
        started,
        isTrue,
        reason: '${workspace.notifications.notifications}',
      );

      final frame = await _eventually(() {
        final thread = debug.viewModel.focusedThread;
        return thread?.stopped == true
            ? thread?.getCallStack().firstOrNull
            : null;
      });
      expect(frame.name, contains('add'));
      expect(frame.range.startLineNumber, 2);
      final breakpoint = debug.model.getBreakpoints().single;
      try {
        await _eventually(() => breakpoint.verified ? breakpoint : null);
      } on TimeoutException {
        fail(
          'Breakpoint was not verified: ${breakpoint.message}; '
          'stop=${frame.thread.stoppedDetails?.reason}; '
          'expected=$source; actual=${frame.source.uri}; raw=${frame.source.raw}; '
          'sessions=${[for (final session in debug.model.getSessions()) '${session.name}: ${breakpoint.getDebugProtocolBreakpoint(session.getId())}']}',
        );
      }
      final scopes = await frame.getScopes();
      final valuesByScope = <String, Map<String, String>>{
        for (final scope in scopes.where((scope) => !scope.expensive))
          scope.name: {
            for (final variable in await scope.getChildren())
              variable.name: variable.value,
          },
      };
      expect(
        valuesByScope.values.any(
          (values) => values['a'] == '40' && values['b'] == '2',
        ),
        isTrue,
        reason: 'Available scopes and variables: $valuesByScope',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: runtime == null || node == null || !File(node).existsSync()
        ? 'No REH Node: set BAOCODE_EXTHOST_DIR'
        : false,
  );

  test(
    'bundled js-debug attaches to a running Node process (9.4)',
    () async {
      final scenario = await _startWorkspace(
        runtime!,
        'attach.js',
        'function add(a, b) {\n'
            '  const sum = a + b;\n'
            '  return sum;\n'
            '}\n'
            "process.stdin.on('data', () => add(40, 2));\n",
      );
      final extensions = scenario.extensions;
      final workspace = scenario.workspace;
      final source = scenario.source;
      final project = Directory(p.dirname(source));
      final debug = extensions.debug!;
      await debug.addBreakpoints(VsUri.file(source), [
        const BreakpointData(lineNumber: 2),
      ]);

      final process = await Process.start(node!, [
        '--inspect=127.0.0.1:0',
        source,
      ], workingDirectory: project.path);
      addTearDown(() async {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 10));
      });
      unawaited(process.stdout.drain<void>());
      final inspectorLine = await process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line.contains('Debugger listening on ws://'))
          .timeout(const Duration(seconds: 10));
      final port = int.parse(
        RegExp(r':(\d+)/').firstMatch(inspectorLine)!.group(1)!,
      );
      final launch = debug.configurationManager.getLaunch(
        VsUri.file(project.path),
      );
      final started = await debug
          .startDebugging(launch, {
            'type': 'pwa-node',
            'request': 'attach',
            'name': 'Node attach',
            'address': '127.0.0.1',
            'port': port,
            'localRoot': project.path,
            'remoteRoot': project.path,
            'sourceMaps': false,
          })
          .timeout(const Duration(seconds: 90));
      expect(
        started,
        isTrue,
        reason: '${workspace.notifications.notifications}',
      );

      final breakpoint = debug.model.getBreakpoints().single;
      try {
        await _eventually(
          () => breakpoint.sessionsThatVerified.isNotEmpty ? breakpoint : null,
        );
      } on TimeoutException {
        fail(
          'Attach did not bind the breakpoint; sessions=${[for (final session in debug.model.getSessions()) '${session.name} (${session.state}): ${breakpoint.getDebugProtocolBreakpoint(session.getId())}']}',
        );
      }
      process.stdin.writeln('run');
      await process.stdin.flush();
      final frame = await _eventually(() {
        final thread = debug.viewModel.focusedThread;
        return thread?.stopped == true
            ? thread?.getCallStack().firstOrNull
            : null;
      });
      expect(frame.name, contains('add'));
      expect(frame.range.startLineNumber, 2);
      final scopes = await frame.getScopes();
      final variables = <String, String>{
        for (final scope in scopes.where((scope) => !scope.expensive))
          for (final variable in await scope.getChildren())
            variable.name: variable.value,
      };
      expect(variables['a'], '40');
      expect(variables['b'], '2');
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: runtime == null || node == null || !File(node).existsSync()
        ? 'No REH Node: set BAOCODE_EXTHOST_DIR'
        : false,
  );
}

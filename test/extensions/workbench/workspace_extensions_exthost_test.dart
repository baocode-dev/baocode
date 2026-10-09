// The app's assembly against a real extension host: an IDE workspace's
// TypeScript file gets the built-in TypeScript extension's diagnostics,
// completions and hover (goal section 九.1, in part: the language
// features through the extension host, without the UI).
@Tags(['exthost'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:baocode/extensions/host/extension_host_manager.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
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
  Future<T?> Function() read, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    final value = await read();
    if (value != null) return value;
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Nothing after $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runtime = exthostRuntimeDir();

  test(
    'a TypeScript file gets diagnostics, completions and hovers (九.1)',
    () => _body(runtime!),
    timeout: const Timeout(Duration(minutes: 4)),
    skip: runtime == null ? 'No runtime: set BAOCODE_EXTHOST_DIR' : false,
  );
}

Future<void> _body(String runtime) async {
  final temp = await Directory.systemTemp.createTemp('exthost-ws');
  addTearDown(() => temp.delete(recursive: true));
  final project = await Directory(
    p.join(temp.resolveSymbolicLinksSync(), 'proj'),
  ).create();
  File(p.join(project.path, 'tsconfig.json')).writeAsStringSync('{}');
  final file = p.join(project.path, 'a.ts');
  File(file).writeAsStringSync("const count: number = 'one';\nconsole.lo\n");

  final app = ExtensionsApp(
    userSettings: _Settings(),
    dataDirectory: p.join(temp.path, 'data'),
    loadRuntime: () => ExtHostRuntime.load(runtime),
    coreConfiguration: () async => CoreConfiguration.fromJson(
      (jsonDecode(
        File('assets/exthost/core_configuration.json').readAsStringSync(),
      ) as Map).cast(),
      platform: CoreConfiguration.currentPlatform,
    ),
  );
  addTearDown(app.dispose);
  final extensions = app.workspace(project.path);
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
  // The TypeScript extension does not run in restricted mode
  // (`untrustedWorkspaces.supported: false`): the user trusts the folder
  // at the startup prompt.
  await extensions.trust!.setWorkspaceTrust(true);
  await workspace.open(file);

  // The document is the extension host's, in VS Code's language.
  expect(extensions.documents.contains(file), isTrue);
  expect(extensions.documents[file]!.mirror.languageId, 'typescript');

  await extensions.startHost().timeout(const Duration(seconds: 90));
  expect(
    extensions.host!.manager.state,
    ExtensionHostState.running,
    reason: '${extensions.host!.manager.error}',
  );

  // Diagnostics from tsserver: a string is not a number.
  final diagnostics = await _eventually(() async {
    final found = extensions.languages.diagnosticsFor(file);
    return found.isEmpty ? null : found;
  });
  expect(
    diagnostics.map((d) => d.message).join('\n'),
    contains("not assignable to type 'number'"),
  );

  // Completions after `console.lo`.
  final completions = await _eventually(() async {
    final list = await extensions.languages.completion(
      file,
      const LspPosition(1, 10),
      triggerCharacter: null,
    );
    return list.items.isEmpty ? null : list;
  });
  expect(completions.items.map((i) => i.label), contains('log'));

  // A hover on `count`.
  final hover = await _eventually(
    () => extensions.languages.hover(file, const LspPosition(0, 8)),
  );
  expect(hover.markdown, contains('count'));
}

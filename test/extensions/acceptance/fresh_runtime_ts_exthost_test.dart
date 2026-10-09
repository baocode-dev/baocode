// Acceptance (goal 九.1 and 九.7) on the real runtime and the real
// built-in TypeScript extension, through the app's assembly
// (ExtensionsApp/WorkspaceExtensions over an IdeWorkspace):
//
// 九.7 — a fresh data folder; opening a TypeScript project downloads the
//   runtime from a mirror (BAOCODE_EXTHOST_BASE_URL) that drops the first
//   transfer half-way: the attempt fails leaving nothing half-installed,
//   and triggering it again completes it.
// 九.1 — the download reports its progress (downloading with the bytes,
//   then installing, then ready), and the TypeScript extension gives
//   completions, hovers, definitions, references, rename, diagnostics,
//   formatting, quick fixes, CodeLenses and inlay hints.
// 九.7 — with the mirror gone (offline), a new app on the same data folder
//   runs on the runtime it has; killed, the extension host comes back by
//   itself and answers again.
//
// The archive is the real one dl.baocode.dev serves (manifest SHA-256),
// cached in /tmp/exthost-dl/dist/ after the first run.
@Tags(['exthost'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:baocode/extensions/host/extension_host_manager.dart';
import 'package:baocode/extensions/runtime/extension_runtime_service.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final class _Settings extends ChangeNotifier implements SettingsFile {
  _Settings(this.values);

  @override
  final Map<String, Object?> values;

  @override
  Future<void> write(List<String> path, Object? value) async {}
}

Future<T> _eventually<T>(
  String what,
  Future<T?> Function() read, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    final value = await read();
    if (value != null) return value;
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('No $what after $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

const _source = '''
function add(first: number, second: number): number {
  return first + second;
}
const total = add(1, 2);
const count: number = 'one';
consol.log(total, count);
const  shape={a:1};
console.lo
''';

/// The manifest's archive for this machine, downloaded once.
Future<(ExtHostRuntimeManifest, ExtHostRuntimeAsset, File)> _archive() async {
  final manifest = ExtHostRuntimeManifest.parse(
    File(ExtensionRuntimeService.manifestAsset).readAsStringSync(),
  );
  final asset = manifest[currentExtHostPlatform()!]!;
  final file = File(p.join('/tmp/exthost-dl/dist', asset.file));
  if (!file.existsSync() || file.lengthSync() != asset.size) {
    file.parent.createSync(recursive: true);
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(asset.url)).close();
      expect(response.statusCode, HttpStatus.ok, reason: '${asset.url}');
      await response.pipe(file.openWrite());
    } finally {
      client.close();
    }
  }
  final digest = await crypto.sha256.bind(file.openRead()).first;
  expect('$digest', asset.sha256, reason: 'the cached ${asset.file}');
  return (manifest, asset, file);
}

/// Serves [file] at `/<name>`; the first [drops] transfers stop half-way.
Future<HttpServer> _mirror(File file, String name, {int drops = 0}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final length = file.lengthSync();
  var dropsLeft = drops;
  server.listen((request) async {
    if (request.uri.path != '/$name') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response
      ..contentLength = length
      ..headers.contentType = ContentType.binary;
    if (dropsLeft > 0) {
      dropsLeft--;
      final socket = await request.response.detachSocket();
      final half = file.openRead(0, length ~/ 2);
      await socket.addStream(half);
      socket.destroy();
      return;
    }
    await request.response.addStream(file.openRead());
    await request.response.close();
  });
  return server;
}

ExtensionRuntimeService _runtimeService(
  ExtHostRuntimeManifest manifest,
  String directory,
  String baseUrl,
) => ExtensionRuntimeService(
  loadManifest: () async =>
      File(ExtensionRuntimeService.manifestAsset).readAsStringSync(),
  directory: directory,
  installer: (manifest, directory) => ExtHostRuntimeInstaller(
    manifest: manifest,
    directory: directory,
    environment: {ExtHostRuntimeInstaller.baseUrlVariable: baseUrl},
    attempts: 1,
  ),
);

ExtensionsApp _app(String data, ExtensionRuntimeService runtime) =>
    ExtensionsApp(
      userSettings: _Settings({
        'typescript.referencesCodeLens.enabled': true,
        'typescript.referencesCodeLens.showOnAllFunctions': true,
        'typescript.inlayHints.parameterNames.enabled': 'all',
      }),
      runtime: runtime,
      dataDirectory: data,
      coreConfiguration: () async => CoreConfiguration.fromJson(
        (jsonDecode(
          File('assets/exthost/core_configuration.json').readAsStringSync(),
        ) as Map).cast(),
        platform: CoreConfiguration.currentPlatform,
      ),
    );

/// The extension host process the server under [data] runs.
Future<int?> _extensionHostPid(String data) async {
  final ps = await Process.run('ps', ['-A', '-o', 'pid=,ppid=,command=']);
  final rows = [
    for (final line in LineSplitter.split('${ps.stdout}'))
      if (RegExp(r'^\s*(\d+)\s+(\d+)\s+(.*)$').firstMatch(line) case final m?)
        (pid: int.parse(m[1]!), ppid: int.parse(m[2]!), command: m[3]!),
  ];
  final servers = {
    for (final row in rows)
      if (row.command.contains('server-main.js') &&
          row.command.contains(p.join(data, 'exthost-data')))
        row.pid,
  };
  for (final row in rows) {
    if (servers.contains(row.ppid) &&
        row.command.contains('--type=extensionHost')) {
      return row.pid;
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The binding answers every HttpClient request with a 400: this test
  // downloads for real.
  HttpOverrides.global = null;

  test(
    '九.1/九.7: fresh data folder download with retry, TypeScript features, '
    'offline start and crash recovery',
    _body,
    timeout: const Timeout(Duration(minutes: 12)),
    skip: currentExtHostPlatform() == null ? 'No runtime build here' : false,
  );
}

Future<void> _body() async {
  final (manifest, asset, archive) = await _archive();
  final temp = Directory(
    (await Directory.systemTemp.createTemp('exthost-accept'))
        .resolveSymbolicLinksSync(),
  );
  addTearDown(() => temp.delete(recursive: true));
  final data = p.join(temp.path, 'data');
  final runtimeDir = p.join(data, 'exthost');
  final project = Directory(p.join(temp.path, 'proj'))..createSync();
  File(p.join(project.path, 'tsconfig.json')).writeAsStringSync('{}');
  final file = p.join(project.path, 'a.ts');
  File(file).writeAsStringSync(_source);

  // --- 九.7: an interrupted download, then a complete one -----------------
  final mirror = await _mirror(archive, asset.file, drops: 1);
  final baseUrl = 'http://127.0.0.1:${mirror.port}';
  final runtime = _runtimeService(manifest, runtimeDir, baseUrl);
  final states = <ExtensionRuntimeState>[];
  runtime.addListener(() => states.add(runtime.state));
  var app = _app(data, runtime);
  var extensions = app.workspace(project.path);
  var workspace = IdeWorkspace(
    project.path,
    languages: extensions.languages,
    extensionLanguageId: extensions.languageIdFor,
  );
  // Opening the project starts the host, which needs the runtime. The
  // TypeScript extension does not run in restricted mode
  // (`untrustedWorkspaces.supported: false`): the user trusts the folder
  // at the startup prompt.
  await extensions.attach(workspace);
  await extensions.trust!.setWorkspaceTrust(true);
  await workspace.open(file);
  final failed = await _eventually(
    'the failed download',
    () async => runtime.state is ExtensionRuntimeFailed ? runtime.state : null,
  ) as ExtensionRuntimeFailed;
  expect(failed.transient, isTrue, reason: '${failed.error}');
  // Nothing half-downloaded or half-unpacked is left.
  expect(
    Directory(runtimeDir).listSync().map((e) => p.basename(e.path)),
    isEmpty,
  );
  final firstStates = states.length;

  // Triggered again (the status bar's retry runs ensureReady; starting the
  // host asks for it the same way).
  await extensions.startHost().timeout(const Duration(minutes: 3));
  expect(
    runtime.state,
    isA<ExtensionRuntimeReady>(),
    reason: switch (runtime.state) {
      ExtensionRuntimeFailed(:final error) => '$error',
      final state => '$state',
    },
  );
  final progress = states.skip(firstStates).toList();
  final downloading = progress.whereType<ExtensionRuntimeDownloading>();
  expect(downloading.map((s) => s.total).toSet(), {asset.size});
  expect(
    downloading.where((s) => s.received > 0 && s.received < asset.size),
    isNotEmpty,
    reason: 'progress in between',
  );
  expect(progress.whereType<ExtensionRuntimeInstalling>(), isNotEmpty);
  expect(Directory(runtimeDir).listSync().map((e) => p.basename(e.path)), [
    manifest.id,
  ]);
  expect(
    extensions.host!.manager.state,
    ExtensionHostState.running,
    reason: '${extensions.host!.manager.error}',
  );
  // Diagnostics prove the extension host works on the fresh install.
  await _eventually('diagnostics after the download', () async {
    final found = extensions.languages.diagnosticsFor(file);
    return found.isEmpty ? null : found;
  });
  extensions.dispose();
  workspace.dispose();
  await app.dispose();
  await mirror.close(force: true);

  // --- 九.7: offline; 九.1: the TypeScript features -------------------------
  final offline = _runtimeService(manifest, runtimeDir, baseUrl);
  app = _app(data, offline);
  addTearDown(app.dispose);
  extensions = app.workspace(project.path);
  workspace = IdeWorkspace(
    project.path,
    languages: extensions.languages,
    extensionLanguageId: extensions.languageIdFor,
  );
  addTearDown(() {
    extensions.dispose();
    workspace.dispose();
  });
  await extensions.attach(workspace, start: false);
  await workspace.open(file);
  await extensions.startHost().timeout(const Duration(minutes: 2));
  expect(offline.state, isA<ExtensionRuntimeReady>());
  expect(extensions.host!.manager.state, ExtensionHostState.running);
  await _typeScriptFeatures(extensions, file);

  // --- 九.7: the extension host killed comes back -------------------------
  final manager = extensions.host!.manager;
  final pid = await _extensionHostPid(data);
  expect(pid, isNotNull, reason: 'no extension host process found');
  final starts = manager.starts;
  expect(Process.killPid(pid!, ProcessSignal.sigkill), isTrue);
  await _eventually(
    'the restarted host',
    () async =>
        manager.starts > starts && manager.state == ExtensionHostState.running
        ? true
        : null,
  );
  expect(await _extensionHostPid(data), isNot(pid));
  final hover = await _eventually(
    'hover after the restart',
    () => extensions.languages.hover(file, const LspPosition(3, 7)),
  );
  expect(hover.markdown, contains('total'));
}

Future<void> _typeScriptFeatures(
  WorkspaceExtensions extensions,
  String file,
) async {
  final languages = extensions.languageRoot.language;

  // Diagnostics: a type error and a misspelt name.
  final diagnostics = await _eventually('diagnostics', () async {
    final found = languages.diagnosticsFor(file);
    return found.length >= 2 ? found : null;
  });
  final messages = diagnostics.map((d) => d.message).join('\n');
  expect(messages, contains("not assignable to type 'number'"));
  expect(messages, contains("Cannot find name 'consol'"));

  // Completion after `console.lo`.
  final completions = await _eventually('completions', () async {
    final list = await languages.completion(file, const LspPosition(7, 10));
    return list.items.isEmpty ? null : list;
  });
  expect(completions.items.map((i) => i.label), contains('log'));

  // Hover on `total`.
  final hover = await _eventually(
    'hover',
    () => languages.hover(file, const LspPosition(3, 7)),
  );
  expect(hover.markdown, contains('const total: number'));

  // Definition of `add` at its call: the function's line.
  final definition = await _eventually('definition', () async {
    final found = await languages.definition(file, const LspPosition(3, 15));
    return found.isEmpty ? null : found;
  });
  expect(definition.first.range.start.line, 0);

  // References of `add`: the declaration and the call.
  final references = await languages.references(file, const LspPosition(0, 10));
  expect(references.map((r) => r.range.start.line).toSet(), {0, 3});

  // Rename `add` to `sum`: both places.
  final rename = await languages.rename(file, const LspPosition(0, 10), 'sum');
  final renameEdits = rename!.changes.values.expand((e) => e).toList();
  expect(renameEdits, hasLength(2));
  expect(renameEdits.map((e) => e.newText).toSet(), {'sum'});

  // Formatting the document fixes `const  shape={a:1};`.
  final format = await languages.format(file, tabSize: 2, insertSpaces: true);
  expect(format, isNotEmpty);

  // A quick fix for the misspelling.
  final misspelt = diagnostics.firstWhere(
    (d) => d.message.contains("'consol'"),
  );
  final actions = await languages.codeActions(
    file,
    misspelt.range,
    diagnostics: [misspelt],
  );
  expect(
    actions.map((a) => a.title),
    contains(contains("Change spelling to 'console'")),
  );

  // CodeLens: references of `add`, resolved.
  final lenses = await _eventually('CodeLenses', () async {
    final found = await languages.codeLenses(file);
    return found.isEmpty ? null : found;
  });
  final resolved = await languages.resolveCodeLens(file, lenses.first);
  expect(resolved.command?.title, contains('reference'));

  // Inlay hints: the parameter names at `add(1, 2)`.
  final hints = await _eventually('inlay hints', () async {
    final found = await languages.inlayHints(file, Range(1, 1, 9, 1));
    return found.isEmpty ? null : found;
  });
  expect(
    hints.expand((h) => h.label).map((part) => part.label).join(),
    contains('first:'),
  );

  // Language status: the TypeScript version item for the document
  // (`createLanguageStatusItem`); JSON's is not the TypeScript file's.
  final statuses = await _eventually('language status', () async {
    final found = extensions.languageStatus.forDocument(
      VsUri.file(file),
      extensions.languageIdFor(file),
    );
    return found.isEmpty ? null : found;
  });
  expect(statuses.map((s) => s.id), [
    'vscode.typescript-language-features/typescript.version',
  ]);
  expect(statuses.single.label, isNotEmpty);
  expect(
    extensions.languageStatus.forDocument(
      VsUri.file('/elsewhere/notes.txt'),
      'plaintext',
    ),
    isEmpty,
  );
}

/// Helpers for running [fake_lsp_server.dart] under an [LspManager].
library;

import 'dart:async';
import 'dart:io';

import 'package:monad/ide/lsp/lsp_protocol.dart';
import 'package:monad/ide/lsp/lsp_server_definition.dart';
import 'package:path/path.dart' as p;

/// The fake server's source, run by `dart` directly (it starts in a
/// fraction of a second).
final String fakeServerScript = p.absolute(
  'test',
  'fixtures',
  'lsp',
  'fake_lsp_server.dart',
);

/// An absolute `dart`, so starting does not depend on the child's PATH.
final String dartExecutable = () {
  if (Platform.environment['FLUTTER_ROOT'] case final root?) {
    final dart = p.join(root, 'bin', 'cache', 'dart-sdk', 'bin', 'dart');
    if (File(dart).existsSync()) return dart;
  }
  final which = Process.runSync('which', ['dart']);
  final found = '${which.stdout}'.trim();
  return found.isEmpty ? 'dart' : found;
}();

LspServerDefinition fakeServer(
  String id, {
  JsonMap options = const {},
  JsonMap? settings,
  List<String> rootMarkers = const [],
  bool requiredRoot = false,
  Set<LspFeature>? onlyFeatures,
  Set<LspFeature>? exceptFeatures,
  String? masonPackage,
}) => LspServerDefinition(
  id: id,
  command: 'dart',
  args: [fakeServerScript],
  initializationOptions: {'name': id, ...options},
  settings: settings,
  rootMarkers: rootMarkers,
  requiredRoot: requiredRoot,
  onlyFeatures: onlyFeatures,
  exceptFeatures: exceptFeatures,
  masonPackage: masonPackage,
);

/// Files ending in `.fake` are the `fake` language, served by [servers].
class FakeCatalog implements LspCatalog {
  FakeCatalog(
    List<LspServerDefinition> definitions, {
    List<String>? servers,
    this.rootMarkers = const [],
  }) : definitions = {for (final d in definitions) d.id: d},
       servers = servers ?? [for (final d in definitions) d.id];

  final Map<String, LspServerDefinition> definitions;
  final List<String> servers;
  final List<String> rootMarkers;

  @override
  LspLanguage? languageFor(String path, {String? firstLine}) =>
      path.endsWith('.fake')
      ? LspLanguage(
          id: 'fake',
          fileTypes: const ['fake'],
          servers: servers,
          rootMarkers: rootMarkers,
        )
      : null;

  @override
  LspServerDefinition? server(String id) => definitions[id];
}

/// Finds `dart` for every server, unless it is [missing] (until installed).
class FakeProvider implements LspServerProvider {
  FakeProvider({Set<String>? missing, this.missingRuntime, this.failInstall})
    : missing = missing ?? {};

  final Set<String> missing;
  final String? missingRuntime;
  final String? failInstall;
  final installs = <String>[];
  Completer<void>? installGate;

  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async =>
      missing.contains(server.id)
      ? LspServerMissing(
          package: server.masonPackage,
          missingRuntime: missingRuntime,
        )
      : LspServerFound(dartExecutable);

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) async {
    installs.add(package);
    onProgress?.call('Downloading $package');
    if (installGate case final gate?) await gate.future;
    if (failInstall case final message?) {
      throw LspInstallException(message, detail: 'exit 1');
    }
    onProgress?.call('Installed $package');
    missing.removeWhere((id) => id == package || '$id-pkg' == package);
  }
}

/// Waits until [condition] holds, polling.
Future<void> until(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(reason ?? 'condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Whether process [pid] still runs (a zombie counts as gone).
bool processRunning(int pid) {
  final result = Process.runSync('ps', ['-o', 'stat=', '-p', '$pid']);
  final stat = '${result.stdout}'.trim();
  return result.exitCode == 0 && stat.isNotEmpty && !stat.startsWith('Z');
}

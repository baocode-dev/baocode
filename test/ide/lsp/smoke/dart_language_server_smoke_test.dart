// Reports what the real server answered, for a person to read.
// ignore_for_file: avoid_print
@Tags(['lsp-smoke'])
@TestOn('mac-os || linux')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_manager.dart';
import 'package:baocode/ide/lsp/lsp_process.dart';
import 'package:baocode/ide/lsp/lsp_process_io.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';
import 'package:baocode/platform/child_process_registry.dart';
import 'package:path/path.dart' as p;

import '../../../fixtures/lsp/fake_lsp.dart';

class _DartCatalog implements LspCatalog {
  static const _server = LspServerDefinition(
    id: 'dart',
    command: 'dart',
    args: ['language-server', '--protocol=lsp'],
    rootMarkers: ['pubspec.yaml'],
  );

  @override
  LspLanguage? languageFor(String path, {String? firstLine}) =>
      path.endsWith('.dart')
      ? const LspLanguage(id: 'dart', fileTypes: ['dart'], servers: ['dart'])
      : null;

  @override
  LspServerDefinition? server(String id) => id == 'dart' ? _server : null;
}

class _PathProvider implements LspServerProvider {
  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async =>
      LspServerFound(dartExecutable);

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) => throw const LspInstallException('Not installable');
}

/// The local `dart language-server` through the manager and workspace, as
/// the IDE runs it (the login shell's environment included).
void main() {
  test('dart language-server answers through the manager', () async {
    final root = Directory.systemTemp
        .createTempSync('baocode-lsp-smoke')
        .resolveSymbolicLinksSync();
    addTearDown(() => Directory(root).deleteSync(recursive: true));
    LspProcesses.registry = ChildProcessRegistry(
      file: File(p.join(root, '.lsp-processes.json')),
    );
    File(p.join(root, 'pubspec.yaml'))
        .writeAsStringSync('name: smoke\nenvironment:\n  sdk: ^3.0.0\n');
    final path = p.join(root, 'lib', 'main.dart');
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        'void main() {\n'
        "  final greeting = 'hi';\n"
        '  print(greeting);\n'
        "  int wrong = 'text';\n"
        '}\n'
        'class   Spaced{}\n',
      );

    final lsp = LspManager(root, _DartCatalog(), _PathProvider());
    final workspace = IdeWorkspace(
      root,
      files: IdeFileService(root),
      languages: lsp,
    );
    addTearDown(() async {
      workspace.dispose();
      await lsp.shutdown();
      await stopLspProcesses();
    });
    final watch = Stopwatch()..start();
    await workspace.open(path);
    await until(
      () => lsp.statusFor(path).single.state == LanguageServerState.running,
      timeout: const Duration(seconds: 60),
      reason: 'dart language-server running',
    );
    print('running after ${watch.elapsedMilliseconds}ms');

    await until(
      () => lsp.diagnosticsFor(path).any((d) => d.range.start.line == 3),
      timeout: const Duration(seconds: 60),
      reason: 'the type error diagnosed',
    );
    for (final d in lsp.diagnosticsFor(path)) {
      print('diagnostic ${d.range} ${d.severity.name} ${d.code}: ${d.message}');
    }

    final hover = await lsp.hover(path, const LspPosition(2, 3));
    print('hover print: ${hover?.markdown.split('\n').take(3).join(' | ')}');
    expect(hover?.markdown, contains('print'));

    final definition = await lsp.definition(path, const LspPosition(2, 10));
    print('definition greeting: ${definition.map((l) => l.revealRange)}');
    expect(definition.single.revealRange.start, const LspPosition(1, 8));

    final completion = await lsp.completion(path, const LspPosition(2, 4));
    print('completion: ${completion.items.length} items');
    expect(completion.items, isNotEmpty);

    final prepared = await lsp.prepareRename(path, const LspPosition(1, 9));
    final rename = await lsp.rename(path, const LspPosition(1, 9), 'hello');
    print(
      'rename ${prepared?.placeholder}: ${rename?.changes.values.first.length} edits',
    );
    expect(prepared?.placeholder, 'greeting');
    expect(rename?.changes.values.single, hasLength(2));

    final symbols = await lsp.documentSymbols(path);
    print('symbols: ${symbols.map((s) => s.name)}');
    expect(symbols.map((s) => s.name), containsAll(['main', 'Spaced']));

    // Edits sync incrementally: fixing the error clears its diagnostic.
    final doc = workspace.active!;
    workspace.edit(path, doc.text.replaceFirst("'text'", '1'));
    await until(
      () =>
          !lsp.diagnosticsFor(path).any((d) => d.code == 'invalid_assignment'),
      timeout: const Duration(seconds: 30),
      reason: 'the fixed error cleared',
    );
    final format = await lsp.format(path, tabSize: 2, insertSpaces: true);
    print('format: ${format.length} edits');
    expect(format, isNotEmpty);
    print(
      'statuses: ${lsp.statusFor(path).map((s) => '${s.serverId} ${s.state.name} ${s.progress ?? ''}')}',
    );
    print('log tail: ${lsp.logFor('dart').reversed.take(3).toList()}');
  });
}

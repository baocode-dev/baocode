// 九.8: BaoCode's own LSP client is gone, the extensions serve languages.
// What docs/extension-host-goal.md's 七 lists is not in the repository, and
// nothing imports or reads it. The `Lsp`-prefixed types of
// lib/ide/language/language_types.dart stay (the editor's contracts, LSP's
// shapes), as 七 allows.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the LSP client, its installers, packs and assets are removed', () {
    for (final path in const [
      'lib/ide/lsp',
      'lib/ide/extensions',
      'assets/lsp',
      'packs',
      'tool/generate_lsp_languages.mjs',
      'tool/generate_mason_registry.mjs',
      'lib/remote/remote_lsp.dart',
      'packages/bao_remote/lib/lsp.dart',
      'packages/bao_remote/lib/lsp_install.dart',
      'packages/bao_remote/lib/src/lsp',
    ]) {
      expect(
        FileSystemEntity.typeSync(path),
        FileSystemEntityType.notFound,
        reason: path,
      );
    }
  });

  test('no code imports or reads what was removed', () {
    final removed = RegExp(
      r'ide/lsp/|remote_lsp|bao_remote/lsp|lsp_install|server_lsp|'
      r'lsp_client|lsp_manager|lsp_process|json_rpc\.dart|mason|'
      r"lsp\.json|assets/lsp|'packs/",
      caseSensitive: false,
    );
    final hits = <String>[];
    for (final root in const ['lib', 'packages', 'tool', 'macos', 'windows']) {
      for (final file in Directory(root).listSync(recursive: true)) {
        if (file is! File) continue;
        final path = file.path;
        if (!RegExp(r'\.(dart|mjs|js|swift|cpp|h|iss|yaml)$').hasMatch(path) ||
            path.contains('/build/') ||
            path.contains('/.dart_tool/')) {
          continue;
        }
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (removed.hasMatch(lines[i])) hits.add('$path:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('assets/lsp')));
  });
}

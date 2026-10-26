import 'dart:io';

import 'package:baocode/ide/lsp/catalog/bundled_lsp_catalog.dart';
import 'package:baocode/ide/lsp/catalog/standard_lsp.dart';
import 'package:baocode/ide/lsp/lsp_manager.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';
import 'package:baocode/ide/lsp/packs/language_packs.dart';
import 'package:baocode/ide/lsp/packs/lsp_settings_template.dart';
import 'package:baocode/ide/lsp/packs/lsp_user_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The `lsp.json` Open Language Server Settings makes: nothing changed by
/// it as it is, and its example, taken out of its comments, a language
/// server of the user's own for Rust (#304).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late String path;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lsp_settings_template');
    path = p.join(temp.path, 'User', LspUserSettings.fileName);
  });

  tearDown(() => temp.delete(recursive: true));

  Future<BundledLspCatalog> catalog() async {
    final catalog = BundledLspCatalog(overlays: [LspUserSettings(path)]);
    await catalog.load();
    return catalog;
  }

  test('made where there is none, it changes nothing', () async {
    await ensureLspSettingsFile(path);
    expect(File(path).readAsStringSync(), lspSettingsTemplate);
    final lsp = await catalog();
    expect(lsp.problems, isEmpty);
    expect(lsp.languageFor('src/main.rs')?.servers, ['rust-analyzer']);
  });

  test('one there already is left as it is', () async {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"servers": {}}');
    await ensureLspSettingsFile(path);
    expect(File(path).readAsStringSync(), '{"servers": {}}');
  });

  test('its example, uncommented, serves Rust with rust-glancer', () async {
    final example = lspSettingsTemplate
        .split('\n')
        .skipWhile((line) => line.trim() != '//')
        .skip(1)
        .map((line) => line.replaceFirst('// ', ''))
        .join('\n');
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{\n$example');
    final lsp = await catalog();
    expect(lsp.problems, isEmpty);
    expect(lsp.languageFor('src/main.rs')?.servers, ['rust-glancer']);
    final server = lsp.server('rust-glancer')!;
    expect(server.command, 'rust-glancer');
    expect(server.args, ['lsp']);
  });

  test('the open files are matched to servers again as lsp.json changes, '
      'till the project closes', () async {
    final catalog = _Counting();
    final manager = LspManager(temp.path, catalog, const _NoServers());
    final changes = ValueNotifier(0);
    StandardLsp(
      catalog: BundledLspCatalog(),
      provider: const _NoServers(),
      packs: LanguagePackRegistry.instance,
      changes: changes,
    ).follow(manager);
    manager.openDocument(p.join(temp.path, 'a.rs'), 'fn main() {}');
    expect(catalog.asked, 1);

    changes.value++;
    expect(catalog.asked, 2);

    await manager.shutdown();
    changes.value++;
    expect(catalog.asked, 2);
    expect(changes.hasListeners, isFalse);
  });
}

class _Counting implements LspCatalog {
  var asked = 0;

  @override
  LspLanguage? languageFor(String path, {String? firstLine}) {
    asked++;
    return null;
  }

  @override
  LspServerDefinition? server(String id) => null;
}

class _NoServers implements LspServerProvider {
  const _NoServers();

  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async =>
      const LspServerMissing();

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) async {}
}

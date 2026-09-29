import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/flutter/document_snapshot.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_document_model.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_surface_controller.dart';
import 'package:monad/ide/editor/monaco/flutter/language_assets.dart';
import 'package:monad/ide/editor/monaco/flutter/language_configuration_assets.dart';
import 'package:monad/ide/editor/monaco/flutter/monaco_syntax.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/languages/language_configuration.dart';
import 'package:monad/ide/lsp/catalog/bundled_lsp_catalog.dart';
import 'package:monad/ide/lsp/packs/language_packs.dart';
import 'package:monad/ide/lsp/packs/lsp_user_settings.dart';
import 'package:path/path.dart' as p;

final packsDirectory = p.absolute('test/fixtures/lsp/packs');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LanguagePackRegistry packs;
  late MonacoLanguageAssets assets;

  setUp(() {
    packs = LanguagePackRegistry(packsDirectory);
    assets = MonacoLanguageAssets(packs: packs);
  });

  test('reads packs and reports what is wrong with them', () async {
    final all = await packs.packs();
    expect(all.map((pack) => pack.name), ['Broken', 'ini-override', 'Toy']);
    final toy = all.last.languages.single;
    expect(toy.extensions, ['.toy', '.toyish']);
    expect(toy.filenames, ['Toyfile']);
    expect(toy.grammarPath, p.join(packsDirectory, 'toy', 'grammar.json'));
    expect(
      toy.configurationPath,
      p.join(packsDirectory, 'toy', 'configuration.json'),
    );
    expect(all.last.servers.single.id, 'toy-ls');
    final problems = packs.problems.map((problem) => '$problem').join('\n');
    expect(problems, contains('languages[0]: needs an "id"'));
    expect(problems, contains('languages[1].extensions: expected strings'));
    expect(problems, contains('languages[1].firstLine'));
    expect(problems, contains('no-manifest'));
    expect(LanguagePackRegistry.instance.directory, isNull);
    expect(await LanguagePackRegistry.instance.packs(), isEmpty);
  });

  test('pack languages register first and resolve by path', () async {
    final registrations = await assets.registrations();
    expect(registrations.first.id, 'better-ini');
    expect(registrations[1].id, 'toy');
    expect(registrations[1].assetId, 'pack:Toy/toy');
    expect(registrations, hasLength(89 + 2));
    expect((await assets.forPath('src/main.toy'))?.id, 'toy');
    expect((await assets.forPath('src/main.TOYISH'))?.id, 'toy');
    expect((await assets.forPath('project/Toyfile'))?.id, 'toy');
    expect(
      (await assets.forPath('run', firstLine: '#!/usr/bin/env toy'))?.id,
      'toy',
    );
    // A pack wins an extension a bundled language also claims.
    expect((await assets.forPath('settings.ini'))?.id, 'better-ini');
    // Bundled languages resolve as before.
    expect((await assets.forPath('lib/main.dart'))?.id, 'dart');
    expect(
      (await const MonacoLanguageAssets().forPath('settings.ini'))?.id,
      'ini',
    );
    expect((await assets.loadLanguage('dart')).id, 'dart');
    expect((await assets.loadLanguage('c')).id, 'c');
  });

  test('a pack grammar highlights through the syntax service', () async {
    final syntax = MonacoSyntaxService(assets: assets);
    final document = DocumentSnapshot(';; greeting\nlet name = "toy" 42\nfn\n');
    final lines = (await syntax.tokenizeFile(document, 'a/hello.toy'))!;
    List<String> types(int line) => [
      for (final token in lines[line].tokens) token.type,
    ];
    expect(types(0), ['comment.toy']);
    expect(types(1), containsAllInOrder(['keyword.toy', 'white.toy']));
    expect(types(1), contains('identifier.toy'));
    expect(types(1), contains('string.toy'));
    expect(types(1), contains('number.toy'));
    expect(types(2), ['keyword.toy']);
  });

  test('code fences name languages by id or alias, in any case', () async {
    expect(await assets.languageIdForName('ts'), 'typescript');
    expect(await assets.languageIdForName('Dart'), 'dart');
    expect(await assets.languageIdForName('toy'), 'toy');
    expect(await assets.languageIdForName('no-such-language'), isNull);
  });

  test('code in hovers is tokenized in the editor\'s theme', () async {
    const keyword = Color(0xFF569CD6);
    final syntax = MonacoSyntaxService(assets: assets);
    final lines = await syntax.colorize(
      'dart',
      'final x = 1;\nfinal y = 2;',
      (type) =>
          type.startsWith('keyword') ? const TextStyle(color: keyword) : null,
    );
    expect(lines, hasLength(2));
    expect(lines![1].first.text, 'final');
    expect(lines[1].first.style?.color, keyword);
    expect(lines[1].map((span) => span.text).join(), 'final y = 2;');
    expect(await syntax.colorize('nothing', 'x', (_) => null), isNull);
  });

  test('a pack configuration drives comment toggling', () async {
    final configuration = (await languageConfigurationForPath(
      'a/hello.toy',
      assets: assets,
    ))!;
    expect(configuration.comments?.lineComment?.comment, ';;');
    expect(configuration.comments?.blockComment, ('#|', '|#'));
    expect(configuration.wordPattern!.isCaseSensitive, isFalse);
    expect(configuration.onEnterRules!.first.action.appendText, ';; ');
    expect(
      configuration.onEnterRules!.last.action.indentAction,
      IndentAction.indentOutdent,
    );
    expect(configuration.autoClosingPairs!.last.notIn, ['string']);
    expect(configuration.folding!.markers, isNotNull);

    final document = EditorDocumentModel('let a = 1\nlet b = 2');
    final controller = EditorSurfaceController(document: document)
      ..languageConfiguration = configuration
      ..setSelections([const TextSelection(baseOffset: 0, extentOffset: 12)]);
    addTearDown(() {
      controller.dispose();
      document.dispose();
    });
    expect(controller.toggleLineComment(), isTrue);
    expect(document.snapshot.text, ';; let a = 1\n;; let b = 2');
    expect(controller.toggleLineComment(), isTrue);
    expect(document.snapshot.text, 'let a = 1\nlet b = 2');

    // No configuration file: the grammar alone still loads.
    expect(await languageConfigurationForPath('a.ini', assets: assets), isNull);
  });

  group('catalog layers', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('lsp_packs_test');
    });

    tearDown(() => temp.delete(recursive: true));

    Future<BundledLspCatalog> catalog(String? settings) async {
      final path = p.join(temp.path, LspUserSettings.fileName);
      if (settings != null) await File(path).writeAsString(settings);
      final catalog = BundledLspCatalog(
        overlays: [
          packs.catalogOverlay,
          LspUserSettings.inDirectory(temp.path),
        ],
      );
      await catalog.load();
      return catalog;
    }

    test('packs add languages and servers over the bundled ones', () async {
      final lsp = await catalog(null);
      final toy = lsp.languageFor('src/main.toy')!;
      expect(toy.id, 'toy');
      expect(toy.servers, ['toy-ls']);
      expect(toy.rootMarkers, ['toy.project']);
      expect(lsp.languageFor('x', firstLine: '#!/usr/bin/toy')?.id, 'toy');
      final server = lsp.server('toy-ls')!;
      expect(server.args, ['--stdio']);
      expect(server.settings, {
        'toy': {'strict': true},
      });
      // A pack language with a bundled id keeps the bundled servers.
      expect(lsp.languageFor('a.ini')?.id, 'better-ini');
      expect(lsp.languageFor('lib/main.dart')?.servers, ['dart']);
      final problems = lsp.problems.map((problem) => '$problem').join('\n');
      expect(problems, contains('needs an "id"'));
    });

    test('user settings override packs and bundled entries', () async {
      final lsp = await catalog('''
{
  "servers": {
    "toy-ls": {"command": "/opt/toy/bin/toy-ls", "args": []},
    "dart": {"environment": {"DART_VM_OPTIONS": "--old_gen_heap_size=4096"}}
  },
  "languages": {
    "toy": {"servers": ["toy-ls", "dart"]},
    "dart": {"fileTypes": ["dart", "dt"]}
  }
}''');
      expect(lsp.problems.where((p) => p.source.endsWith('lsp.json')), isEmpty);
      expect(lsp.server('toy-ls')!.command, '/opt/toy/bin/toy-ls');
      expect(lsp.server('toy-ls')!.args, isEmpty);
      expect(lsp.server('dart')!.environment, {
        'DART_VM_OPTIONS': '--old_gen_heap_size=4096',
      });
      expect(lsp.server('dart')!.command, 'dart');
      expect(lsp.languageFor('a.toy')!.servers, ['toy-ls', 'dart']);
      expect(lsp.languageFor('a.dt')?.id, 'dart');
    });

    test('an invalid settings file is reported, not fatal', () async {
      final lsp = await catalog('{ "servers": ');
      expect(
        lsp.problems.map((p) => '$p'),
        contains(startsWith('${p.join(temp.path, 'lsp.json')}: invalid JSON')),
      );
      expect(lsp.languageFor('a.toy')?.servers, ['toy-ls']);
      expect(lsp.languageFor('a.rs')?.servers, ['rust-analyzer']);
    });
  });

  test('a broken pack grammar fails to load with a clear error', () async {
    final temp = await Directory.systemTemp.createTemp('lsp_pack_broken');
    addTearDown(() => temp.delete(recursive: true));
    final pack = Directory(p.join(temp.path, 'bad'))..createSync();
    File(p.join(pack.path, 'manifest.json')).writeAsStringSync(
      '{"languages": [{"id": "bad", "extensions": [".bad"]}]}',
    );
    File(p.join(pack.path, 'grammar.json')).writeAsStringSync('{"x": 1}');
    final broken = MonacoLanguageAssets(packs: LanguagePackRegistry(temp.path));
    await expectLater(
      broken.forPath('a.bad'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('"tokenizer"'),
        ),
      ),
    );
  });
}

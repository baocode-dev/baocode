import 'dart:convert';
import 'dart:io';

import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/extensions/gallery/extension_management_backend.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/import/extension_import.dart';
import 'package:baocode/extensions/import/external_extensions.dart';
import 'package:baocode/extensions/import/proprietary_extensions.dart';
import 'package:baocode/extensions/import/settings_import.dart';
import 'package:baocode/extensions/vsix/target_platform.dart';
import 'package:baocode/keybindings/vscode_import.dart';
import 'package:baocode/settings/jsonc.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../gallery/fixture_http.dart';
import '../ui/fake_backend.dart';
import '../vsix/zip_writer.dart';

Map<String, Object> _extension(
  String id,
  String version, {
  Map<String, Object?> configuration = const {},
  Map<String, Object?> extra = const {},
}) {
  final dot = id.indexOf('.');
  return {
    'package.json': {
      'name': id.substring(dot + 1),
      'publisher': id.substring(0, dot),
      'version': version,
      'displayName': id.substring(dot + 1),
      'engines': {'vscode': '^1.80.0'},
      'main': './extension.js',
      'contributes': {
        'configuration': {'properties': configuration},
      },
      ...extra,
    },
    'extension.js': 'exports.activate = () => {};',
  };
}

void main() {
  late Directory home;
  late VsCodeInstalls installs;
  late String vscode;
  late String cursor;

  setUp(() {
    home = Directory.systemTemp.createTempSync('import-home');
    installs = VsCodeInstalls(
      home: home.path,
      environment: {'HOME': home.path},
      platform: KeybindingPlatform.mac,
    );
    vscode = installs.extensionsDir(VsCodeProduct.code);
    cursor = installs.extensionsDir(VsCodeProduct.cursor);

    // VS Code: extensions.json lists them.
    writeFolder(
      '$vscode/esbenp.prettier-vscode-11.0.0',
      _extension(
        'esbenp.prettier-vscode',
        '11.0.0',
        configuration: {
          'prettier.singleQuote': {'type': 'boolean'},
          'prettier.tabWidth': {'type': 'number'},
        },
      ),
    );
    writeFolder(
      '$vscode/ms-python.vscode-pylance-2024.1.1',
      _extension('ms-python.vscode-pylance', '2024.1.1'),
    );
    writeFolder(
      '$vscode/acme.private-1.0.0',
      _extension(
        'acme.private',
        '1.0.0',
        configuration: {
          'acme.private.flag': {'type': 'boolean'},
        },
      ),
    );
    // On disk, not listed: uninstalled.
    writeFolder('$vscode/acme.gone-1.0.0', _extension('acme.gone', '1.0.0'));
    File('$vscode/extensions.json').writeAsStringSync(
      jsonEncode([
        {
          'identifier': {'id': 'esbenp.prettier-vscode'},
          'version': '11.0.0',
          'location': {
            '\$mid': 1,
            'path': '$vscode/esbenp.prettier-vscode-11.0.0',
            'scheme': 'file',
          },
          'relativeLocation': 'esbenp.prettier-vscode-11.0.0',
          'metadata': {'source': 'gallery', 'targetPlatform': 'undefined'},
        },
        {
          'identifier': {'id': 'ms-python.vscode-pylance'},
          'version': '2024.1.1',
          'location': {
            'path': '$vscode/ms-python.vscode-pylance-2024.1.1',
            'scheme': 'file',
          },
        },
        {
          'identifier': {'id': 'acme.private'},
          'version': '1.0.0',
          'relativeLocation': 'acme.private-1.0.0',
          'metadata': {'source': 'vsix'},
        },
      ]),
    );

    // Cursor: no extensions.json; an older prettier, its own extension,
    // and an updated one waiting to be deleted.
    writeFolder(
      '$cursor/esbenp.prettier-vscode-10.0.0',
      _extension('esbenp.prettier-vscode', '10.0.0'),
    );
    writeFolder(
      '$cursor/anysphere.cursorpyright-1.0.0',
      _extension('anysphere.cursorpyright', '1.0.0'),
    );
    writeFolder(
      '$cursor/esbenp.prettier-vscode-13.0.0',
      _extension('esbenp.prettier-vscode', '13.0.0'),
    );
    File('$cursor/.obsolete')
        .writeAsStringSync(jsonEncode({'esbenp.prettier-vscode-13.0.0': true}));

    // Settings.
    final codeUser = installs.userDir(VsCodeProduct.code);
    Directory(codeUser).createSync(recursive: true);
    File('$codeUser/settings.json').writeAsStringSync('''
{
  // Mine
  "editor.fontSize": 14,
  "prettier.singleQuote": true,
  "[javascript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "prettier.tabWidth": 4,
  },
  "acme.private.flag": true,
  "python.analysis.typeCheckingMode": "strict",
}
''');
    final cursorUser = installs.userDir(VsCodeProduct.cursor);
    Directory(cursorUser).createSync(recursive: true);
    File('$cursorUser/settings.json').writeAsStringSync(
      '{"prettier.singleQuote": false, "prettier.tabWidth": 8}',
    );
  });

  tearDown(() => home.deleteSync(recursive: true));

  group('scanning', () {
    test('editors with extensions', () async {
      final products = await ExternalExtensionScanner(installs)
          .detectProducts();
      expect(products, {VsCodeProduct.code: 3, VsCodeProduct.cursor: 2});
    });

    test(
      'the highest version of each, skipping obsolete and unlisted ones',
      () async {
        final found = await ExternalExtensionScanner(installs).scan();
        final byId = {for (final e in found) e.id: e};
        expect(
          byId.keys,
          unorderedEquals([
            'esbenp.prettier-vscode',
            'ms-python.vscode-pylance',
            'acme.private',
            'anysphere.cursorpyright',
          ]),
        );
        final prettier = byId['esbenp.prettier-vscode']!;
        expect(prettier.version, '11.0.0');
        expect(prettier.products, [VsCodeProduct.code, VsCodeProduct.cursor]);
        expect(prettier.manifest.configurationKeys, {
          'prettier.singleQuote',
          'prettier.tabWidth',
        });
        expect(byId['acme.private']!.fromGallery, isFalse);
      },
    );
  });

  group('rules', () {
    test('proprietary extensions and their alternatives', () {
      expect(proprietaryRuleFor('ms-python.vscode-pylance')!.alternatives, [
        'detachhead.basedpyright',
      ]);
      expect(
        proprietaryRuleFor('ms-vscode.cpptools-extension-pack')!.alternatives,
        contains('llvm-vs-code-extensions.vscode-clangd'),
      );
      expect(
        proprietaryRuleFor('MS-DotNetTools.csdevkit')!.reason,
        ProprietaryReason.license,
      );
      expect(
        proprietaryRuleFor('ms-vscode-remote.remote-ssh')!.reason,
        ProprietaryReason.remoteDevelopment,
      );
      expect(proprietaryRuleFor('github.copilot-chat')!.alternatives, isEmpty);
      expect(proprietaryRuleFor('ms-python.python'), isNull);
      expect(isSkippedExtension('anysphere.cursorpyright'), isTrue);
      expect(isSkippedExtension('esbenp.prettier-vscode'), isFalse);
    });
  });

  group('settings', () {
    test(
      "collects the extensions' settings, the first editor's winning",
      () async {
        final settings = await collectExtensionSettings(
          installs,
          [VsCodeProduct.code, VsCodeProduct.cursor],
          {
            'esbenp.prettier-vscode': {
              'prettier.singleQuote',
              'prettier.tabWidth',
            },
          },
        );
        expect(
          [for (final s in settings.settings) '${s.label}=${s.value}'],
          [
            'prettier.singleQuote=true',
            '[javascript] prettier.tabWidth=4',
            'prettier.tabWidth=8',
          ],
        );
        expect(settings.settings.last.product, VsCodeProduct.cursor);
      },
    );

    test("merges without replacing ours, keeping our file's comments", () {
      const ours = '''
{
\t// Ours
\t"prettier.singleQuote": false
}''';
      final result = mergeSettings(ours, const [
        ImportedSetting(
          key: 'prettier.singleQuote',
          value: true,
          extensionId: 'esbenp.prettier-vscode',
          product: VsCodeProduct.code,
        ),
        ImportedSetting(
          key: 'prettier.tabWidth',
          value: 4,
          extensionId: 'esbenp.prettier-vscode',
          product: VsCodeProduct.code,
          languageOverride: '[javascript]',
        ),
        ImportedSetting(
          key: 'prettier.semi',
          value: false,
          extensionId: 'esbenp.prettier-vscode',
          product: VsCodeProduct.code,
          languageOverride: '[javascript]',
        ),
      ]);
      expect(result.kept.single.key, 'prettier.singleQuote');
      expect(result.added, hasLength(2));
      expect(result.text, contains('// Ours'));
      expect(parseJsonc(result.text), {
        'prettier.singleQuote': false,
        '[javascript]': {'prettier.tabWidth': 4, 'prettier.semi': false},
      });
      expect(() => mergeSettings('{ "a": ', const []), throwsFormatException);
    });
  });

  group('plan and run', () {
    late FixtureHttp http;
    late OpenVsxClient client;
    late Directory cache;
    late List<int> prettierVsix;

    setUp(() {
      cache = Directory.systemTemp.createTempSync('import-cache');
      http = FixtureHttp();
      for (final path in [
        '/api/ms-python/vscode-pylance/darwin-arm64/latest',
        '/api/ms-python/vscode-pylance/universal/latest',
        '/api/acme/private/darwin-arm64/latest',
        '/api/acme/private/universal/latest',
        '/api/acme/private',
        '/api/detachhead/basedpyright/darwin-arm64/latest',
      ]) {
        http.add(path, utf8.encode('{"error": "Not found"}'), status: 404);
      }
      http.addJson('/api/detachhead/basedpyright/universal/latest', {
        'namespace': 'detachhead',
        'name': 'basedpyright',
        'version': '1.30.0',
        'targetPlatform': 'universal',
        'engines': {'vscode': '^1.80.0'},
        'files': {'download': 'https://open-vsx.org/basedpyright-1.30.0.vsix'},
      });
      prettierVsix = buildVsix(_extension('esbenp.prettier-vscode', '12.4.0'));
      http
        ..add(
          '/api/esbenp/prettier-vscode/12.4.0/file/esbenp.prettier-vscode-12.4.0.vsix',
          prettierVsix,
        )
        ..add(
          '/api/esbenp/prettier-vscode/12.4.0/file/esbenp.prettier-vscode-12.4.0.sha256',
          utf8.encode(crypto.sha256.convert(prettierVsix).toString()),
        )
        ..add(
          '/basedpyright-1.30.0.vsix',
          buildVsix(_extension('detachhead.basedpyright', '1.30.0')),
        );
      client = OpenVsxClient(
        http: http,
        cacheDir: cache.path,
        targetPlatform: ExtensionTargetPlatform.darwinArm64,
      );
    });
    tearDown(() => cache.deleteSync(recursive: true));

    Future<ImportPlan> plan({List<InstalledExtension> installed = const []}) =>
        ExtensionImportPlanner(installs: installs, gallery: client).plan([
          VsCodeProduct.code,
          VsCodeProduct.cursor,
        ], installed: installed);

    test('classifies each extension', () async {
      final result = await plan();
      final byId = {for (final item in result.items) item.id: item};
      final prettier = byId['esbenp.prettier-vscode']!;
      expect(prettier.action, ImportAction.reinstall);
      expect(prettier.gallery!.version, '12.4.0');
      expect(prettier.selectedByDefault, isTrue);

      final pylance = byId['ms-python.vscode-pylance']!;
      expect(pylance.action, ImportAction.proprietary);
      expect(pylance.rule!.reason, ProprietaryReason.license);
      expect(pylance.alternatives.single.id, 'detachhead.basedpyright');
      expect(pylance.alternatives.single.available, isTrue);
      expect(pylance.selectable, isTrue);
      expect(pylance.selectedByDefault, isFalse);

      final private = byId['acme.private']!;
      expect(private.action, ImportAction.copyLocal);
      expect(private.galleryProblem, ImportGalleryProblem.notFound);
      expect(private.requiresConsent, isTrue);
      expect(private.selectedByDefault, isFalse);
      expect(private.capability, isNotNull);

      final cursorOwn = byId['anysphere.cursorpyright']!;
      expect(cursorOwn.action, ImportAction.skip);
      expect(cursorOwn.skipReason, ImportSkipReason.editorSpecific);

      expect(result.defaultSelection, {'esbenp.prettier-vscode'});
      expect(result.settings.settings, isNotEmpty);
    });

    test('skips what is installed already', () async {
      final result = await plan(
        installed: [
          InstalledExtension(
            manifest: fakeManifest('esbenp.prettier-vscode', version: '12.4.0'),
            location: '/x',
          ),
        ],
      );
      final prettier = result.items.firstWhere(
        (item) => item.id == 'esbenp.prettier-vscode',
      );
      expect(prettier.action, ImportAction.skip);
      expect(prettier.skipReason, ImportSkipReason.alreadyInstalled);
    });

    test('installs, copies with consent and imports their settings', () async {
      final result = await plan();
      final backend = FakeBackend();
      final settingsPath = p.join(
        home.path,
        'baocode',
        'User',
        'settings.json',
      );
      Directory(p.dirname(settingsPath)).createSync(recursive: true);
      File(settingsPath).writeAsStringSync('{\n  "prettier.tabWidth": 2\n}');
      final report = await ExtensionImporter(backend: backend, gallery: client)
          .run(
            result,
            selected: {
              ...result.defaultSelection,
              'ms-python.vscode-pylance',
              'acme.private',
            },
            consented: {'acme.private'},
            settingsPath: settingsPath,
          );
      expect(
        backend.installed.map((e) => e.id),
        unorderedEquals([
          'esbenp.prettier-vscode',
          'detachhead.basedpyright',
          'acme.private',
        ]),
      );
      expect(report.count(ImportOutcome.installed), 1);
      expect(
        report
            .withOutcome(ImportOutcome.alternativeInstalled)
            .single
            .alternativeId,
        'detachhead.basedpyright',
      );
      expect(report.count(ImportOutcome.copied), 1);
      expect(report.count(ImportOutcome.notImported), 1);
      expect(report.count(ImportOutcome.failed), 0);
      expect(
        backend.calls,
        contains('installFromFolder $vscode/acme.private-1.0.0'),
      );
      // Pylance's settings are not imported: it was not.
      expect(parseJsonc(File(settingsPath).readAsStringSync()), {
        'prettier.tabWidth': 2,
        'prettier.singleQuote': true,
        '[javascript]': {'prettier.tabWidth': 4},
        'acme.private.flag': true,
      });
      expect(report.settingsKept.single.key, 'prettier.tabWidth');
    });

    test('a copy without consent is not made; failures are reported', () async {
      final result = await plan();
      final backend = FakeBackend()..failNextInstall = StateError('disk full');
      final report = await ExtensionImporter(
        backend: backend,
        gallery: client,
      ).run(result, selected: {'esbenp.prettier-vscode', 'acme.private'});
      expect(backend.installed, isEmpty);
      final failed = report.withOutcome(ImportOutcome.failed).single;
      expect(failed.id, 'esbenp.prettier-vscode');
      expect(failed.error, contains('disk full'));
      expect(
        report.entries.firstWhere((e) => e.id == 'acme.private').outcome,
        ImportOutcome.notImported,
      );
    });
  });
}

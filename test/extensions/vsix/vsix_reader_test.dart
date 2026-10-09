import 'dart:convert';
import 'dart:io';

import 'package:baocode/extensions/vsix/engine_version.dart';
import 'package:baocode/extensions/vsix/extension_manifest.dart';
import 'package:baocode/extensions/vsix/semver.dart';
import 'package:baocode/extensions/vsix/target_platform.dart';
import 'package:baocode/extensions/vsix/vsix_reader.dart';
import 'package:baocode/extensions/vsix/zip_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine_version_cases.dart';
import 'zip_writer.dart';

final _icon = List.generate(300, (i) => i % 256);

Map<String, Object> _extensionFiles({
  String engine = '^1.90.0',
  Object? extra,
}) => {
  'package.json': {
    'name': 'tool',
    'publisher': 'acme',
    'version': '1.2.3',
    'displayName': '%displayName%',
    'description': '%description%',
    'engines': {'vscode': engine},
    'main': './out/extension.js',
    'icon': 'images/icon.png',
    'license': 'MIT',
    'repository': {'type': 'git', 'url': 'https://example.test/tool.git'},
    'extensionKind': ['workspace'],
    'categories': ['Programming Languages'],
    'activationEvents': ['onLanguage:tool'],
    'enabledApiProposals': ['terminalDataWriteEvent@2', 'fileSearchProvider'],
    'extensionDependencies': ['acme.base'],
    'contributes': {
      'commands': [
        {'command': 'tool.run', 'title': '%command.run%'},
        {'command': 'tool.stop', 'title': 'Stop'},
      ],
      'languages': [
        {'id': 'tool'},
      ],
      'grammars': [
        {'scopeName': 'source.tool', 'language': 'tool'},
      ],
      'configuration': [
        {
          'title': 'Tool',
          'properties': {
            'tool.path': {'type': 'string'},
          },
        },
        {
          'properties': {
            'tool.trace': {'type': 'boolean'},
          },
        },
      ],
      'views': {
        'explorer': [
          {'id': 'tool.tree', 'name': 'Tool Tree'},
        ],
      },
    },
    ...?extra as Map<String, Object?>?,
  },
  'package.nls.json': {
    'displayName': 'Tool',
    'description': 'Does things',
    'command.run': 'Run Tool',
  },
  'package.nls.zh-cn.json': {
    'displayName': '工具',
    'command.run': {'message': '运行工具', 'comment': []},
  },
  'images/icon.png': _icon,
  'out/extension.js': 'exports.activate = () => {};',
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vsix-reader'));
  tearDown(() => dir.deleteSync(recursive: true));

  String writeVsix(
    Map<String, Object> files, {
    String? manifest,
    bool deflate = true,
  }) {
    final path = '${dir.path}/tool.vsix';
    File(path).writeAsBytesSync(
      buildVsix(files, vsixManifest: manifest, deflate: deflate),
    );
    return path;
  }

  group('VSIX', () {
    for (final deflate in [true, false]) {
      test('reads the manifest (${deflate ? 'deflated' : 'stored'})', () async {
        final path = writeVsix(
          _extensionFiles(),
          manifest: vsixManifestXml(
            publisher: 'acme',
            id: 'tool',
            version: '1.2.3',
            targetPlatform: 'darwin-arm64',
            preRelease: true,
          ),
          deflate: deflate,
        );
        final manifest = await readVsixManifest(path);
        expect(manifest.id, 'acme.tool');
        expect(manifest.key, 'acme.tool');
        expect(manifest.version, '1.2.3');
        expect(manifest.displayName, 'Tool');
        expect(manifest.description, 'Does things');
        expect(manifest.engine, '^1.90.0');
        expect(manifest.engineCompatible, isTrue);
        expect(manifest.targetPlatform, ExtensionTargetPlatform.darwinArm64);
        expect(manifest.preRelease, isTrue);
        expect(manifest.main, './out/extension.js');
        expect(manifest.extensionKind, ['workspace']);
        expect(manifest.enabledApiProposals, [
          'terminalDataWriteEvent',
          'fileSearchProvider',
        ]);
        expect(manifest.extensionDependencies, ['acme.base']);
        expect(manifest.iconBytes, _icon);
        expect(manifest.license, 'MIT');
        expect(manifest.repository, 'https://example.test/tool.git');
        expect(manifest.configurationKeys, {'tool.path', 'tool.trace'});
        expect(manifest.contributions.count('commands'), 2);
        expect(manifest.contributions['commands']!.items, ['Run Tool', 'Stop']);
        expect(manifest.contributions['languages']!.items, ['tool']);
        expect(manifest.contributions['views']!.items, ['Tool Tree']);
        expect(manifest.installFolderName, 'acme.tool-1.2.3-darwin-arm64');
      });
    }

    test('localized for a locale with a fallback', () async {
      final path = writeVsix(_extensionFiles());
      final manifest = await readVsixManifest(path, locale: 'zh-CN');
      expect(manifest.displayName, '工具');
      // Not in the locale's file: the default one's.
      expect(manifest.description, 'Does things');
      expect(manifest.contributions['commands']!.items.first, '运行工具');
      expect(manifest.targetPlatform, ExtensionTargetPlatform.undefined);
      expect(manifest.preRelease, isFalse);
      expect(manifest.installFolderName, 'acme.tool-1.2.3');
    });

    test('an engine newer than ours is incompatible', () async {
      final path = writeVsix(_extensionFiles(engine: '^1.200.0'));
      final manifest = await readVsixManifest(path);
      expect(manifest.engineCompatible, isFalse);
      expect(manifest.engineNotices.single.kind, EngineNoticeKind.mismatch);
      expect(manifest.engineNotices.single.message, contains('1.135.0'));
    });

    test('a declarative extension is not engine checked', () async {
      final path = writeVsix({
        'package.json': {
          'name': 'theme',
          'publisher': 'acme',
          'version': '1.0.0',
          'engines': {'vscode': '^9.0.0'},
          'contributes': {
            'themes': [
              {'label': 'Night', 'path': './night.json'},
            ],
          },
        },
      });
      final manifest = await readVsixManifest(path);
      expect(manifest.hasCode, isFalse);
      expect(manifest.engineCompatible, isTrue);
      expect(manifest.contributions['themes']!.items, ['Night']);
    });

    test('reads single entries without extracting', () async {
      final path = writeVsix(_extensionFiles());
      final package = await ExtensionPackage.openVsix(path);
      addTearDown(package.close);
      expect(
        utf8.decode((await package.files.read('out/extension.js'))!),
        contains('activate'),
      );
      expect(await package.files.read('missing.js'), isNull);
      expect(
        await package.files.read('out/extension.js', maxBytes: 7),
        utf8.encode('exports'),
      );
      final listed = await package.files.list();
      expect(
        listed.map((file) => file.path),
        containsAll(['package.json', 'out/extension.js', 'images/icon.png']),
      );
      expect(
        listed.every((file) => !file.path.startsWith('extension/')),
        isTrue,
      );
    });

    test('not a ZIP', () async {
      final path = '${dir.path}/broken.vsix';
      File(path).writeAsStringSync('not a zip at all');
      await expectLater(
        readVsixManifest(path),
        throwsA(
          isA<ExtensionPackageException>().having(
            (e) => e.error,
            'error',
            ExtensionPackageError.notArchive,
          ),
        ),
      );
    });

    test('a ZIP without a manifest', () async {
      final path = '${dir.path}/empty.vsix';
      File(path).writeAsBytesSync(buildZip({'readme.md': utf8.encode('hi')}));
      await expectLater(
        readVsixManifest(path),
        throwsA(
          isA<ExtensionPackageException>().having(
            (e) => e.error,
            'error',
            ExtensionPackageError.noManifest,
          ),
        ),
      );
    });

    test('a manifest that is not an extension', () async {
      final path = writeVsix({
        'package.json': {'name': 'lib'},
      });
      await expectLater(
        readVsixManifest(path),
        throwsA(
          isA<ExtensionPackageException>().having(
            (e) => e.error,
            'error',
            ExtensionPackageError.invalidManifest,
          ),
        ),
      );
    });
  });

  group('folders', () {
    test('an installed extension with its metadata', () async {
      final folder = '${dir.path}/acme.tool-1.2.3';
      writeFolder(folder, {
        ..._extensionFiles(
          extra: {
            '__metadata': {
              'targetPlatform': 'linux-x64',
              'isPreReleaseVersion': true,
            },
          },
        ),
      });
      final manifest = await readExtensionFolderManifest(folder);
      expect(manifest.id, 'acme.tool');
      expect(manifest.displayName, 'Tool');
      expect(manifest.targetPlatform, ExtensionTargetPlatform.linuxX64);
      expect(manifest.preRelease, isTrue);
      expect(manifest.iconBytes, _icon);
      expect(await isExtensionFolder(folder), isTrue);
      expect(await isExtensionFolder(dir.path), isFalse);
    });

    test('its .vsixmanifest wins', () async {
      final folder = '${dir.path}/acme.tool';
      writeFolder(folder, {
        ..._extensionFiles(),
        '.vsixmanifest': vsixManifestXml(
          publisher: 'acme',
          id: 'tool',
          version: '1.2.3',
          targetPlatform: 'win32-x64',
        ),
      });
      final package = await ExtensionPackage.open(folder);
      expect(package.isVsix, isFalse);
      expect(package.manifest.targetPlatform, ExtensionTargetPlatform.win32X64);
    });

    test('files outside the folder are not read', () async {
      final folder = '${dir.path}/inner';
      writeFolder(folder, _extensionFiles());
      File('${dir.path}/secret.txt').writeAsStringSync('x');
      final package = await ExtensionPackage.openFolder(folder);
      expect(await package.files.read('../secret.txt'), isNull);
    });
  });

  group('vsixmanifest', () {
    test('identity, properties and text', () {
      final manifest = VsixManifest.parse(
        vsixManifestXml(
          publisher: 'acme',
          id: 'tool',
          version: '2.0.0',
          targetPlatform: 'alpine-x64',
          preRelease: true,
        ),
      );
      expect(manifest.publisher, 'acme');
      expect(manifest.id, 'tool');
      expect(manifest.version, '2.0.0');
      expect(manifest.targetPlatform, ExtensionTargetPlatform.alpineX64);
      expect(manifest.preRelease, isTrue);
      expect(manifest.displayName, 'Tool & More');
      expect(
        manifest.properties['Microsoft.VisualStudio.Code.Engine'],
        '^1.80.0',
      );
    });
  });

  group('ZipReader', () {
    test('the central directory, from bytes', () async {
      final zip = await ZipReader.fromBytes(
        buildZip({'a/b.txt': utf8.encode('hello'), 'c.txt': utf8.encode('')}),
      );
      expect(zip.entries.map((e) => e.name), ['a/b.txt', 'c.txt']);
      expect(await zip.readText('a/b.txt'), 'hello');
      expect(await zip.readText('A/B.TXT', ignoreCase: true), 'hello');
      expect(await zip.readText('missing'), isNull);
    });
  });

  group('engine versions (upstream extensionValidator.test.ts)', () {
    final productDate = DateTime.parse('2021-05-11T21:54:30.577Z');
    test('isValidVersion', () {
      for (final (version, desired, expected) in isValidVersionCases) {
        expect(
          isValidEngineVersion(version, productDate, desired),
          expected,
          reason: '$version vs $desired',
        );
      }
    });
    test('isValidExtensionVersion', () {
      for (final (version, desired, expected) in extensionVersionCases) {
        expect(
          isValidExtensionVersion(
            engine: desired,
            hasCode: true,
            version: version,
            productDate: productDate,
          ),
          expected,
          reason: '$version vs $desired',
        );
      }
      for (final (version, desired, builtin, main, expected) in builtinCases) {
        expect(
          isValidExtensionVersion(
            engine: desired,
            hasCode: main,
            builtin: builtin,
            version: version,
            productDate: productDate,
          ),
          expected,
          reason: '$version vs $desired builtin: $builtin main: $main',
        );
      }
    });
    test('1.135.0', () {
      expect(isEngineCompatible('^1.101.0'), isTrue);
      expect(isEngineCompatible('^1.135.0'), isTrue);
      expect(isEngineCompatible('^1.136.0'), isFalse);
      expect(isEngineCompatible('>=1.130.0'), isTrue);
      expect(isEngineCompatible('*'), isFalse);
      expect(isEngineValid('*'), isTrue);
      final notices = <EngineNotice>[];
      expect(isEngineCompatible('1.x', notices: notices), isFalse);
      expect(notices.single.kind, EngineNoticeKind.syntax);
    });
  });

  group('target platforms', () {
    test('compatibility', () {
      const mac = ExtensionTargetPlatform.darwinArm64;
      expect(ExtensionTargetPlatform.universal.isCompatibleWith(mac), isTrue);
      expect(ExtensionTargetPlatform.undefined.isCompatibleWith(mac), isTrue);
      expect(mac.isCompatibleWith(mac), isTrue);
      expect(ExtensionTargetPlatform.linuxX64.isCompatibleWith(mac), isFalse);
      expect(ExtensionTargetPlatform.unknown.isCompatibleWith(mac), isFalse);
      expect(
        ExtensionTargetPlatform.parse('darwin-x64'),
        ExtensionTargetPlatform.darwinX64,
      );
      expect(
        ExtensionTargetPlatform.parse('nope'),
        ExtensionTargetPlatform.unknown,
      );
      expect(
        ExtensionTargetPlatform.current,
        isNot(ExtensionTargetPlatform.web),
      );
    });
  });

  group('semver', () {
    test('compares versions', () {
      expect(compareExtensionVersions('1.2.3', '1.2.3'), 0);
      expect(compareExtensionVersions('1.10.0', '1.9.9'), 1);
      expect(compareExtensionVersions('1.0.0-next.1', '1.0.0'), -1);
      expect(compareExtensionVersions('1.0.0-next.2', '1.0.0-next.10'), -1);
      expect(compareExtensionVersions('2026.10.1', '17.11.1'), 1);
      expect(isSemver('1.2.3-beta+5'), isTrue);
      expect(isSemver('1.2'), isFalse);
    });
  });
}

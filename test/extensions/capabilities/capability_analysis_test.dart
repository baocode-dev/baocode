import 'dart:io';

import 'package:baocode/extensions/capabilities/capability_analysis.dart';
import 'package:baocode/extensions/vsix/vsix_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/fake_backend.dart';
import '../vsix/zip_writer.dart';

const _fixtures = 'test/fixtures/extensions/capabilities';

Future<CapabilityReport> _analyze(String path) async {
  final package = await ExtensionPackage.open(path);
  try {
    return analyzeExtensionPackage(package);
  } finally {
    await package.close();
  }
}

/// Every file under [dir], by its relative path.
Map<String, Object> _read(String dir) => {
  for (final file in Directory(dir).listSync(recursive: true).whereType<File>())
    file.path.substring(dir.length + 1): file.readAsBytesSync(),
};

const _theme = {
  'themes': [
    {'label': 'Night', 'uiTheme': 'vs-dark', 'path': './night.json'},
  ],
};

void main() {
  test('a color theme alone is fully supported', () async {
    final report = await _analyze('$_fixtures/theme');
    expect(report.level, ExtensionCapabilityLevel.full);
    expect(report.findings, isEmpty);
    expect(report.installable, isTrue);
  });

  test('a .vsix is analyzed as its folder would be', () async {
    final dir = Directory.systemTemp.createTempSync('capabilities');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/theme.vsix';
    File(path).writeAsBytesSync(buildVsix(_read('$_fixtures/theme')));
    final report = await _analyze(path);
    expect(report.level, ExtensionCapabilityLevel.full);
  });

  test('an extension without a theme is not supported', () async {
    final report = await _analyze('$_fixtures/language');
    expect(report.level, ExtensionCapabilityLevel.unsupported);
    expect(report.installable, isFalse);
    expect(
      report.findings,
      containsAll(const [
        CapabilityFinding(CapabilityFindingKind.code),
        CapabilityFinding(CapabilityFindingKind.contribution, 'languages'),
      ]),
    );
  });

  test('a theme beside code and other contributions is partly supported, '
      'with what will not run', () {
    final report = analyzeExtensionCapabilities(
      fakeManifest(
        'acme.mixed',
        manifest: {
          'main': './out/extension.js',
          'contributes': {
            ..._theme,
            'colors': [
              {'id': 'acme.color'},
            ],
            'commands': [
              {'command': 'acme.go', 'title': 'Go'},
            ],
            'keybindings': <Object?>[],
          },
        },
      ),
    );
    expect(report.level, ExtensionCapabilityLevel.partial);
    expect(report.findings, const [
      CapabilityFinding(CapabilityFindingKind.code),
      CapabilityFinding(CapabilityFindingKind.contribution, 'commands'),
    ]);
  });

  test('a file icon theme counts as a theme', () {
    final manifest = fakeManifest(
      'acme.icons',
      manifest: {
        'contributes': {
          'iconThemes': [
            {'id': 'acme', 'label': 'Acme', 'path': './icons.json'},
          ],
          'icons': {'acme-logo': <String, Object?>{}},
        },
      },
    );
    expect(hasThemes(manifest), isTrue);
    expect(
      analyzeExtensionCapabilities(manifest).level,
      ExtensionCapabilityLevel.full,
    );
  });

  test('empty theme lists are no theme', () {
    final manifest = fakeManifest(
      'acme.empty',
      manifest: {
        'contributes': {'themes': <Object?>[], 'iconThemes': <Object?>[]},
      },
    );
    expect(hasThemes(manifest), isFalse);
    expect(
      analyzeExtensionCapabilities(manifest).level,
      ExtensionCapabilityLevel.unsupported,
    );
  });
}

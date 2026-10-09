// Dropping a .vsix on the workbench: the confirmation shows what the
// package is, whether it fits this VS Code and platform, and installs once
// confirmed. Dropping an extension folder asks before loading it as a
// development extension.
//
// The sheet reads the package while building, so its body runs inside
// `tester.runAsync` ([_io]): those futures only complete with real IO.

import 'dart:io';

import 'package:baocode/extensions/gallery/extension_management_backend.dart';
import 'package:baocode/extensions/ui/vsix_drop.dart';
import 'package:baocode/extensions/vsix/target_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../vsix/zip_writer.dart';
import 'fake_backend.dart';

/// Runs [body] with real async and IO, pumping between steps (a dialog
/// opened by [body] needs a few rounds of them).
Future<void> _io(WidgetTester tester, Future<void> Function() body) async {
  await tester.runAsync(() async {
    await body();
    for (var round = 0; round < 4; round++) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

const _vsixManifest = '''
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="tool" Version="1.2.0" Publisher="acme"/>
    <DisplayName>Tool</DisplayName>
    <Description xml:space="preserve">A tool.</Description>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.101.0" />
    </Properties>
  </Metadata>
</PackageManifest>
''';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('vsix-drop'));
  tearDown(() => dir.deleteSync(recursive: true));

  void writeVsix(
    String name, {
    String? vsixManifest = _vsixManifest,
    String engine = '^1.101.0',
  }) {
    final bytes = buildVsix({
      'package.json': {
        'name': 'tool',
        'publisher': 'acme',
        'version': '1.2.0',
        'displayName': 'Tool',
        'description': 'A tool.',
        // Code (so that the engine is actually checked; a declarative
        // extension's is always accepted).
        'main': './extension.js',
        'engines': {'vscode': engine},
      },
      'extension.js': 'exports.activate = () => {};',
    }, vsixManifest: vsixManifest);
    File('${dir.path}/$name').writeAsBytesSync(bytes);
  }

  Widget sheet({
    required ExtensionManagementBackend backend,
    ValueChanged<InstalledExtension?>? onClose,
    ExtensionTargetPlatform? platform,
    String? name,
  }) => MaterialApp(
    home: Scaffold(
      body: VsixInstallSheet(
        path: '${dir.path}/${name ?? 'tool.vsix'}',
        backend: backend,
        platform: platform ?? ExtensionTargetPlatform.universal,
        onClose: onClose ?? (_) {},
      ),
    ),
  );

  testWidgets('shows a .vsix and installs it once confirmed', (tester) async {
    writeVsix('tool.vsix');
    final backend = FakeBackend();
    InstalledExtension? installed;
    await _io(tester, () async {
      await tester.pumpWidget(
        sheet(backend: backend, onClose: (value) => installed = value),
      );
    });

    expect(find.text('Install Extension VSIX'), findsOneWidget);
    expect(find.text('Tool'), findsOneWidget);
    expect(find.textContaining('acme.tool'), findsOneWidget);
    expect(find.text('Requires VS Code ^1.101.0.'), findsOneWidget);
    expect(find.text('Platform: universal'), findsOneWidget);
    expect(find.text('Fully supported'), findsOneWidget);

    await _io(tester, () => tester.tap(find.text('Install')));
    expect(backend.calls.single, contains('tool.vsix'));
    expect(installed, isNotNull);
    expect(installed!.id, 'acme.tool');
    expect(installed!.version, '1.2.0');
  });

  testWidgets('refuses an engine this VS Code does not satisfy', (
    tester,
  ) async {
    writeVsix('tool.vsix', engine: '^1.999.0');
    final backend = FakeBackend();
    await _io(tester, () async {
      await tester.pumpWidget(sheet(backend: backend));
    });

    expect(find.textContaining('Needs VS Code ^1.999.0'), findsOneWidget);
    expect(find.textContaining('this is 1.135.0'), findsOneWidget);
    expect(find.text('Install Extension VSIX'), findsOneWidget);
    // Install is disabled, so nothing happens.
    await _io(tester, () async {
      await tester.tap(find.text('Install'), warnIfMissed: false);
    });
    expect(backend.calls, isEmpty);
  });

  testWidgets('refuses a package for another platform', (tester) async {
    writeVsix(
      'tool.vsix',
      vsixManifest: _vsixManifest.replaceAll(
        '<Identity Language="en-US" Id="tool" Version="1.2.0" Publisher="acme"/>',
        '<Identity Language="en-US" Id="tool" Version="1.2.0" '
            'Publisher="acme" TargetPlatform="win32-x64"/>',
      ),
    );
    final backend = FakeBackend();
    await _io(tester, () async {
      await tester.pumpWidget(
        sheet(backend: backend, platform: ExtensionTargetPlatform.darwinArm64),
      );
    });

    expect(
      find.textContaining('It is built for Windows 64 bit, not for Mac '
          'Silicon.'),
      findsOneWidget,
    );
    await _io(tester, () async {
      await tester.tap(find.text('Install'), warnIfMissed: false);
    });
    expect(backend.calls, isEmpty);
  });

  testWidgets('says when what was dropped is not a VSIX', (tester) async {
    File('${dir.path}/notes.txt').writeAsStringSync('hello');
    await _io(tester, () async {
      await tester.pumpWidget(sheet(backend: FakeBackend(), name: 'notes.txt'));
    });
    expect(find.textContaining('is not a valid VSIX'), findsOneWidget);
  });

  testWidgets('notices an installed version it would replace', (tester) async {
    writeVsix('tool.vsix');
    final backend = FakeBackend(
      installed: [
        InstalledExtension(
          manifest: fakeManifest('acme.tool', version: '1.0.0'),
          location: '/extensions/acme.tool',
        ),
      ],
    );
    await _io(tester, () async {
      await tester.pumpWidget(sheet(backend: backend));
    });
    expect(find.text('It replaces version 1.0.0.'), findsOneWidget);
  });

  group('dropping', () {
    testWidgets('a file that is not an extension is left alone', (
      tester,
    ) async {
      File('${dir.path}/notes.txt').writeAsStringSync('hello');
      final backend = FakeBackend();
      bool? handled;
      await _io(tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    handled = await handleExtensionDrop(
                      context,
                      ['${dir.path}/notes.txt'],
                      backend: backend,
                      onLoadDevelopmentFolder: (_) {},
                    );
                  },
                  child: const Text('drop'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('drop'));
      });
      // Nothing was shown: the workbench opens the file itself.
      expect(find.text('Install Extension VSIX'), findsNothing);
      expect(handled, isFalse);
    });

    testWidgets('a dropped .vsix shows the sheet', (tester) async {
      writeVsix('tool.vsix');
      final backend = FakeBackend();
      await _io(tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => handleExtensionDrop(
                    context,
                    ['${dir.path}/tool.vsix'],
                    backend: backend,
                    onLoadDevelopmentFolder: (_) {},
                  ),
                  child: const Text('drop'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('drop'));
      });
      expect(find.text('Install Extension VSIX'), findsOneWidget);
      expect(find.text('Tool'), findsOneWidget);
    });

    testWidgets('an extension folder is offered as a development one', (
      tester,
    ) async {
      writeFolder('${dir.path}/acme.tool', {
        'package.json': {
          'name': 'tool',
          'publisher': 'acme',
          'version': '1.0.0',
          'engines': {'vscode': '^1.101.0'},
        },
      });
      final loaded = <String>[];
      await _io(tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => handleExtensionDrop(
                    context,
                    ['${dir.path}/acme.tool'],
                    backend: FakeBackend(),
                    onLoadDevelopmentFolder: loaded.add,
                  ),
                  child: const Text('drop'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('drop'));
      });
      expect(find.text('Development Extension'), findsOneWidget);
      expect(
        find.text('Load acme.tool as a development extension?'),
        findsOneWidget,
      );
      await _io(tester, () => tester.tap(find.text('Load')));
      expect(loaded, ['${dir.path}/acme.tool']);
    });

    testWidgets('classifies a dropped path', (tester) async {
      writeVsix('tool.vsix');
      writeFolder('${dir.path}/acme.tool', {
        'package.json': {
          'name': 'tool',
          'publisher': 'acme',
          'version': '1.0.0',
          'engines': {'vscode': '^1.101.0'},
        },
      });
      File('${dir.path}/notes.txt').writeAsStringSync('hello');
      await tester.runAsync(() async {
        expect(
          await classifyExtensionDrop('${dir.path}/tool.vsix'),
          ExtensionDropKind.vsix,
        );
        expect(
          await classifyExtensionDrop('${dir.path}/acme.tool'),
          ExtensionDropKind.developmentFolder,
        );
        expect(
          await classifyExtensionDrop('${dir.path}/notes.txt'),
          ExtensionDropKind.other,
        );
      });
    });
  });
}

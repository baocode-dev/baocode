// The import dialog: pick the editors, see the plan (what Open VSX has,
// what is proprietary and what could only be copied), import, then the
// report.
//
// Everything it does is real filesystem and HTTP work (through the fake
// http), so the body of each test runs inside [WidgetTester.runAsync].

import 'dart:convert';
import 'dart:io';

import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/import/extension_import.dart';
import 'package:baocode/extensions/ui/import_dialog.dart';
import 'package:baocode/extensions/vsix/target_platform.dart';
import 'package:baocode/keybindings/vscode_import.dart';
import 'package:baocode/settings/jsonc.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../gallery/fixture_http.dart';
import '../vsix/zip_writer.dart';
import 'fake_backend.dart';

Map<String, Object> _extension(
  String id,
  String version, {
  Map<String, Object?> configuration = const {},
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
    },
    'extension.js': 'exports.activate = () => {};',
  };
}

/// Runs [body] with real async and IO, pumping between its steps.
Future<void> _io(
  WidgetTester tester,
  Future<void> Function() body, {
  Finder? tap,
}) async {
  await tester.runAsync(() async {
    if (tap != null) {
      await tester.ensureVisible(tap);
    }
    await body();
    for (var round = 0; round < 4; round++) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  late Directory home;
  late Directory cache;
  late VsCodeInstalls installs;
  late FixtureHttp http;
  late OpenVsxClient client;
  late String vscode;
  late String settingsPath;

  setUp(() {
    home = Directory.systemTemp.createTempSync('import-dialog');
    cache = Directory.systemTemp.createTempSync('import-dialog-cache');
    installs = VsCodeInstalls(
      home: home.path,
      environment: {'HOME': home.path},
      platform: KeybindingPlatform.mac,
    );
    vscode = installs.extensionsDir(VsCodeProduct.code);
    final cursor = installs.extensionsDir(VsCodeProduct.cursor);

    // VS Code: a prettier (on Open VSX), a proprietary pylance, and a
    // private one only a copy can bring.
    writeFolder(
      '$vscode/esbenp.prettier-vscode-11.0.0',
      _extension(
        'esbenp.prettier-vscode',
        '11.0.0',
        configuration: {
          'prettier.singleQuote': {'type': 'boolean'},
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
    File('$vscode/extensions.json').writeAsStringSync(
      jsonEncode([
        {
          'identifier': {'id': 'esbenp.prettier-vscode'},
          'version': '11.0.0',
          'location': {
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
          'relativeLocation': 'ms-python.vscode-pylance-2024.1.1',
        },
        {
          'identifier': {'id': 'acme.private'},
          'version': '1.0.0',
          'location': {
            'path': '$vscode/acme.private-1.0.0',
            'scheme': 'file',
          },
          'relativeLocation': 'acme.private-1.0.0',
          'metadata': {'source': 'vsix'},
        },
      ]),
    );

    // Cursor: an older prettier and its own extension.
    writeFolder(
      '$cursor/esbenp.prettier-vscode-10.0.0',
      _extension('esbenp.prettier-vscode', '10.0.0'),
    );
    writeFolder(
      '$cursor/anysphere.cursorpyright-1.0.0',
      _extension('anysphere.cursorpyright', '1.0.0'),
    );

    final codeUser = installs.userDir(VsCodeProduct.code);
    Directory(codeUser).createSync(recursive: true);
    File('$codeUser/settings.json').writeAsStringSync('''
{
  // Mine
  "editor.fontSize": 14,
  "prettier.singleQuote": true,
  "acme.private.flag": true,
}
''');
    settingsPath = p.join(home.path, 'baocode', 'User', 'settings.json');
    Directory(p.dirname(settingsPath)).createSync(recursive: true);
    File(settingsPath).writeAsStringSync('{\n  "editor.fontSize": 14\n}');

    // Open VSX: prettier is there, pylance is proprietary (its alternative
    // is), the private one is not.
    http = FixtureHttp(recorded: false);
    for (final path in [
      '/api/esbenp/prettier-vscode/darwin-arm64/latest',
      '/api/ms-python/vscode-pylance',
      '/api/ms-python/vscode-pylance/darwin-arm64/latest',
      '/api/ms-python/vscode-pylance/universal/latest',
      '/api/acme/private/darwin-arm64/latest',
      '/api/acme/private/universal/latest',
      '/api/acme/private',
      '/api/detachhead/basedpyright/darwin-arm64/latest',
    ]) {
      http.add(path, utf8.encode('{"error": "Not found"}'), status: 404);
    }
    http.addJson('/api/esbenp/prettier-vscode/universal/latest', {
      'namespace': 'esbenp',
      'name': 'prettier-vscode',
      'version': '12.4.0',
      'targetPlatform': 'universal',
      'engines': {'vscode': '^1.80.0'},
      'files': {
        'download': 'https://open-vsx.org/prettier-12.4.0.vsix',
        'sha256': 'https://open-vsx.org/prettier-12.4.0.sha256',
      },
    });
    http.addJson('/api/detachhead/basedpyright/universal/latest', {
      'namespace': 'detachhead',
      'name': 'basedpyright',
      'version': '1.30.0',
      'targetPlatform': 'universal',
      'engines': {'vscode': '^1.80.0'},
      'files': {
        'download': 'https://open-vsx.org/basedpyright-1.30.0.vsix',
        'sha256': 'https://open-vsx.org/basedpyright-1.30.0.sha256',
      },
    });
    final prettierVsix = buildVsix(_extension('esbenp.prettier-vscode', '12.4.0'));
    final basedpyrightVsix = buildVsix(
      _extension('detachhead.basedpyright', '1.30.0'),
    );
    http
      ..add('/prettier-12.4.0.vsix', prettierVsix)
      ..add(
        '/prettier-12.4.0.sha256',
        utf8.encode(crypto.sha256.convert(prettierVsix).toString()),
      )
      ..add('/basedpyright-1.30.0.vsix', basedpyrightVsix)
      ..add(
        '/basedpyright-1.30.0.sha256',
        utf8.encode(crypto.sha256.convert(basedpyrightVsix).toString()),
      );
    client = OpenVsxClient(
      http: http,
      cacheDir: cache.path,
      targetPlatform: ExtensionTargetPlatform.darwinArm64,
    );
  });

  tearDown(() {
    home.deleteSync(recursive: true);
    cache.deleteSync(recursive: true);
  });

  Widget dialog({
    required FakeBackend backend,
    required ValueChanged<ImportReport?> onClose,
  }) => MaterialApp(
    home: Scaffold(
      body: ExtensionImportDialog(
        planner: ExtensionImportPlanner(installs: installs, gallery: client),
        importer: ExtensionImporter(backend: backend, gallery: client),
        backend: backend,
        settingsPath: settingsPath,
        onClose: onClose,
      ),
    ),
  );

  testWidgets('picks the editors, plans and reports', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    ImportReport? report;
    await _io(tester, () async {
      await tester.pumpWidget(
        dialog(backend: backend, onClose: (value) => report = value),
      );
    });

    expect(find.text('Import Extensions'), findsOneWidget);
    expect(find.text('Visual Studio Code (3)'), findsOneWidget);
    expect(find.text('Cursor (2)'), findsOneWidget);
    expect(find.text('Import extensions from:'), findsOneWidget);

    await _io(tester, () => tester.tap(find.text('Continue')));

    // The plan, grouped by what would happen.
    expect(find.text('On Open VSX (1)'), findsOneWidget);
    expect(find.text('Proprietary (1)'), findsOneWidget);
    expect(find.text('Copy from disk (1)'), findsOneWidget);
    expect(find.text('Skipped (1)'), findsOneWidget);
    expect(find.text('v11.0.0 here, v12.4.0 on Open VSX'), findsOneWidget);
    expect(
      find.text('Its license does not allow other editors to use it.'),
      findsOneWidget,
    );
    expect(
      find.text('Use basedpyright (detachhead.basedpyright) instead.'),
      findsOneWidget,
    );
    expect(find.text('It is not on Open VSX.'), findsOneWidget);
    expect(find.text('Only for another editor.'), findsOneWidget);
    // Only the prettier is selected to start with.
    expect(find.text('Import (1)'), findsOneWidget);

    await _io(tester, () => tester.tap(find.text('Import (1)')));

    expect(find.text('Import Report'), findsOneWidget);
    expect(
      find.textContaining('Installed v12.4.0.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Not imported.', findRichText: true),
      findsWidgets,
    );
    expect(
      backend.calls.any((call) => call.startsWith('install /')),
      isTrue,
    );
    // Its settings came along.
    expect(
      parseJsonc(File(settingsPath).readAsStringSync()),
      containsPair('prettier.singleQuote', true),
    );
    await _io(tester, () => tester.tap(find.text('Close')));
    expect(report, isNotNull);
  });

  testWidgets('does not copy without consent and can pick an alternative', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    await _io(tester, () async {
      await tester.pumpWidget(dialog(backend: backend, onClose: (_) {}));
    });
    await _io(tester, () => tester.tap(find.text('Continue')));

    // Select the proprietary one (its alternative is installed instead)
    // and the local copy, which selecting is the consent to copy it.
    await _io(tester, () => tester.tap(find.text('vscode-pylance')));
    await _io(tester, () => tester.tap(find.text('private')));
    expect(find.text('Import (3)'), findsOneWidget);

    await _io(tester, () => tester.tap(find.text('Import (3)')));

    expect(find.text('Import Report'), findsOneWidget);
    expect(
      find.textContaining('Installed v12.4.0.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Installed detachhead.basedpyright instead.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Copied from disk.', findRichText: true),
      findsOneWidget,
    );
    expect(
      backend.installed.map((extension) => extension.id),
      unorderedEquals([
        'esbenp.prettier-vscode',
        'detachhead.basedpyright',
        'acme.private',
      ]),
    );
    expect(
      backend.calls,
      contains('installFromFolder $vscode/acme.private-1.0.0'),
    );
    // Everything selectable was imported: only Cursor's own extension,
    // always skipped, is left.
    expect(
      find.textContaining('Not imported.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('cursorpyright', findRichText: true),
      findsOneWidget,
    );
  });
}

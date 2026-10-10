// The theme extensions in `<data>/extensions/`: installed from a .vsix in
// VS Code's layout, refused without a theme, replaced, disabled and
// uninstalled.

import 'dart:convert';
import 'dart:io';

import 'package:baocode/extensions/gallery/extension_management_backend.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/theme_extensions.dart';
import 'package:baocode/extensions/window/json_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'gallery/fixture_http.dart';
import 'vsix/zip_writer.dart';

void main() {
  late Directory dir;
  late ThemeExtensions extensions;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('theme-extensions');
    extensions = ThemeExtensions(
      directory: p.join(dir.path, 'extensions'),
      gallery: OpenVsxClient(http: FixtureHttp(recorded: false)),
      enablement: JsonStateStore(
        p.join(dir.path, 'enablement.json'),
        writeDelay: Duration.zero,
      ),
    );
  });
  tearDown(() async {
    await extensions.dispose();
    dir.deleteSync(recursive: true);
  });

  String vsix(
    String name, {
    String version = '1.0.0',
    Map<String, Object?>? contributes,
    Map<String, Object> files = const {},
  }) {
    final path = p.join(dir.path, '$name-$version.vsix');
    File(path).writeAsBytesSync(
      buildVsix({
        'package.json': {
          'name': name,
          'publisher': 'acme',
          'version': version,
          'engines': {'vscode': '^1.50.0'},
          'contributes':
              contributes ??
              {
                'themes': [
                  {
                    'label': 'Night',
                    'uiTheme': 'vs-dark',
                    'path': './themes/night.json',
                  },
                ],
              },
        },
        'themes/night.json': {
          'colors': {'editor.background': '#000000'},
        },
        ...files,
      }),
    );
    return path;
  }

  List<Object?> list() => jsonDecode(
    File(p.join(dir.path, 'extensions', 'extensions.json')).readAsStringSync(),
  ) as List<Object?>;

  test('installs a theme in VS Code\'s layout', () async {
    final installed = await extensions.install(vsix('night'));
    final folder = p.join(dir.path, 'extensions', 'acme.night-1.0.0');
    expect(installed.location, folder);
    expect(File(p.join(folder, 'themes', 'night.json')).existsSync(), isTrue);
    expect(list(), [
      containsPair('identifier', {'id': 'acme.night'}),
    ]);
    expect(list().single, containsPair('relativeLocation', 'acme.night-1.0.0'));
    expect((list().single! as Map)['metadata'], containsPair('source', 'vsix'));

    final listed = await extensions.getInstalled();
    expect(listed.map((e) => e.id), ['acme.night']);
    expect(listed.single.enabled, isTrue);
    expect(listed.single.fromGallery, isFalse);
  });

  test('refuses an extension without a theme', () async {
    final path = vsix(
      'tool',
      contributes: {
        'commands': [
          {'command': 'acme.go', 'title': 'Go'},
        ],
      },
    );
    await expectLater(
      extensions.install(path),
      throwsA(isA<ThemeExtensionException>()),
    );
    expect(Directory(p.join(dir.path, 'extensions')).existsSync(), isFalse);
    expect(await extensions.getInstalled(), isEmpty);
  });

  test('a new version replaces the old one and its folder', () async {
    await extensions.install(vsix('night'));
    await extensions.install(vsix('night', version: '1.1.0'));
    final root = p.join(dir.path, 'extensions');
    expect(Directory(p.join(root, 'acme.night-1.0.0')).existsSync(), isFalse);
    expect(Directory(p.join(root, 'acme.night-1.1.0')).existsSync(), isTrue);
    final listed = await extensions.getInstalled();
    expect(listed.map((e) => e.version), ['1.1.0']);
  });

  test('nothing is written out of its folder', () async {
    await extensions.install(vsix('night', files: {'../../escaped.txt': 'no'}));
    expect(File(p.join(dir.path, 'escaped.txt')).existsSync(), isFalse);
    expect(
      File(p.join(dir.path, 'extensions', 'escaped.txt')).existsSync(),
      isFalse,
    );
  });

  test('disabling is kept under VS Code\'s key and told', () async {
    await extensions.install(vsix('night'));
    final events = <ExtensionManagementEventKind>[];
    final subscription = extensions.onDidChange.listen(
      (event) => events.add(event.kind),
    );
    addTearDown(subscription.cancel);

    await extensions.setEnabled('Acme.Night', false);
    expect((await extensions.getInstalled()).single.enabled, isFalse);
    await extensions.enablement.flush();
    final saved = File(p.join(dir.path, 'enablement.json')).readAsStringSync();
    expect(saved, contains('extensionsIdentifiers/disabled'));
    expect(saved, contains('acme.night'));

    await extensions.setEnabled('acme.night', true);
    expect((await extensions.getInstalled()).single.enabled, isTrue);
    await pumpEventQueue();
    expect(events, [
      ExtensionManagementEventKind.enablement,
      ExtensionManagementEventKind.enablement,
    ]);
  });

  test('uninstalling removes its entry and folder', () async {
    final installed = await extensions.install(vsix('night'));
    await extensions.uninstall('acme.night');
    expect(Directory(installed.location).existsSync(), isFalse);
    expect(list(), isEmpty);
    expect(await extensions.getInstalled(), isEmpty);
  });

  test('an entry whose folder is gone is not listed', () async {
    final installed = await extensions.install(vsix('night'));
    Directory(installed.location).deleteSync(recursive: true);
    expect(await extensions.getInstalled(), isEmpty);
  });
}

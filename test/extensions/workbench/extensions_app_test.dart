// What the app keeps of its extensions across restarts (goal 九.3: the
// enablement survives a restart) and reads without a server (the
// installed extensions' manifests, for their themes before any host runs).

import 'dart:convert';
import 'dart:io';

import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final class _Settings extends ChangeNotifier implements SettingsFile {
  @override
  final Map<String, Object?> values = {};

  @override
  Future<void> write(List<String> path, Object? value) async {}
}

void main() {
  late Directory data;

  setUp(() => data = Directory.systemTemp.createTempSync('extensions-app'));
  tearDown(() => data.deleteSync(recursive: true));

  ExtensionsApp app() => ExtensionsApp(
    userSettings: _Settings(),
    dataDirectory: data.path,
    loadRuntime: () async => throw StateError('No runtime under test'),
  );

  test('an extension disabled stays disabled in the next run', () async {
    final first = app();
    await first.load();
    first.enablement.setEnabled('acme.tools', false);
    await first.enablement.flush();

    final next = app();
    await next.load();
    expect(next.enablement.isEnabled('acme.tools'), isFalse);
    expect(next.enablement.isEnabled('acme.other'), isTrue);
  });

  test('the installed extensions are read from extensions.json, the '
      'disabled ones left out', () async {
    final extensions = Directory(p.join(data.path, 'extensions'))
      ..createSync();
    for (final id in ['acme.theme', 'acme.off']) {
      final folder = Directory(p.join(extensions.path, '$id-1.0.0'))
        ..createSync();
      File(p.join(folder.path, 'package.json')).writeAsStringSync(
        jsonEncode({
          'name': id.split('.').last,
          'publisher': 'acme',
          'contributes': {
            'themes': [
              {'label': 'Acme', 'uiTheme': 'vs-dark', 'path': './t.json'},
            ],
          },
        }),
      );
    }
    File(p.join(extensions.path, 'extensions.json')).writeAsStringSync(
      jsonEncode([
        for (final id in ['acme.theme', 'acme.off'])
          {
            'identifier': {'id': id},
            'version': '1.0.0',
            'relativeLocation': '$id-1.0.0',
          },
      ]),
    );
    final extensionsApp = app();
    await extensionsApp.load();
    extensionsApp.enablement.setEnabled('acme.off', false);

    final manifests = await extensionsApp.installedManifests();
    expect(manifests, hasLength(1));
    expect(manifests.single['identifier'], {'value': 'acme.theme'});
    expect(manifests.single['contributes'], isA<Map<Object?, Object?>>());
  });
}

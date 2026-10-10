import 'dart:convert';
import 'dart:io';

import 'package:baocode/extensions/configuration/configuration_model.dart';
import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final json = (jsonDecode(
    File('assets/exthost/core_configuration.json').readAsStringSync(),
  ) as Map).cast<String, Object?>();
  CoreConfiguration core(String platform) =>
      CoreConfiguration.fromJson(json, platform: platform);

  test('generated from the pinned upstream', () {
    expect(json['upstreamCommit'], '08d4889f9ec4a1685d257b9b95de036c8e1ce1e5');
    expect(core('linux').properties.length, greaterThan(1000));
  });

  test('has upstream defaults and scopes', () {
    final registry = core('darwin').registry();
    final defaults = registry.defaults();
    expect(defaults.getValue('editor.tabSize'), 4);
    expect(defaults.getValue('editor.insertSpaces'), true);
    expect(defaults.getValue('editor.formatOnSave'), false);
    expect(defaults.getValue('files.exclude'), containsPair('**/.git', true));
    expect(defaults.getValue('files.encoding'), 'utf8');
    expect(defaults.getValue('http.proxyStrictSSL'), true);
    expect(defaults.getValue('telemetry.telemetryLevel'), 'all');
    expect(defaults.getValue('security.workspace.trust.enabled'), true);
    expect(
      registry.properties['http.proxy']!.scope,
      ConfigurationScope.application,
    );
    expect(
      registry.properties['editor.tabSize']!.scope,
      ConfigurationScope.languageOverridable,
    );
    expect(registry.properties['editor.tabSize']!.title, 'Editor');
    expect(registry.properties['editor.tabSize']!.order, 5);
    expect(
      registry.properties['security.workspace.trust.enabled']!.restricted,
      isFalse,
    );
    for (final key in [
      'files.associations',
      'search.exclude',
      'http.proxy',
      'terminal.integrated.fontSize',
      'debug.console.fontSize',
      'editor.codeActionsOnSave',
      'editor.defaultFormatter',
      'workbench.colorTheme',
      'extensions.autoUpdate',
      'scm.diffDecorations',
      'testing.automaticallyOpenPeekView',
      'task.autoDetect',
      'notebook.lineNumbers',
      'explorer.confirmDelete',
    ]) {
      expect(registry.properties, contains(key));
    }
  });

  test('platform defaults and platform-only settings', () {
    expect(
      core('darwin').properties['editor.fontFamily']!['default'],
      contains('Menlo'),
    );
    expect(
      core('win32').properties['editor.fontFamily']!['default'],
      contains('Consolas'),
    );
    expect(core('darwin').properties, contains('window.nativeTabs'));
    expect(core('linux').properties, isNot(contains('window.nativeTabs')));
    expect(core('linux').properties, contains('editor.selectionClipboard'));
    expect(
      core('darwin').properties['window.nativeTabs'],
      isNot(contains('platforms')),
    );
  });

  test('language defaults: core and declarative built-in extensions', () {
    final registry = core('linux').registry(
      extensions: [
        {
          'identifier': {'value': 'pub.md'},
          'contributes': {
            'configurationDefaults': {
              '[markdown]': {'editor.wordWrap': 'on'},
            },
          },
        },
      ],
    );
    final defaults = registry.defaults();
    final markdown = defaults.overrides.firstWhere(
      (o) => o.identifiers.contains('markdown'),
    );
    expect(markdown.contents['editor'], {
      'unicodeHighlight': {
        'ambiguousCharacters': false,
        'invisibleCharacters': false,
      },
      'wordWrap': 'on',
    });
    expect(markdown.contents['diffEditor'], {'ignoreTrimWhitespace': false});
    final go = defaults.overrides.firstWhere(
      (o) => o.identifiers.contains('go'),
    );
    expect(go.contents, {
      'editor': {'insertSpaces': false},
    });
    expect(registry.languageDefaults, contains('[yaml]'));
  });
}

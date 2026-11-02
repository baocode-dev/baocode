import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';
import 'package:baocode/ide/lsp/vue_language_tools.dart';
import 'package:path/path.dart' as p;

void main() {
  group('withTypeScriptPlugin', () {
    test('typescript-language-server: initializationOptions.plugins', () {
      const server = LspServerDefinition(
        id: 'typescript-language-server',
        command: 'typescript-language-server',
        args: ['--stdio'],
        initializationOptions: {
          'hostInfo': 'helix',
          'plugins': [
            {'name': 'other', 'location': '/o'},
          ],
        },
        settings: {'typescript': <String, Object?>{}},
        exceptFeatures: {LspFeature.format},
      );
      final added = withTypeScriptPlugin(
        server,
        name: vuePluginName,
        location: '/vue',
        languages: const ['vue'],
      );
      expect(added.initializationOptions, {
        'hostInfo': 'helix',
        'plugins': [
          {'name': 'other', 'location': '/o'},
          {
            'name': '@vue/typescript-plugin',
            'location': '/vue',
            'languages': ['vue'],
          },
        ],
      });
      expect(added.settings, server.settings);
      expect(added.args, server.args);
      expect(added.exceptFeatures, server.exceptFeatures);
      // Already there (e.g. from the user's lsp.json): left as it is.
      expect(
        withTypeScriptPlugin(added, name: vuePluginName, location: '/x'),
        same(added),
      );
    });

    test('vtsls: vtsls.tsserver.globalPlugins in its settings', () {
      const server = LspServerDefinition(
        id: 'vtsls',
        command: '/opt/bin/vtsls',
        settings: {
          'vtsls': {'autoUseWorkspaceTsdk': true},
        },
      );
      final added = withTypeScriptPlugin(
        server,
        name: vuePluginName,
        location: '/vue',
        languages: const ['vue'],
      );
      expect(added.settings, {
        'vtsls': {
          'autoUseWorkspaceTsdk': true,
          'tsserver': {
            'globalPlugins': [
              {
                'name': '@vue/typescript-plugin',
                'location': '/vue',
                'languages': ['vue'],
                'configNamespace': 'typescript',
                'enableForWorkspaceTypeScriptVersions': true,
              },
            ],
          },
        },
      });
    });

    test('other servers are left as they are', () {
      const server = LspServerDefinition(id: 'pyright', command: 'pyright');
      expect(
        withTypeScriptPlugin(server, name: vuePluginName, location: '/vue'),
        same(server),
      );
    });
  });

  test('which servers are TypeScript\'s and Vue\'s', () {
    LspServerDefinition server(String command) =>
        LspServerDefinition(id: 'x', command: command);
    expect(isTypeScriptServer(server('typescript-language-server')), isTrue);
    expect(
      isTypeScriptServer(server(r'C:\npm\typescript-language-server.cmd')),
      isTrue,
    );
    expect(isTypeScriptServer(server('vtsls')), isTrue);
    expect(isTypeScriptServer(server('deno')), isFalse);
    expect(isVueLanguageServer(server('vue-language-server')), isTrue);
    expect(isVueLanguageServer(server('/a/vue-language-server')), isTrue);
    expect(isVueLanguageServer(server('vls')), isFalse);
  });

  group('vueLanguageServerPackage', () {
    Future<String?> find(
      String executable,
      Set<String> files, {
      p.Context? paths,
    }) => vueLanguageServerPackage(
      executable,
      paths: paths ?? p.posix,
      exists: files.contains,
    );

    test('installed by mason', () async {
      expect(
        await find(
          '/data/servers/vue-language-server/node_modules/.bin/'
          'vue-language-server',
          {
            '/data/servers/vue-language-server/node_modules/@vue/'
                'language-server/package.json',
          },
        ),
        '/data/servers/vue-language-server/node_modules/@vue/language-server',
      );
    });

    test('npm global, its link followed or not', () async {
      const package = '/usr/local/lib/node_modules/@vue/language-server';
      const files = {'$package/package.json'};
      expect(await find('/usr/local/bin/vue-language-server', files), package);
      expect(await find('$package/bin/vue-language-server.js', files), package);
    });

    test('npm global on Windows', () async {
      expect(
        await find(r'C:\Users\a\AppData\Roaming\npm\vue-language-server.cmd', {
          r'C:\Users\a\AppData\Roaming\npm\node_modules\@vue\language-server'
              r'\package.json',
        }, paths: p.windows),
        r'C:\Users\a\AppData\Roaming\npm\node_modules\@vue\language-server',
      );
    });

    test('none', () async {
      expect(await find('/usr/bin/vue-language-server', const {}), isNull);
    });
  });

  test('projectVuePlugin: the project\'s plugin, or its Vue server', () async {
    Future<String?> find(Set<String> files) =>
        projectVuePlugin('/app', paths: p.posix, exists: files.contains);
    expect(
      await find({'/app/node_modules/@vue/typescript-plugin/package.json'}),
      '/app',
    );
    expect(
      await find({'/app/node_modules/@vue/language-server/package.json'}),
      '/app/node_modules/@vue/language-server',
    );
    expect(await find(const {}), isNull);
  });

  test('tsserverRequests: wrapped, bare, and not requests', () {
    final args = {'file': '/a.vue'};
    expect(
      tsserverRequests([
        [1, '_vue:projectInfo', args],
      ]),
      [(1, '_vue:projectInfo', args)],
    );
    expect(tsserverRequests([2, 'quickinfo']), [(2, 'quickinfo', null)]);
    expect(tsserverRequests({'id': 1}), isEmpty);
    expect(tsserverRequests(null), isEmpty);
  });
}

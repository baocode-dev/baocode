import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/lsp/catalog/bundled_lsp_catalog.dart';
import 'package:monad/ide/lsp/catalog/file_matching.dart';
import 'package:monad/ide/lsp/catalog/lsp_catalog_overlay.dart';
import 'package:monad/ide/lsp/install/mason_install_plan.dart';
import 'package:monad/ide/lsp/install/mason_platform.dart';
import 'package:monad/ide/lsp/install/mason_registry.dart';
import 'package:monad/ide/lsp/lsp_server_definition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled Helix catalog', () {
    late BundledLspCatalog catalog;

    setUpAll(() async {
      catalog = BundledLspCatalog();
      await catalog.load();
    });

    List<String>? servers(String path, {String? firstLine}) =>
        catalog.languageFor(path, firstLine: firstLine)?.servers;

    test('records its pinned upstream and loads without problems', () {
      expect(catalog.isLoaded, isTrue);
      expect(catalog.problems, isEmpty);
      expect(catalog.source['repository'], contains('helix-editor/helix'));
      expect(catalog.source['commit'], matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(catalog.languages.length, greaterThan(300));
    });

    test('resolves well-known languages to Helix servers', () {
      expect(servers('lib/main.dart'), ['dart']);
      expect(servers('src/main.rs'), ['rust-analyzer']);
      expect(servers('cmd/app/main.go'), contains('gopls'));
      expect(servers('a.c'), ['clangd']);
      expect(servers('a.cpp'), ['clangd']);
      expect(catalog.languageFor('include/a.h')?.id, 'cpp');
      expect(servers('Sources/App/main.swift'), ['sourcekit-lsp']);
      for (final file in ['a.ts', 'a.tsx', 'a.js', 'a.mjs']) {
        expect(servers(file), contains('typescript-language-server'));
      }
      expect(catalog.languageFor('a.tsx')?.languageId, 'typescriptreact');
      expect(servers('app/main.py'), ['ty', 'ruff', 'jedi', 'pylsp', 'zuban']);
      expect(catalog.languageFor('app/main.py')?.rootMarkers, [
        'pyproject.toml',
        'setup.py',
        'poetry.lock',
        'pyrightconfig.json',
      ]);
    });

    test('matches names, longest extensions, globs and shebangs', () {
      expect(catalog.languageFor('Dockerfile')?.id, 'dockerfile');
      expect(catalog.languageFor('/repo/docker/Dockerfile')?.id, 'dockerfile');
      expect(catalog.languageFor('/repo/Dockerfile.dev')?.id, 'dockerfile');
      expect(catalog.languageFor('Makefile')?.id, 'make');
      expect(catalog.languageFor(r'C:\repo\Makefile')?.id, 'make');
      expect(catalog.languageFor('src/a.test.ts')?.id, 'typescript');
      expect(
        catalog.languageFor('/repo/.github/workflows/ci.yml')?.id,
        'github-action',
      );
      expect(catalog.languageFor('/repo/config.yml')?.id, 'yaml');
      expect(
        catalog
            .languageFor('bin/tool', firstLine: '#!/usr/bin/env python3')
            ?.id,
        'python',
      );
      expect(
        catalog.languageFor('bin/tool', firstLine: '#!/usr/bin/python3.12')?.id,
        'python',
      );
      expect(catalog.languageFor('run', firstLine: '#!/bin/bash')?.id, 'bash');
      expect(
        catalog.languageFor('run', firstLine: '#!/usr/bin/env -S deno run')?.id,
        'typescript',
      );
      expect(catalog.languageFor('notes.unknown-extension'), isNull);
      expect(catalog.languageFor('run', firstLine: 'echo hi'), isNull);
    });

    test('mirrors Helix config as settings and initializationOptions', () {
      final server = catalog.server('rust-analyzer')!;
      expect(server.command, 'rust-analyzer');
      expect(server.masonPackage, 'rust-analyzer');
      expect(server.settings, same(server.initializationOptions));
      expect((server.settings!['files'] as Map)['watcher'], 'server');
      final ts = catalog.server('typescript-language-server')!;
      expect(ts.args, ['--stdio']);
      expect(ts.initializationOptions!['hostInfo'], 'helix');
      expect(catalog.server('not-a-server'), isNull);
    });

    test('limits features per language through derived server ids', () {
      final gjs = catalog.language('gjs')!;
      final id = gjs.servers.first;
      expect(id, 'typescript-language-server#except=diagnostics,format');
      expect(catalog.language('gts')!.servers.first, id);
      final server = catalog.server(id)!;
      expect(server.id, id);
      expect(server.command, 'typescript-language-server');
      expect(server.provides(LspFeature.format), isFalse);
      expect(server.provides(LspFeature.diagnostics), isFalse);
      expect(server.provides(LspFeature.hover), isTrue);
      final hare = catalog.server(catalog.language('hare')!.servers.single)!;
      expect(hare.provides(LspFeature.rename), isFalse);
      expect(hare.provides(LspFeature.completion), isFalse);
      expect(hare.provides(LspFeature.gotoDefinition), isTrue);
    });

    test('maps servers to mason packages that exist and plan', () async {
      final registry = await MasonRegistry.load();
      expect(registry.source['commit'], matches(RegExp(r'^[0-9a-f]{40}$')));
      var mapped = 0;
      for (final id in catalog.serverIds) {
        final package = catalog.server(id)!.masonPackage;
        if (package == null) continue;
        mapped++;
        expect(registry[package], isNotNull, reason: id);
        expect(registry[package]!.bin, contains(catalog.server(id)!.command));
      }
      expect(mapped, greaterThan(100));
      for (final package in registry.packages) {
        expect(() => package.purl, returnsNormally, reason: package.name);
      }
      const mac = MasonPlatform('darwin', 'arm64');
      for (final name in [
        'rust-analyzer',
        'typescript-language-server',
        'gopls',
        'clangd',
        'pyright',
        'lua-language-server',
      ]) {
        expect(
          () => MasonInstallPlan.of(registry[name]!, mac),
          returnsNormally,
          reason: name,
        );
      }
    });
  });

  group('matching rules', () {
    const data = '''
{
  "languages": [
    {"id": "yaml", "fileTypes": ["yml", "yaml"], "servers": ["yls"]},
    {"id": "gitlab", "globs": ["*.gitlab-ci.yml"], "servers": ["yls"]},
    {"id": "ci", "globs": [".ci/**/*.yml"]},
    {"id": "upper", "fileTypes": ["R"]},
    {"id": "lower", "fileTypes": ["r"]},
    {"id": "first", "fileTypes": ["dup"]},
    {"id": "second", "fileTypes": ["dup"]},
    {"id": "spec", "fileTypes": ["spec.ts"]},
    {"id": "ts", "fileTypes": ["ts"], "shebangs": ["deno"]}
  ],
  "servers": {"yls": {"command": "yls"}}
}''';
    late BundledLspCatalog catalog;

    setUp(() async {
      catalog = BundledLspCatalog(data: data);
      await catalog.load();
    });

    test('globs before extensions, longest dotted extension first', () {
      expect(catalog.languageFor('/r/.gitlab-ci.yml')?.id, 'gitlab');
      expect(catalog.languageFor('/r/gitlab-ci.yml')?.id, 'yaml');
      expect(catalog.languageFor('/r/app.gitlab-ci.yml')?.id, 'gitlab');
      expect(catalog.languageFor('/r/.ci/a/b/job.yml')?.id, 'ci');
      expect(catalog.languageFor('a.spec.ts')?.id, 'spec');
      expect(catalog.languageFor('a.test.ts')?.id, 'ts');
      expect(catalog.languageFor('a.R')?.id, 'upper');
      expect(catalog.languageFor('a.r')?.id, 'lower');
      expect(catalog.languageFor('a.YML')?.id, 'yaml');
      expect(catalog.languageFor('a.dup')?.id, 'second');
    });

    test('glob and shebang helpers', () {
      expect(LspGlob('Dockerfile.*').matches('/a/Dockerfile.dev'), isTrue);
      expect(LspGlob('Dockerfile.*').matches('/a/xDockerfile.dev'), isFalse);
      expect(LspGlob('*.{yml,yaml}').matches('a/b.yaml'), isTrue);
      expect(LspGlob('file?.[ch]').matches('file1.c'), isTrue);
      expect(LspGlob('file?.[!ch]').matches('file1.c'), isFalse);
      expect(LspGlob('/etc/hosts').matches('/etc/hosts'), isTrue);
      expect(LspGlob('/etc/hosts').matches('/x/etc/hosts'), isFalse);
      expect(shebangCandidates('#!/usr/bin/env python3.12'), [
        'python3.12',
        'python',
      ]);
      expect(shebangCandidates('#! /bin/sh -e'), ['sh']);
      expect(shebangCandidates('#!/usr/bin/env -S deno run -A'), ['deno']);
      expect(shebangCandidates('print(1)'), isEmpty);
      expect(extensionCandidates('a.test.ts'), ['test.ts', 'ts']);
      expect(extensionCandidates('.bashrc'), ['bashrc']);
      expect(extensionCandidates('Makefile'), isEmpty);
    });
  });

  group('overlays', () {
    const data = '''
{
  "languages": [
    {"id": "python", "fileTypes": ["py"], "shebangs": ["python"],
     "servers": ["pyright", "ruff"]},
    {"id": "toml", "fileTypes": ["toml"], "servers": ["taplo"]}
  ],
  "servers": {
    "pyright": {"command": "pyright-langserver", "args": ["--stdio"],
                "config": {"python": {"analysis": {"typeCheckingMode": "basic"}}},
                "mason": "pyright"},
    "ruff": {"command": "ruff", "args": ["server"], "mason": "ruff"},
    "taplo": {"command": "taplo", "args": ["lsp", "stdio"]}
  }
}''';

    Future<BundledLspCatalog> load(List<Map<String, Object?>> layers) async {
      final catalog = BundledLspCatalog(
        data: data,
        overlays: [
          for (final (index, layer) in layers.indexed)
            _JsonOverlay('layer$index', layer),
        ],
      );
      await catalog.load();
      return catalog;
    }

    test(
      'later layers override servers and languages field by field',
      () async {
        final catalog = await load([
          {
            'servers': {
              'pyright': {
                'command': '/opt/pyright/bin/pyright-langserver',
                'settings': {
                  'python': {'pythonPath': '/usr/bin/python3'},
                },
              },
              'mylsp': {
                'command': 'mylsp',
                'rootMarkers': ['my.toml'],
                'requiredRoot': true,
                'onlyFeatures': ['hover', 'goto-definition'],
              },
            },
            'languages': {
              'python': {
                'servers': [
                  'mylsp',
                  {
                    'name': 'ruff',
                    'onlyFeatures': ['format', 'diagnostics'],
                  },
                ],
              },
              'mine': {
                'fileTypes': ['.mine'],
                'fileNames': ['Minefile'],
                'servers': ['mylsp'],
              },
            },
          },
          {
            'servers': {
              'taplo': {'disabled': true},
            },
            'languages': {
              'mine': {
                'fileTypes': ['py'],
              },
            },
          },
        ]);
        expect(catalog.problems, isEmpty);
        final pyright = catalog.server('pyright')!;
        expect(pyright.command, '/opt/pyright/bin/pyright-langserver');
        expect(pyright.args, ['--stdio']);
        expect(pyright.masonPackage, 'pyright');
        expect(pyright.settings, {
          'python': {'pythonPath': '/usr/bin/python3'},
        });
        expect(pyright.initializationOptions, {
          'python': {
            'analysis': {'typeCheckingMode': 'basic'},
          },
        });
        final mylsp = catalog.server('mylsp')!;
        expect(mylsp.rootMarkers, ['my.toml']);
        expect(mylsp.requiredRoot, isTrue);
        expect(mylsp.provides(LspFeature.hover), isTrue);
        expect(mylsp.provides(LspFeature.format), isFalse);

        final python = catalog.language('python')!;
        expect(python.servers, ['mylsp', 'ruff#only=diagnostics,format']);
        final ruff = catalog.server(python.servers.last)!;
        expect(ruff.provides(LspFeature.format), isTrue);
        expect(ruff.provides(LspFeature.hover), isFalse);

        // The later layer claimed .py for "mine"; the name stays with it too.
        expect(catalog.languageFor('a.py')?.id, 'mine');
        expect(catalog.languageFor('a.mine'), isNull);
        expect(catalog.languageFor('Minefile')?.id, 'mine');
        expect(
          catalog.languageFor('x', firstLine: '#!/usr/bin/env python')?.id,
          'python',
        );
        expect(catalog.server('taplo'), isNull);
        expect(catalog.language('toml')!.servers, isEmpty);
      },
    );

    test('invalid entries are reported and skipped, not fatal', () async {
      final catalog = await load([
        {
          'servers': {
            'nocommand': {'args': []},
            'pyright': {'args': 'not-a-list', 'bogus': 1},
            'bad#id': {'command': 'x'},
            'ruff': 'not-an-object',
          },
          'languages': {
            'python': {
              'servers': ['pyright', 'ghost', 42],
              'fileTypes': 'py',
            },
            'broken': {
              'firstLine': '(unclosed',
              'globs': ['{a,b'],
            },
          },
        },
      ]);
      final messages = catalog.problems.map((p) => p.toString()).join('\n');
      expect(messages, contains('servers.nocommand: a new server needs'));
      expect(messages, contains('servers.pyright.args: expected a list'));
      expect(messages, contains('servers.pyright: unknown "bogus"'));
      expect(messages, contains('servers.bad#id'));
      expect(messages, contains('servers.ruff: expected an object'));
      expect(messages, contains('languages.python.servers[2]'));
      expect(messages, contains('unknown server "ghost"'));
      expect(messages, contains('languages.python.fileTypes'));
      expect(messages, contains('bad firstLine'));
      expect(messages, contains('bad glob'));
      expect(catalog.problems.first.source, 'layer0');
      // What was valid still applies.
      expect(catalog.server('pyright')!.args, ['--stdio']);
      expect(catalog.language('python')!.servers, ['pyright']);
      expect(catalog.languageFor('a.py')?.id, 'python');
      expect(catalog.server('nocommand'), isNull);
    });

    test('an overlay that fails to read is a problem', () async {
      final catalog = BundledLspCatalog(
        data: data,
        overlays: [_FailingOverlay()],
      );
      await catalog.load();
      expect(catalog.problems.single.source, 'failing');
      expect(catalog.languageFor('a.py')?.id, 'python');
    });

    test('patches read from JSON report unknown keys', () {
      final patch = lspCatalogPatchFromJson('f', {
        'servers': {'a': {}},
        'language': {},
      });
      expect(patch.servers, contains('a'));
      expect(patch.problems.single.message, contains('"language"'));
      expect(
        lspCatalogPatchFromJson('f', []).problems.single.message,
        contains('object'),
      );
    });
  });

  test('loads from any asset bundle', () async {
    final catalog = BundledLspCatalog(
      bundle: _Bundle({
        BundledLspCatalog.assetPath: jsonEncode({
          'languages': [
            {
              'id': 'zig',
              'fileTypes': ['zig'],
              'servers': ['zls'],
            },
          ],
          'servers': {
            'zls': {'command': 'zls'},
          },
        }),
      }),
    );
    expect(catalog.languageFor('a.zig'), isNull);
    await catalog.load();
    expect(catalog.languageFor('a.zig')?.servers, ['zls']);
  });
}

class _JsonOverlay implements LspCatalogOverlay {
  _JsonOverlay(this.name, this.json);

  @override
  final String name;
  final Map<String, Object?> json;

  @override
  Future<LspCatalogPatch> read() async => lspCatalogPatchFromJson(name, json);
}

class _FailingOverlay implements LspCatalogOverlay {
  @override
  String get name => 'failing';

  @override
  Future<LspCatalogPatch> read() => Future.error(StateError('unreadable'));
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final text = assets[key];
    if (text == null) throw StateError('No asset $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}

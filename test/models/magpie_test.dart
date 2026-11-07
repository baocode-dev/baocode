import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:baocode/models/magpie.dart';
import 'package:baocode/models/magpie_follow.dart';
import 'package:baocode/models/magpie_io.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/upstream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// magpie's `/v1/models?kind=chat,image`, as 0.12 answers it.
final _catalog = {
  'data': [
    {
      'id': 'auto/claude-opus-5-5',
      'display_name': 'Claude Opus 5.5',
      'magpie_label': 'Claude Opus 5.5 · routing group',
      'context_window': 1000000,
      'reasoning': true,
      'reasoning_levels': ['low', 'medium', 'high', 'xhigh', 'max'],
      'modalities': {
        'input': ['text', 'image'],
      },
    },
    {
      'id': 'claude/claude-opus-5-5',
      'display_name': 'Claude Opus 5.5',
      'magpie_label': 'Claude Opus 5.5 · Claude Code',
      'context_window': 1000000,
      'modalities': {
        'input': ['text', 'image'],
        'output': ['text'],
      },
    },
    {
      'id': 'deepseek/deepseek-v4.1-flash',
      'magpie_label': 'DeepSeek V4.1 Flash · DeepSeek',
      'context_window': 128000,
      'modalities': {
        'input': ['text'],
        'output': ['text'],
      },
    },
    {
      'id': 'yiyuan/gpt-image-2',
      'magpie_label': 'GPT Image 2 · 一元生图',
      'kind': 'image',
    },
  ],
};

void main() {
  group('the catalog', () {
    test('magpie\'s fields: label, efforts, images, kind', () {
      final models = parseModelList(_catalog);
      final group = models.first;
      expect(group.label, 'Claude Opus 5.5 · routing group');
      expect(group.contextWindow, 1000000);
      expect(group.efforts, ['low', 'medium', 'high', 'xhigh', 'max']);
      expect(group.images, isTrue);
      expect(group.kind, isNull);
      expect(models[1].kind, ModelKind.chat);
      expect(models[2].images, isFalse);
      expect(models[3].kind, ModelKind.image);
    });
  });

  group('Magpie', () {
    test('its port, from its settings', () {
      expect(Magpie.portOf({'port': 4000}), 4000);
      expect(Magpie.portOf({'port': 'x'}), Magpie.defaultPort);
      expect(Magpie.portOf(null), Magpie.defaultPort);
    });

    test('its version, only when magpie answers', () {
      expect(
        Magpie.versionOf({'name': 'magpie', 'version': '0.12.6'}),
        '0.12.6',
      );
      expect(Magpie.versionOf({'name': 'other', 'version': '1'}), isNull);
      expect(Magpie.versionOf('magpie'), isNull);
    });

    test('Claude Code\'s models, only when it goes to the gateway', () {
      final settings = {
        'model': 'deepseek/deepseek-v4-1-flash:high[1m]',
        'env': {
          'ANTHROPIC_BASE_URL': 'http://127.0.0.1:3425',
          'ANTHROPIC_DEFAULT_OPUS_MODEL': 'auto/claude-opus-5-5',
          'ANTHROPIC_SMALL_FAST_MODEL': 'claude/claude-haiku-5-5',
        },
      };
      expect(Magpie.claudePicks(settings, 3425), {
        'main': 'deepseek/deepseek-v4-1-flash:high[1m]',
        'opus': 'auto/claude-opus-5-5',
        'haiku': 'claude/claude-haiku-5-5',
      });
      // Another port: another gateway's.
      expect(Magpie.claudePicks(settings, 4000), isEmpty);
      expect(Magpie.claudePicks({'model': 'opus'}, 3425), isEmpty);
    });

    test('a pick matches its model, effort and marks aside', () {
      const ids = ['deepseek/deepseek-v4.1-flash', 'claude/claude-opus-4.6'];
      expect(
        Magpie.match('deepseek/deepseek-v4.1-flash:high[1m]', ids),
        'deepseek/deepseek-v4.1-flash',
      );
      expect(
        Magpie.match('claude/claude-opus-4-6', ids),
        'claude/claude-opus-4.6',
      );
      expect(Magpie.match('claude/claude-opus-5', ids), isNull);
    });

    test('first listed: groups, images and Claude Code\'s on, roles set', () {
      final listed = parseModelList(_catalog);
      final provider = Magpie.synced(Magpie.provider('magpie'), listed, {
        'main': 'deepseek/deepseek-v4-1-flash',
        'opus': 'auto/claude-opus-5-5',
      });
      expect(
        {
          for (final model in provider.models)
            if (model.enabled) model.id,
        },
        {
          'auto/claude-opus-5-5',
          'deepseek/deepseek-v4.1-flash',
          'yiyuan/gpt-image-2',
        },
      );
      expect(provider.roles.main, 'deepseek/deepseek-v4.1-flash');
      expect(provider.roles.opus, 'auto/claude-opus-5-5');
      expect(provider.imageModels.single.id, 'yiyuan/gpt-image-2');
    });

    test('first listed with no group nor pick: every conversation model', () {
      final listed = parseModelList({
        'data': [
          {'id': 'a/one'},
          {'id': 'b/two'},
        ],
      });
      final provider = Magpie.synced(Magpie.provider('magpie'), listed, {});
      expect(provider.enabledModels.map((m) => m.id), ['a/one', 'b/two']);
    });

    test('listed again: new groups on, the rest off, the user\'s kept', () {
      final before = Magpie.provider('magpie').copyWith(
        models: const [
          ProviderModel(id: 'auto/claude-opus-5-5', enabled: false),
          ProviderModel(id: 'claude/claude-opus-5-5', label: 'Old'),
          ProviderModel(id: 'gone/model'),
        ],
        roles: const ProviderRoles(opus: 'claude/claude-opus-5-5'),
      );
      final listed = [
        ...parseModelList(_catalog),
        const RemoteModel('group/fast'),
      ];
      final after = Magpie.synced(before, listed, {
        'main': 'deepseek/deepseek-v4.1-flash',
      });
      ProviderModel model(String id) => after.model(id)!;
      // Turned off by the user: stays so.
      expect(model('auto/claude-opus-5-5').enabled, isFalse);
      // Its name, as magpie says it now.
      expect(
        model('claude/claude-opus-5-5').label,
        'Claude Opus 5.5 · Claude Code',
      );
      expect(model('claude/claude-opus-5-5').enabled, isTrue);
      expect(model('gone/model').missing, isTrue);
      expect(model('group/fast').enabled, isTrue);
      expect(model('deepseek/deepseek-v4.1-flash').enabled, isTrue);
      expect(model('yiyuan/gpt-image-2').enabled, isTrue);
      // Roles set already: left.
      expect(after.roles, before.roles);
    });

    test('moved to another port: there', () {
      final provider = Magpie.provider('magpie');
      expect(identical(Magpie.at(provider, 3425), provider), isTrue);
      final moved = Magpie.at(provider, 4000);
      expect(moved.baseUrl, 'http://127.0.0.1:4000');
      expect(
        moved.modelsUrl,
        'http://127.0.0.1:4000/v1/models?kind=chat,image',
      );
    });

    test('kept with what it follows; a copy does not follow', () async {
      final store = ModelProviders.memory();
      await store.save(Magpie.provider('magpie'));
      expect(store.provider('magpie')!.followsMagpie, isTrue);
      final copy = await store.duplicate('magpie', 'mine');
      expect(store.provider(copy)!.followsMagpie, isFalse);
    });
  });

  group('magpie here', () {
    late HttpServer server;
    late Directory home;
    final asked = <Uri>[];
    final keys = <String?>[];

    setUp(() async {
      HttpOverrides.global = null;
      asked.clear();
      keys.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        asked.add(request.uri);
        keys.add(request.headers.value('authorization'));
        final response = request.response;
        switch (request.uri.path) {
          case '/api/hello':
            response.write(jsonEncode({'name': 'magpie', 'version': '0.13.0'}));
          case '/v1/models':
            response.write(jsonEncode(_catalog));
          default:
            response.statusCode = 404;
        }
        await response.close();
      });
      home = await Directory.systemTemp.createTemp('magpie-home');
      final magpie = Directory(p.join(home.path, '.config', 'magpie'));
      await magpie.create(recursive: true);
      await File(p.join(magpie.path, 'settings.json'))
          .writeAsString(jsonEncode({'theme': 'system', 'port': server.port}));
      final claude = Directory(p.join(home.path, '.claude'));
      await claude.create();
      await File(p.join(claude.path, 'settings.json')).writeAsString(
        jsonEncode({
          'model': 'claude/claude-opus-5-5',
          'env': {'ANTHROPIC_BASE_URL': 'http://127.0.0.1:${server.port}'},
        }),
      );
      ClaudeEnvironment.use({'HOME': home.path, 'USERPROFILE': home.path});
    });

    tearDown(() async {
      await server.close(force: true);
      ClaudeEnvironment.use(null);
      await home.delete(recursive: true);
    });

    test('found at the port its settings name', () async {
      final status = await probeMagpie();
      expect(status.installed, isTrue);
      expect(status.port, server.port);
      expect(status.version, '0.13.0');
    });

    test('not running: installed, no version', () async {
      final port = server.port;
      await server.close(force: true);
      final status = await probeMagpie();
      expect(status.installed, isTrue);
      expect(status.port, port);
      expect(status.running, isFalse);
    });

    test(
      'joined: an upstream with magpie\'s models, under BaoCode\'s key',
      () async {
        final store = ModelProviders.memory();
        final follow = MagpieFollow(providers: store);
        final id = await follow.join();
        await follow.sync();
        final provider = store.provider(id)!;
        expect(provider.followsMagpie, isTrue);
        expect(provider.baseUrl, 'http://127.0.0.1:${server.port}');
        expect(await store.key(id), Magpie.key);
        expect(provider.enabledModels.map((m) => m.id), [
          'claude/claude-opus-5-5',
          'auto/claude-opus-5-5',
        ]);
        expect(provider.roles.main, 'claude/claude-opus-5-5');
        expect(provider.imageModels.single.id, 'yiyuan/gpt-image-2');
        final list = asked.lastWhere((uri) => uri.path == '/v1/models');
        expect(list.queryParameters['kind'], 'chat,image');
        expect(keys.last, 'Bearer ${Magpie.key}');
        expect(follow.status!.running, isTrue);
      },
    );
  });
}

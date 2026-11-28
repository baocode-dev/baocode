import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:baocode/customize/customization_store.dart';
import 'package:baocode/customize/plugin_ui_slots.dart';

void main() {
  late Directory temp;
  late String home;
  late String config;
  late String project;
  late CustomizationStore store;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('plugin_ui_slots');
    home = p.join(temp.path, 'home');
    config = p.join(home, '.claude');
    project = p.join(temp.path, 'app');
    store = CustomizationStore(configDir: config, homeDir: home);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('parses abovePrompt toggle and button slots and ignores others', () {
    final slots = PluginUiSlot.parseAbovePrompt('speak-toggle', {
      'ui': {
        'slots': [
          {
            'slot': 'abovePrompt',
            'type': 'toggle',
            'label': {'on': 'Speak: On', 'off': 'Speak: Off'},
            'state': {
              'file': '~/.claude/switches/speak.json',
              'key': 'isOn',
              'default': true,
            },
            'on': {
              'type': 'writeFile',
              'file': '~/.claude/switches/speak.json',
              'content': '{"isOn":true}',
            },
            'off': {
              'type': 'writeFile',
              'file': '~/.claude/switches/speak.json',
              'content': '{"isOn":false}',
            },
          },
          {
            'slot': 'abovePrompt',
            'type': 'button',
            'label': 'Ping TTS',
            'action': {
              'type': 'http',
              'method': 'post',
              'url': 'http://127.0.0.1:8010/api/speak',
              'body': '{"text":"hi"}',
            },
          },
          {
            'slot': 'abovePrompt',
            'type': 'button',
            'label': 'Blocked Remote',
            'action': {'type': 'http', 'url': 'https://example.com/hook'},
          },
          {
            'slot': 'sidebar',
            'type': 'button',
            'label': 'Ignored Slot',
            'action': {'type': 'http', 'url': 'http://localhost:8010/ping'},
          },
        ],
      },
    });

    expect(slots, hasLength(2));
    expect(slots[0].kind, PluginSlotKind.toggle);
    expect(slots[0].labelFor(on: true), 'Speak: On');
    expect(slots[0].labelFor(on: false), 'Speak: Off');
    expect(slots[0].stateDefault, isTrue);

    expect(slots[1].kind, PluginSlotKind.button);
    expect(slots[1].onLabel, 'Ping TTS');
    final action = slots[1].action!;
    expect(action.method, 'POST');
    expect(action.url.toString(), 'http://127.0.0.1:8010/api/speak');
  });

  test('confines file paths to Claude config directory', () {
    final paths = p.Context(style: p.Style.posix);
    expect(
      resolvePluginConfigPath(
        '~/.claude/switches/speak.json',
        configDir: '/Users/me/.claude',
        homeDir: '/Users/me',
        paths: paths,
      ),
      '/Users/me/.claude/switches/speak.json',
    );
    expect(
      resolvePluginConfigPath(
        'switches/speak.json',
        configDir: '/Users/me/.claude',
        homeDir: '/Users/me',
        paths: paths,
      ),
      '/Users/me/.claude/switches/speak.json',
    );
    for (final escaped in [
      '~/secret.json',
      '~/.claude/../.ssh/id_rsa',
      '/etc/passwd',
      '../outside.json',
    ]) {
      expect(
        resolvePluginConfigPath(
          escaped,
          configDir: '/Users/me/.claude',
          homeDir: '/Users/me',
          paths: paths,
        ),
        isNull,
        reason: escaped,
      );
    }
  });

  test('allows only loopback HTTP(S) URIs', () {
    for (final allowed in [
      'http://127.0.0.1:8010/api/speak',
      'http://localhost:8770/ping',
      'https://[::1]:8443/hook',
    ]) {
      expect(isLoopbackHttpUri(Uri.parse(allowed)), isTrue, reason: allowed);
    }
    for (final blocked in [
      'https://example.com/api',
      'http://192.168.1.10/api',
      'file:///Users/me/.claude/settings.json',
    ]) {
      expect(isLoopbackHttpUri(Uri.parse(blocked)), isFalse, reason: blocked);
    }
  });

  test(
    'loads enabled plugin slots, toggles file state, and runs HTTP',
    () async {
      final enabledRoot = p.join(config, 'plugins', 'cache', 'speak');
      final disabledRoot = p.join(config, 'plugins', 'cache', 'muted');
      write(
        p.join(config, 'settings.json'),
        jsonEncode({
          'enabledPlugins': {'speak@local': true, 'muted@local': false},
        }),
      );
      write(
        p.join(config, 'plugins', 'installed_plugins.json'),
        jsonEncode({
          'version': 2,
          'plugins': {
            'speak@local': [
              {'installPath': enabledRoot},
            ],
            'muted@local': [
              {'installPath': disabledRoot},
            ],
          },
        }),
      );
      write(
        p.join(enabledRoot, '.claude-plugin', 'plugin.json'),
        jsonEncode({
          'name': 'speak',
          'ui': {
            'slots': [
              {
                'slot': 'abovePrompt',
                'type': 'toggle',
                'label': {'on': 'Speak: On', 'off': 'Speak: Off'},
                'state': {
                  'file': '~/.claude/switches/speak.json',
                  'key': 'isOn',
                },
                'on': {
                  'type': 'writeFile',
                  'file': '~/.claude/switches/speak.json',
                  'content': '{"isOn":true}',
                },
                'off': {
                  'type': 'writeFile',
                  'file': '~/.claude/switches/speak.json',
                  'content': '{"isOn":false}',
                },
              },
              {
                'slot': 'abovePrompt',
                'type': 'button',
                'label': 'Stop',
                'action': {
                  'type': 'http',
                  'method': 'POST',
                  'url': 'http://127.0.0.1:8010/api/stop',
                },
              },
            ],
          },
        }),
      );
      write(
        p.join(disabledRoot, '.claude-plugin', 'plugin.json'),
        jsonEncode({
          'name': 'muted',
          'ui': {
            'slots': [
              {
                'slot': 'abovePrompt',
                'type': 'button',
                'label': 'Should Not Load',
                'action': {
                  'type': 'http',
                  'url': 'http://127.0.0.1:8010/ignored',
                },
              },
            ],
          },
        }),
      );

      final called = <String>[];
      final runner = PluginUiSlotRunner(
        store: store,
        sendHttp: (url, {method = 'POST', headers = const {}, body}) async {
          called.add('$method $url');
        },
      );

      final slots = await runner.loadAbovePrompt(project: project);
      expect(slots, hasLength(2));
      expect(await runner.readToggleState(slots[0]), isFalse);

      await runner.runAction(slots[0].onAction!);
      expect(await runner.readToggleState(slots[0]), isTrue);

      await runner.runAction(slots[0].offAction!);
      expect(await runner.readToggleState(slots[0]), isFalse);

      await runner.runAction(slots[1].action!);
      expect(called, ['POST http://127.0.0.1:8010/api/stop']);

      await expectLater(
        runner.runAction(
          const PluginSlotAction.writeFile('~/escape.json', '{}'),
        ),
        throwsArgumentError,
      );
    },
  );
}

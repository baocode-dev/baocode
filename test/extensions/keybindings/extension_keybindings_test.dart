// Extensions' `contributes.keybindings`: parsing, the platform keys, the
// `when` clause with the command's `enablement`, the weights and how they
// reach the app's keybinding service.

import 'package:bao_exthost/bao_exthost.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/extensions/commands/extension_command_registry.dart';
import 'package:baocode/extensions/contextkey/context_key_service.dart';
import 'package:baocode/extensions/keybindings/extension_keybindings.dart';
import 'package:baocode/keybindings/key_chord.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _extension(String id, List<Object?> keybindings) => {
  'identifier': {'value': id},
  'name': id.split('.').last,
  'displayName': id,
  'extensionLocation': VsUri.file('/ext/$id').toJson(),
  'contributes': {
    'commands': [
      {'command': 'ext.toggle', 'title': 'Toggle', 'enablement': 'editorTextFocus'},
      {'command': 'ext.refresh', 'title': 'Refresh'},
    ],
    'keybindings': keybindings,
  },
};

void main() {
  test('parses contributions, with the command\'s enablement', () {
    final registry = ExtensionCommandRegistry()
      ..setExtensions([
        _extension('pub.ext', [
          {
            'command': 'ext.toggle',
            'key': 'ctrl+alt+t',
            'mac': 'cmd+alt+t',
            'when': 'editorFocus',
          },
          {'command': 'ext.refresh', 'key': 'ctrl+shift+r'},
          {'command': 'ext.refresh'}, // no key for this platform: dropped
          {'command': 'ext.refresh', 'key': 3}, // invalid: reported
        ]),
      ]);
    final keybindings = ExtensionKeybindings(
      registry.extensions,
      commands: registry.contributions,
    );
    expect(keybindings.rules, hasLength(2));
    final toggle = keybindings.rules.singleWhere(
      (r) => r.command == 'ext.toggle',
    );
    expect(toggle.entry.mac, 'cmd+alt+t');
    // `editorFocus` (its `when`) && `editorTextFocus` (the command's
    // `enablement`), normalized.
    expect(toggle.when!.serialize(), 'editorFocus && editorTextFocus');
    expect(toggle.weight, KeybindingWeight.externalExtension + 1);
    expect(keybindings.messages, hasLength(1));
  });

  test('built-in extensions weigh less, and order breaks ties', () {
    final registry = ExtensionCommandRegistry();
    registry.setExtensions([
      {
        ..._extension('pub.builtin', [
          {'command': 'ext.refresh', 'key': 'ctrl+k'},
        ]),
        'isBuiltin': true,
      },
      _extension('pub.ext', [
        {'command': 'ext.toggle', 'key': 'ctrl+j'},
      ]),
    ]);
    final keybindings = ExtensionKeybindings(
      registry.extensions,
      commands: registry.contributions,
    );
    expect(keybindings.rules.first.isBuiltin, isTrue);
    expect(keybindings.rules.first.weight, KeybindingWeight.builtinExtension + 1);
    expect(keybindings.rules.last.weight, KeybindingWeight.externalExtension + 1);
  });

  test('reaches the app\'s keybinding service, over its defaults', () {
    // BaoCode has a default for the same key, on another command.
    final service = KeybindingService(
      defaults: [
        const KeybindingEntry(command: 'app.other', key: 'ctrl+alt+t'),
      ],
      commands: const {'app.other': null},
    );
    final registry = ExtensionCommandRegistry()
      ..setExtensions([
        _extension('pub.ext', [
          {
            'command': 'ext.toggle',
            'key': 'ctrl+alt+t',
            'when': 'editorTextFocus',
          },
        ]),
      ]);
    final keys = ContextKeyService();
    final bridge = ExtensionKeybindingsBridge(
      registry: registry,
      contextKeys: keys,
      keybindings: service,
    );
    addTearDown(bridge.dispose);
    registry.registerExtensionCommand('ext.toggle', (id, args) async => null);
    expect(service.isSupported('ext.toggle'), isTrue);
    final chord = KeyChord.parse('ctrl+alt+t')!;
    var ran = <String>[];
    service.contextKeys.isNotEmpty; // the app's known keys
    void press() {
      // The service rebuilds its resolvers when what is in them changes.
      final resolver = service.resolver(KeybindingPlatform.linux);
      final result = resolver.resolve(
        (key) => keys.getContextKeyValue(key),
        const [],
        chord,
        canRun: (item) => service.isSupported(item.command),
      );
      if (result case KeybindingFound(:final command)) ran.add(command);
    }

    keys.setContext('editorTextFocus', true);
    press();
    // Without the clause it does not apply: the app's default does.
    keys.setContext('editorTextFocus', false);
    press();
    expect(ran, ['ext.toggle', 'app.other']);
    // The extension's keybinding is a default: the user's wins over it.
    service.userEntries = const [
      KeybindingEntry(command: 'app.other', key: 'ctrl+alt+t'),
    ];
    ran = [];
    keys.setContext('editorTextFocus', true);
    press();
    expect(ran, ['app.other']);
  });

  test('a removed extension keybinding stops resolving', () {
    final service = KeybindingService(
      defaults: const [],
      commands: const {},
    );
    final registry = ExtensionCommandRegistry()
      ..setExtensions([
        _extension('pub.ext', [
          {'command': 'ext.refresh', 'key': 'ctrl+alt+y'},
        ]),
      ]);
    final bridge = ExtensionKeybindingsBridge(
      registry: registry,
      contextKeys: ContextKeyService(),
      keybindings: service,
    );
    addTearDown(bridge.dispose);
    registry.registerExtensionCommand('ext.refresh', (id, args) async => null);
    expect(bridge.current.rules, hasLength(1));
    // The extension is gone: its keybindings go with it.
    registry.setExtensions(const []);
    expect(bridge.current.rules, isEmpty);
    expect(service.isSupported('ext.refresh'), isFalse);
  });

  test('the command\'s enablement is part of the clause', () {
    final registry = ExtensionCommandRegistry()
      ..setExtensions([
        _extension('pub.ext', [
          {'command': 'ext.toggle', 'key': 'ctrl+alt+t'},
        ]),
      ]);
    final keybindings = ExtensionKeybindings(
      registry.extensions,
      commands: registry.contributions,
    );
    expect(keybindings.rules.single.when!.serialize(), 'editorTextFocus');
  });

  test('platform keys, chords and args survive', () {
    final registry = ExtensionCommandRegistry()
      ..setExtensions([
        _extension('pub.ext', [
          {
            'command': 'ext.refresh',
            'key': 'ctrl+k ctrl+r',
            'mac': 'cmd+k cmd+r',
            'linux': 'ctrl+shift+r',
            'args': {'full': true},
          },
        ]),
      ]);
    final keybindings = ExtensionKeybindings(
      registry.extensions,
      commands: registry.contributions,
    );
    final entry = keybindings.rules.single.entry;
    expect(entry.keyFor(KeybindingPlatform.mac), 'cmd+k cmd+r');
    expect(entry.keyFor(KeybindingPlatform.linux), 'ctrl+shift+r');
    expect(entry.keyFor(KeybindingPlatform.windows), 'ctrl+k ctrl+r');
    expect(entry.args, {'full': true});
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/keybindings/default_keybindings.dart';
import 'package:baocode/keybindings/key_chord.dart';
import 'package:baocode/keybindings/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_resolver.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/keybindings/keymap.dart';
import 'package:baocode/settings/jsonc.dart';

import 'fake_home.dart';

const _mac = KeybindingPlatform.mac;

List<KeybindingItem> _items(
  List<KeybindingEntry> entries,
  KeybindingSource source,
) => [
  for (final (index, entry) in entries.indexed)
    KeybindingItem(entry: entry, source: source, platform: _mac, index: index),
];

KeybindingResolver _resolver(
  List<KeybindingEntry> defaults, [
  List<KeybindingEntry> user = const [],
]) => KeybindingResolver(
  _items(defaults, KeybindingSource.defaults),
  _items(user, KeybindingSource.user),
  knownContextKeys: knownContextKeys,
);

KeyChord _chord(String text) => KeyChord.parse(text)!;

String? _run(
  KeybindingResolver resolver,
  String keys, {
  Map<String, Object?> context = const {},
}) {
  final chords = KeySequence.parse(keys)!.chords;
  final result = resolver.resolve(
    (key) => context[key],
    chords.sublist(0, chords.length - 1),
    chords.last,
  );
  return switch (result) {
    KeybindingFound(:final command) => command,
    MoreChordsNeeded() => '…',
    NoKeybinding() => null,
  };
}

void main() {
  group('KeybindingResolver', () {
    test('the last applicable keybinding wins', () {
      final resolver = _resolver(const [
        KeybindingEntry(command: 'a', key: 'cmd+k'),
        KeybindingEntry(command: 'b', key: 'cmd+k', when: 'editorTextFocus'),
      ]);
      expect(_run(resolver, 'cmd+k'), 'a');
      expect(_run(resolver, 'cmd+k', context: {'editorTextFocus': true}), 'b');
    });

    test("the user's override the defaults", () {
      final resolver = _resolver(
        const [KeybindingEntry(command: 'a', key: 'cmd+k')],
        const [KeybindingEntry(command: 'b', key: 'cmd+k')],
      );
      expect(_run(resolver, 'cmd+k'), 'b');
      // The default one is shadowed: nothing shows it for `a` any more.
      expect(resolver.lookupPrimaryKeybinding('a'), isNull);
      expect(
        resolver.lookupPrimaryKeybinding('b')!.source,
        KeybindingSource.user,
      );
    });

    test('-command removes default keybindings, by key and when', () {
      final defaults = const [
        KeybindingEntry(command: 'a', key: 'cmd+k'),
        KeybindingEntry(command: 'a', key: 'cmd+j', when: 'editorTextFocus'),
        KeybindingEntry(command: 'b', key: 'cmd+l'),
      ];
      var resolver = _resolver(defaults, const [
        KeybindingEntry(command: '-a', key: 'cmd+k'),
      ]);
      expect(_run(resolver, 'cmd+k'), isNull);
      expect(_run(resolver, 'cmd+j', context: {'editorTextFocus': true}), 'a');
      // Without a key, every one of the command's (matching the when).
      resolver = _resolver(defaults, const [KeybindingEntry(command: '-a')]);
      expect(resolver.lookupKeybindings('a'), isEmpty);
      expect(_run(resolver, 'cmd+l'), 'b');
      resolver = _resolver(defaults, const [
        KeybindingEntry(command: '-a', when: 'editorTextFocus'),
      ]);
      expect(
        resolver.lookupKeybindings('a').single.keys,
        KeySequence.parse('cmd+k'),
      );
    });

    test("a removal leaves the user's own keybindings", () {
      final resolver = _resolver(const [], const [
        KeybindingEntry(command: 'a', key: 'cmd+k'),
        KeybindingEntry(command: '-a', key: 'cmd+k'),
      ]);
      expect(_run(resolver, 'cmd+k'), 'a');
    });

    test('a sequence waits for its next chord', () {
      final resolver = _resolver(const [
        KeybindingEntry(command: 'settings', key: 'cmd+k cmd+s'),
        KeybindingEntry(command: 'theme', key: 'cmd+k cmd+t'),
      ]);
      final first = resolver.resolve((_) => null, const [], _chord('cmd+k'));
      expect(first, isA<MoreChordsNeeded>());
      expect((first as MoreChordsNeeded).chords, [_chord('cmd+k')]);
      expect(_run(resolver, 'cmd+k cmd+s'), 'settings');
      expect(_run(resolver, 'cmd+k cmd+t'), 'theme');
      expect(_run(resolver, 'cmd+k cmd+x'), isNull);
    });

    test('a when with an unknown key or that does not parse never holds', () {
      final resolver = _resolver(const [
        KeybindingEntry(command: 'a', key: 'cmd+k'),
        KeybindingEntry(command: 'b', key: 'cmd+k', when: 'someExtensionKey'),
        KeybindingEntry(command: 'c', key: 'cmd+j', when: 'a =~ /x/'),
      ]);
      expect(_run(resolver, 'cmd+k', context: {'someExtensionKey': true}), 'a');
      expect(_run(resolver, 'cmd+j'), isNull);
      expect(resolver.items[1].unknownContextKeys(knownContextKeys), {
        'someExtensionKey',
      });
    });

    test('a keybinding whose command cannot run leaves the key', () {
      final resolver = _resolver(
        const [KeybindingEntry(command: 'a', key: 'cmd+k')],
        const [KeybindingEntry(command: 'missing', key: 'cmd+k')],
      );
      final result = resolver.resolve(
        (_) => null,
        const [],
        _chord('cmd+k'),
        canRun: (item) => item.command != 'missing',
      );
      expect((result as KeybindingFound).command, 'a');
    });

    test('the primary keybinding is the last one', () {
      final resolver = _resolver(const [
        KeybindingEntry(command: 'palette', key: 'f1'),
        KeybindingEntry(command: 'palette', key: 'shift+cmd+p'),
      ]);
      expect(
        resolver.lookupPrimaryKeybinding('palette')!.keys,
        KeySequence.parse('shift+cmd+p'),
      );
      expect(
        resolver.itemsWithKeys(KeySequence.parse('f1')!).single.command,
        'palette',
      );
    });

    test('a key that does not parse is reported', () {
      final item = KeybindingItem(
        entry: const KeybindingEntry(command: 'a', key: 'cmd+nonsense'),
        source: KeybindingSource.user,
        platform: _mac,
      );
      expect(item.keys, isNull);
      expect(item.keyError(_mac), 'cmd+nonsense');
    });
  });

  group('the default keybindings', () {
    final service = KeybindingService()..debugPlatform = _mac;

    test('every command they bind is in the catalog', () {
      for (final entry in defaultKeybindings) {
        expect(commandCatalog, contains(entry.commandId), reason: '$entry');
        expect(
          entry.keyFor(_mac) == null ||
              KeySequence.parse(entry.keyFor(_mac)!) != null,
          isTrue,
          reason: '$entry',
        );
      }
    });

    test('are labelled as VS Code labels them', () {
      expect(service.labelFor('workbench.action.showCommands'), '⇧⌘P');
      expect(service.labelFor(openSettingsCommandId), '⌘,');
      expect(service.labelFor(openKeybindingsCommandId), '⌘K ⌘S');
      expect(
        service.labelFor(
          'workbench.action.showCommands',
          platform: KeybindingPlatform.windows,
        ),
        'Ctrl+Shift+P',
      );
      expect(
        service.labelFor(
          'workbench.action.navigateBack',
          platform: KeybindingPlatform.windows,
        ),
        'Alt+LeftArrow',
      );
      expect(service.labelFor('workbench.action.navigateBack'), '⌃-');
    });

    test("a button's tooltip: its title and its command's keys, as the "
        'user binds them', () {
      final service = KeybindingService()..debugPlatform = _mac;
      expect(
        service.titleWithKeybinding(
          'Toggle Primary Side Bar',
          'workbench.action.toggleSidebarVisibility',
        ),
        'Toggle Primary Side Bar (⌘B)',
      );
      // None: the title alone.
      expect(
        service.titleWithKeybinding(
          'Refresh',
          'workbench.files.action.refresh',
        ),
        'Refresh',
      );
      var heard = 0;
      service
        ..addListener(() => heard++)
        ..userEntries = const [
          KeybindingEntry(
            command: '-workbench.action.toggleSidebarVisibility',
            key: 'cmd+b',
          ),
          KeybindingEntry(
            command: 'workbench.action.toggleSidebarVisibility',
            key: 'cmd+k cmd+b',
          ),
        ];
      expect(heard, 1);
      expect(
        service.titleWithKeybinding(
          '切换主侧栏',
          'workbench.action.toggleSidebarVisibility',
        ),
        '切换主侧栏 (⌘K ⌘B)',
      );
    });
  });

  group('KeybindingService', () {
    late KeybindingService service;

    setUp(() => service = KeybindingService()..debugPlatform = _mac);

    KeybindingResolution press(
      String chord, {
      Map<String, Object?> context = const {},
      List<KeyChord> pending = const [],
    }) => service.resolver().resolve(
      service.withPlatformKeys((key) => context[key]),
      pending,
      _chord(chord),
      canRun: (item) => service.isSupported(item.command),
    );

    String? command(String chord, {Map<String, Object?> context = const {}}) =>
        switch (press(chord, context: context)) {
          KeybindingFound(:final command) => command,
          _ => null,
        };

    test('notifies and resolves again when the keybindings change', () {
      var notified = 0;
      service.addListener(() => notified++);
      expect(command('cmd+b'), 'workbench.action.toggleSidebarVisibility');
      service.userEntries = const [
        KeybindingEntry(command: 'workbench.view.explorer', key: 'cmd+b'),
      ];
      expect(notified, 1);
      expect(command('cmd+b'), 'workbench.view.explorer');
      service.userEntries = const [
        KeybindingEntry(command: 'workbench.view.explorer', key: 'cmd+b'),
      ];
      expect(notified, 1, reason: 'the same entries change nothing');
    });

    test('isMac and the like are filled in', () {
      service.userEntries = const [
        KeybindingEntry(
          command: 'workbench.view.explorer',
          key: 'cmd+b',
          when: 'isMac',
        ),
      ];
      expect(command('cmd+b'), 'workbench.view.explorer');
      service.debugPlatform = KeybindingPlatform.windows;
      expect(
        service
            .primaryKeybinding('workbench.view.explorer', context: (_) => null)!
            .source,
        KeybindingSource.defaults,
      );
    });

    test("a command it does not have is kept, but never runs", () {
      service.userEntries = const [
        KeybindingEntry(command: 'cursor.somethingElse', key: 'cmd+b'),
      ];
      expect(service.isSupported('cursor.somethingElse'), isFalse);
      expect(command('cmd+b'), 'workbench.action.toggleSidebarVisibility');
      expect(
        service.resolver().items.where(
          (i) => i.source == KeybindingSource.user,
        ),
        hasLength(1),
      );
    });

    test('registers the keybindings of commands the catalog lacks', () {
      service.registerExtraDefaults(const [
        KeybindingEntry(command: 'baocode.extra', key: 'cmd+k cmd+x'),
      ]);
      expect(service.isSupported('baocode.extra'), isTrue);
      expect(service.labelFor('baocode.extra'), '⌘K ⌘X');
    });

    test('resolves a key event, by its character too', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyP,
        logicalKey: LogicalKeyboardKey.keyP,
        character: 'p',
        timeStamp: Duration.zero,
      );
      service.userEntries = const [
        KeybindingEntry(command: 'workbench.view.explorer', key: 'p'),
      ];
      final result = service.resolveEvent(event, context: (_) => null);
      expect((result as KeybindingFound).command, 'workbench.view.explorer');
      expect(
        service.resolveEvent(
          KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.keyP,
            logicalKey: LogicalKeyboardKey.keyP,
            timeStamp: Duration.zero,
          ),
          context: (_) => null,
        ),
        isA<NoKeybinding>(),
      );
    });

    group("the user's keybindings over the Atom keymap", () {
      setUp(() {
        final atom = Keymap.fromJson(
          jsonDecode(
            File('assets/keymaps/ms-vscode.atom-keybindings.json')
                .readAsStringSync(),
          ),
          builtIn: true,
        )!;
        service
          ..setKeymap(atom.id, name: atom.name, entries: atom.entries)
          ..userEntries = KeybindingEntry.listFromJson(
            parseJsonc(codeKeybindings),
          );
      });

      test('⌘E and ⇧⌘E go back and forward, when they can', () {
        const both = {'canNavigateBack': true, 'canNavigateForward': true};
        expect(
          command('cmd+e', context: both),
          'workbench.action.navigateBack',
        );
        expect(
          command('shift+cmd+e', context: both),
          'workbench.action.navigateForward',
        );
        expect(
          command('cmd+e', context: const {'canNavigateForward': true}),
          isNot('workbench.action.navigateBack'),
        );
        expect(service.labelFor('workbench.action.navigateBack'), '⌘E');
      });

      test("⌘1 toggles the side bar, over Atom's ⌘1", () {
        expect(
          service.keymapEntries.any(
            (e) =>
                e.mac == 'cmd+1' &&
                e.command == 'workbench.action.openEditorAtIndex1',
          ),
          isTrue,
        );
        expect(command('cmd+1'), 'workbench.action.toggleSidebarVisibility');
        expect(
          command('cmd+1', context: const {'editorTextFocus': true}),
          'workbench.action.toggleSidebarVisibility',
        );
        // Atom's ⌘1 no longer shows for the first editor.
        expect(
          service.labelFor('workbench.action.openEditorAtIndex1'),
          isNot('⌘1'),
        );
      });

      test('⌘2 the terminal, ⌘3 the chat', () {
        expect(command('cmd+2'), 'workbench.action.terminal.toggleTerminal');
        expect(command('cmd+3'), 'workbench.action.toggleAuxiliaryBar');
      });

      test("Atom's other keybindings apply", () {
        expect(command('cmd+4'), 'workbench.action.openEditorAtIndex4');
        final sources = {
          for (final item in service.resolver().items) item.source,
        };
        expect(sources, KeybindingSource.values.toSet());
        expect(
          service
              .primaryKeybinding('workbench.action.openEditorAtIndex4')!
              .keymapName,
          'Atom',
        );
      });
    });
  });
}

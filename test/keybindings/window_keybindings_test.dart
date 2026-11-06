import 'package:baocode/keybindings/chat_keybindings.dart';
import 'package:baocode/keybindings/default_keybindings.dart';
import 'package:baocode/keybindings/key_chord.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/keybindings/window_keybindings.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the window\'s commands are in the catalog', () {
    for (final info in windowCommands) {
      expect(commandCatalog, contains(info.id));
    }
  });

  test('their keys parse everywhere, and their `when` clauses read only '
      'the context keys there are', () {
    for (final entry in windowKeybindings) {
      expect(commandCatalog, contains(entry.command), reason: entry.command);
      for (final platform in KeybindingPlatform.values) {
        final item = KeybindingItem(
          entry: entry,
          source: KeybindingSource.defaults,
          platform: platform,
        );
        expect(item.keyError(platform), isNull, reason: '$entry');
        expect(item.when?.error, isNull, reason: '$entry');
        expect(
          item.unknownContextKeys(knownContextKeys),
          isEmpty,
          reason: '$entry',
        );
      }
    }
  });

  group('Close Pane\'s keys (⌘W / Ctrl+W) in the chat\'s window', () {
    final service = KeybindingService()..debugPlatform = KeybindingPlatform.mac;

    KeybindingResolution press(String chord, Map<String, Object?> context) =>
        service.resolver().resolve(
          service.withPlatformKeys((key) => context[key]),
          const [],
          KeyChord.parse(chord)!,
          canRun: (item) => service.isSupported(item.command),
        );

    String? command(String chord, Map<String, Object?> context) =>
        switch (press(chord, context)) {
          KeybindingFound(:final command) => command,
          _ => null,
        };

    test('closes the focused pane where another shows beside it', () {
      expect(
        command('cmd+w', const {'chatMode': true, 'chatSinglePane': false}),
        ChatCommandIds.closePane,
      );
    });

    test('closes the window where its last pane is all that shows, as VS '
        'Code\'s Close Window does with no editor open (#457)', () {
      expect(
        command('cmd+w', const {'chatMode': true, 'chatSinglePane': true}),
        WindowCommandIds.closeWindow,
      );
    });

    test('Ctrl+W elsewhere: the same, where it is the window\'s keys', () {
      final windows = KeybindingService()
        ..debugPlatform = KeybindingPlatform.windows;
      final chord = KeyChord.parse('ctrl+w')!;
      final context = windows.withPlatformKeys(
        (key) => const {'chatMode': true, 'chatSinglePane': true}[key],
      );
      expect(
        windows.resolver().resolve(
          context,
          const [],
          chord,
          canRun: (item) => windows.isSupported(item.command),
        ),
        isA<KeybindingFound>().having(
          (found) => found.command,
          'command',
          WindowCommandIds.closeWindow,
        ),
      );
    });

    test('closes the side panel\'s tab first, where it is focused', () {
      expect(
        command('cmd+w', const {
          'chatMode': true,
          'chatSinglePane': true,
          'sidePanelFocus': true,
        }),
        ChatCommandIds.sidePanelCloseTab,
      );
    });

    test('closes the window with no editor open outside the chat, as '
        'before', () {
      expect(
        command('cmd+w', const {'chatMode': false}),
        WindowCommandIds.closeWindow,
      );
    });
  });
}

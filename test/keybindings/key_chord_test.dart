import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/keybindings/key_chord.dart';
import 'package:baocode/keybindings/keybinding_entry.dart';

void main() {
  group('KeyChord.parse', () {
    test('reads modifiers in any order, with + or -', () {
      expect(
        KeyChord.parse('shift+cmd+p'),
        const KeyChord(LogicalKeyboardKey.keyP, shift: true, meta: true),
      );
      expect(KeyChord.parse('cmd-shift-p'), KeyChord.parse('shift+cmd+p'));
      expect(
        KeyChord.parse('ctrl+alt+-'),
        const KeyChord(LogicalKeyboardKey.minus, ctrl: true, alt: true),
      );
      expect(KeyChord.parse('option+a'), KeyChord.parse('alt+a'));
      expect(KeyChord.parse('win+a'), KeyChord.parse('meta+a'));
    });

    test('reads named keys and their aliases', () {
      expect(KeyChord.parse('ctrl+pagedown')!.key, LogicalKeyboardKey.pageDown);
      expect(KeyChord.parse('escape'), KeyChord.parse('esc'));
      expect(KeyChord.parse('f12')!.key, LogicalKeyboardKey.f12);
      expect(KeyChord.parse('ctrl+]')!.key, LogicalKeyboardKey.bracketRight);
      expect(KeyChord.parse(r'shift+cmd+\')!.key, LogicalKeyboardKey.backslash);
      expect(KeyChord.parse('[KeyA]')!.key, LogicalKeyboardKey.keyA);
    });

    test('rejects what is not a key', () {
      expect(KeyChord.parse(''), isNull);
      expect(KeyChord.parse('cmd+'), isNull);
      expect(KeyChord.parse('cmd+nonsense'), isNull);
    });
  });

  group('KeySequence', () {
    test('parses chords separated by spaces', () {
      final sequence = KeySequence.parse('ctrl+k  ctrl+s')!;
      expect(sequence.chords, [
        KeyChord.parse('ctrl+k'),
        KeyChord.parse('ctrl+s'),
      ]);
      expect(KeySequence.parse('ctrl+k nonsense+'), isNull);
    });

    test('labels as each platform writes them', () {
      final palette = KeySequence.parse('shift+cmd+p')!;
      expect(palette.label(KeybindingPlatform.mac), '⇧⌘P');
      expect(palette.userSettingsLabel(KeybindingPlatform.mac), 'shift+cmd+p');
      final settings = KeySequence.parse('ctrl+k ctrl+s')!;
      expect(settings.label(KeybindingPlatform.windows), 'Ctrl+K Ctrl+S');
      expect(settings.label(KeybindingPlatform.mac), '⌃K ⌃S');
      final back = KeySequence.parse('alt+left')!;
      expect(back.label(KeybindingPlatform.windows), 'Alt+LeftArrow');
      expect(back.label(KeybindingPlatform.mac), '⌥←');
      expect(
        KeySequence.parse('ctrl+alt+shift+cmd+k')!
            .label(KeybindingPlatform.mac),
        '⌃⌥⇧⌘K',
      );
    });
  });

  group('KeyChord.fromEvent', () {
    KeyDownEvent down(LogicalKeyboardKey key, {String? character}) =>
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: key,
          character: character,
          timeStamp: Duration.zero,
        );

    testWidgets('reads the modifiers held', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(
        KeyChord.fromEvent(down(LogicalKeyboardKey.keyE)),
        KeyChord.parse('shift+cmd+e'),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(
        KeyChord.fromEvent(down(LogicalKeyboardKey.keyE)),
        KeyChord.parse('e'),
      );
    });

    testWidgets('a modifier alone is no chord', (tester) async {
      expect(KeyChord.fromEvent(down(LogicalKeyboardKey.shiftLeft)), isNull);
      expect(KeyChord.fromEvent(down(LogicalKeyboardKey.metaRight)), isNull);
    });

    testWidgets('a shifted symbol is its key with Shift', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(
        KeyChord.fromEvent(down(LogicalKeyboardKey.braceRight)),
        KeyChord.parse('shift+cmd+]'),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    });
  });
}

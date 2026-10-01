import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../keybindings/key_chord.dart';
import '../keybindings/keybinding_entry.dart';
import '../keybindings/keybinding_service.dart';

/// The keys of the characters [IdeKeybinding.character] matches, as the US
/// layout types them.
const _characterKeys = <String?, LogicalKeyboardKey>{
  '}': LogicalKeyboardKey.bracketRight,
  '{': LogicalKeyboardKey.bracketLeft,
  ']': LogicalKeyboardKey.bracketRight,
  '[': LogicalKeyboardKey.bracketLeft,
};
const _shiftedCharacters = {'}', '{'};

/// Whether keybindings use the macOS conventions (⌘ as the primary modifier
/// and glyph labels). Read at call time so tests can override the platform.
bool get ideUsesMacKeys =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// A single key chord, described once for both its label and its activator.
///
/// [primary] is ⌘ on macOS and Ctrl elsewhere (VS Code's `CtrlCmd`), while
/// [control] is the literal Control key on every platform (VS Code's
/// `WinCtrl` on macOS, e.g. ⌃G). [mac] limits the binding to macOS (`true`) or
/// to the other platforms (`false`).
@immutable
class IdeKeybinding {
  const IdeKeybinding(
    this.key, {
    this.primary = false,
    this.shift = false,
    this.alt = false,
    this.control = false,
    this.mac,
    this.second,
  }) : character = null;

  /// Matches the produced character instead of the key, for chords like
  /// ⇧⌘] whose logical key depends on the keyboard layout.
  const IdeKeybinding.character(
    String this.character, {
    this.primary = false,
    this.alt = false,
    this.control = false,
    this.mac,
  }) : key = null,
       shift = false,
       second = null;

  /// The chord [event] presses, with the modifiers held now (for labels).
  factory IdeKeybinding.pressed(KeyEvent event, {bool? mac}) {
    final isMac = mac ?? ideUsesMacKeys;
    final keyboard = HardwareKeyboard.instance;
    return IdeKeybinding(
      event.logicalKey,
      primary: isMac ? keyboard.isMetaPressed : keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      control: isMac && keyboard.isControlPressed,
    );
  }

  final LogicalKeyboardKey? key;
  final String? character;
  final bool primary;
  final bool shift;
  final bool alt;
  final bool control;
  final bool? mac;

  /// The chord after this one in a two-chord keybinding such as ⌘K ⌘T
  /// (upstream `KeyChord`), which the workbench's chord mode dispatches.
  final IdeKeybinding? second;

  bool appliesTo({required bool mac}) => this.mac == null || this.mac == mac;

  /// As a `keybindings.json` entry binding it to [command] (`cmd+k cmd+t`
  /// on macOS, `ctrl+k ctrl+t` elsewhere); null for one [KeyChord] cannot
  /// read.
  KeybindingEntry? toEntry(String command) {
    String? text({required bool mac}) {
      final chords = <String>[];
      for (IdeKeybinding? chord = this; chord != null; chord = chord.second) {
        final key = chord.key ?? _characterKeys[chord.character];
        if (key == null) return null;
        final platform = mac
            ? KeybindingPlatform.mac
            : KeybindingPlatform.windows;
        chords.add(
          KeyChord(
            key,
            ctrl: chord.control || (chord.primary && !mac),
            shift:
                chord.shift ||
                chord.character != null &&
                    chord.key == null &&
                    _shiftedCharacters.contains(chord.character),
            alt: chord.alt,
            meta: chord.primary && mac,
          ).userSettingsLabel(platform),
        );
      }
      return chords.join(' ');
    }

    final macKey = mac == false ? null : text(mac: true);
    final otherKey = mac == true ? null : text(mac: false);
    if (macKey == null && otherKey == null) return null;
    return KeybindingEntry(
      command: command,
      key: macKey == null || otherKey == null ? null : otherKey,
      mac: macKey,
      win: macKey == null ? otherKey : null,
      linux: macKey == null ? otherKey : null,
    );
  }

  /// For a two-chord keybinding, its first chord's.
  ShortcutActivator activator({bool? mac}) {
    final isMac = mac ?? ideUsesMacKeys;
    final meta = primary && isMac;
    final ctrl = control || (primary && !isMac);
    if (character case final character?) {
      return CharacterActivator(character, alt: alt, control: ctrl, meta: meta);
    }
    return SingleActivator(
      key!,
      shift: shift,
      alt: alt,
      control: ctrl,
      meta: meta,
    );
  }

  /// `⇧⌘P` on macOS, `Ctrl+Shift+P` elsewhere (VS Code's label order); a
  /// space between two chords (`⌘K ⌘T`).
  String label({bool? mac}) {
    final isMac = mac ?? ideUsesMacKeys;
    if (second case final second?) {
      return '${_chordLabel(isMac)} ${second.label(mac: isMac)}';
    }
    return _chordLabel(isMac);
  }

  String _chordLabel(bool isMac) {
    final keyLabel = character ?? _keyLabel(key!, isMac);
    final ctrl = control || (primary && !isMac);
    if (isMac) {
      return [
        if (ctrl) '⌃',
        if (alt) '⌥',
        if (shift) '⇧',
        if (primary) '⌘',
        keyLabel,
      ].join();
    }
    return [
      if (ctrl) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      keyLabel,
    ].join('+');
  }

  static String _keyLabel(LogicalKeyboardKey key, bool mac) {
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.escape) return 'Escape';
    if (key == LogicalKeyboardKey.backspace) return 'Backspace';
    if (key == LogicalKeyboardKey.arrowUp) return mac ? '↑' : 'UpArrow';
    if (key == LogicalKeyboardKey.arrowDown) return mac ? '↓' : 'DownArrow';
    if (key == LogicalKeyboardKey.arrowLeft) return mac ? '←' : 'LeftArrow';
    if (key == LogicalKeyboardKey.arrowRight) return mac ? '→' : 'RightArrow';
    if (key == LogicalKeyboardKey.bracketLeft) return '[';
    if (key == LogicalKeyboardKey.bracketRight) return ']';
    if (key == LogicalKeyboardKey.backquote) return '`';
    if (key == LogicalKeyboardKey.slash) return '/';
    if (key == LogicalKeyboardKey.backslash) return '\\';
    final label = key.keyLabel;
    return label.length == 1 ? label.toUpperCase() : label;
  }
}

/// [withKeys]' text with [keys], a command's keybinding label, or without
/// them and their parentheses when the command has none (a tooltip's
/// `Toggle Panel (⌃`)`).
String ideWithKeybinding(String Function(String keys) withKeys, String? keys) =>
    keys != null
    ? withKeys(keys)
    : withKeys('\u0000').replaceAll(RegExp('\\s*[(（]\u0000[)）]'), '');

/// One entry of the command palette and, for workbench commands, a shortcut.
///
/// Keybindings of workbench-owned commands are registered at the workbench
/// level. Editor-supplied commands (`IdeEditorState.editorCommands`) show their
/// keybinding labels in the palette but the editor dispatches those keys itself.
@immutable
class IdeCommand {
  const IdeCommand({
    required this.id,
    required this.label,
    required this.run,
    this.runWithArgs,
    this.category,
    this.keybindings = const [],
    this.keybindingLabel,
    this.enabled = true,
  });

  final String id;
  final String label;
  final String? category;
  final List<IdeKeybinding> keybindings;

  /// Overrides the label derived from [keybindings] (e.g. for chords).
  final String? keybindingLabel;
  final VoidCallback run;

  /// Runs it with a keybinding's `args` (upstream `executeCommand(id,
  /// args)`, e.g. `workbench.action.terminal.sendSequence`'s `{"text":
  /// …}`); [run] runs it without any. Null: it takes none.
  final void Function(Object? args)? runWithArgs;
  final bool enabled;

  /// Runs it with [args] (a keybinding's), as [runWithArgs] reads them;
  /// [run] when it takes none, or there are none.
  void invoke([Object? args]) {
    final withArgs = runWithArgs;
    if (withArgs != null && args != null) {
      withArgs(args);
    } else {
      run();
    }
  }

  /// `Category: Label`, as the palette lists and matches it.
  String get title => category == null ? label : '$category: $label';

  /// Its keybinding for the current platform (or macOS's, or another's),
  /// formatted for display: the one the app's keybindings show for it (see
  /// [KeybindingService.labelFor]), the user's and the keymap's included.
  String? shortcutLabel({bool? mac}) {
    if (keybindingLabel != null) return keybindingLabel;
    final service = KeybindingService.instance;
    final isMac = mac ?? ideUsesMacKeys;
    if (service.isSupported(id)) {
      final platform = isMac
          ? KeybindingPlatform.mac
          : service.platform == KeybindingPlatform.mac
          ? KeybindingPlatform.windows
          : service.platform;
      return service.labelFor(id, platform: platform);
    }
    for (final binding in keybindings) {
      if (binding.appliesTo(mac: isMac)) return binding.label(mac: isMac);
    }
    return null;
  }

  /// [keybindings] as `keybindings.json` entries, for commands the app's
  /// default keybindings do not have (see
  /// [KeybindingService.registerExtraDefaults]).
  List<KeybindingEntry> get keybindingEntries => [
    for (final binding in keybindings) ?binding.toEntry(id),
  ];
}

/// Most-recently-used ids, newest first, e.g. for commands or files.
class IdeRecentList {
  IdeRecentList({this.capacity = 50});

  final int capacity;
  final List<String> _items = [];

  List<String> get items => List.unmodifiable(_items);

  void add(String id) {
    _items.remove(id);
    _items.insert(0, id);
    if (_items.length > capacity) _items.removeLast();
  }

  void remove(String id) => _items.remove(id);

  /// Position in the list (0 = most recent), or -1 when absent.
  int indexOf(String id) => _items.indexOf(id);
}

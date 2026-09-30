import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
  final bool enabled;

  /// `Category: Label`, as the palette lists and matches it.
  String get title => category == null ? label : '$category: $label';

  /// The first keybinding for the current platform, formatted for display.
  String? shortcutLabel({bool? mac}) {
    if (keybindingLabel != null) return keybindingLabel;
    final isMac = mac ?? ideUsesMacKeys;
    for (final binding in keybindings) {
      if (binding.appliesTo(mac: isMac)) return binding.label(mac: isMac);
    }
    return null;
  }
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

/// Builds the shortcut map for [commands] on the current platform, but for
/// two-chord keybindings (see [ideChordBindings]).
Map<ShortcutActivator, VoidCallback> ideShortcutBindings(
  Iterable<IdeCommand> commands,
) {
  final mac = ideUsesMacKeys;
  return {
    for (final command in commands)
      if (command.enabled)
        for (final binding in command.keybindings)
          if (binding.second == null && binding.appliesTo(mac: mac))
            binding.activator(mac: mac): command.run,
  };
}

/// The two-chord keybindings (⌘K ⌘T) of [commands] on the current platform,
/// for the workbench's chord mode.
List<({IdeKeybinding binding, VoidCallback run})> ideChordBindings(
  Iterable<IdeCommand> commands,
) {
  final mac = ideUsesMacKeys;
  return [
    for (final command in commands)
      if (command.enabled)
        for (final binding in command.keybindings)
          if (binding.second != null && binding.appliesTo(mac: mac))
            (binding: binding, run: command.run),
  ];
}

// The app's keybindings: the defaults, the selected keymap's and the
// user's `keybindings.json`, resolved for this platform (upstream
// `WorkbenchKeybindingService` over a `KeybindingResolver`).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'default_keybindings.dart';
import 'key_chord.dart';
import 'keybinding_entry.dart';
import 'keybinding_resolver.dart';
import 'when_expression.dart';

export 'keybinding_resolver.dart'
    show
        KeybindingFound,
        KeybindingItem,
        KeybindingResolution,
        KeybindingSource,
        MoreChordsNeeded,
        NoKeybinding;

/// The keybindings in effect and what a key press runs.
class KeybindingService extends ChangeNotifier {
  KeybindingService({
    List<KeybindingEntry>? defaults,
    Map<String, Object?>? commands,
    this.contextKeys = knownContextKeys,
  }) : _defaults = defaults ?? defaultKeybindings,
       _commands = commands ?? commandCatalog;

  /// The app's keybindings: the one the workbench and the settings read.
  static KeybindingService instance = KeybindingService();

  /// The context keys a `when` clause may read.
  final Set<String> contextKeys;

  final List<KeybindingEntry> _defaults;
  final Map<String, Object?> _commands;

  /// Overrides [KeybindingPlatform.current], e.g. under test.
  KeybindingPlatform? debugPlatform;

  KeybindingPlatform get platform =>
      debugPlatform ?? KeybindingPlatform.current;

  List<KeybindingEntry> get defaults => _defaults;

  /// The selected keymap (Atom, JetBrains, …): its id and name, and its
  /// keybindings; none when [keymapId] is null.
  String? get keymapId => _keymapId;
  String? _keymapId;
  String? get keymapName => _keymapName;
  String? _keymapName;
  List<KeybindingEntry> get keymapEntries => _keymapEntries;
  List<KeybindingEntry> _keymapEntries = const [];

  void setKeymap(
    String? id, {
    String? name,
    List<KeybindingEntry> entries = const [],
  }) {
    _keymapId = id;
    _keymapName = id == null ? null : name ?? id;
    _keymapEntries = id == null ? const [] : List.unmodifiable(entries);
    _changed();
  }

  /// The user's `keybindings.json`.
  List<KeybindingEntry> get userEntries => _userEntries;
  List<KeybindingEntry> _userEntries = const [];

  set userEntries(List<KeybindingEntry> entries) {
    if (listEquals(entries, _userEntries)) return;
    _userEntries = List.unmodifiable(entries);
    _changed();
  }

  /// Keybindings of commands not in the catalog, registered with them
  /// (e.g. a command handed to the IDE with its own keybindings).
  List<KeybindingEntry> _extraDefaults = const [];
  final Set<String> _extraCommands = {};

  /// Adds the default keybindings of commands the catalog does not know.
  void registerExtraDefaults(List<KeybindingEntry> entries) {
    final fresh = [
      for (final entry in entries)
        if (!_commands.containsKey(entry.commandId)) entry,
    ];
    final commands = {for (final entry in fresh) entry.commandId};
    if (listEquals(fresh, _extraDefaults) &&
        setEquals(commands, _extraCommands)) {
      return;
    }
    _extraDefaults = List.unmodifiable(fresh);
    _extraCommands
      ..clear()
      ..addAll(commands);
    _changed();
  }

  /// Whether BaoCode has [command]: a keybinding for one it has not (another
  /// editor's) is kept, but shown as not supported and never runs.
  bool isSupported(String command) =>
      _commands.containsKey(command) || _extraCommands.contains(command);

  final Map<KeybindingPlatform, KeybindingResolver> _resolvers = {};

  void _changed() {
    _resolvers.clear();
    notifyListeners();
  }

  /// The resolver for [platform] (this one by default).
  KeybindingResolver resolver([KeybindingPlatform? platform]) {
    final target = platform ?? this.platform;
    return _resolvers[target] ??= KeybindingResolver(
      [
        for (final (index, entry) in [..._defaults, ..._extraDefaults].indexed)
          KeybindingItem(
            entry: entry,
            source: KeybindingSource.defaults,
            platform: target,
            index: index,
          ),
        for (final (index, entry) in _keymapEntries.indexed)
          KeybindingItem(
            entry: entry,
            source: KeybindingSource.keymap,
            platform: target,
            index: index,
            keymapName: _keymapName,
          ),
      ],
      [
        for (final (index, entry) in _userEntries.indexed)
          KeybindingItem(
            entry: entry,
            source: KeybindingSource.user,
            platform: target,
            index: index,
          ),
      ],
      knownContextKeys: contextKeys,
    );
  }

  /// [context] with the platform keys (`isMac`, …) filled in.
  ContextLookup withPlatformKeys(ContextLookup context) {
    final target = platform;
    return (key) => switch (key) {
      'isMac' => target == KeybindingPlatform.mac,
      'isWindows' => target == KeybindingPlatform.windows,
      'isLinux' => target == KeybindingPlatform.linux,
      _ => context(key),
    };
  }

  /// What [event] does after the chords [pending], in [context], among the
  /// keybindings whose command [canRun]. A key a layout types with Shift or
  /// Option is tried by the character it made as well.
  KeybindingResolution resolveEvent(
    KeyEvent event, {
    List<KeyChord> pending = const [],
    required ContextLookup context,
    bool Function(KeybindingItem item)? canRun,
    HardwareKeyboard? keyboard,
  }) {
    if (event is KeyUpEvent) return const NoKeybinding();
    final chord = KeyChord.fromEvent(event, keyboard);
    if (chord == null) return const NoKeybinding();
    final resolver = this.resolver();
    final lookup = withPlatformKeys(context);
    bool runs(KeybindingItem item) =>
        isSupported(item.command) && (canRun?.call(item) ?? true);
    final result = resolver.resolve(lookup, pending, chord, canRun: runs);
    if (result is! NoKeybinding) return result;
    final character = KeyChord.characterChordOf(event, keyboard);
    if (character == null) return result;
    return resolver.resolve(lookup, pending, character, canRun: runs);
  }

  /// The keybinding shown for [command] on [platform] (this one by
  /// default); null when it has none.
  KeybindingItem? primaryKeybinding(
    String command, {
    KeybindingPlatform? platform,
    ContextLookup? context,
  }) => resolver(platform).lookupPrimaryKeybinding(
    command,
    context: context == null ? null : withPlatformKeys(context),
  );

  /// Its label (`⇧⌘P`, `Ctrl+K Ctrl+S`); null when it has none.
  String? labelFor(
    String command, {
    KeybindingPlatform? platform,
    ContextLookup? context,
  }) {
    final target = platform ?? this.platform;
    return primaryKeybinding(
      command,
      platform: target,
      context: context,
    )?.keys?.label(target);
  }

  /// A button's tooltip: [title] and the keybinding of [command], the one
  /// it runs, as upstream's action bar titles its items
  /// (`ActionViewItem.getTooltip`, `titleAndKb`: `{0} ({1})`, so
  /// `Toggle Primary Side Bar (⌘B)`); [title] alone when it has none.
  /// [context]: where the button is (the keybinding applying there).
  String titleWithKeybinding(
    String title,
    String command, {
    ContextLookup? context,
  }) => switch (labelFor(command, context: context)) {
    final keys? => '$title ($keys)',
    null => title,
  };
}

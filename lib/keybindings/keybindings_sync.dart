// Keeps the keybindings in effect ([KeybindingService]) in step with the
// files they come from: the user's `keybindings.json`, and the keymap the
// `monad.keymap` setting in `settings.json` selects (as VS Code's
// `UserKeybindings` follows its file, and a keymap extension, once
// installed, is in effect until uninstalled).

import 'dart:async';

import '../settings/jsonc_file.dart';
import '../settings/user_settings.dart';
import 'keybinding_entry.dart';
import 'keybinding_service.dart';
import 'keymap.dart';

/// Follows [keybindings] and [settings] into [service].
class KeybindingsSync {
  KeybindingsSync({
    required this.keybindings,
    required this.settings,
    required this.catalog,
    KeybindingService? service,
  }) : service = service ?? KeybindingService.instance;

  /// The setting that holds the selected keymap's id.
  static const keymapSetting = 'monad.keymap';

  /// `User/keybindings.json`.
  final JsoncFile keybindings;

  /// `User/settings.json`.
  final UserSettings settings;

  final KeymapCatalog catalog;
  final KeybindingService service;

  /// The keymap last asked for, and how many loads were started (a load
  /// finishing after a later one started is dropped).
  String? _keymapId;
  int _keymapLoads = 0;
  Future<void> _keymapLoaded = Future.value();
  bool _started = false;

  /// Completes once the selected keymap is in effect.
  Future<void> get ready => _keymapLoaded;

  /// The keymap the setting selects; null for none.
  String? get selectedKeymap => switch (settings[keymapSetting]) {
    final String id when id.trim().isNotEmpty => id.trim(),
    _ => null,
  };

  /// Applies the files as they are now, then follows them.
  void start() {
    if (_started) return;
    _started = true;
    keybindings.addListener(_keybindingsChanged);
    settings.addListener(_settingsChanged);
    _keybindingsChanged();
    _settingsChanged();
  }

  /// Makes [id] the keymap in effect (none when null), in the setting too.
  /// Loads it again even if it was the one selected (it may have been
  /// imported afresh).
  Future<void> selectKeymap(String? id) async {
    await settings.update(keymapSetting, id);
    _keymapId = id;
    await (_keymapLoaded = _loadKeymap());
  }

  // A file that does not parse keeps its last good value (JsoncFile), so
  // the keybindings stay as they were until it is fixed.
  void _keybindingsChanged() =>
      service.userEntries = KeybindingEntry.listFromJson(keybindings.value);

  void _settingsChanged() {
    final id = selectedKeymap;
    if (id == _keymapId && _keymapLoads > 0) return;
    _keymapId = id;
    _keymapLoaded = _loadKeymap();
  }

  Future<void> _loadKeymap() async {
    final id = _keymapId;
    final load = ++_keymapLoads;
    final keymap = id == null ? null : await catalog.load(id);
    if (load != _keymapLoads || !_started) return;
    if (keymap == null) {
      service.setKeymap(null);
    } else {
      service.setKeymap(keymap.id, name: keymap.name, entries: keymap.entries);
    }
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    keybindings.removeListener(_keybindingsChanged);
    settings.removeListener(_settingsChanged);
  }
}

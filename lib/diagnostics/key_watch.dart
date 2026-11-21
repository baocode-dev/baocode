import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../keybindings/key_chord.dart';
import '../keybindings/keybinding_service.dart';
import '../platform/event_log.dart';

/// Writes to the event log (under `keys`) a key that types a character,
/// pressed in a text field, that something in the app took before the
/// field had it: the keybinding it was resolved to, if one, and the keys
/// the app and the system have as held then.
///
/// For N2S9TV9F (Windows 2.0.1): 1 typed nowhere, on the keyboard's row or
/// the keypad, nor `!`, in the chat's and the IDE's fields alike, until
/// the app was started again; nothing was written.
abstract final class KeyWatch {
  static bool _started = false;

  /// What the keybindings made of this key message's key, if anything.
  static String? _resolved;

  static final Map<int, DateTime> _lastWritten = {};
  static int _written = 0;
  static const _gap = Duration(minutes: 1);
  static const _most = 100;

  @visibleForTesting
  static void debugReset() {
    _lastWritten.clear();
    _written = 0;
  }

  /// Puts itself between the engine's key messages and the binding.
  static void start() {
    if (_started) return;
    _started = true;
    KeybindingService.onResolved = _noteResolved;
    // The raw message is where the engine hears whether the key was taken
    // (the field then gets no text for it).
    // ignore: deprecated_member_use
    final manager = ServicesBinding.instance.keyEventManager;
    SystemChannels.keyEvent.setMessageHandler((message) async {
      _resolved = null;
      // ignore: deprecated_member_use
      final reply = await manager.handleRawKeyMessage(message);
      if (reply['handled'] == true) {
        try {
          _taken(message);
        } on Object {
          // Only diagnostics.
        }
      }
      return reply;
    });
  }

  static void _noteResolved(
    KeyEvent event,
    List<KeyChord> pending,
    KeybindingResolution result,
  ) {
    final platform = KeybindingService.instance.platform;
    String label(List<KeyChord> chords) =>
        chords.map((chord) => chord.userSettingsLabel(platform)).join(' ');
    final key = switch (KeyChord.fromEvent(event)) {
      final chord? => chord.userSettingsLabel(platform),
      null => '?',
    };
    final after = pending.isEmpty ? '' : ' after ${label(pending)}';
    switch (result) {
      case KeybindingFound(:final item):
        final from = [
          item.source.name,
          ?item.keymapName,
          ?item.extensionId,
        ].join(' ');
        _resolved = 'keybinding $key$after -> ${item.command} ($from)';
      case MoreChordsNeeded(:final chords):
        _resolved = 'the first keys of a sequence, ${label(chords)}';
      case NoKeybinding():
        // A sequence's next key that completes none is swallowed, as
        // upstream does.
        if (pending.isNotEmpty) {
          _resolved ??= '$key$after, completing no keybinding';
        }
    }
  }

  static void _taken(Object? message) {
    if (message is! Map<String, dynamic>) return;
    // ignore: deprecated_member_use
    final raw = RawKeyEvent.fromMessage(message);
    // ignore: deprecated_member_use
    if (raw is! RawKeyDownEvent) return;
    final character = raw.character;
    if (character == null || character.isEmpty) return;
    final first = character.runes.first;
    if (first < 0x20 || first == 0x7f) return;
    // The system's own modifiers: a shortcut of theirs is no lost key.
    final data = raw.data;
    // ignore: deprecated_member_use
    if (data.isControlPressed || data.isMetaPressed || data.isAltPressed) {
      return;
    }
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorStateOfType<EditableTextState>() == null) {
      return;
    }
    final physical = raw.physicalKey.usbHidUsage;
    final now = DateTime.now();
    final last = _lastWritten[physical];
    if (_written >= _most || last != null && now.difference(last) < _gap) {
      return;
    }
    _lastWritten[physical] = now;
    _written++;
    appEvent(
      'keys',
      'a text field did not get ${_keyName(raw.logicalKey)} '
          '(0x${physical.toRadixString(16)}): '
          '${_resolved ?? 'no keybinding, a widget of its own'}; '
          '${describe(pressing: raw.physicalKey)}',
    );
  }

  /// The keys the app has as held, but [pressing]: a key the app missed
  /// going up stays held for it.
  static String describe({PhysicalKeyboardKey? pressing}) {
    final keyboard = HardwareKeyboard.instance;
    final held = [
      for (final physical in keyboard.physicalKeysPressed)
        if (physical != pressing)
          switch (keyboard.lookUpLayout(physical)) {
            final logical? => _keyName(logical),
            null => '0x${physical.usbHidUsage.toRadixString(16)}',
          },
    ];
    return 'held ${held.isEmpty ? 'none' : held.join(', ')}';
  }

  static String _keyName(LogicalKeyboardKey key) =>
      key.keyLabel.isEmpty ? '0x${key.keyId.toRadixString(16)}' : key.keyLabel;
}

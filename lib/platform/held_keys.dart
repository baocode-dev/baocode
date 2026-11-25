import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../workspace/window_controls.dart';
import 'event_log.dart';

/// The modifier keys held, as the system has them: to make the app's own
/// ([HardwareKeyboard]) right.
///
/// The app's can keep one held after it went up, its key up lost (the
/// app out of front then, an input method or a system shortcut taking it).
/// The engine checks the system's modifiers at each mouse event, but
/// against what it has itself, not against the app's (macOS); on Windows
/// only Shift and Ctrl, as the pointer moves. Till the key was pressed
/// again, a click was then taken as ⌘- or Ctrl-clicked, a key typed as a
/// shortcut (1 typing nothing, N2S9TV9F).
///
/// So the system is asked: as the app comes in front, at a press while the
/// app has one held, and before a click is taken as one with ⌘ or Ctrl
/// ([commandOrControl]). One the app has held and the system has not is
/// let go, and written to the event log (under `keys`).
abstract final class HeldKeys {
  /// Each modifier the system tells of, by its name there (see the windows'
  /// `heldModifiers`), and its keys, on either side.
  static const _modifiers = {
    'shift': [LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight],
    'control': [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
    ],
    'alt': [LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight],
    'meta': [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight],
  };

  static bool _started = false;

  /// How long the system is waited for: then the app's taken as it is.
  static const _patience = Duration(milliseconds: 300);

  /// The system asked, from the app's start: on the desktop.
  static void start() {
    if (_started) return;
    _started = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      if (event is PointerDownEvent && _anyHeld) unawaited(sync('a press'));
    });
    AppLifecycleListener(onResume: () => unawaited(sync('back in front')));
    // A window key again with the app in front all along: the keyboard
    // back from another app's panel (macos/Runner/FocusWatch.swift), its
    // modifier's key up gone to the panel.
    WidgetsBinding.instance.addObserver(_KeyAgain());
  }

  /// Whether ⌘ or Ctrl is held, either on any platform, for a click now:
  /// the app's, made right by the system's first when the app has one held.
  /// As the app has it where the system cannot be asked.
  static Future<bool> commandOrControl() async {
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isMetaPressed && !keyboard.isControlPressed) return false;
    await sync('a click with ⌘ or Ctrl');
    return keyboard.isMetaPressed || keyboard.isControlPressed;
  }

  /// Lets go of the modifiers the app has held and the system has not;
  /// [why], for the log.
  static Future<void> sync(String why) async {
    if (!_anyHeld) return;
    final keyboard = HardwareKeyboard.instance;
    final before = keyboard.physicalKeysPressed.toSet();
    final Map<String, bool> system;
    try {
      system =
          await WindowControls.channelFor(0)
              .invokeMapMethod<String, bool>('heldModifiers')
              .timeout(_patience) ??
          const {};
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    } on TimeoutException {
      return;
    }
    // A key pressed or let go meanwhile: what was answered may be old.
    final after = keyboard.physicalKeysPressed;
    if (system.isEmpty ||
        after.length != before.length ||
        !before.containsAll(after)) {
      return;
    }
    letGo(system, why);
  }

  /// Lets go of the modifiers the app has held that [system] (each by its
  /// name, held or not) has not: as their key up would.
  @visibleForTesting
  static void letGo(Map<String, bool> system, String why) {
    final keyboard = HardwareKeyboard.instance;
    final stale = <PhysicalKeyboardKey, LogicalKeyboardKey>{};
    for (final physical in keyboard.physicalKeysPressed) {
      final logical = keyboard.lookUpLayout(physical);
      if (logical == null) continue;
      for (final MapEntry(key: name, value: keys) in _modifiers.entries) {
        if (keys.contains(logical) && system[name] == false) {
          stale[physical] = logical;
        }
      }
    }
    if (stale.isEmpty) return;
    for (final MapEntry(key: physical, value: logical) in stale.entries) {
      keyboard.handleKeyEvent(
        KeyUpEvent(
          physicalKey: physical,
          logicalKey: logical,
          timeStamp: Duration.zero,
          synthesized: true,
        ),
      );
    }
    final names = stale.values.map((key) => key.keyLabel).join(', ');
    appEvent('keys', 'held for the app, not the system ($why): $names; let go');
  }

  static bool get _anyHeld {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed;
  }
}

class _KeyAgain with WidgetsBindingObserver {
  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state == ViewFocusState.focused) {
      unawaited(HeldKeys.sync('the window key again'));
    }
  }
}

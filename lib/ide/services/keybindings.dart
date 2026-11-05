// What a key press runs in the window, as the keybindings resolve it
// (defaults, the keymap's, the user's; see KeybindingService) against the
// window's commands and context keys, with two-chord keybindings (⌘K ⌘T)
// ported from VS Code src/vs/platform/keybinding/common/
// abstractKeybindingService.ts at 6a598d4a13031703d483d103c1d934a36ad27971
// (`_doDispatch`, `_expectAnotherChord`, `_scheduleLeaveChordMode`,
// `_leaveChordMode`), with the status bar messages of
// notificationsStatus.ts. A key counts when the focus lets it bubble to
// the workbench (a terminal keeps its keys, the editor its own
// commands'); the key after a first chord is taken before the focus sees
// it.

import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_keybindings.dart'
    show editorChordPrefix;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../chat/chat_keys.dart';
import '../../keybindings/key_chord.dart';
import '../../keybindings/keybinding_service.dart';
import '../../l10n/l10n.dart';
import '../ide_commands.dart';
import '../terminal/terminal_panel.dart' show terminalCommandsToSkipShell;
import '../workbench/context_keys.dart';
import '../workbench/contributions.dart';
import '../workbench/services.dart';
import '../workbench/statusbar.dart';
import 'commands.dart';

/// A chord being typed: its label, the chords so far, and the status
/// bar's message for it.
typedef _Chord = ({String label, List<KeyChord> chords, String message});

class KeybindingDispatchService implements WorkbenchDisposable {
  KeybindingDispatchService({
    required this.host,
    required this.commands,
    required this.contextKeys,
    required this.statusbar,
    required this.focusNode,
    required this._active,
  }) {
    FocusManager.instance
      ..addEarlyKeyEventHandler(onChordKey)
      ..addLateKeyEventHandler(onLateKey);
  }

  final WorkbenchHost host;
  final CommandService commands;
  final ContextKeyService contextKeys;
  final StatusbarService statusbar;

  /// The workbench's own, which the keys the focus lets through reach.
  final FocusNode focusNode;

  /// Whether the window shows (another's keys are not its).
  final bool Function() _active;

  static final _modifierKeys = {
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
  };

  /// The chord being typed (upstream `_currentChords`).
  _Chord? _chord;
  Timer? _chordChecker;

  /// What [event] does after the chords [pending]: a command that is here
  /// and enabled, among the palette's.
  KeybindingResolution resolve(
    KeyEvent event, {
    List<KeyChord> pending = const [],
    Map<String, IdeCommand>? commands,
  }) {
    final byId = commands ?? this.commands.byId();
    return KeybindingService.instance.resolveEvent(
      event,
      pending: pending,
      // The extensions' keys (`setContext`) over the workbench's.
      context: contextKeys.getValue,
      canRun: (item) => byId[item.command]?.enabled ?? false,
    );
  }

  /// For the editor: the command a key runs, [editorChordPrefix] when it
  /// starts a sequence, null when no keybinding has it.
  String? resolveEditorKey(KeyEvent event) => switch (resolve(event)) {
    KeybindingFound(:final command) => command,
    MoreChordsNeeded() => editorChordPrefix,
    NoKeybinding() => null,
  };

  /// A key the focus let through: the command its keybinding runs, or the
  /// first chord of a two-chord keybinding, which starts chord mode
  /// (`ResultKind.KbFound`, `ResultKind.MoreChordsNeeded`).
  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    _offeredKey = event;
    // An input method composing text has its keys (Enter picks a
    // candidate); upstream's keyboard events read as `KeyCode.Unknown`.
    if (_chord != null || event is KeyUpEvent || ChatKeys.isComposing) {
      return KeyEventResult.ignored;
    }
    final commands = this.commands.byId();
    switch (resolve(event, commands: commands)) {
      case KeybindingFound(:final item):
        commands[item.command]!.invoke(item.entry.args);
        return KeyEventResult.handled;
      case MoreChordsNeeded(:final chords):
        _expectAnotherChord(chords);
        return KeyEventResult.handled;
      case NoKeybinding():
        return KeyEventResult.ignored;
    }
  }

  /// The last key [onKey] was offered, which [onLateKey] leaves.
  KeyEvent? _offeredKey;

  /// A key that did not reach [onKey]: one a widget in the workbench
  /// stopped without handling it (the chat's input keeps its rich text
  /// editor's shortcuts from it, `skipRemainingHandlers`), or one pressed
  /// with the focus on none of the workbench's widgets but on the window
  /// (the focused one went). Upstream's keybinding service listens on the
  /// window, and hears both (`_registerKeyListeners`); a dialog over the
  /// workbench, a menu in the overlay, or an input method composing text
  /// keeps its keys.
  KeyEventResult onLateKey(KeyEvent event) {
    final context = host.context;
    if (identical(event, _offeredKey) || !_active() || context == null) {
      return KeyEventResult.ignored;
    }
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null ||
        !(focus.ancestors.contains(focusNode) ||
            focusNode.ancestors.contains(focus)) ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return KeyEventResult.ignored;
    }
    return onKey(focusNode, event);
  }

  /// The key after a first chord, before the focus sees it: upstream's
  /// keybinding service takes it wherever the focus is.
  KeyEventResult onChordKey(KeyEvent event) {
    final chord = _chord;
    if (chord == null ||
        event is KeyUpEvent ||
        _modifierKeys.contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    _resolveChord(chord, event);
    return KeyEventResult.handled;
  }

  void _expectAnotherChord(List<KeyChord> chords) {
    final context = host.context;
    if (context == null) return;
    final platform = KeybindingService.instance.platform;
    final label = chords.map((chord) => chord.label(platform)).join(' ');
    final message = context.l10n.wbChordWaiting(label);
    _chord = (label: label, chords: chords, message: message);
    statusbar.setMessage(message);
    // `_scheduleLeaveChordMode`: out after 5 seconds, or once the window
    // is not the active one.
    _chordChecker?.cancel();
    _chordChecker = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final state = WidgetsBinding.instance.lifecycleState;
      if ((state != null && state != AppLifecycleState.resumed) ||
          timer.tick * 500 > 5000) {
        _leaveChordMode();
      }
    });
  }

  /// Runs the keybinding [event] completes, or says there is none.
  void _resolveChord(_Chord chord, KeyEvent event) {
    _leaveChordMode();
    final commands = this.commands.byId();
    final result = resolve(event, pending: chord.chords, commands: commands);
    if (result case KeybindingFound(:final item)) {
      commands[item.command]!.invoke(item.entry.args);
      return;
    }
    final context = host.context;
    if (context == null) return;
    final platform = KeybindingService.instance.platform;
    final keypress = KeyChord.fromEvent(event)?.label(platform) ?? '';
    statusbar.setMessage(
      context.l10n.wbChordNotCommand(chord.label, keypress),
      hideAfter: const Duration(seconds: 10),
    );
  }

  void _leaveChordMode() {
    final chord = _chord;
    if (chord == null) return;
    _chord = null;
    _chordChecker?.cancel();
    _chordChecker = null;
    if (identical(statusbar.message, chord.message)) statusbar.setMessage(null);
  }

  /// VS Code's custom key event handler for a terminal with the keyboard
  /// (`TerminalInstance`'s `attachCustomKeyEventHandler`): the workbench
  /// takes a key that resolves to a command of
  /// [terminalCommandsToSkipShell] (any, with ⌘ down), or to the first
  /// chord of a two-chord keybinding but Escape
  /// (`terminal.integrated.allowChords`); the shell gets the others.
  bool terminalSkipsShell(KeyEvent event) {
    if (event is KeyUpEvent || _modifierKeys.contains(event.logicalKey)) {
      return false;
    }
    return switch (resolve(event)) {
      KeybindingFound(:final command) =>
        HardwareKeyboard.instance.isMetaPressed ||
            terminalCommandsToSkipShell.contains(command),
      MoreChordsNeeded() => event.logicalKey != LogicalKeyboardKey.escape,
      NoKeybinding() => false,
    };
  }

  /// The command a key in a terminal's find widget runs, as the
  /// workbench's keybindings resolve it (see TerminalView.resolveKey).
  String? terminalFindKey(KeyEvent event) => switch (resolve(event)) {
    KeybindingFound(:final command) => command,
    _ => null,
  };

  @override
  void dispose() {
    _chordChecker?.cancel();
    FocusManager.instance
      ..removeEarlyKeyEventHandler(onChordKey)
      ..removeLateKeyEventHandler(onLateKey);
  }
}

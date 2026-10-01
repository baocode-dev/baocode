// The chat's keys: its widgets (the composer, a prompt's options, the
// history, the chat itself) run the commands its keybindings resolve to
// (see keybindings/chat_keybindings.dart), as upstream's chat widget
// contributes its context keys and actions to the keybinding service.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../keybindings/key_chord.dart';
import '../keybindings/keybinding_service.dart';
import '../keybindings/when_expression.dart';

/// A chat widget's part in the keybindings: the context keys it knows and
/// the commands it runs, which hold and run while the focus is in it (an
/// inner target's first).
mixin ChatKeyTarget<T extends StatefulWidget> on State<T> {
  /// Context key [key]'s value here; null for one it does not know (one
  /// outside it may).
  Object? chatContextKey(String key) => null;

  /// The commands it runs now, by id: not those with nothing to do (no
  /// turn to cancel, no menu open).
  Map<String, VoidCallback> get chatCommands => const {};

  /// An input method is composing text in it: the keys are the input
  /// method's.
  bool get chatComposing => false;
}

/// The context keys around the chats under it (`chatMode`, `ideMode`: the
/// layout they are shown in), read when a key is pressed in one.
class ChatKeyScope extends InheritedWidget {
  const ChatKeyScope({super.key, required this.lookup, required super.child});

  final ContextLookup lookup;

  static ContextLookup? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChatKeyScope>()?.lookup;

  // Read at the time of a key, not built with.
  @override
  bool updateShouldNotify(ChatKeyScope oldWidget) => false;
}

/// Resolves keys among the chat's commands.
abstract final class ChatKeys {
  /// The last key that ran a command, or was swallowed (part of a chord):
  /// the focus sees it after the window's keyboard handler, which sees each
  /// key first, and lets it be.
  static KeyEvent? _handled;

  static void markHandled(KeyEvent event) => _handled = event;

  static bool isHandled(KeyEvent event) => identical(event, _handled);

  /// The targets at [context] (its own and its ancestors'), innermost
  /// first.
  static List<ChatKeyTarget> targetsOf(BuildContext? context) {
    if (context == null || (context is Element && !context.mounted)) {
      return const [];
    }
    final targets = <ChatKeyTarget>[];
    void add(Element element) {
      if (element case StatefulElement(:final ChatKeyTarget state)) {
        targets.add(state);
      }
    }

    if (context is Element) add(context);
    context.visitAncestorElements((element) {
      add(element);
      return true;
    });
    return targets;
  }

  /// Those at the focus.
  static List<ChatKeyTarget> focusedTargets() =>
      targetsOf(FocusManager.instance.primaryFocus?.context);

  /// The context keys of [targets] (the innermost answering), then of
  /// [outer], then whether the focus is in a text field.
  static ContextLookup lookupOf(
    List<ChatKeyTarget> targets, [
    ContextLookup? outer,
  ]) => (key) {
    for (final target in targets) {
      if (target.chatContextKey(key) case final value?) return value;
    }
    if (outer?.call(key) case final value?) return value;
    return switch (key) {
      'inputFocus' || 'textInputFocus' => _editableFocused(),
      _ => null,
    };
  };

  /// The commands of [targets]: an inner one's in place of an outer's.
  static Map<String, VoidCallback> commandsOf(List<ChatKeyTarget> targets) => {
    for (final target in targets.reversed) ...target.chatCommands,
  };

  static bool _editableFocused() =>
      _focusedEditable(FocusManager.instance.primaryFocus) != null;

  static EditableTextState? _focusedEditable(FocusNode? focus) =>
      focus?.context?.findAncestorStateOfType<EditableTextState>();

  /// An input method is composing text where the focus is: keys are its
  /// (Enter picks a candidate, Esc drops them).
  static bool get isComposing {
    final focus = FocusManager.instance.primaryFocus;
    if (_focusedEditable(focus)?.textEditingValue.composing.isValid ?? false) {
      return true;
    }
    return targetsOf(focus?.context).any((target) => target.chatComposing);
  }

  /// [title] and the key that runs [command] where the context keys
  /// [context] hold (the last such keybinding's), as upstream's buttons
  /// title themselves: `Send (Enter)`.
  static String titleWithKey(
    String title,
    String command, [
    Map<String, Object> context = const {},
  ]) => KeybindingService.instance.titleWithKeybinding(
    title,
    command,
    context: (key) => context[key],
  );

  /// The chords of a sequence typed so far, where the window does not
  /// follow them (the IDE's chat).
  static List<KeyChord>? _pending;
  static Timer? _pendingTimer;

  static void _leaveChord() {
    _pending = null;
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }

  /// Runs the command [event] resolves to among those of the targets at
  /// the focus: handled if it did (or the window already had), null if
  /// there is none. For the focused target's key handler, before its own.
  static KeyEventResult? dispatch(KeyEvent event) {
    if (event is KeyUpEvent) return null;
    if (isHandled(event)) return KeyEventResult.handled;
    final focus = FocusManager.instance.primaryFocus?.context;
    final targets = targetsOf(focus);
    if (targets.isEmpty || isComposing) return null;
    // A dialog over the chat keeps its keys.
    if (!(ModalRoute.isCurrentOf(focus!) ?? true)) return null;
    final commands = commandsOf(targets);
    final pending = _pending;
    final result = KeybindingService.instance.resolveEvent(
      event,
      pending: pending ?? const [],
      context: lookupOf(targets, ChatKeyScope.maybeOf(focus)),
      canRun: (item) => commands.containsKey(item.command),
    );
    _leaveChord();
    switch (result) {
      case KeybindingFound(:final command):
        markHandled(event);
        commands[command]!();
        return KeyEventResult.handled;
      case MoreChordsNeeded(:final chords):
        markHandled(event);
        _pending = chords;
        _pendingTimer = Timer(const Duration(seconds: 5), _leaveChord);
        return KeyEventResult.handled;
      case NoKeybinding():
        if (pending == null) return null;
        // Upstream swallows a second key that completes nothing.
        markHandled(event);
        return KeyEventResult.handled;
    }
  }
}

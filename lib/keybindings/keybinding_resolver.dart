/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Which command a key press runs: the default keybindings, then a keymap's,
// then the user's `keybindings.json`, the last applicable one winning.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/keybinding/common/keybindingResolver.ts
// (`KeybindingResolver`: `handleRemovals`, `_isTargetedForRemoval`,
// `_addKeyPress`, `whenIsEntirelyIncluded`, `resolve`, `_findCommand`,
// `lookupKeybindings`, `lookupPrimaryKeybinding`) and
// src/vs/platform/keybinding/common/resolvedKeybindingItem.ts.
//
// Deviations:
// - A keybinding applies only if its command can run here ([canRun]: the
//   command exists and is enabled), so one for a command Monad does not have
//   yet, or one disabled now, leaves the key to the others; upstream picks it
//   anyway and reports the missing command.
// - A `when` clause that reads a context key Monad does not know, or does not
//   parse, never holds (upstream treats unknown keys as undefined).
// - `whenIsEntirelyIncluded` compares `&&` terms instead of upstream's
//   `implies`.

import 'package:flutter/foundation.dart';

import 'key_chord.dart';
import 'keybinding_entry.dart';
import 'when_expression.dart';

/// Where a keybinding comes from.
enum KeybindingSource { defaults, keymap, user }

/// One keybinding as read for a platform (upstream `ResolvedKeybindingItem`).
@immutable
class KeybindingItem {
  KeybindingItem({
    required this.entry,
    required this.source,
    required KeybindingPlatform platform,
    this.index,
    this.keymapName,
  }) : keys = switch (entry.keyFor(platform)) {
         final String key => KeySequence.parse(key),
         null => null,
       },
       when = switch (entry.when?.trim()) {
         final String text when text.isNotEmpty => WhenExpression.parse(text),
         _ => null,
       };

  final KeybindingEntry entry;
  final KeybindingSource source;

  /// Its position in its file (the user's `keybindings.json`, a keymap).
  final int? index;

  /// The keymap it comes from, for [KeybindingSource.keymap].
  final String? keymapName;

  /// Null when the entry has no key for this platform, or one that does
  /// not parse (see [keyError]).
  final KeySequence? keys;
  final WhenExpression? when;

  String get command => entry.command;
  Object? get args => entry.args;

  /// Whether it comes with the app or a keymap (upstream `isDefault`).
  bool get isDefault => source != KeybindingSource.user;

  /// The key text that did not parse; null when it did, or there is none.
  String? keyError(KeybindingPlatform platform) {
    final key = entry.keyFor(platform);
    return key != null && keys == null ? key : null;
  }

  /// The keys of its `when` clause not in [known].
  Set<String> unknownContextKeys(Set<String> known) =>
      when?.keys.difference(known) ?? const {};

  @override
  String toString() => 'KeybindingItem($source ${entry.toJson()})';
}

/// What a key press resolves to.
sealed class KeybindingResolution {
  const KeybindingResolution();
}

/// No keybinding for it.
final class NoKeybinding extends KeybindingResolution {
  const NoKeybinding();
}

/// It starts a sequence (⌘K of ⌘K ⌘S): the next key completes it.
final class MoreChordsNeeded extends KeybindingResolution {
  const MoreChordsNeeded(this.chords);

  /// The chords pressed so far, the next key's `pending`.
  final List<KeyChord> chords;
}

/// It runs [item]'s command.
final class KeybindingFound extends KeybindingResolution {
  const KeybindingFound(this.item);

  final KeybindingItem item;

  String get command => item.command;
}

class KeybindingResolver {
  KeybindingResolver(
    List<KeybindingItem> defaults,
    List<KeybindingItem> overrides, {
    required this.knownContextKeys,
  }) : items = List.unmodifiable(handleRemovals([...defaults, ...overrides])) {
    for (final item in items) {
      final keys = item.keys;
      if (keys == null || keys.chords.isEmpty) {
        _addToLookup(item);
        continue;
      }
      _addKeyPress(keys.chords.first, item);
    }
  }

  /// The context keys a `when` clause may read (see [appliesIn]).
  final Set<String> knownContextKeys;

  /// The keybindings in effect, in order (removals applied and dropped).
  final List<KeybindingItem> items;

  final Map<KeyChord, List<KeybindingItem>> _byFirstChord = {};
  final Map<String, List<KeybindingItem>> _byCommand = {};

  /// Drops the default keybindings the `-command` entries remove, and those
  /// entries (upstream `handleRemovals`).
  static List<KeybindingItem> handleRemovals(List<KeybindingItem> items) {
    final removals = <String, List<KeybindingItem>>{};
    for (final item in items) {
      if (item.entry.isRemoval) {
        (removals[item.entry.commandId] ??= []).add(item);
      }
    }
    if (removals.isEmpty) return items;
    return [
      for (final item in items)
        if (!item.entry.isRemoval &&
            !(item.isDefault &&
                (removals[item.command]?.any(
                      (removal) => _isTargetedForRemoval(item, removal),
                    ) ??
                    false)))
          item,
    ];
  }

  static bool _isTargetedForRemoval(
    KeybindingItem item,
    KeybindingItem removal,
  ) {
    final keys = removal.keys;
    if (keys != null) {
      final target = item.keys?.chords ?? const [];
      if (keys.chords.length > target.length) return false;
      for (var i = 0; i < keys.chords.length; i++) {
        if (keys.chords[i] != target[i]) return false;
      }
    }
    final when = removal.when;
    if (when != null) {
      final targetWhen = item.when;
      if (targetWhen == null || targetWhen != when) return false;
    }
    return true;
  }

  void _addKeyPress(KeyChord chord, KeybindingItem item) {
    final conflicts = _byFirstChord[chord];
    if (conflicts == null) {
      _byFirstChord[chord] = [item];
      _addToLookup(item);
      return;
    }
    for (final conflict in conflicts.reversed.toList()) {
      if (conflict.command == item.command) continue;
      // A shorter sequence that is a prefix of a longer one shadows it.
      final a = conflict.keys!.chords;
      final b = item.keys!.chords;
      var prefix = true;
      for (var i = 1; i < a.length && i < b.length; i++) {
        if (a[i] != b[i]) {
          prefix = false;
          break;
        }
      }
      if (!prefix) continue;
      if (whenIsEntirelyIncluded(conflict.when, item.when)) {
        // [item] overwrites [conflict] wherever it applies.
        _byCommand[conflict.command]?.remove(conflict);
      }
    }
    conflicts.add(item);
    _addToLookup(item);
  }

  void _addToLookup(KeybindingItem item) {
    if (item.command.isEmpty) return;
    (_byCommand[item.command] ??= []).add(item);
  }

  /// Whether wherever [a] holds, [b] does too (upstream: `a` implies `b`).
  static bool whenIsEntirelyIncluded(WhenExpression? a, WhenExpression? b) {
    if (b == null) return true;
    if (a == null) return false;
    Set<String> terms(WhenExpression e) => {
      for (final term in e.serialize().split(' && ')) term.trim(),
    };
    return terms(a).containsAll(terms(b));
  }

  /// Whether [item]'s `when` holds in [context]: never for a clause that
  /// does not parse or reads a key not in [knownContextKeys].
  bool appliesIn(KeybindingItem item, ContextLookup context) {
    final when = item.when;
    if (when == null) return true;
    if (when.error != null) return false;
    if (item.unknownContextKeys(knownContextKeys).isNotEmpty) return false;
    return when.evaluate(context);
  }

  /// What pressing [chord] after [pending] (the chords of a sequence so
  /// far) does in [context], among the keybindings whose command [canRun].
  KeybindingResolution resolve(
    ContextLookup context,
    List<KeyChord> pending,
    KeyChord chord, {
    bool Function(KeybindingItem item)? canRun,
  }) {
    final pressed = [...pending, chord];
    final candidates = _byFirstChord[pressed.first];
    if (candidates == null) return const NoKeybinding();
    final matching = pressed.length == 1
        ? candidates
        : [
            for (final candidate in candidates)
              if (_startsWith(candidate.keys!.chords, pressed)) candidate,
          ];
    for (final item in matching.reversed) {
      if (!appliesIn(item, context)) continue;
      if (canRun != null && !canRun(item)) continue;
      return pressed.length < item.keys!.chords.length
          ? MoreChordsNeeded(List.unmodifiable(pressed))
          : KeybindingFound(item);
    }
    return const NoKeybinding();
  }

  static bool _startsWith(List<KeyChord> chords, List<KeyChord> pressed) {
    if (chords.length < pressed.length) return false;
    for (var i = 1; i < pressed.length; i++) {
      if (chords[i] != pressed[i]) return false;
    }
    return true;
  }

  /// The keybindings of [command] still in effect, the one applied last
  /// first (upstream `lookupKeybindings`).
  List<KeybindingItem> lookupKeybindings(String command) => [
    for (final item in (_byCommand[command] ?? const []).reversed)
      if (item.keys != null) item,
  ];

  /// The keybinding shown for [command] (upstream
  /// `lookupPrimaryKeybinding`): the last one applying in [context] if
  /// given, else the last one.
  KeybindingItem? lookupPrimaryKeybinding(
    String command, {
    ContextLookup? context,
  }) {
    final items = lookupKeybindings(command);
    if (items.isEmpty) return null;
    if (context != null) {
      for (final item in items) {
        if (appliesIn(item, context)) return item;
      }
    }
    return items.first;
  }

  /// The keybindings whose key starts with [keys] (for "Show Same
  /// Keybindings" and conflicts).
  List<KeybindingItem> itemsWithKeys(KeySequence keys) => [
    for (final item in items)
      if (item.keys case final own?
          when own.chords.length >= keys.chords.length &&
              listEquals(
                own.chords.sublist(0, keys.chords.length),
                keys.chords,
              ))
        item,
  ];
}

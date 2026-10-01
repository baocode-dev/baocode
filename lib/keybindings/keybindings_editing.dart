/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Changes the user's `keybindings.json` as the Keyboard Shortcuts page asks:
// a keybinding's key or `when`, one more for a command, one removed, a
// command reset; in place, so the user's comments and layout stay.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/services/keybinding/common/keybindingEditing.ts
// (`KeybindingsEditingService`: `doEditKeybinding`, `doRemoveKeybinding`,
// `doResetKeybinding`, `updateKeybinding`, `removeDefaultKeybinding`,
// `removeUnassignedDefaultKeybinding`, `findUserKeybindingEntryIndex`,
// `asObject`, `areSame`, `resolveAndValidate`, `getEmptyContent`).
//
// Deviations:
// - A user keybinding is found by its position among the file's entries
//   (checked against what it holds), then by its command and `when` as
//   upstream finds it.
// - Changing a default (or keymap) keybinding always adds a user one;
//   upstream changes a user keybinding of the same command and `when`
//   instead, where there is one, losing it.
// - A user keybinding keeps the `mac`/`win`/`linux` key it has for this
//   platform: that one is changed, where upstream sets `key` (which the
//   platform's own then still overrides).
// - The keybinding added in place of a default one keeps its `args`.
// - Reset removes every user keybinding of the command, its removals
//   (`-command`) too, from any row of it; upstream only from a user row,
//   that row's and the removals.
// - A change that changes nothing (the same key and `when`) writes nothing
//   (upstream checks that in the editor).
// - Each change is written at once, not saved from an editor's buffer;
//   one the user has unsaved in an editor is not known here.

import 'dart:async';

import '../settings/jsonc.dart';
import '../settings/jsonc_file.dart';
import 'key_chord.dart';
import 'keybinding_entry.dart';
import 'keybinding_resolver.dart';
import 'when_expression.dart';

/// Writes the Keyboard Shortcuts page's changes into [file], the user's
/// `keybindings.json`, as keys for [platform].
///
/// Every change reads the file afresh and writes it once; they run one at
/// a time, in order. One throws a [JsoncFileException] while the file does
/// not parse or is not an array (the user is to fix it first).
class KeybindingsEditingService {
  KeybindingsEditingService(this.file, {this._platform});

  final JsoncFile file;

  final KeybindingPlatform? _platform;

  /// The platform the keys are written for: [KeybindingPlatform.current]
  /// unless given.
  KeybindingPlatform get platform => _platform ?? KeybindingPlatform.current;

  /// What a new `keybindings.json` holds (upstream `getEmptyContent`).
  static const emptyContent =
      '// Place your key bindings in this file to override the defaults\n'
      '[\n]';

  /// Binds [item]'s command to [keys] in its place (upstream
  /// `editKeybinding`): a user keybinding is changed where it is; for a
  /// default or keymap one a user keybinding is added, and a removal
  /// (`-command`) of the old one. [when] replaces its `when` clause (empty
  /// for none); null keeps it.
  Future<void> editKeybinding(
    KeybindingItem item,
    KeySequence keys, {
    String? when,
  }) => _queue(() => _edit(item, keys, when ?? item.entry.when));

  /// Sets [item]'s `when` clause to [when] (none when null or blank),
  /// keeping its key: as [editKeybinding] does.
  Future<void> changeWhen(KeybindingItem item, String? when) =>
      _queue(() async {
        if (item.isDefault) {
          final keys = item.keys;
          // Nothing to bind again (upstream offers it only with a key).
          if (keys == null) return;
          return _edit(item, keys, when);
        }
        return _edit(item, null, when);
      });

  /// Binds [command] to [keys] as well (upstream `addKeybinding`): a new
  /// user keybinding, the others staying.
  Future<void> addKeybinding(
    String command,
    KeySequence keys, {
    String? when,
    Object? args,
  }) => _queue(
    () => _change(
      (edit) => edit.append(_asObject(keys, command, when, args: args)),
    ),
  );

  /// Removes [item] (upstream `removeKeybinding`): a user keybinding from
  /// the file; a default or keymap one by a removal (`-command`) of its key
  /// and `when`, unless there is one.
  Future<void> removeKeybinding(KeybindingItem item) => _queue(
    () => _change((edit) {
      if (item.isDefault) {
        _removeDefault(edit, item);
      } else {
        final index = _findUserEntry(edit.entries, item);
        if (index >= 0) edit.remove(index);
      }
    }),
  );

  /// Removes every user keybinding of [command], and every removal
  /// (`-command`) of its default ones: they are the defaults again
  /// (upstream `resetKeybinding`).
  Future<void> resetKeybinding(String command) => _queue(
    () => _change((edit) {
      final entries = edit.entries;
      for (var index = entries.length - 1; index >= 0; index--) {
        if (KeybindingEntry.fromJson(entries[index])?.commandId == command) {
          edit.remove(index);
        }
      }
    }),
  );

  /// Upstream `doEditKeybinding` (not adding): [keys] null keeps a user
  /// keybinding's key.
  Future<void> _edit(
    KeybindingItem item,
    KeySequence? keys,
    String? when,
  ) async {
    when = _normalizeWhen(when);
    if ((keys == null || keys == item.keys) &&
        _sameWhen(when, item.entry.when)) {
      return;
    }
    return _change((edit) {
      if (item.isDefault) {
        edit.append(_asObject(keys!, item.command, when, args: item.args));
        _removeDefault(edit, item);
      } else {
        final index = _findUserEntry(edit.entries, item);
        if (index < 0) {
          // Gone from the file meanwhile: bound anew.
          final key = keys ?? item.keys;
          if (key == null) return;
          edit.append(_asObject(key, item.command, when, args: item.args));
        } else {
          if (keys != null && keys != item.keys) {
            edit.set([index, _keyProperty(item.entry)], _label(keys));
          }
          if (!_sameWhen(when, item.entry.when)) {
            if (when == null) {
              edit.delete([index, 'when']);
            } else {
              edit.set([index, 'when'], when);
            }
          }
        }
      }
    });
  }

  /// Adds a removal of [item]'s key and `when`, unless the file has the
  /// same (upstream `removeDefaultKeybinding`). Nothing for one without a
  /// key here: a removal without one would remove all of the command's.
  void _removeDefault(_Edit edit, KeybindingItem item) {
    final keys = item.keys;
    if (keys == null) return;
    final removal = _asObject(
      keys,
      item.command,
      item.when?.serialize(),
      negate: true,
    );
    final same = edit.entries.any(
      (entry) => _areSame(KeybindingEntry.fromJson(entry), removal),
    );
    if (!same) edit.append(removal);
  }

  /// The file's entry [item] is: at its position among the entries if it
  /// is still the same there, else the same one elsewhere, else the first
  /// of its command with its `when` (upstream `findUserKeybindingEntryIndex`);
  /// -1 when there is none.
  static int _findUserEntry(List<Object?> entries, KeybindingItem item) {
    final parsed = [
      for (final entry in entries) KeybindingEntry.fromJson(entry),
    ];
    if (item.index case final position?) {
      var seen = -1;
      for (final (index, entry) in parsed.indexed) {
        if (entry == null) continue;
        if (++seen == position) {
          if (entry == item.entry) return index;
          break;
        }
      }
    }
    final same = parsed.indexWhere((entry) => entry == item.entry);
    if (same >= 0) return same;
    return parsed.indexWhere(
      (entry) =>
          entry != null &&
          entry.command == item.command &&
          _sameWhen(entry.when, item.entry.when),
    );
  }

  /// The property holding [entry]'s key here: its own for this platform
  /// if it has one, else `key`.
  String _keyProperty(KeybindingEntry entry) => switch (platform) {
    KeybindingPlatform.mac when entry.mac != null => 'mac',
    KeybindingPlatform.windows when entry.win != null => 'win',
    KeybindingPlatform.linux when entry.linux != null => 'linux',
    _ => 'key',
  };

  String _label(KeySequence keys) => keys.userSettingsLabel(platform);

  /// An entry as `keybindings.json` writes it (upstream `asObject`).
  Map<String, Object?> _asObject(
    KeySequence keys,
    String command,
    String? when, {
    Object? args,
    bool negate = false,
  }) {
    when = _normalizeWhen(when);
    return {
      'key': _label(keys),
      'command': negate ? '-$command' : command,
      'when': ?when,
      'args': ?args,
    };
  }

  /// Whether [entry] is [removal] (upstream `areSame`): the same command,
  /// key, `when` and arguments.
  bool _areSame(KeybindingEntry? entry, Map<String, Object?> removal) {
    if (entry == null || entry.command != removal['command']) return false;
    final key = entry.keyFor(platform);
    if (key == null) return false;
    final keys = KeySequence.parse(key);
    if (keys == null
        ? key != removal['key']
        : keys != KeySequence.parse(removal['key']! as String)) {
      return false;
    }
    return _sameWhen(entry.when, removal['when'] as String?) &&
        entry.args == null;
  }

  static String? _normalizeWhen(String? when) {
    final text = when?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// Whether two `when` clauses are the same once parsed.
  static bool _sameWhen(String? a, String? b) {
    final (left, right) = (_normalizeWhen(a), _normalizeWhen(b));
    if (left == null || right == null) return left == right;
    return WhenExpression.parse(left) == WhenExpression.parse(right);
  }

  /// Changes the file in one step ([JsoncFile.transform]): its text is
  /// read, [apply] changes it, and it is written once if it changed.
  Future<void> _change(void Function(_Edit edit) apply) =>
      file.transform((read) {
        final edit = _open(read ?? '');
        apply(edit);
        return edit.text == edit.original ? null : edit.text;
      });

  /// The file's text ([read]) to change, checked as upstream's
  /// `resolveAndValidate` checks it: a missing or empty file starts as
  /// [emptyContent], one with only comments gets an array.
  _Edit _open(String read) {
    var text = read.trim().isEmpty ? emptyContent : read;
    final errors = <JsoncParseError>[];
    final value = parseJsonc(text, errors: errors);
    if (errors.isNotEmpty) {
      throw JsoncFileException(
        file.path,
        'Unable to write to the keybindings configuration file. Please open '
        'it to correct errors/warnings in the file and try again. '
        '(${errors.first.describe(text)})',
      );
    }
    if (value == null) {
      text = '$text${JsoncFormatting.detect(text).eol}[]';
    } else if (value is! List) {
      throw JsoncFileException(
        file.path,
        'Unable to write to the keybindings configuration file. It has an '
        'object which is not of type Array. Please open the file to clean '
        'up and try again.',
      );
    }
    return _Edit(read, text);
  }

  Future<void> _pending = Future.value();

  /// One change at a time, in order (upstream's `Queue`).
  Future<void> _queue(Future<void> Function() task) {
    final result = _pending.then((_) => task());
    _pending = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}

/// The file's text being changed.
class _Edit {
  _Edit(this.original, this.text);

  final String original;
  String text;

  /// The array's elements now.
  List<Object?> get entries => switch (parseJsonc(text)) {
    final List<Object?> list => list,
    _ => const [],
  };

  void _modify(
    List<Object> path,
    Object? value, {
    bool remove = false,
    bool insert = false,
  }) {
    text = applyJsoncEdits(
      text,
      modifyJsonc(text, path, value, remove: remove, insert: insert),
    );
  }

  void append(Map<String, Object?> entry) => _modify([-1], entry, insert: true);

  void set(List<Object> path, Object? value) => _modify(path, value);

  void delete(List<Object> path) => _modify(path, null, remove: true);

  void remove(int index) => delete([index]);
}

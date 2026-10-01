/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// One entry of a `keybindings.json`, or of a keymap extension's
// `contributes.keybindings`, as VS Code reads and writes them.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/keybinding/common/keybindingsRegistry.ts
// (`IKeybindingRule`), src/vs/workbench/services/keybinding/common/
// keybindingIO.ts (`KeybindingIO.writeKeybindingItem`, `readUserKeybindingItem`)
// and src/vs/workbench/services/keybinding/browser/keybindingService.ts
// (`keybindingsExtPoint`'s `key`/`mac`/`linux`/`win`).

import 'package:flutter/foundation.dart';

/// The platform a keybinding is read for: what `cmd` means, and which of an
/// entry's `mac`/`win`/`linux` keys applies.
enum KeybindingPlatform {
  mac,
  windows,
  linux;

  /// The platform the app runs on (read at call time, so tests can
  /// override it).
  static KeybindingPlatform get current => switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.iOS => mac,
    TargetPlatform.windows => windows,
    _ => linux,
  };
}

/// One entry: [command] bound to a key sequence, when [when] holds.
///
/// A [command] starting with `-` removes the default keybinding(s) of the
/// rest (`-editor.action.commentLine`), those with the same [key] and
/// [when] when they are given.
@immutable
class KeybindingEntry {
  const KeybindingEntry({
    required this.command,
    this.key,
    this.mac,
    this.win,
    this.linux,
    this.when,
    this.args,
  });

  /// Reads one entry; null when [json] is not one (no `command`).
  static KeybindingEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final command = json['command'];
    if (command is! String || command.isEmpty) return null;
    String? string(String name) => switch (json[name]) {
      final String value => value,
      _ => null,
    };
    return KeybindingEntry(
      command: command,
      key: string('key'),
      mac: string('mac'),
      win: string('win'),
      linux: string('linux'),
      when: string('when'),
      args: json['args'],
    );
  }

  /// The entries of a `keybindings.json` (an array), skipping what is not
  /// one; empty when [json] is not an array.
  static List<KeybindingEntry> listFromJson(Object? json) => [
    if (json is List)
      for (final item in json) ?KeybindingEntry.fromJson(item),
  ];

  final String command;

  /// The key sequence (`shift+cmd+e`, `ctrl+k ctrl+s`), for every platform
  /// but one with its own below.
  final String? key;
  final String? mac;
  final String? win;
  final String? linux;

  /// A context key expression (`editorTextFocus && !editorReadonly`).
  final String? when;

  /// Passed to the command.
  final Object? args;

  /// Whether this removes default keybindings (`-command`).
  bool get isRemoval => command.startsWith('-');

  /// The command bound, without a removal's `-`.
  String get commandId => isRemoval ? command.substring(1) : command;

  /// The key sequence on [platform]: its own, else [key].
  String? keyFor(KeybindingPlatform platform) =>
      switch (platform) {
        KeybindingPlatform.mac => mac,
        KeybindingPlatform.windows => win,
        KeybindingPlatform.linux => linux,
      } ??
      key;

  /// As `keybindings.json` keeps it: `key`, `command`, then `when` and
  /// `args` when there are any (`KeybindingIO.writeKeybindingItem`).
  Map<String, Object?> toJson() => {
    'key': ?key,
    'mac': ?mac,
    'win': ?win,
    'linux': ?linux,
    'command': command,
    'when': ?when,
    'args': ?args,
  };

  KeybindingEntry copyWith({String? command, String? key, String? when}) =>
      KeybindingEntry(
        command: command ?? this.command,
        key: key ?? this.key,
        mac: mac,
        win: win,
        linux: linux,
        when: when ?? this.when,
        args: args,
      );

  @override
  bool operator ==(Object other) =>
      other is KeybindingEntry &&
      other.command == command &&
      other.key == key &&
      other.mac == mac &&
      other.win == win &&
      other.linux == linux &&
      other.when == when &&
      _deepEquals(other.args, args);

  @override
  int get hashCode => Object.hash(command, key, mac, win, linux, when);

  @override
  String toString() => 'KeybindingEntry(${toJson()})';
}

bool _deepEquals(Object? a, Object? b) {
  if (a is List && b is List) return listEquals(a, b);
  if (a is Map && b is Map) return mapEquals(a, b);
  return a == b;
}

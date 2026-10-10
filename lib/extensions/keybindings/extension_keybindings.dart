/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Extensions' `contributes.keybindings`, in the app's keybinding service:
// after BaoCode's defaults (so they win over them), before the keymap's and
// the user's `keybindings.json` (which win over them), their `when`
// clauses evaluated over the context keys extensions set too.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/keybinding/browser/keybindingService.ts
// (`isValidContributedKeyBinding`, `_handleKeybindingsExtensionPointUser`,
// `_handleKeybinding`, `bindToCurrentPlatform`, `_asCommandRule`: the
// command's `enablement` joins the `when` clause, weights
// `BuiltinExtension + idx` / `ExternalExtension + idx`) and
// src/vs/platform/keybinding/common/keybindingsRegistry.ts (`sorter`: by
// weight, then command, the later one winning).
//
// Deviations: the platform's key is chosen by the keybinding service
// (`KeybindingEntry.keyFor`), not here; messages for extension authors are
// collected in [ExtensionKeybindings.messages].

import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:flutter/foundation.dart';

import '../../keybindings/keybinding_service.dart';
import '../../keybindings/when_expression.dart' show ContextLookup;
import '../commands/command_contributions.dart';
import '../commands/extension_command_registry.dart';
import '../contextkey/context_key_service.dart';
import '../contextkey/contextkey.dart';

/// `KeybindingWeight`.
abstract final class KeybindingWeight {
  static const builtinExtension = 300;
  static const externalExtension = 400;
}

/// One extension keybinding (`IExtensionKeybindingRule`).
final class ExtensionKeybindingRule {
  const ExtensionKeybindingRule({
    required this.entry,
    required this.extensionId,
    required this.isBuiltin,
    required this.weight,
    this.when,
  });

  /// As `keybindings.json` writes it; its `when` the full clause.
  final KeybindingEntry entry;
  final String extensionId;
  final bool isBuiltin;
  final int weight;

  /// The `when` clause and the command's `enablement`, joined.
  final ContextKeyExpression? when;

  String get command => entry.command;
}

/// Every extension's keybindings, in the order they apply (the last that
/// applies wins).
final class ExtensionKeybindings {
  ExtensionKeybindings(
    List<ExtensionSource> extensions, {
    required CommandContributions commands,
  }) {
    for (final extension in extensions) {
      final value = extension.contributes['keybindings'];
      final list = value is List ? value : value == null ? const [] : [value];
      for (var i = 0; i < list.length; i++) {
        _handle(extension, i + 1, list[i], commands);
      }
    }
    // `sorter`: by weight, then by command (stable otherwise).
    final indexed = [for (final (i, r) in rules.indexed) (i, r)];
    indexed.sort((a, b) {
      final w = a.$2.weight - b.$2.weight;
      if (w != 0) return w;
      final c = a.$2.command.compareTo(b.$2.command);
      if (c != 0) return c;
      return a.$1 - b.$1;
    });
    rules
      ..clear()
      ..addAll([for (final (_, r) in indexed) r]);
  }

  final List<ExtensionKeybindingRule> rules = [];

  /// Problems in the manifests, for extension authors.
  final List<String> messages = [];

  void _handle(
    ExtensionSource extension,
    int idx,
    Object? raw,
    CommandContributions commands,
  ) {
    void reject(String m) => messages.add(
      '${extension.id}: Invalid `contributes.keybindings`: $m',
    );
    if (raw is! Map) {
      reject('expected non-empty value.');
      return;
    }
    if (raw['command'] is! String) {
      reject('property `command` is mandatory and must be of type `string`');
      return;
    }
    for (final prop in const ['key', 'when', 'mac', 'linux', 'win']) {
      final v = raw[prop];
      if (v != null && v != '' && v is! String) {
        reject('property `$prop` can be omitted or must be of type `string`');
        return;
      }
    }
    String? text(String prop) => switch (raw[prop]) {
      final String s when s.isNotEmpty => s,
      _ => null,
    };
    final command = raw['command'] as String;
    final whenText = text('when');
    final precondition = commands.byId[command]?.enablement;
    final ContextKeyExpression? fullWhen;
    if (whenText != null && precondition != null) {
      fullWhen = ContextKeyExpr.and([
        precondition,
        ContextKeyExpr.deserialize(whenText),
      ]);
    } else if (whenText != null) {
      fullWhen = ContextKeyExpr.deserialize(whenText);
    } else {
      fullWhen = precondition;
    }
    final entry = KeybindingEntry(
      command: command,
      key: text('key'),
      mac: text('mac'),
      win: text('win'),
      linux: text('linux'),
      when: fullWhen?.serialize() ?? whenText,
      args: raw['args'],
    );
    if (entry.key == null &&
        entry.mac == null &&
        entry.win == null &&
        entry.linux == null) {
      return;
    }
    rules.add(
      ExtensionKeybindingRule(
        entry: entry,
        extensionId: extension.id,
        isBuiltin: extension.isBuiltin,
        weight:
            (extension.isBuiltin
                ? KeybindingWeight.builtinExtension
                : KeybindingWeight.externalExtension) +
            idx,
        when: whenText != null && ContextKeyExpr.deserialize(whenText) == null
            // A clause that does not parse: upstream's `when` is then the
            // precondition alone (`deserialize` gives undefined).
            ? precondition
            : fullWhen,
      ),
    );
  }
}

/// Keeps the keybinding service's extension keybindings in step with the
/// extensions: [ExtensionKeybindingsBridge.new] pushes them, and again
/// whenever the registry changes (an extension activated and registered
/// its commands, or the extension list changed).
final class ExtensionKeybindingsBridge {
  ExtensionKeybindingsBridge({
    required this.registry,
    required this.contextKeys,
    KeybindingService? keybindings,
  }) : keybindings = keybindings ?? KeybindingService.instance {
    registry.addListener(_update);
    _update();
  }

  final ExtensionCommandRegistry registry;
  final ContextKeyValues contextKeys;
  final KeybindingService keybindings;

  /// The rules last pushed.
  ExtensionKeybindings get current => _current;
  ExtensionKeybindings _current = ExtensionKeybindings(
    const [],
    commands: CommandContributions(const []),
  );
  List<ExtensionSource>? _lastExtensions;
  Set<String> _lastCommands = const {};

  static bool _always(ContextLookup _) => true;

  /// [rule]'s clause over [context] (the workbench's, at the key press),
  /// then this workspace's context keys (extensions' `setContext` ones,
  /// `config.*`).
  bool Function(ContextLookup) _applies(ExtensionKeybindingRule rule) {
    final when = rule.when;
    if (when == null) return _always;
    return (context) =>
        when.evaluate((key) => context(key) ?? contextKeys.getContextKeyValue(key));
  }

  void _update() {
    final extensions = registry.extensions;
    final commands = {
      ...registry.contributions.byId.keys,
      for (final rule in _current.rules) rule.command,
    };
    if (!identical(extensions, _lastExtensions)) {
      _current = ExtensionKeybindings(
        extensions,
        commands: registry.contributions,
      );
      _lastExtensions = extensions;
    }
    // A keybinding whose command nothing has (an extension that never
    // registered it) is shown but never runs.
    final runnable = {
      for (final rule in _current.rules)
        if (registry.hasCommand(rule.command) ||
            registry.contributions.byId.containsKey(rule.command))
          rule.command,
    };
    if (setEquals(commands, _lastCommands) &&
        setEquals(runnable, _lastCommands)) {
      return;
    }
    _lastCommands = runnable;
    keybindings.setContributedKeybindings([
      for (final rule in _current.rules)
        ContributedKeybinding(
          entry: rule.entry,
          extensionId: rule.extensionId,
          applies: _applies(rule),
        ),
    ], commands: runnable);
  }

  void dispose() {
    registry.removeListener(_update);
    keybindings.setContributedKeybindings(const []);
  }
}

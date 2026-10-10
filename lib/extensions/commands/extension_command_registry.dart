/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Every command an extension can run or contribute: BaoCode's own
// (IdeCommand), the built-in ones extensions call (`vscode.open`…), and
// extensions' (registered in the extension host, declared in
// `contributes.commands`); and running one as VS Code's command service
// does, activating `onCommand:<id>` first.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/commands/common/commandService.ts
// (`CommandService.executeCommand`, `_activateStar`, `_tryExecuteCommand`)
// and src/vs/platform/commands/common/commands.ts (`CommandsRegistry`:
// the latest registration of an id wins).
//
// Deviations:
// - Three layers instead of one registry: an extension's registration
//   wins over a built-in handler, which wins over BaoCode's command of the
//   same id (the order upstream's registrations happen in).
// - A BaoCode command that is disabled (IdeCommand.enabled false) does
//   nothing; one takes a single argument, the first.
// - `*` activation is raced against registration without upstream's 30s
//   cap (the extension host manager has its own timeouts).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ide/ide_commands.dart';
import 'builtin_commands.dart';
import 'command_contributions.dart';

/// Activating extensions for a command (`IExtensionService`'s part the
/// command service uses).
abstract interface class CommandActivation {
  Future<void> activateByEvent(String activationEvent);

  /// Whether [activationEvent] was activated already.
  bool activationEventIsDone(String activationEvent);

  /// Whether the extension host runs (`whenInstalledExtensionsRegistered`).
  bool get extensionHostIsReady;
}

/// Runs an extension's command in its extension host
/// (`ExtHostCommands.$executeContributedCommand`).
typedef ExtensionCommandExecutor =
    Future<Object?> Function(String id, List<Object?> args);

/// An error a command reports, as the extension host gets it.
final class CommandError implements Exception {
  const CommandError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The commands of one workspace.
final class ExtensionCommandRegistry extends ChangeNotifier {
  ExtensionCommandRegistry({
    this.appCommands,
    this.activation,
    BuiltinCommands? builtins,
  }) : builtins = builtins ?? BuiltinCommands();

  /// BaoCode's commands by id (the workbench's palette and keyboard
  /// commands), read when needed.
  Map<String, IdeCommand> Function()? appCommands;

  /// Activates extensions (the [ExtensionHostService]'s).
  CommandActivation? activation;

  final BuiltinCommands builtins;

  /// `contributes.commands` of every extension.
  CommandContributions get contributions => _contributions;
  CommandContributions _contributions = CommandContributions(const []);

  /// The extensions, as the extension host scanned them.
  List<ExtensionSource> get extensions => _extensions;
  List<ExtensionSource> _extensions = const [];

  /// After the extensions change.
  void setExtensions(List<Map<String, Object?>> descriptions) {
    _extensions = [
      for (final d in descriptions) ExtensionSource.fromDescription(d),
    ];
    _contributions = CommandContributions(_extensions);
    notifyListeners();
  }

  /// Its declaration in some extension's `contributes.commands`.
  ExtensionCommandContribution? contribution(String id) =>
      _contributions.byId[id];

  final _extensionCommands = <String, List<ExtensionCommandExecutor>>{};
  final _onDidRegisterCommand = StreamController<String>.broadcast(
    sync: true,
  );

  /// Ids as extensions (or built-ins) register them.
  Stream<String> get onDidRegisterCommand => _onDidRegisterCommand.stream;

  /// `$registerCommand`: [id] runs in an extension host through
  /// [executor]. Returns what removes it.
  void Function() registerExtensionCommand(
    String id,
    ExtensionCommandExecutor executor,
  ) {
    final list = _extensionCommands.putIfAbsent(id, () => []);
    list.add(executor);
    _onDidRegisterCommand.add(id);
    notifyListeners();
    return () {
      if (!list.remove(executor)) return;
      if (list.isEmpty && identical(_extensionCommands[id], list)) {
        _extensionCommands.remove(id);
      }
      notifyListeners();
    };
  }

  /// Whether an extension registered [id] (in its extension host).
  bool isExtensionCommand(String id) =>
      _extensionCommands[id]?.isNotEmpty ?? false;

  IdeCommand? _appCommand(String id) => appCommands?.call()[id];

  /// `CommandsRegistry.getCommand(id) != null`.
  bool hasCommand(String id) =>
      isExtensionCommand(id) || builtins.has(id) || _appCommand(id) != null;

  /// `CommandsRegistry.getCommands().keys`: every id that runs now.
  List<String> get commandIds => {
    ...?appCommands?.call().keys,
    ...builtins.ids,
    ..._extensionCommands.keys,
  }.toList();

  Future<void>? _starActivation;

  Future<void> _activateStar() =>
      _starActivation ??= activation?.activateByEvent('*') ?? Future.value();

  /// `CommandService.executeCommand`: runs [id] with [args], activating
  /// the extensions listening to `onCommand:<id>` first.
  Future<Object?> executeCommand(String id, [List<Object?> args = const []]) async {
    final activationEvent = 'onCommand:$id';
    final activation = this.activation;
    if (hasCommand(id)) {
      if (activation == null || activation.activationEventIsDone(activationEvent)) {
        return _tryExecuteCommand(id, args);
      }
      if (!activation.extensionHostIsReady) {
        unawaited(activation.activateByEvent(activationEvent).catchError((Object _) {}));
        return _tryExecuteCommand(id, args);
      }
      await activation.activateByEvent(activationEvent);
      return _tryExecuteCommand(id, args);
    }
    if (activation != null) {
      final registered = Completer<void>();
      final subscription = onDidRegisterCommand.listen((registeredId) {
        if (registeredId == id && !registered.isCompleted) registered.complete();
      });
      final builtinSubscription = builtins.onDidRegister.listen((registeredId) {
        if (registeredId == id && !registered.isCompleted) registered.complete();
      });
      try {
        await Future.wait([
          activation.activateByEvent(activationEvent),
          Future.any([_activateStar(), registered.future]),
        ]);
      } finally {
        await subscription.cancel();
        await builtinSubscription.cancel();
      }
    }
    return _tryExecuteCommand(id, args);
  }

  Future<Object?> _tryExecuteCommand(String id, List<Object?> args) async {
    final executors = _extensionCommands[id];
    if (executors != null && executors.isNotEmpty) {
      return executors.last(id, args);
    }
    final builtin = builtins.lookup(id);
    if (builtin != null) return builtin(args);
    final app = _appCommand(id);
    if (app != null) {
      if (app.enabled) app.invoke(args.isEmpty ? null : args.first);
      return null;
    }
    throw CommandError("command '$id' not found");
  }

  @override
  void dispose() {
    unawaited(_onDidRegisterCommand.close());
    builtins.dispose();
    super.dispose();
  }
}

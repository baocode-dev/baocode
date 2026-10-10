/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadCommands.ts.
//
// Deviations:
// - Commands go to the workspace's [ExtensionCommandRegistry] (upstream's
//   `CommandsRegistry` and `ICommandService`); registrations end with the
//   session.
// - No `_generateCommandsDocumentation` (a developer command).
// - A command that fails rejects with its message as an `Error` (upstream
//   rejects with the error object itself).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../commands/command_arguments.dart';
import '../commands/extension_command_registry.dart';
import 'main_thread_context.dart';

final class MainThreadCommands extends MainThreadCommandsUnsupported {
  MainThreadCommands(this._registry, this._proxy, {this.activation});

  final ExtensionCommandRegistry _registry;
  final ExtHostCommandsProxy _proxy;

  /// Activates extensions; the registry's when null.
  final CommandActivation? activation;

  final _registrations = <String, void Function()>{};

  static RpcActor customer(MainThreadContext context) {
    final actor = MainThreadCommands(
      context.service<ExtensionCommandRegistry>(),
      ExtHostCommandsProxy(context.rpc),
      activation: context.maybeService<CommandActivation>(),
    );
    context.onDispose(actor.dispose);
    return MainThreadCommandsActor(actor);
  }

  CommandActivation? get _activation => activation ?? _registry.activation;

  void dispose() {
    for (final unregister in _registrations.values) {
      unregister();
    }
    _registrations.clear();
  }

  @override
  void $registerCommand(String id) {
    _registrations.remove(id)?.call();
    _registrations[id] = _registry.registerExtensionCommand(id, (
      id,
      args,
    ) async {
      final result = await _proxy.$executeContributedCommand(id, args);
      return reviveMarshalled(result);
    });
  }

  @override
  void $unregisterCommand(String id) => _registrations.remove(id)?.call();

  @override
  void $fireCommandActivationEvent(String id) {
    final activationEvent = 'onCommand:$id';
    final activation = _activation;
    if (activation != null && !activation.activationEventIsDone(activationEvent)) {
      // Drive-by activation: not awaited.
      unawaited(
        activation.activateByEvent(activationEvent).catchError((Object _) {}),
      );
    }
  }

  @override
  Future<Object?> $executeCommand(String id, Object? args, bool retry) async {
    final raw = switch (args) {
      RpcObjectWithBuffers(:final value) => value,
      _ => args,
    };
    final list = [
      if (raw is List)
        for (final a in raw) reviveMarshalled(a),
    ];
    if (retry && list.isNotEmpty && !_registry.hasCommand(id)) {
      await _activation?.activateByEvent('onCommand:$id');
      throw RpcRemoteError(name: 'Error', message: r'$executeCommand:retry');
    }
    try {
      return await _registry.executeCommand(id, list);
    } on RpcRemoteError {
      rethrow;
    } on CancellationException {
      rethrow;
    } on Object catch (error) {
      throw RpcRemoteError(
        name: 'Error',
        message: error is CommandError ? error.message : '$error',
      );
    }
  }

  @override
  Future<List<String>> $getCommands() async => _registry.commandIds;
}

// Activation for commands through the workspace's extension host.

import '../extension_host_service_io.dart';
import '../host/extension_host_manager.dart';
import 'extension_command_registry.dart';

/// [CommandActivation] over an [ExtensionHostService].
final class ExtensionHostCommandActivation implements CommandActivation {
  ExtensionHostCommandActivation(this.host);

  final ExtensionHostService host;

  @override
  Future<void> activateByEvent(String activationEvent) =>
      host.activateByEvent(activationEvent);

  @override
  bool activationEventIsDone(String activationEvent) =>
      host.manager.activatedOn(activationEvent);

  @override
  bool get extensionHostIsReady =>
      host.manager.state == ExtensionHostState.running;
}

// Activation for commands through the workspace's extension hosts.

import '../extension_host_service_io.dart';
import '../host/extension_host_manager.dart';
import 'extension_command_registry.dart';

/// [CommandActivation] over a workspace's [ExtensionHostService]s (a remote
/// project has two: its host's and this machine's).
final class ExtensionHostCommandActivation implements CommandActivation {
  ExtensionHostCommandActivation(ExtensionHostService host) : hosts = [host];

  ExtensionHostCommandActivation.all(this.hosts);

  final List<ExtensionHostService> hosts;

  @override
  Future<void> activateByEvent(String activationEvent) => Future.wait([
    for (final host in hosts) host.activateByEvent(activationEvent),
  ]);

  @override
  bool activationEventIsDone(String activationEvent) =>
      hosts.every((host) => host.manager.activatedOn(activationEvent));

  @override
  bool get extensionHostIsReady => hosts.every(
    (host) => host.manager.state == ExtensionHostState.running,
  );
}

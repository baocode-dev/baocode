// Language servers of remote projects. The client (the editor's features,
// the catalog, the user's LSP settings, the mason registry) stays in the
// app; the servers run on the host, their bytes carried by its server. A
// server not there is installed there, by the host's server, from the
// registry's package the app sends.

import 'dart:async';

import 'package:bao_remote/client.dart';
import 'package:path/path.dart' as p;

import '../ide/lsp/catalog/standard_lsp.dart';
import '../ide/lsp/install/mason_registry.dart';
import '../ide/lsp/install/mason_server_provider.dart';
import '../ide/lsp/lsp_manager.dart';
import '../ide/lsp/lsp_server_definition.dart';
import 'remote_services.dart';
import 'ssh_host.dart';

/// Finds language servers on [host] (its login shell's PATH, or those
/// installed there) and installs them there.
class RemoteLspProvider implements LspServerProvider {
  RemoteLspProvider(this.host, this._registry);

  final SshHost host;
  final Future<MasonRegistry> _registry;

  /// The installs under way, by host and package: one each, whichever
  /// project asked.
  static final Map<(String, String), Future<void>> _installs = {};

  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async {
    final client = await host.ready;
    final registry = await _registry;
    final packages = {
      ?registry[server.masonPackage ?? ''],
      ?registry.providing(server.command),
    };
    return client.locateLanguageServer(
      server.command,
      masonPackage: server.masonPackage,
      packages: [...packages],
    );
  }

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) {
    final key = (host.host, package);
    return _installs[key] ??= _install(package, onProgress).whenComplete(() {
      _installs.remove(key);
    });
  }

  Future<void> _install(
    String name,
    void Function(String message)? onProgress,
  ) async {
    final package = (await _registry)[name];
    if (package == null) {
      throw LspInstallException('$name is not in the registry');
    }
    final client = await host.ready;
    onProgress?.call('Installing $name on ${host.host}…');
    await client.installLanguageServer(package, onProgress: onProgress);
  }
}

/// The language servers of the project at [root] on [host]: the standard
/// catalog, its servers run there.
class RemoteLspManager extends LspManager {
  RemoteLspManager._(
    this.host,
    String root,
    LspCatalog catalog,
    LspServerProvider provider,
  ) : super(
        root,
        catalog,
        provider,
        startProcess: remoteLspStarter(host),
        watchDirectory: remoteLspWatcher(host),
        pathExists: (path) async {
          try {
            return await (await host.ready).stat(path) != null;
          } on Object {
            return false;
          }
        },
        listDirectory: (directory) async {
          try {
            return await (await host.ready).entries(directory);
          } on Object {
            return const [];
          }
        },
        paths: p.posix,
        processId: () => host.hello?.pid,
      ) {
    // What ran over a lost connection is gone with it: started again.
    _reconnected = host.reconnected.listen((_) => restartServers());
  }

  factory RemoteLspManager(SshHost host, String root) {
    final loading = standardLsp();
    final catalog = LoadingLspCatalog();
    final manager = RemoteLspManager._(
      host,
      root,
      catalog,
      RemoteLspProvider(host, loading.then(_registryOf)),
    );
    unawaited(
      loading.then((lsp) {
        catalog.loaded = lsp.catalog;
        manager.reloadCatalog();
      }, onError: (Object _) {}),
    );
    return manager;
  }

  final SshHost host;
  late final StreamSubscription<RemoteClient> _reconnected;

  static MasonRegistry _registryOf(StandardLsp lsp) => switch (lsp.provider) {
    final MasonServerProvider provider => provider.registry,
    _ => MasonRegistry(const []),
  };

  @override
  Future<void> shutdown() {
    unawaited(_reconnected.cancel());
    return super.shutdown();
  }
}

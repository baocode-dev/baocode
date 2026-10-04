import 'dart:async';

import '../lsp/install/mason_registry.dart';
import '../lsp/install/mason_server_provider.dart';
import '../lsp/lsp_server_definition.dart';
import '../protocol.dart';
import '../rpc/rpc_peer.dart';
import 'remote_server.dart';
import 'server_streams.dart';

/// Language servers of this machine: found on its login shell's PATH or
/// among those installed under [installRoot], and installed there from the
/// mason-registry package the app sends (the registry is the app's).
class ServerLsp {
  ServerLsp(RpcPeer peer, this._streams, {required this.installRoot}) {
    final handlers = peer.handlers;
    handlers[RemoteProtocol.lspLocate] = (params, _) async {
      final args = paramsOf(params);
      final location = await _provider(args['packages']).locate(
        LspServerDefinition(
          id: args['command'] as String,
          command: args['command'] as String,
          masonPackage: args['masonPackage'] as String?,
        ),
      );
      return switch (location) {
        LspServerFound(:final executable) => {'found': executable},
        LspServerMissing(:final package, :final missingRuntime) => {
          'package': ?package,
          'missingRuntime': ?missingRuntime,
        },
      };
    };
    handlers[RemoteProtocol.lspInstall] = (params, _) {
      final args = paramsOf(params);
      final provider = _provider(args['packages']);
      final progress = StreamController<Object?>();
      final install = provider.install(
        args['package'] as String,
        onProgress: progress.add,
      );
      _installs.add(progress);
      unawaited(
        install
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) =>
                  progress.addError(error, stack),
            )
            .whenComplete(() {
              _installs.remove(progress);
              unawaited(progress.close());
            }),
      );
      return _streams.open(progress.stream);
    };
    handlers[RemoteProtocol.lspInstalled] = (_, _) =>
        _provider(null).installedPackages();
    handlers[RemoteProtocol.lspUninstall] = (params, _) async {
      await _provider(null).uninstall(paramsOf(params)['package'] as String);
      return null;
    };
  }

  final String installRoot;
  final ServerStreams _streams;
  final Set<StreamController<Object?>> _installs = {};

  /// The provider of the packages the app sent: the one asked for, and
  /// the one providing the command, if they differ.
  MasonServerProvider _provider(Object? packages) => MasonServerProvider(
    registry: MasonRegistry([
      for (final package in packages as List? ?? const [])
        MasonPackage.fromJson((package as Map).cast<String, Object?>()),
    ]),
    installRoot: installRoot,
  );

  Future<void> cancelAll() async {
    for (final progress in [..._installs]) {
      await progress.close();
    }
  }
}

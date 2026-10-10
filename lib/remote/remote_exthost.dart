// The extensions of a remote project run on its host, as VS Code's do: the
// extension runtime installed there (downloaded by the host, or by this
// machine and sent over the connection when the host cannot reach the
// downloads), its VS Code server started there by the BaoCode server, and
// every connection to it made through the SSH connection
// (`tcp/connect`): nothing listens on this machine.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:bao_remote/client.dart';
import 'package:path/path.dart' as p;

import '../extensions/host/extension_server_io.dart';

/// Where installing the runtime on a host is at.
final class RemoteRuntimeProgress {
  const RemoteRuntimeProgress(
    this.phase, {
    this.received = 0,
    this.total = 0,
    this.uploading = false,
  });

  /// `downloading`, `verifying`, `extracting`… (a [RuntimePhase]'s name).
  final String phase;
  final int received;
  final int total;

  /// Sent from this machine (the host cannot reach the downloads).
  final bool uploading;
}

/// A connection to a port of the remote host as the extension protocols
/// take a socket.
final class TunnelExtHostSocket implements ExtHostSocket {
  TunnelExtHostSocket(this._tunnel);

  final RemoteTunnel _tunnel;

  @override
  Stream<Uint8List> get data => _tunnel.data;

  @override
  void write(Uint8List bytes) => _tunnel.add(bytes);

  /// The bytes are handed to the SSH connection as they are written.
  @override
  Future<void> drain() async {}

  @override
  Future<void> close() => _tunnel.close();
}

/// The extension runtime platform of a host ([RemoteHello.platform]);
/// null when there is no build for it (musl, Windows).
String? remoteExtHostPlatform(RemotePlatform platform) {
  if (platform.libc == 'musl') return null;
  final name = '${platform.os}-${platform.arch}';
  return extHostRuntimePlatforms.contains(name) && platform.os != 'win'
      ? name
      : null;
}

/// Installs [manifest]'s runtime on [client]'s host unless it is there,
/// then starts its VS Code server there and connects to it.
///
/// The host downloads the runtime itself; when it cannot, the archive is
/// downloaded into [downloads] here (once for every host of the platform)
/// and sent.
Future<ExtensionServer> startRemoteExtensionServer(
  RemoteClient client, {
  required ExtHostRuntimeManifest manifest,
  required String downloads,
  void Function(RemoteRuntimeProgress progress)? onProgress,
}) async {
  final json = manifest.toJson();
  void progress(String phase, int received, int total) => onProgress?.call(
    RemoteRuntimeProgress(phase, received: received, total: total),
  );
  try {
    await client.installExtHostRuntime(json, onProgress: progress);
  } on ExtHostRuntimeException catch (error) {
    if (error.kind != ExtHostRuntimeErrorKind.network) rethrow;
    final platform = switch (client.hello?.platform) {
      final platform? => remoteExtHostPlatform(platform),
      null => null,
    };
    final asset = platform == null ? null : manifest[platform];
    if (platform == null || asset == null) rethrow;
    final archive = p.join(downloads, asset.file);
    await ExtHostRuntimeInstaller(
      manifest: manifest,
      directory: downloads,
    ).downloadArchive(
      platform: platform,
      file: archive,
      onProgress: (event) => onProgress?.call(
        RemoteRuntimeProgress(
          event.phase.name,
          received: event.received,
          total: event.total,
        ),
      ),
    );
    await client.uploadExtHostRuntime(
      json,
      File(archive),
      onProgress: (sent, size) => onProgress?.call(
        RemoteRuntimeProgress(
          RuntimePhase.downloading.name,
          received: sent,
          total: size,
          uploading: true,
        ),
      ),
    );
    await client.installExtHostRuntime(
      json,
      uploaded: true,
      onProgress: progress,
    );
  }
  final started = await client.startExtHostServer(json);
  return ExtensionServer.connect(
    ServerAddress(
      host: '127.0.0.1',
      port: started.port,
      connectionToken: started.connectionToken,
      commit: started.product['commit'] as String,
    ),
    connector: (host, port) async =>
        TunnelExtHostSocket(await client.connectTcp(port, host: host)),
    product: started.product,
  );
}

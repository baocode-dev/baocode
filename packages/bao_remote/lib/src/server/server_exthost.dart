import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;

import '../protocol.dart';
import '../rpc/rpc_peer.dart';
import 'remote_server.dart' show paramsOf;
import 'server_streams.dart';

/// The extension runtime here, for the app's extensions on a remote
/// project: installed from the downloads ([RemoteProtocol.exthostInstall])
/// or from the archive the app sends where this host cannot reach them
/// ([RemoteProtocol.exthostUpload]), and its VS Code server, started for the
/// connection ([RemoteProtocol.exthostStart]) and ended with it.
///
/// Its state: `<dataDir>/exthost/runtimes/<id>/` (the runtimes),
/// `uploads/` (archives being sent), `data/` (the server's data) and
/// `extensions/` (the extensions installed on this host).
class ServerExtHost {
  ServerExtHost(RpcPeer peer, this._streams, {required this.directory}) {
    peer.handlers[RemoteProtocol.exthostInstall] = (params, _) async =>
        _install(paramsOf(params));
    peer.handlers[RemoteProtocol.exthostUpload] = (params, _) =>
        _upload(paramsOf(params));
    peer.handlers[RemoteProtocol.exthostStart] = (params, _) =>
        _start(paramsOf(params));
  }

  final ServerStreams _streams;

  /// `<dataDir>/exthost`.
  final String directory;

  String get _runtimes => p.join(directory, 'runtimes');
  String get _uploads => p.join(directory, 'uploads');

  StartedExtensionServer? _server;
  Future<Map<String, Object?>>? _starting;

  static ExtHostRuntimeManifest _manifest(Map<String, Object?> args) =>
      ExtHostRuntimeManifest.fromJson(args['manifest']);

  static String _platform() =>
      currentExtHostPlatform() ??
      (throw const ExtHostRuntimeException(
        ExtHostRuntimeErrorKind.unsupportedPlatform,
        'There is no extension runtime for this host',
      ));

  ExtHostRuntimeInstaller _installer(
    ExtHostRuntimeManifest manifest, {
    bool uploaded = false,
  }) => ExtHostRuntimeInstaller(
    manifest: uploaded
        ? manifest.withBaseUrl(Uri.directory(_uploads).toString())
        : manifest,
    directory: _runtimes,
    // What the app asks for, not the variables of whoever started this.
    environment: const {},
  );

  /// Installs the runtime unless it is: its progress, `{phase, received,
  /// total}`, as a stream. `uploaded`: from the archive sent.
  int _install(Map<String, Object?> args) {
    final manifest = _manifest(args);
    final uploaded = args['uploaded'] == true;
    final progress = StreamController<Object?>();
    unawaited(() async {
      try {
        await _installer(manifest, uploaded: uploaded).ensure(
          platform: _platform(),
          onProgress: (event) => progress.add({
            'phase': event.phase.name,
            'received': event.received,
            'total': event.total,
          }),
        );
        if (uploaded) await _deleteUploads(manifest);
      } on Object catch (error, stack) {
        progress.addError(error, stack);
      } finally {
        await progress.close();
      }
    }());
    return _streams.open(progress.stream);
  }

  /// A piece of the archive the app downloaded: `{manifest, offset, data}`,
  /// in order. Whether it is whole.
  Future<bool> _upload(Map<String, Object?> args) async {
    final manifest = _manifest(args);
    final asset = manifest[_platform()];
    if (asset == null) {
      throw const ExtHostRuntimeException(
        ExtHostRuntimeErrorKind.unsupportedPlatform,
        'There is no extension runtime for this host',
      );
    }
    final offset = args['offset'] as int;
    final data = decodeBytes(args['data']);
    final part = File(p.join(_uploads, asset.file));
    if (offset == 0) {
      await part.parent.create(recursive: true);
      await part.writeAsBytes(const []);
    } else if (!await part.exists() || await part.length() != offset) {
      throw const ExtHostRuntimeException(
        ExtHostRuntimeErrorKind.verification,
        'The extension runtime was not uploaded whole',
      );
    }
    await part.writeAsBytes(data, mode: FileMode.append, flush: true);
    return offset + data.length >= asset.size;
  }

  Future<void> _deleteUploads(ExtHostRuntimeManifest manifest) async {
    final asset = manifest[_platform()];
    if (asset == null) return;
    try {
      await File(p.join(_uploads, asset.file)).delete();
    } on FileSystemException {
      // Not there.
    }
  }

  /// The installed runtime's server, started unless it runs:
  /// `{port, connectionToken, product, platform}` (its `product.json`).
  Future<Map<String, Object?>> _start(Map<String, Object?> args) {
    if (_server case final server?) {
      return Future.value(_described(server, args));
    }
    return _starting ??= () async {
      try {
        final manifest = _manifest(args);
        final platform = _platform();
        final runtime = await _installer(
          manifest,
        ).installed(platform: platform);
        if (runtime == null) {
          throw const ExtHostRuntimeException(
            ExtHostRuntimeErrorKind.install,
            'The extension runtime is not installed on this host',
          );
        }
        final server = await StartedExtensionServer.start(
          node: runtime.nodeExecutable,
          serverMain: runtime.serverMain,
          serverDataDir: p.join(directory, 'data'),
          extensionsDir: p.join(directory, 'extensions'),
        );
        _server = server;
        unawaited(
          server.process.exitCode.then((_) {
            if (identical(_server, server)) _server = null;
          }),
        );
        return _described(server, args, runtime: runtime);
      } finally {
        _starting = null;
      }
    }();
  }

  ExtHostRuntime? _runtime;

  Map<String, Object?> _described(
    StartedExtensionServer server,
    Map<String, Object?> args, {
    ExtHostRuntime? runtime,
  }) {
    if (runtime != null) _runtime = runtime;
    return {
      'port': server.port,
      'connectionToken': server.connectionToken,
      'platform': _platform(),
      'product': jsonDecode(File(_runtime!.productJson).readAsStringSync()),
    };
  }

  /// Ends the server.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server == null) return;
    server.process.kill();
    await server.process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        server.process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }
}

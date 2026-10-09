import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../platform/child_process_registry.dart';
import '../../platform/data_dir.dart';
import 'server_uris.dart';

/// How to run a VS Code server (the runtime's `node` and `server-main.js`)
/// and where it keeps its state.
final class ExtensionServerLaunch {
  const ExtensionServerLaunch({
    required this.node,
    required this.serverMain,
    required this.commit,
    required this.serverDataDir,
    required this.extensionsDir,
    this.environment = const {},
  });

  final String node;
  final String serverMain;

  /// The runtime's `product.json` commit: connections must present it.
  final String commit;

  /// `--server-data-dir`: the server's logs, machine settings and the
  /// extensions' global storage.
  final String serverDataDir;

  /// `--extensions-dir`: installed extensions, in VS Code's layout.
  final String extensionsDir;

  final Map<String, String> environment;
}

/// The environment the server runs in: the app's, without what would
/// point it elsewhere (`npm_config_arch` picks a ripgrep the runtime does
/// not ship; the `VSCODE_*`/`ELECTRON_*` of a VS Code terminal the app
/// may have been started from), plus [extra].
Map<String, String> serverEnvironment(
  Map<String, String> parent,
  Map<String, String> extra,
) => {
  for (final MapEntry(:key, :value) in parent.entries)
    if (key.toLowerCase() != 'npm_config_arch' &&
        !key.startsWith('VSCODE_') &&
        !key.startsWith('ELECTRON_'))
      key: value,
  ...extra,
};

/// The server's `IRemoteAgentEnvironment`, with `file:` URIs.
typedef ServerEnvironment = Map<String, Object?>;

/// A running VS Code server (`server-main.js`) and its management
/// connection: one per app for this machine; extension hosts are started
/// through it, one per workspace.
final class ExtensionServer {
  ExtensionServer._(
    this.address,
    this.management,
    this._connection,
    this._process,
  );

  /// The connection details extension hosts are started with.
  final ServerAddress address;

  /// The management connection's channels (`remoteextensionsenvironment`,
  /// `remoteExtensionsScanner`, `extensions`, …).
  final IpcClient management;
  final RemoteConnection _connection;
  final Process? _process;

  /// The server's processes, ended by the next run if this one cannot.
  @visibleForTesting
  static ChildProcessRegistry registry = ChildProcessRegistry(
    file: File(DataDirectory.current.processRegistryFile('exthost')),
    recognizes: (command) => command.contains('server-main.js'),
  );

  final _exited = Completer<int>();

  /// Completes with the server's exit code once it ends (or its management
  /// connection does).
  Future<int> get exited => _exited.future;
  bool get isRunning => !_exited.isCompleted;

  /// Starts a server for [launch] and connects to it.
  static Future<ExtensionServer> start(ExtensionServerLaunch launch) async {
    await registry.reaped;
    await Directory(launch.serverDataDir).create(recursive: true);
    await Directory(launch.extensionsDir).create(recursive: true);
    final token = _token();
    final tokenFile = File(p.join(launch.serverDataDir, 'connection-token'));
    await tokenFile.writeAsString(token, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', tokenFile.path]);
    }
    final process = await Process.start(
      launch.node,
      [
        launch.serverMain,
        '--host',
        '127.0.0.1',
        '--port',
        '0',
        '--connection-token-file',
        tokenFile.path,
        '--server-data-dir',
        launch.serverDataDir,
        '--extensions-dir',
        launch.extensionsDir,
        '--accept-server-license-terms',
        '--telemetry-level',
        'off',
      ],
      environment: serverEnvironment(Platform.environment, launch.environment),
      includeParentEnvironment: false,
    );
    unawaited(registry.add(process.pid));
    final port = Completer<int>();
    final output = StringBuffer();
    void onLine(String line) {
      if (output.length < 16 * 1024) output.writeln(line);
      final m = _listening.firstMatch(line);
      if (m != null && !port.isCompleted) port.complete(int.parse(m[1]!));
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine);
    unawaited(
      process.exitCode.then((code) {
        unawaited(registry.remove(process.pid));
        if (!port.isCompleted) {
          port.completeError(
            ExtensionServerException('exited with $code', '$output'),
          );
        }
      }),
    );
    final int listening;
    try {
      listening = await port.future.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      process.kill();
      throw ExtensionServerException('did not start listening', '$output');
    }
    final address = ServerAddress(
      host: '127.0.0.1',
      port: listening,
      connectionToken: token,
      commit: launch.commit,
    );
    final server = await connect(address, process: process);
    return server;
  }

  /// Connects to a server already listening at [address] (a remote one,
  /// through [connector]); [process] is ours to end when it is local.
  static Future<ExtensionServer> connect(
    ServerAddress address, {
    Process? process,
    SocketConnector? connector,
  }) async {
    final connection = connector == null
        ? await connectToServer(address, ConnectionType.management)
        : await connectToServer(
            address,
            ConnectionType.management,
            connector: connector,
          );
    final ipc = IpcClient(ProtocolMessagePassing(connection.protocol), {
      'remoteAuthority': serverAuthority,
      'clientId': 'baocode-$pid',
    });
    final server = ExtensionServer._(address, ipc, connection, process);
    connection.protocol.onDidDispose.listener = (_) => server._end(-1);
    unawaited(process?.exitCode.then(server._end));
    return server;
  }

  void _end(int code) {
    if (_exited.isCompleted) return;
    _exited.complete(code);
    management.dispose();
  }

  /// `remoteextensionsenvironment.getEnvironmentData`.
  Future<ServerEnvironment> environment() async {
    final data = await management
        .getChannel('remoteextensionsenvironment')
        .call('getEnvironmentData', {'remoteAuthority': serverAuthority});
    return (fromServer(data) as Map).cast<String, Object?>();
  }

  /// `remoteExtensionsScanner.scanExtensions`: the server's builtin and
  /// installed extensions, plus those under development in
  /// [developmentLocations], as `IExtensionDescription`s with `file:` URIs.
  Future<List<Map<String, Object?>>> scanExtensions({
    String language = 'en',
    List<VsUri> developmentLocations = const [],
  }) async {
    final scanned = await management.getChannel('remoteExtensionsScanner').call(
      'scanExtensions',
      [
        language,
        null,
        <Object?>[],
        [for (final uri in developmentLocations) toServer(uri).toJson()],
        null,
      ],
    );
    return [
      for (final e in fromServer(scanned) as List)
        (e as Map).cast<String, Object?>(),
    ];
  }

  /// The management channel [name].
  IpcChannel channel(String name) => management.getChannel(name);

  /// Ends the connection, and the server when it is ours.
  Future<void> dispose() async {
    _end(0);
    try {
      _connection.protocol.sendDisconnect();
      await _connection.protocol.drain();
    } on Object {
      // Already gone.
    }
    await _connection.protocol.close();
    final process = _process;
    if (process != null) {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
  }

  static final _listening = RegExp(r'Extension host agent listening on (\d+)');

  static String _token() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 24; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}

/// The server did not start.
final class ExtensionServerException implements Exception {
  const ExtensionServerException(this.message, this.output);

  final String message;

  /// What it printed.
  final String output;

  @override
  String toString() => 'Extension server $message\n$output';
}

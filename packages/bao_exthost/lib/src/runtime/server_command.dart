// How a VS Code server (`server-main.js` of the runtime) is started, the
// same on this machine and on a remote host.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'runtime.dart';

/// The arguments `node` runs [ExtHostRuntime.serverMain] with: listening on
/// 127.0.0.1 at a port it picks, the token from [connectionTokenFile].
List<String> extensionServerArguments({
  required String serverMain,
  required String connectionTokenFile,
  required String serverDataDir,
  required String extensionsDir,
}) => [
  serverMain,
  '--host',
  '127.0.0.1',
  '--port',
  '0',
  '--connection-token-file',
  connectionTokenFile,
  '--server-data-dir',
  serverDataDir,
  '--extensions-dir',
  extensionsDir,
  '--accept-server-license-terms',
  '--telemetry-level',
  'off',
];

/// The line the server prints once it listens, with its port.
final extensionServerListening = RegExp(
  r'Extension host agent listening on (\d+)',
);

/// The environment the server runs in: [parent]'s, without what would
/// point it elsewhere (`npm_config_arch` picks a ripgrep the runtime does
/// not ship; the `VSCODE_*`/`ELECTRON_*` of a VS Code terminal the app
/// may have been started from), plus [extra].
Map<String, String> extensionServerEnvironment(
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

/// A new connection token (48 hex digits).
String newConnectionToken() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 24; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// A server started from a runtime, listening.
final class StartedExtensionServer {
  StartedExtensionServer._(this.process, this.port, this.connectionToken);

  final Process process;
  final int port;
  final String connectionToken;

  /// Starts the server ([ExtHostRuntime.nodeExecutable] running
  /// [ExtHostRuntime.serverMain]) keeping its state in [serverDataDir] and
  /// its extensions in [extensionsDir]; waits until it listens (60 s at
  /// most). Throws an [ExtensionServerStartException] when it ends or does
  /// not listen.
  static Future<StartedExtensionServer> start({
    required String node,
    required String serverMain,
    required String serverDataDir,
    required String extensionsDir,
    Map<String, String> environment = const {},
    Map<String, String>? parentEnvironment,
    void Function(int pid)? onStarted,
  }) async {
    await Directory(serverDataDir).create(recursive: true);
    await Directory(extensionsDir).create(recursive: true);
    final token = newConnectionToken();
    final tokenFile = File(p.join(serverDataDir, 'connection-token'));
    await tokenFile.writeAsString(token, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', tokenFile.path]);
    }
    final process = await Process.start(
      node,
      extensionServerArguments(
        serverMain: serverMain,
        connectionTokenFile: tokenFile.path,
        serverDataDir: serverDataDir,
        extensionsDir: extensionsDir,
      ),
      environment: extensionServerEnvironment(
        parentEnvironment ?? Platform.environment,
        environment,
      ),
      includeParentEnvironment: false,
    );
    onStarted?.call(process.pid);
    final port = Completer<int>();
    final output = StringBuffer();
    void onLine(String line) {
      if (output.length < 16 * 1024) output.writeln(line);
      final m = extensionServerListening.firstMatch(line);
      if (m != null && !port.isCompleted) port.complete(int.parse(m[1]!));
    }

    for (final stream in [process.stdout, process.stderr]) {
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(onLine, onError: (Object _) {});
    }
    unawaited(
      process.exitCode.then((code) {
        if (!port.isCompleted) {
          port.completeError(
            ExtensionServerStartException('exited with $code', '$output'),
          );
        }
      }),
    );
    try {
      final listening = await port.future.timeout(const Duration(seconds: 60));
      return StartedExtensionServer._(process, listening, token);
    } on TimeoutException {
      process.kill();
      throw ExtensionServerStartException('did not start listening', '$output');
    }
  }
}

/// The server did not start.
final class ExtensionServerStartException implements Exception {
  const ExtensionServerStartException(this.message, this.output);

  final String message;

  /// What it printed.
  final String output;

  @override
  String toString() => 'Extension server $message\n$output';
}

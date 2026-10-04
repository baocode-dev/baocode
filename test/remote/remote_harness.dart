/// A server and a client joined by in-memory streams: the whole protocol,
/// in the test's own process, with no SSH.
library;

import 'dart:async';
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:bao_remote/server.dart';

/// The two ends of a connection, and the server's folder.
class RemoteHarness {
  RemoteHarness._(this.server, this.client, this.dataDir, this._lines);

  /// A server with its state in a new temporary folder, and a client
  /// talking to it (initialized).
  static Future<RemoteHarness> start() async {
    final dataDir = Directory.systemTemp.createTempSync('baocode-remote-');
    final toServer = StreamController<String>();
    final toClient = StreamController<String>();
    final lines = <String>[];
    final server = RemoteServer(
      RpcPeer(toServer.stream, toClient.add),
      dataDir: dataDir.path,
      version: 'test',
    );
    final client = RemoteClient(
      RpcPeer(toClient.stream, (line) {
        lines.add(line);
        toServer.add(line);
      }),
    );
    await client.initialize();
    return RemoteHarness._(server, client, dataDir, lines);
  }

  final RemoteServer server;
  final RemoteClient client;
  final Directory dataDir;

  /// What the client sent, a line a message.
  final List<String> _lines;

  List<String> get sent => List.unmodifiable(_lines);

  Future<void> close() async {
    await server.shutdown();
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  }
}

/// Waits until [condition] holds, polling; fails after [timeout].
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

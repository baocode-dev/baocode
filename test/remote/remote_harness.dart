/// A server and a client joined by in-memory streams: the whole protocol,
/// in the test's own process, with no SSH.
library;

import 'dart:async';
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:bao_remote/server.dart';
import 'package:path/path.dart' as p;

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

/// A connection to a server in memory, which [drop] cuts as a network
/// would.
class MemoryLink {
  MemoryLink._(this.server, this.client, this._toServer, this._toClient);

  static Future<MemoryLink> open(String dataDir) async {
    final toServer = StreamController<String>();
    final toClient = StreamController<String>();
    final server = RemoteServer(
      RpcPeer(toServer.stream, toClient.add),
      dataDir: dataDir,
      version: 'test',
    );
    final client = RemoteClient(RpcPeer(toClient.stream, toServer.add));
    await client.initialize();
    return MemoryLink._(server, client, toServer, toClient);
  }

  final RemoteServer server;
  final RemoteClient client;
  final StreamController<String> _toServer;
  final StreamController<String> _toClient;

  /// The connection is gone: both ends find out.
  Future<void> drop() async {
    await _toServer.close();
    await _toClient.close();
  }
}

/// Connects [SshHost]s to servers in memory sharing [dataDir]; fails with
/// [failure] while it is set.
class MemoryConnector {
  MemoryConnector(this.dataDir);

  final String dataDir;
  final List<MemoryLink> links = [];
  Object? failure;
  int attempts = 0;

  Future<SshConnection> call(
    SshTarget target, {
    void Function(String message)? onProgress,
  }) async {
    attempts++;
    if (failure case final failure?) throw failure;
    onProgress?.call('Starting the BaoCode server on ${target.text}');
    final link = await MemoryLink.open(dataDir);
    links.add(link);
    return SshConnection.over(
      target,
      link.client,
      ended: () => link.server.shutdown(),
    );
  }
}

/// An absolute `dart`, so starting does not depend on the child's PATH.
final String dartExecutable = () {
  if (Platform.environment['FLUTTER_ROOT'] case final root?) {
    final dart = p.join(root, 'bin', 'cache', 'dart-sdk', 'bin', 'dart');
    if (File(dart).existsSync()) return dart;
  }
  final which = Process.runSync('which', ['dart']);
  final found = '${which.stdout}'.trim();
  return found.isEmpty ? 'dart' : found;
}();

// A tiny stand-in for the extension runtime, and a local server for it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:crypto/crypto.dart';

const fakeCommit = '0123456789abcdef0123456789abcdef01234567';
const fakeVersion = '9.9.9';

/// The files of a runtime: `node` (or `node.exe`), the server's entry, a
/// script in bin/, a native module, product.json; [executable] marked so.
Map<String, (List<int>, bool executable)> fakeRuntimeFiles({
  bool windows = false,
}) => {
  windows ? 'node.exe' : 'node': (utf8.encode('#!/bin/sh\necho node\n'), true),
  'out/server-main.js': (utf8.encode('console.log("server")\n'), false),
  'bin/baocode-server': (utf8.encode('#!/bin/sh\n'), true),
  'node_modules/native/build/Release/native.node': (
    Uint8List.fromList(List.generate(4096, (i) => i % 251)),
    false,
  ),
  // A long path, for the tar's pax and prefix headers.
  'extensions/${'very-long-extension-name-' * 4}/dist/${'nested/' * 12}main.js':
      (utf8.encode('exports.activate = () => {}\n'), false),
  'product.json': (
    utf8.encode(
      jsonEncode({
        'nameShort': 'BaoCode',
        'version': fakeVersion,
        'commit': fakeCommit,
        'quality': 'stable',
      }),
    ),
    false,
  ),
};

/// [files] as a gzipped tar.
Uint8List fakeTarGz([Map<String, (List<int>, bool)>? files]) {
  final builder = BytesBuilder(copy: false);
  final sink = _BytesSink(builder);
  final tar = TarWriter(sink, mtime: 1700000000);
  final entries = (files ?? fakeRuntimeFiles()).entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final directories = <String>{};
  for (final MapEntry(key: path, value: (content, executable)) in entries) {
    final parts = path.split('/');
    for (var i = 1; i < parts.length; i++) {
      final directory = parts.take(i).join('/');
      if (directories.add(directory)) tar.addDirectory(directory);
    }
    tar.addFile(path, content, mode: executable ? 0x1ED : 0x1A4);
  }
  tar.close();
  return Uint8List.fromList(gzip.encode(builder.takeBytes()));
}

/// [files] as a ZIP, written to [path].
void fakeZip(String path, [Map<String, (List<int>, bool)>? files]) {
  final writer = ZipWriter(File(path).openSync(mode: FileMode.write));
  for (final MapEntry(key: name, value: (content, executable))
      in (files ?? fakeRuntimeFiles(windows: true)).entries) {
    writer.addFile(name, content, mode: executable ? 0x1ED : 0x1A4);
  }
  writer.close();
}

final class _BytesSink implements Sink<List<int>> {
  _BytesSink(this._builder);

  final BytesBuilder _builder;

  @override
  void add(List<int> data) => _builder.add(data);

  @override
  void close() {}
}

String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

/// A manifest with one archive per [archives] entry (platform → bytes), at
/// [baseUrl].
ExtHostRuntimeManifest fakeManifest(
  Map<String, Uint8List> archives, {
  required String baseUrl,
  String id = '$fakeVersion-abcdef12',
  String? sha256Override,
  int? sizeOverride,
}) => ExtHostRuntimeManifest.fromJson({
  'version': fakeVersion,
  'id': id,
  'productCommit': fakeCommit,
  'upstreamVersion': '1.0.0',
  'upstreamCommit': fakeCommit,
  'nodeVersion': '24.0.0',
  'baseUrl': baseUrl,
  'platforms': {
    for (final MapEntry(key: platform, value: bytes) in archives.entries)
      platform: {
        'file':
            'runtime-$platform.${platform.startsWith('win32') ? 'zip' : 'tar.gz'}',
        'size': sizeOverride ?? bytes.length,
        'sha256': sha256Override ?? sha256Of(bytes),
      },
  },
});

/// How the server answers one request.
enum Serve {
  /// The whole file.
  whole,

  /// Half of it, then the connection is dropped.
  half,

  /// 404.
  missing,

  /// 503.
  unavailable,
}

/// Serves `/<file>` from [files]; each request answered as [plan] says
/// (its last entry for the rest), after [gate] when given.
final class FakeRuntimeServer {
  FakeRuntimeServer._(this._server);

  static Future<FakeRuntimeServer> start() async => FakeRuntimeServer._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  ).._listen();

  final HttpServer _server;
  final files = <String, Uint8List>{};
  final plan = <Serve>[Serve.whole];
  final requests = <String>[];

  /// Held until completed: the response's first half is sent, the rest
  /// waits.
  Completer<void>? gate;

  String get baseUrl => 'http://127.0.0.1:${_server.port}/';

  Future<void> close() => _server.close(force: true);

  void _listen() {
    _server.listen((request) async {
      final name = request.uri.pathSegments.join('/');
      requests.add(name);
      final serve = plan.length > 1 ? plan.removeAt(0) : plan.single;
      final bytes = files[name];
      final response = request.response;
      if (bytes == null || serve == Serve.missing) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      if (serve == Serve.unavailable) {
        response.statusCode = HttpStatus.serviceUnavailable;
        await response.close();
        return;
      }
      if (serve == Serve.half) {
        final socket = await response.detachSocket(writeHeaders: false);
        socket.add(
          utf8.encode(
            'HTTP/1.1 200 OK\r\n'
            'Content-Length: ${bytes.length}\r\n'
            'Content-Type: application/gzip\r\n\r\n',
          ),
        );
        socket.add(bytes.sublist(0, bytes.length ~/ 2));
        await socket.flush();
        socket.destroy();
        return;
      }
      response.contentLength = bytes.length;
      response.headers.contentType = ContentType.binary;
      final half = bytes.length ~/ 2;
      response.add(bytes.sublist(0, half));
      await response.flush();
      if (gate case final gate?) await gate.future;
      response.add(bytes.sublist(half));
      await response.close();
    });
  }
}

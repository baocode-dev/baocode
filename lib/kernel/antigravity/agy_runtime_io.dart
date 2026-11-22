import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_remote/local.dart' show AppPaths, ClaudeEnvironment;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../network/network_proxy_io.dart';
import '../../platform/child_process_registry.dart';
import '../../platform/data_dir.dart';
import '../acp/acp_connection.dart';
import '../acp/mcp_endpoint.dart';
import '../acp/mcp_http_server.dart';
import '../agent_kernel.dart' show SessionRecord;
import 'agy_runtime.dart';

AgyRuntime localAgyRuntime() => LocalAgyRuntime();

/// agy on this machine.
class LocalAgyRuntime implements AgyRuntime {
  LocalAgyRuntime({
    Future<Map<String, String>> Function()? environment,
    String? installDir,
    String? dataDir,
    String? cacheDir,
    String? stateDir,
    this._bootTimeout = const Duration(seconds: 60),
  }) : _environment = environment ?? ClaudeEnvironment.of,
       _installDirOverride = installDir,
       _dataDirOverride = dataDir,
       _cacheDirOverride = cacheDir,
       _stateDirOverride = stateDir;

  final String? _cacheDirOverride;
  final String? _stateDirOverride;
  final Duration _bootTimeout;

  final Future<Map<String, String>> Function() _environment;
  final String? _installDirOverride;

  /// Where BaoCode installs it: `<data>/antigravity`.
  String get installDir =>
      _installDirOverride ?? p.join(DataDirectory.current.path, 'antigravity');

  static String get _exe => Platform.isWindows ? '.exe' : '';

  /// The one BaoCode installed.
  String get _installed => p.join(installDir, 'antigravity$_exe');

  /// The processes running, kept track of across runs (see
  /// [ChildProcessRegistry]).
  static final registry = ChildProcessRegistry(
    file: File(DataDirectory.current.processRegistryFile('antigravity')),
    recognizes: (command) =>
        command.contains(' acp') &&
        (command.contains('agy') || command.contains('antigravity')),
  );

  /// The running ones, to end as the app quits.
  static final Set<Process> _live = {};

  /// Ends the agy this run keeps (as the app quits).
  static Future<void> stopProcesses() async {
    _host?.close();
    _host = null;
    for (final process in [..._live]) {
      process.kill();
    }
    _live.clear();
    await _tools?.close();
    _tools = null;
    await registry.flush();
  }

  String get _stateDir =>
      _stateDirOverride ?? DataDirectory.current.stateDir;

  @override
  Future<String?> locate() async {
    if (File(_installed).existsSync()) return _installed;
    final environment = await _environment();
    final home = AppPaths.home(environment);
    final separator = Platform.isWindows ? ';' : ':';
    final candidates = [
      for (final dir in (environment['PATH'] ?? '').split(separator))
        if (dir.isNotEmpty) p.join(dir, 'agy$_exe'),
      p.join(home, '.local', 'bin', 'agy$_exe'),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<String> _located() async {
    final found = await locate();
    if (found == null) {
      throw const AgyUnavailable(
        'Antigravity is not installed',
        notInstalled: true,
      );
    }
    return found;
  }

  Future<Map<String, String>> _runEnvironment() async => {
    ...await _environment(),
    ...await NetworkProxy.instance.environment(),
  };

  // --- The host ------------------------------------------------------------------------

  /// The agy kept running for the app: `agy acp`, its stdin held open (it
  /// ends with it), its language server up once a session was asked of it.
  /// Started again if gone.
  static _Host? _host;
  static Future<_Host>? _booting;

  @override
  Future<AgyLanguageServer> server() async {
    if (_host case final host? when !host.ended) return host.server;
    final booting = _booting ??= _boot().whenComplete(() => _booting = null);
    return (await booting).server;
  }

  /// What this app tells agy of itself: no files or terminals of its own
  /// to offer, nothing is prompted this way.
  static const _hello = {
    'protocolVersion': 1,
    'clientCapabilities': {
      'fs': {'readTextFile': false, 'writeTextFile': false},
      'terminal': false,
    },
    'clientInfo': {'name': 'baocode', 'title': 'BaoCode', 'version': '1'},
  };

  /// Where the host logs: the language server's port is read from it.
  File get _hostLog => File(p.join(_stateDir, 'antigravity', 'host.log'));

  static final _portLine = RegExp(
    r'listening on random port at (\d+) for HTTP\s*$',
    multiLine: true,
  );

  Future<_Host> _boot() async {
    await registry.reaped;
    final executable = await _located();
    final log = _hostLog;
    try {
      log.parent.createSync(recursive: true);
      if (log.existsSync()) log.deleteSync();
    } on FileSystemException {
      // Written over then.
    }
    final AgyProcessTransport transport;
    try {
      final process = await Process.start(
        executable,
        ['acp', '--disable-telemetry', '--log-file', log.path],
        workingDirectory: AppPaths.home(await _environment()),
        environment: await _runEnvironment(),
        includeParentEnvironment: Platform.isWindows,
      );
      transport = AgyProcessTransport(process);
    } on ProcessException catch (error) {
      throw AgyUnavailable(
        'Antigravity could not start',
        detail: '$executable\n${error.message}',
      );
    }
    final connection = AcpConnection(
      transport,
      onRequest: (method, _) async =>
          throw AcpError(-32601, 'Method not found: $method'),
      onNotification: (_, _) {},
    );
    try {
      await connection.request('initialize', _hello).timeout(_bootTimeout);
      // Its language server comes up with the first session asked of it.
      await connection.request('session/list', {}).timeout(_bootTimeout);
      final port = await _portOf(log, transport).timeout(_bootTimeout);
      final host = _Host(transport, connection, _ConnectServer(port));
      unawaited(
        transport.exited.then((_) {
          if (identical(_host, host)) _host = null;
        }),
      );
      return _host = host;
    } on Object catch (error) {
      connection.close();
      final exit = await transport.exited
          .timeout(const Duration(seconds: 3))
          .catchError((_) => const AcpExit(-1));
      final stderr = exit.stderr.trim();
      throw AgyUnavailable(
        switch (error) {
          AcpError(closed: true) =>
            'Antigravity stopped as it started (exit code ${exit.code})',
          AcpError(:final message) => 'Antigravity could not start: $message',
          TimeoutException() => 'Antigravity took too long to start',
          _ => 'Antigravity could not start',
        },
        detail: stderr.isEmpty ? null : stderr,
      );
    }
  }

  /// The language server's port, from the host's log once written there.
  static Future<int> _portOf(File log, AgyProcessTransport transport) async {
    while (!transport.ended) {
      try {
        if (log.existsSync()) {
          final match = _portLine.firstMatch(log.readAsStringSync());
          if (match != null) return int.parse(match.group(1)!);
        }
      } on FileSystemException {
        // Being written.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const AcpError(AcpError.closedCode, 'Agent stopped');
  }

  // --- Installing ----------------------------------------------------------------

  /// Google's update feed: `<feed>/<os>_<arch>.json` tells the version, its
  /// download and its SHA-512 (as `agy update` reads it).
  static const feed =
      'https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests';

  static String get _target {
    final os = switch (Platform.operatingSystem) {
      'macos' => 'darwin',
      final os => os,
    };
    final arch = switch (Abi.current()) {
      Abi.macosArm64 || Abi.linuxArm64 || Abi.windowsArm64 => 'arm64',
      _ => 'amd64',
    };
    return '${os}_$arch';
  }

  @override
  Future<void> install({void Function(double progress)? onProgress}) async {
    final client = HttpClient();
    try {
      final manifest = await _json(client, Uri.parse('$feed/$_target.json'));
      final url = manifest['url'];
      final sha = manifest['sha512'];
      if (url is! String || sha is! String) {
        throw const AgyUnavailable('Antigravity’s update feed said nothing');
      }
      await Directory(installDir).create(recursive: true);
      final download = File(p.join(installDir, 'download.part'));
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw AgyUnavailable(
          'Antigravity could not be downloaded (${response.statusCode})',
        );
      }
      final total = response.contentLength;
      var received = 0;
      final sink = download.openWrite();
      final digest = _DigestSink();
      final hasher = sha512.startChunkedConversion(digest);
      await for (final chunk in response) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      hasher.close();
      if ('${digest.value}' != sha.toLowerCase()) {
        await download.delete();
        throw const AgyUnavailable(
          'Antigravity’s download did not match its checksum',
        );
      }
      final target = File(_installed);
      if (url.endsWith('.tar.gz')) {
        final unpacked = Directory(p.join(installDir, 'unpacked'));
        if (unpacked.existsSync()) await unpacked.delete(recursive: true);
        await unpacked.create();
        final result = await Process.run('tar', [
          '-xzf',
          download.path,
          '-C',
          unpacked.path,
        ]);
        await download.delete();
        final binary = File(p.join(unpacked.path, 'antigravity'));
        if (result.exitCode != 0 || !binary.existsSync()) {
          throw AgyUnavailable(
            'Antigravity could not be unpacked',
            detail: '${result.stderr}',
          );
        }
        await binary.rename(target.path);
        await unpacked.delete(recursive: true);
        await Process.run('chmod', ['755', target.path]);
      } else {
        await download.rename(target.path);
      }
    } on SocketException catch (error) {
      throw AgyUnavailable(
        'Antigravity could not be downloaded',
        detail: error.message,
      );
    } finally {
      client.close();
    }
  }

  static Future<Map<String, Object?>> _json(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode != 200) {
      throw AgyUnavailable(
        'Antigravity’s update feed answered ${response.statusCode}',
      );
    }
    return switch (jsonDecode(text)) {
      final Map<String, Object?> json => json,
      _ => const {},
    };
  }

  // --- Signing in ------------------------------------------------------------------

  @override
  Future<void> login({
    required void Function(Uri link) link,
    required Future<String?> Function() code,
  }) async {
    final executable = await _located();
    final process = await Process.start(
      executable,
      const ['acp', '--login'],
      environment: await _runEnvironment(),
      includeParentEnvironment: Platform.isWindows,
    );
    final output = StringBuffer();
    final linked = Completer<void>();
    void read(String line) {
      output.writeln(line);
      if (linked.isCompleted) return;
      final match = RegExp(r'https://\S+').firstMatch(line);
      if (match == null) return;
      final uri = Uri.tryParse(match.group(0)!);
      if (uri == null) return;
      linked.complete();
      link(uri);
      unawaited(() async {
        final answer = await code();
        if (answer == null || answer.trim().isEmpty) {
          process.kill();
          return;
        }
        process.stdin.writeln(answer.trim());
        await process.stdin.flush();
      }());
    }

    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(read);
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(read);
    final exit = await process.exitCode;
    if (exit != 0) {
      throw AgyUnavailable(
        'Signing in to Antigravity did not finish',
        detail: '$output',
      );
    }
    // The host booted before the sign-in has the account before: anew.
    _host?.close();
    _host = null;
  }

  // --- MCP servers -----------------------------------------------------------------

  Future<File> _mcpConfig() async =>
      File(p.join(p.dirname(dataDir), 'config', 'mcp_config.json'));

  @override
  Future<List<AgyMcpServer>> mcpServers() async {
    final file = await _mcpConfig();
    if (!file.existsSync()) return const [];
    try {
      return parseAgyMcpConfig(await file.readAsString());
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> setMcpServerEnabled(String name, bool enabled) async {
    final executable = await _located();
    await Process.run(
      executable,
      ['mcp', enabled ? 'enable' : 'disable', name],
      environment: await _runEnvironment(),
      includeParentEnvironment: Platform.isWindows,
    );
  }

  @override
  Future<void> stopAll() => stopProcesses();

  // --- The app's own tools -----------------------------------------------------------

  /// The server the app's tools are served on, one for all conversations:
  /// each conversation keeps its address (told agy as it started), so the
  /// port and token are kept from run to run, as far as the port is free.
  static McpHttpServer? _tools;
  static Future<McpHttpServer>? _openingTools;

  /// Where the tools server's port and token are kept, with each
  /// conversation's key on it.
  File get _toolsFile => File(p.join(_stateDir, 'antigravity', 'tools.json'));

  Map<String, Object?> _toolsKept() {
    try {
      final file = _toolsFile;
      if (!file.existsSync()) return {};
      return switch (jsonDecode(file.readAsStringSync())) {
        final Map<String, Object?> kept => kept,
        _ => {},
      };
    } on Object {
      return {};
    }
  }

  void _keepTools(Map<String, Object?> kept) {
    try {
      final file = _toolsFile;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(kept));
    } on FileSystemException {
      // Served anew next run then.
    }
  }

  @override
  Future<McpEndpoint> serveTools(McpHandler handle, {String key = ''}) async {
    final server = _tools ?? await (_openingTools ??= _openTools());
    return server.serve(key, handle);
  }

  Future<McpHttpServer> _openTools() async {
    try {
      final kept = _toolsKept();
      final port = kept['port'];
      final token = kept['token'];
      McpHttpServer? server;
      if (port is int && token is String && token.isNotEmpty) {
        try {
          server = await McpHttpServer.open(port: port, token: token);
        } on SocketException {
          // Taken meanwhile: another, the conversations told of this one
          // lose their tools.
        }
      }
      server ??= await McpHttpServer.open();
      if (server.port != port || server.token != token) {
        _keepTools({...kept, 'port': server.port, 'token': server.token});
      }
      return _tools = server;
    } finally {
      _openingTools = null;
    }
  }

  /// The most conversations whose tool keys are kept.
  static const _keysKept = 500;

  @override
  String? toolKey(String sessionId) => switch (_toolsKept()['keys']) {
    final Map keys => keys[sessionId] as String?,
    _ => null,
  };

  @override
  void keepToolKey(String sessionId, String key) {
    final kept = _toolsKept();
    final keys = switch (kept['keys']) {
      final Map<String, Object?> keys => {...keys},
      _ => <String, Object?>{},
    };
    keys.remove(sessionId);
    keys[sessionId] = key;
    while (keys.length > _keysKept) {
      keys.remove(keys.keys.first);
    }
    _keepTools({...kept, 'keys': keys});
  }

  // --- What is kept ----------------------------------------------------------------

  /// Where it keeps its conversations: `~/.gemini/antigravity-cli`.
  @override
  String get dataDir =>
      _dataDirOverride ??
      p.join(AppPaths.home(Platform.environment), '.gemini', 'antigravity-cli');
  final String? _dataDirOverride;

  /// Where [kept] is kept: the app's cache, not agy's folder.
  String get _keptFile => p.join(
    _cacheDirOverride ?? DataDirectory.current.cacheDir,
    'antigravity.json',
  );

  @override
  Map<String, Object?>? get kept {
    try {
      final file = File(_keptFile);
      if (!file.existsSync()) return null;
      return switch (jsonDecode(file.readAsStringSync())) {
        final Map<String, Object?> kept => kept,
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  @override
  set kept(Map<String, Object?>? value) {
    try {
      final file = File(_keptFile);
      if (value == null) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(value));
    } on FileSystemException {
      // Asked again next run then.
    }
  }

  @override
  String? fileText(String path) {
    try {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() > 8 << 20) return null;
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Where the conversations last listed are kept: the app's own state.
  File get _sessionsFile =>
      File(p.join(_stateDir, 'antigravity', 'sessions.json'));

  @override
  List<SessionRecord>? get lastSessions {
    try {
      final file = _sessionsFile;
      if (!file.existsSync()) return null;
      return switch (jsonDecode(file.readAsStringSync())) {
        final List<Object?> kept => [
          for (final session in kept)
            if (session case {
              'id': final String id,
              'title': final String title,
              'updatedAt': final String at,
              'cwd': final String cwd,
            })
              SessionRecord(
                id: id,
                title: title,
                updatedAt: DateTime.tryParse(at) ?? DateTime(2000),
                cwd: cwd,
                path: session['path'] as String?,
              ),
        ],
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  @override
  set lastSessions(List<SessionRecord>? records) {
    try {
      final file = _sessionsFile;
      if (records == null) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode([
          for (final record in records)
            {
              'id': record.id,
              'title': record.title,
              'updatedAt': record.updatedAt.toIso8601String(),
              'cwd': record.cwd,
              'path': ?record.path,
            },
        ]),
      );
    } on FileSystemException {
      // Listed anew next run then.
    }
  }

  /// Where the conversations agy lists are kept: its own folder, and the
  /// Antigravity app's beside it (`~/.gemini/antigravity`).
  List<String> get _conversationRoots => [
    dataDir,
    p.join(p.dirname(dataDir), 'antigravity'),
  ];

  /// Deleted in agy (`DeleteCascadeTrajectory`, which takes its files and
  /// its folder with it), then whatever is left of it, in whichever
  /// folder keeps it: agy lists a conversation while its files are there.
  @override
  Future<void> delete(String sessionId) async {
    final id = p.basename(sessionId);
    if (lastSessions case final kept?) {
      lastSessions = [
        for (final record in kept)
          if (record.id != id) record,
      ];
    }
    if (await locate() != null) {
      try {
        await (await server()).call('DeleteCascadeTrajectory', {
          'cascadeId': id,
        });
      } on Object {
        // Its files then.
      }
    }
    for (final root in _conversationRoots) {
      for (final path in [
        p.join(root, 'conversations', '$id.db'),
        p.join(root, 'conversations', '$id.db-wal'),
        p.join(root, 'conversations', '$id.db-shm'),
        p.join(root, 'conversations', '$id.pb'),
        p.join(root, 'annotations', '$id.pbtxt'),
        p.join(root, 'presence', '$id.lock'),
      ]) {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      }
      final brain = Directory(p.join(root, 'brain', id));
      if (brain.existsSync()) await brain.delete(recursive: true);
    }
  }
}

/// A project's path as agy lists it: URL-encoded (`Application%20Support`).
@visibleForTesting
String agyPath(String path) {
  if (!RegExp('%[0-9A-Fa-f]{2}').hasMatch(path)) return path;
  try {
    return Uri.decodeFull(path);
  } on ArgumentError {
    return path;
  }
}

/// agy's MCP servers, from its `mcp_config.json`.
@visibleForTesting
List<AgyMcpServer> parseAgyMcpConfig(String text) {
  final servers = switch (jsonDecode(text)) {
    {'mcpServers': final Map<String, Object?> servers} => servers,
    _ => const <String, Object?>{},
  };
  return [
    for (final MapEntry(key: name, value: config) in servers.entries)
      if (config is Map)
        AgyMcpServer(
          name: name,
          enabled: config['disabled'] != true,
          target: switch (config) {
            {'serverUrl': final String url} => url,
            {'url': final String url} => url,
            {'command': final String command} => [
              command,
              for (final arg in config['args'] as List? ?? const []) '$arg',
            ].join(' '),
            _ => '',
          },
        ),
  ];
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// The agy kept running (see [LocalAgyRuntime._host]).
class _Host {
  _Host(this.transport, this.connection, this.server);

  final AgyProcessTransport transport;
  final AcpConnection connection;
  final _ConnectServer server;

  bool get ended => transport.ended;

  void close() {
    server.close();
    connection.close();
  }
}

/// agy's language server over Connect: JSON calls, and enveloped streams.
class _ConnectServer implements AgyLanguageServer {
  _ConnectServer(this.port);

  final int port;

  /// Its own client: never through a proxy, this machine's loopback.
  final HttpClient _client = HttpClient()
    ..findProxy = ((_) => 'DIRECT')
    ..idleTimeout = const Duration(minutes: 5);

  static const _service = 'exa.language_server_pb.LanguageServerService';

  Uri _url(String method) => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: port,
    path: '/$_service/$method',
  );

  void close() => _client.close(force: true);

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> body = const {},
  ]) async {
    final HttpClientResponse response;
    final String text;
    try {
      final request = await _client.postUrl(_url(method));
      final bytes = utf8.encode(jsonEncode(body));
      request.headers
        ..contentType = ContentType.json
        ..contentLength = bytes.length
        ..set('Connect-Protocol-Version', '1');
      request.add(bytes);
      response = await request.close();
      text = await utf8.decodeStream(response);
    } on IOException catch (error) {
      throw AgyError('Antigravity is not answering: $error', gone: true);
    }
    if (response.statusCode != 200) {
      throw _refused(text, response.statusCode);
    }
    return switch (_decode(text)) {
      final Map<String, Object?> json => json,
      _ => const {},
    };
  }

  static Object? _decode(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static AgyError _refused(String text, int status) {
    final json = _decode(text);
    return AgyError(
      switch (json) {
        {'message': final String message} when message.isNotEmpty => message,
        _ => 'Antigravity answered $status',
      },
      code: json is Map ? json['code'] as String? : null,
      status: status,
    );
  }

  /// A server stream: the request and each answer an envelope of a flag
  /// byte, a big-endian length and JSON; the last, flagged 2, the end (and
  /// the error, if any).
  @override
  Stream<Map<String, Object?>> stream(
    String method, [
    Map<String, Object?> body = const {},
  ]) {
    late StreamController<Map<String, Object?>> controller;
    StreamSubscription<List<int>>? subscription;
    HttpClientRequest? request;
    var ended = false;

    Future<void> open() async {
      try {
        request = await _client.postUrl(_url(method));
        final bytes = _envelope(0, utf8.encode(jsonEncode(body)));
        request!.headers
          ..contentType = ContentType('application', 'connect+json')
          ..contentLength = bytes.length
          ..set('Connect-Protocol-Version', '1');
        request!.add(bytes);
        final response = await request!.close();
        if (controller.isClosed) {
          await response.drain<void>();
          return;
        }
        if (response.statusCode != 200) {
          final text = await utf8.decodeStream(response);
          controller.addError(_refused(text, response.statusCode));
          await controller.close();
          return;
        }
        final buffer = BytesBuilder(copy: false);
        subscription = response.listen(
          (chunk) {
            buffer.add(chunk);
            for (final (flag, frame) in _frames(buffer)) {
              if (ended || controller.isClosed) return;
              if (flag & 2 != 0) {
                ended = true;
                if (_decode(frame) case {'error': final Map error}) {
                  controller.addError(
                    AgyError(
                      '${error['message'] ?? 'Antigravity ended the stream'}',
                      code: error['code'] as String?,
                    ),
                  );
                }
                unawaited(controller.close());
                return;
              }
              if (_decode(frame) case final Map<String, Object?> json) {
                controller.add(json);
              }
            }
          },
          onError: (Object error) {
            if (controller.isClosed) return;
            controller.addError(
              AgyError('Antigravity is not answering: $error', gone: true),
            );
            unawaited(controller.close());
          },
          onDone: () {
            if (controller.isClosed) return;
            if (!ended) {
              controller.addError(
                const AgyError('Antigravity ended the stream', gone: true),
              );
            }
            unawaited(controller.close());
          },
          cancelOnError: true,
        );
      } on IOException catch (error) {
        if (controller.isClosed) return;
        controller.addError(
          AgyError('Antigravity is not answering: $error', gone: true),
        );
        unawaited(controller.close());
      }
    }

    controller = StreamController(
      onListen: () => unawaited(open()),
      onCancel: () {
        unawaited(subscription?.cancel());
        request?.abort();
      },
    );
    return controller.stream;
  }

  static Uint8List _envelope(int flag, List<int> payload) {
    final out = BytesBuilder(copy: false)
      ..addByte(flag)
      ..add(
        Uint8List(4)..buffer.asByteData().setUint32(0, payload.length),
      )
      ..add(payload);
    return out.takeBytes();
  }

  /// The whole envelopes at the start of [buffer], taken out of it.
  static List<(int, String)> _frames(BytesBuilder buffer) {
    final bytes = buffer.takeBytes();
    final frames = <(int, String)>[];
    var at = 0;
    while (bytes.length - at >= 5) {
      final length = ByteData.sublistView(bytes, at + 1, at + 5).getUint32(0);
      if (bytes.length - at - 5 < length) break;
      frames.add((
        bytes[at],
        utf8.decode(
          Uint8List.sublistView(bytes, at + 5, at + 5 + length),
          allowMalformed: true,
        ),
      ));
      at += 5 + length;
    }
    if (at < bytes.length) buffer.add(Uint8List.sublistView(bytes, at));
    return frames;
  }
}

/// `agy acp` as a child process, over its stdin and stdout.
class AgyProcessTransport implements AcpTransport {
  AgyProcessTransport(this._process) {
    LocalAgyRuntime._live.add(_process);
    unawaited(LocalAgyRuntime.registry.add(_process.pid));
    _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_line, onDone: _stdoutDone);
    _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_stderrLine);
    unawaited(
      _process.exitCode.then((code) {
        _code = code;
        LocalAgyRuntime._live.remove(_process);
        unawaited(LocalAgyRuntime.registry.remove(_process.pid));
        _finish();
      }),
    );
  }

  final Process _process;
  final StreamController<Map<String, Object?>> _messages =
      StreamController.broadcast();
  final List<String> _stderr = [];
  final Completer<AcpExit> _exit = Completer();
  int? _code;
  bool _stdoutClosed = false;

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  Future<AcpExit> get exited => _exit.future;

  void _line(String line) {
    if (line.trim().isEmpty) return;
    try {
      if (jsonDecode(line) case final Map<String, Object?> message) {
        _messages.add(message);
        return;
      }
    } on FormatException {
      // Not protocol: kept to say why it failed.
    }
    _stderrLine(line);
  }

  void _stderrLine(String line) {
    _stderr.add(line);
    if (_stderr.length > 30) _stderr.removeAt(0);
  }

  void _stdoutDone() {
    _stdoutClosed = true;
    _finish();
  }

  /// Whether it is gone, or going.
  bool get ended => _code != null || _closing;
  bool _closing = false;

  void _finish() {
    final code = _code;
    if (code == null || !_stdoutClosed || _exit.isCompleted) return;
    _exit.complete(AcpExit(code, _stderr.join('\n')));
    unawaited(_messages.close());
  }

  @override
  void write(Map<String, Object?> message) {
    if (_code != null) return;
    try {
      _process.stdin.writeln(jsonEncode(message));
    } on StateError {
      // Closed under us: the exit follows.
    }
  }

  @override
  void close() {
    if (_code != null) return;
    _closing = true;
    unawaited(_process.stdin.close().catchError((_) {}));
    if (Platform.isWindows) {
      unawaited(
        Process.run('taskkill', [
          '/pid',
          '${_process.pid}',
          '/T',
          '/F',
        ]).then<void>((_) {}, onError: (Object _) => _process.kill()),
      );
    } else {
      _process.kill();
    }
  }
}

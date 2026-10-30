import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../kernel/claude_code/claude_environment.dart';
import 'mcp_probe.dart';

McpProber? get platformMcpProber => probeMcpServer;

/// The `initialize` request a client opens with.
final String _initialize = jsonEncode({
  'jsonrpc': '2.0',
  'id': 1,
  'method': 'initialize',
  'params': {
    'protocolVersion': '2025-06-18',
    'capabilities': <String, Object?>{},
    'clientInfo': {'name': 'BaoCode', 'version': '1.0.0'},
  },
});

/// What a client says once `initialize` is answered.
final String _initialized = jsonEncode({
  'jsonrpc': '2.0',
  'method': 'notifications/initialized',
});

const _toolsId = 2;

/// Asks for the server's tools.
final String _listTools = jsonEncode({
  'jsonrpc': '2.0',
  'id': _toolsId,
  'method': 'tools/list',
});

/// How long a server connected has to list its tools.
const _toolsTimeout = Duration(seconds: 10);

/// Asks the server [config] describes, in the login shell's environment
/// (the PATH a terminal has, where `npx` and `uvx` are).
Future<McpProbeResult> probeMcpServer(
  Map<String, Object?> config, {
  String? cwd,
  Duration timeout = mcpProbeTimeout,
}) async {
  final environment = await ClaudeEnvironment.of();
  String expand(Object? value) => expandMcpVariables('$value', environment);
  if (config['url'] case final String url) {
    return _probeRemote(
      Uri.tryParse(expand(url)),
      sse: config['type'] == 'sse',
      headers: {
        if (config['headers'] case final Map<Object?, Object?> headers)
          for (final MapEntry(:key, :value) in headers.entries)
            '$key': expand(value),
      },
      timeout: timeout,
    );
  }
  final command = config['command'];
  if (command is! String || command.trim().isEmpty) {
    return const McpProbeResult(McpProbeStatus.failed);
  }
  return _probeCommand(
    expand(command),
    [
      if (config['args'] case final List<Object?> args)
        for (final arg in args) expand(arg),
    ],
    environment: {
      ...environment,
      if (config['env'] case final Map<Object?, Object?> env)
        for (final MapEntry(:key, :value) in env.entries) '$key': expand(value),
    },
    cwd: cwd != null && Directory(cwd).existsSync() ? cwd : null,
    timeout: timeout,
  );
}

/// Starts [command] and greets it on its stdin; its answer on stdout.
Future<McpProbeResult> _probeCommand(
  String command,
  List<String> args, {
  required Map<String, String> environment,
  required String? cwd,
  required Duration timeout,
}) async {
  final Process process;
  try {
    process = await Process.start(
      command,
      args,
      environment: environment,
      workingDirectory: cwd,
      // `npx` and the like are batch files on Windows.
      runInShell: Platform.isWindows,
    );
  } on ProcessException catch (error) {
    return McpProbeResult(McpProbeStatus.failed, message: error.message);
  }
  final stderr = McpLogTail();
  final answered = Completer<McpProbeResult>();
  final listed = Completer<List<McpProbeTool>?>();
  final subscriptions = [
    process.stderr.transform(_consoleText).listen(stderr.add),
    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          if (!answered.isCompleted) {
            if (_answer(line) case final result?) answered.complete(result);
            return;
          }
          if (listed.isCompleted) return;
          final Object? message;
          try {
            message = jsonDecode(line);
          } on FormatException {
            return;
          }
          if (mcpToolsOf(message, id: _toolsId) case final tools?) {
            listed.complete(tools);
          }
        }),
  ];
  unawaited(
    process.exitCode.then((code) {
      // Its last words first.
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (answered.isCompleted) return;
        answered.complete(
          McpProbeResult(
            McpProbeStatus.failed,
            exitCode: code,
            log: stderr.toString(),
          ),
        );
      });
    }),
  );
  process.stdin.writeln(_initialize);
  // A server that is gone takes no more: its exit says why.
  unawaited(process.stdin.flush().catchError((Object _) {}));
  unawaited(process.stdin.done.catchError((Object _) {}));
  var result = await answered.future.timeout(
    timeout,
    onTimeout: () => McpProbeResult(
      McpProbeStatus.failed,
      timedOut: true,
      log: stderr.toString(),
    ),
  );
  // Connected: its tools, for their switches; a server that does not say
  // is connected all the same.
  if (result.status == McpProbeStatus.connected) {
    try {
      process.stdin
        ..writeln(_initialized)
        ..writeln(_listTools);
      result = result.withTools(
        await listed.future.timeout(_toolsTimeout, onTimeout: () => null),
      );
    } on Object {
      // Gone already.
    }
  }
  await _stop(process);
  for (final subscription in subscriptions) {
    unawaited(subscription.cancel());
  }
  return switch (result) {
    McpProbeResult(status: McpProbeStatus.connected) => result,
    _ when result.log.isEmpty => McpProbeResult(
      result.status,
      message: result.message,
      exitCode: result.exitCode,
      timedOut: result.timedOut,
      log: stderr.toString(),
    ),
    _ => result,
  };
}

/// A program's console output, a line at a time: UTF-8 if it is, else in
/// the system's code page (cmd.exe's and npm's errors on a Chinese Windows
/// come in GBK), so that why it failed reads as it was said.
final StreamTransformer<List<int>, String> _consoleText =
    StreamTransformer.fromBind((bytes) async* {
      final line = BytesBuilder(copy: false);
      String text(List<int> bytes) {
        try {
          return utf8.decode(bytes);
        } on FormatException {
          return Platform.isWindows
              ? systemEncoding.decode(bytes)
              : utf8.decode(bytes, allowMalformed: true);
        }
      }

      await for (final chunk in bytes) {
        var start = 0;
        for (var i = 0; i < chunk.length; i++) {
          if (chunk[i] != 0x0A) continue;
          line.add(chunk.sublist(start, i + 1));
          start = i + 1;
          yield text(line.takeBytes());
        }
        if (start < chunk.length) line.add(chunk.sublist(start));
      }
      if (line.isNotEmpty) yield text(line.takeBytes());
    });

/// What a line of a server's says of `initialize`, if it is the answer.
McpProbeResult? _answer(String line) {
  final Object? message;
  try {
    message = jsonDecode(line);
  } on FormatException {
    return null;
  }
  if (message is! Map<String, Object?> || message['id'] != 1) return null;
  if (message['error'] case final Map<String, Object?> error) {
    return McpProbeResult(
      McpProbeStatus.failed,
      message: '${error['message'] ?? error}',
    );
  }
  final info = switch (message['result']) {
    {'serverInfo': final Map<String, Object?> info} => info,
    _ => const <String, Object?>{},
  };
  return McpProbeResult(
    McpProbeStatus.connected,
    server: [?info['name'], ?info['version']].join(' ').trim(),
  );
}

/// Ends [process]: its input closed, which ends a server that keeps to
/// MCP; then killed, with what it started (Windows' shell's children).
Future<void> _stop(Process process) async {
  unawaited(process.stdin.close().catchError((Object _) {}));
  final ended = await process.exitCode
      .timeout(const Duration(seconds: 1))
      .then((_) => true, onError: (Object _) => false);
  if (ended) return;
  if (Platform.isWindows) {
    await Process.run('taskkill', [
      '/pid',
      '${process.pid}',
      '/T',
      '/F',
    ]).catchError((Object _) => ProcessResult(0, 1, '', ''));
  } else {
    process.kill();
  }
}

/// Greets a remote server at [url]: Streamable HTTP's POST of
/// `initialize`, or the old SSE transport's stream opened ([sse]).
Future<McpProbeResult> _probeRemote(
  Uri? url, {
  required bool sse,
  required Map<String, String> headers,
  required Duration timeout,
}) async {
  if (url == null || !url.hasScheme) {
    return const McpProbeResult(McpProbeStatus.failed);
  }
  // Through the app's proxy (see network_proxy_io.dart).
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await (sse ? client.getUrl(url) : client.postUrl(url))
        .timeout(timeout);
    headers.forEach(request.headers.set);
    request.headers.set(
      HttpHeaders.acceptHeader,
      sse ? 'text/event-stream' : 'application/json, text/event-stream',
    );
    if (!sse) {
      // `application/json` alone, as Claude Code sends it: some servers
      // refuse it with a charset (HTTP 415).
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.add(utf8.encode(_initialize));
    }
    final response = await request.close().timeout(timeout);
    final status = response.statusCode;
    if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
      return McpProbeResult(
        McpProbeStatus.needsAuth,
        message: 'HTTP $status ${response.reasonPhrase}'.trim(),
      );
    }
    final body = await _start(response);
    if (status >= 300) {
      return McpProbeResult(
        McpProbeStatus.failed,
        message: 'HTTP $status ${response.reasonPhrase}'.trim(),
        log: body,
      );
    }
    if (sse) return const McpProbeResult(McpProbeStatus.connected);
    // The answer, as JSON or an event's data.
    var result = const McpProbeResult(McpProbeStatus.connected);
    for (final data in _dataLines(body)) {
      if (_answer(data) case final answer?) {
        result = answer;
        break;
      }
    }
    if (result.status != McpProbeStatus.connected) return result;
    return result.withTools(
      await _remoteTools(
        client,
        url,
        headers: {
          ...headers,
          'mcp-session-id': ?response.headers.value('mcp-session-id'),
        },
      ).timeout(_toolsTimeout, onTimeout: () => null),
    );
  } on Object catch (error) {
    return McpProbeResult(
      McpProbeStatus.failed,
      message: error is TimeoutException ? null : '$error',
      timedOut: error is TimeoutException,
    );
  } finally {
    client.close(force: true);
  }
}

/// Each JSON message of a body: its lines, an event's `data:` unwrapped.
Iterable<String> _dataLines(String body) => [
  for (final line in body.split('\n'))
    line.startsWith('data:') ? line.substring(5).trim() : line,
];

/// A remote server's tools, once it is greeted: `initialized` told it,
/// then `tools/list` asked, in the session it opened. Null where it does
/// not say.
Future<List<McpProbeTool>?> _remoteTools(
  HttpClient client,
  Uri url, {
  required Map<String, String> headers,
}) async {
  Future<String?> post(String message) async {
    final request = await client.postUrl(url);
    headers.forEach(request.headers.set);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set(HttpHeaders.contentTypeHeader, 'application/json');
    request.add(utf8.encode(message));
    final response = await request.close();
    if (response.statusCode >= 300) {
      await response.drain<void>().catchError((Object _) {});
      return null;
    }
    return _start(response, until: '"id":$_toolsId');
  }

  try {
    await post(_initialized);
    final body = await post(_listTools);
    if (body == null) return null;
    for (final data in _dataLines(body)) {
      try {
        if (mcpToolsOf(jsonDecode(data), id: _toolsId) case final tools?) {
          return tools;
        }
      } on FormatException {
        continue;
      }
    }
  } on Object {
    // Not listed: the switches of its tools are not shown.
  }
  return null;
}

/// The start of [response]'s body: an event stream may never end.
Future<String> _start(
  HttpClientResponse response, {
  String until = '"id":1',
  int most = 16000,
}) async {
  final body = StringBuffer();
  try {
    await for (final chunk
        in response
            .transform(const Utf8Decoder(allowMalformed: true))
            .timeout(const Duration(seconds: 5))) {
      body.write(chunk);
      if (body.length > most || chunk.contains(until)) break;
    }
  } on TimeoutException {
    // What came is enough.
  }
  return body.toString().trim();
}

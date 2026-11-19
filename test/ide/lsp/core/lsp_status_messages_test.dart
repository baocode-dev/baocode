import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_manager.dart';
import 'package:baocode/ide/lsp/lsp_process.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';
import 'package:path/path.dart' as p;

class _StaticCatalog implements LspCatalog {
  _StaticCatalog(this.definition);

  final LspServerDefinition definition;

  @override
  LspLanguage? languageFor(String path, {String? firstLine}) => LspLanguage(
    id: 'java',
    fileTypes: const ['java'],
    rootMarkers: const ['pom.xml'],
    servers: [definition.id],
  );

  @override
  LspServerDefinition? server(String id) =>
      id == definition.id ? definition : null;
}

class _FoundProvider implements LspServerProvider {
  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async =>
      const LspServerFound('jdtls');

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) async {}
}

/// In-memory LSP process that answers `initialize`/`shutdown` and lets tests
/// push arbitrary server-to-client notifications and requests.
class _MockLspProcess implements LspProcess {
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  final _buffer = <int>[];
  final List<Map<String, Object?>> received = [];
  bool _stopped = false;

  @override
  int get pid => 42;

  @override
  bool get stopRequested => _stopped;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  void sendMessage(Map<String, Object?> payload) {
    final body = utf8.encode(jsonEncode(payload));
    final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');
    _stdout.add([...header, ...body]);
  }

  void sendNotification(String method, Object? params) =>
      sendMessage({'jsonrpc': '2.0', 'method': method, 'params': params});

  void sendRequest(int id, String method, Object? params) => sendMessage({
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  });

  void emitStderr(String line) => _stderr.add(utf8.encode('$line\n'));

  void crash([int code = 1]) {
    if (!_exit.isCompleted) _exit.complete(code);
    unawaited(_stdout.close());
    unawaited(_stderr.close());
  }

  @override
  void write(List<int> bytes) {
    _buffer.addAll(bytes);
    while (true) {
      final headerEnd = _indexOfHeaderEnd(_buffer);
      if (headerEnd < 0) return;
      final header = ascii.decode(_buffer.sublist(0, headerEnd));
      final match = RegExp(
        r'Content-Length:\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(header);
      if (match == null) return;
      final length = int.parse(match.group(1)!);
      final bodyStart = headerEnd + 4;
      if (_buffer.length < bodyStart + length) return;
      final body = utf8.decode(_buffer.sublist(bodyStart, bodyStart + length));
      _buffer.removeRange(0, bodyStart + length);
      final message = (jsonDecode(body) as Map).cast<String, Object?>();
      received.add(message);
      _handleIncoming(message);
    }
  }

  void _handleIncoming(Map<String, Object?> message) {
    final id = message['id'];
    final method = message['method'];
    if (method == 'initialize' && id != null) {
      sendMessage({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'capabilities': <String, Object?>{}},
      });
    } else if (method == 'shutdown' && id != null) {
      sendMessage({'jsonrpc': '2.0', 'id': id, 'result': null});
    } else if (method == 'exit') {
      _stopped = true;
      if (!_exit.isCompleted) _exit.complete(0);
      unawaited(_stdout.close());
      unawaited(_stderr.close());
    }
  }

  static int _indexOfHeaderEnd(List<int> bytes) {
    for (var i = 0; i <= bytes.length - 4; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  @override
  Future<void> closeStdin() async {}

  @override
  void kill({bool force = false}) {
    _stopped = true;
    if (!_exit.isCompleted) _exit.complete(0);
    unawaited(_stdout.close());
    unawaited(_stderr.close());
  }
}

void main() {
  Future<void> pumpMicrotasks() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('window/showMessage and window/showMessageRequest emit error/warning '
      'messages and record all levels in logFor', () async {
    final process = _MockLspProcess();
    final paths = p.Context(style: p.Style.posix, current: '/workspace');
    final manager = LspManager(
      '/workspace',
      _StaticCatalog(const LspServerDefinition(id: 'jdtls', command: 'jdtls')),
      _FoundProvider(),
      paths: paths,
      pathExists: (path) => path == '/workspace/pom.xml',
      listDirectory: (_) => const [],
      startProcess: (_) async => process,
      watchDirectory: (_) => const Stream.empty(),
    );
    addTearDown(manager.dispose);

    final messages = <LspServerMessage>[];
    final sub = manager.serverMessages.listen(messages.add);
    addTearDown(sub.cancel);

    const filePath = '/workspace/src/Main.java';
    manager.openDocument(filePath, 'class Main {}');
    await pumpMicrotasks();
    expect(
      manager.statusFor(filePath).single.state,
      LanguageServerState.running,
    );

    // Error and warning showMessage -> emitted + logged.
    process.sendNotification('window/showMessage', {
      'type': 1,
      'message': 'Maven import failed',
    });
    process.sendNotification('window/showMessage', {
      'type': 2,
      'message': 'Using fallback JDK',
    });
    // Info showMessage and Error logMessage -> logged only, not emitted.
    process.sendNotification('window/showMessage', {
      'type': 3,
      'message': 'FYI message',
    });
    process.sendNotification('window/logMessage', {
      'type': 1,
      'message': 'Internal log line',
    });
    // showMessageRequest Warning -> emitted + logged + answered null.
    process.sendRequest(99, 'window/showMessageRequest', {
      'type': 2,
      'message': 'Reload project?',
    });
    await pumpMicrotasks();

    expect(messages.length, 3);
    expect(messages[0].serverId, 'jdtls');
    expect(messages[0].type, LspMessageType.error);
    expect(messages[0].message, 'Maven import failed');
    expect(messages[0].path, filePath);
    expect(messages[1].type, LspMessageType.warning);
    expect(messages[1].message, 'Using fallback JDK');
    expect(messages[2].type, LspMessageType.warning);
    expect(messages[2].message, 'Reload project?');

    expect(
      process.received.any((m) => m['id'] == 99 && m.containsKey('result')),
      isTrue,
    );

    final log = manager.logFor('jdtls', path: filePath);
    expect(
      log,
      containsAllInOrder([
        '[error] Maven import failed',
        '[warning] Using fallback JDK',
        '[info] FYI message',
        '[error] Internal log line',
        '[warning] Reload project?',
      ]),
    );
  });

  test('JDTLS language/status maps Starting/Message to progress, clears on '
      'ServiceReady, preserves Error across ServiceReady, and retains log after crash', () async {
    final process = _MockLspProcess();
    final paths = p.Context(style: p.Style.posix, current: '/workspace');
    final manager = LspManager(
      '/workspace',
      _StaticCatalog(const LspServerDefinition(id: 'jdtls', command: 'jdtls')),
      _FoundProvider(),
      paths: paths,
      pathExists: (path) => path == '/workspace/pom.xml',
      listDirectory: (_) => const [],
      startProcess: (_) async => process,
      watchDirectory: (_) => const Stream.empty(),
      maxCrashes: 1,
    );
    addTearDown(manager.dispose);

    final messages = <LspServerMessage>[];
    final sub = manager.serverMessages.listen(messages.add);
    addTearDown(sub.cancel);

    var progressTicks = 0;
    manager.progressChanges.addListener(() => progressTicks++);

    const filePath = '/workspace/src/Main.java';
    manager.openDocument(filePath, 'class Main {}');
    await pumpMicrotasks();

    process.sendNotification('language/status', {
      'type': 'Starting',
      'message': 'Importing Maven project...',
    });
    await pumpMicrotasks();
    var status = manager.statusFor(filePath).single;
    expect(status.progress, 'Importing Maven project...');
    expect(status.error, isNull);
    expect(progressTicks, greaterThan(0));

    process.sendNotification('language/status', {
      'type': 'ServiceReady',
      'message': 'ServiceReady',
    });
    await pumpMicrotasks();
    status = manager.statusFor(filePath).single;
    expect(status.progress, isNull);
    expect(status.error, isNull);

    // Simulate a project import error followed by Started/ServiceReady.
    process.sendNotification('language/status', {
      'type': 'Message',
      'message': 'Updating Maven configuration',
    });
    process.sendNotification('language/status', {
      'type': 'Error',
      'message': 'Non-resolvable parent POM for cn.dian1:cms.agent',
    });
    await pumpMicrotasks();
    status = manager.statusFor(filePath).single;
    expect(status.progress, isNull);
    expect(status.error, 'Non-resolvable parent POM for cn.dian1:cms.agent');
    expect(status.severity, LanguageServerSeverity.error);
    expect(messages.length, 1);
    expect(messages.single.type, LspMessageType.error);
    expect(
      messages.single.message,
      'Non-resolvable parent POM for cn.dian1:cms.agent',
    );

    // ServiceReady after an Error does NOT erase the recorded error.
    process.sendNotification('language/status', {
      'type': 'Started',
      'message': 'Ready',
    });
    await pumpMicrotasks();
    status = manager.statusFor(filePath).single;
    expect(status.error, 'Non-resolvable parent POM for cn.dian1:cms.agent');
    expect(status.severity, LanguageServerSeverity.error);

    // A Warning does not downgrade an existing Error severity.
    process.sendNotification('language/status', {
      'type': 'Warning',
      'message': 'Minor warning',
    });
    await pumpMicrotasks();
    status = manager.statusFor(filePath).single;
    expect(status.severity, LanguageServerSeverity.error);
    expect(messages.length, 2);
    expect(messages.last.type, LspMessageType.warning);

    // Log lines include [status] entries and survive server crash.
    process.emitStderr('SEVERE: maven error');
    await pumpMicrotasks();
    process.crash(1);
    await pumpMicrotasks();
    expect(
      manager.statusFor(filePath).single.state,
      LanguageServerState.failed,
    );
    final log = manager.logFor('jdtls', path: filePath);
    expect(
      log,
      contains(
        '[status] Error: Non-resolvable parent POM for cn.dian1:cms.agent',
      ),
    );
    expect(log, contains('[stderr] SEVERE: maven error'));
  });

  test('Maven model diagnostics notify once, persist across readiness, and clear on repair', () async {
    final process = _MockLspProcess();
    final manager = LspManager(
      '/workspace',
      _StaticCatalog(const LspServerDefinition(id: 'jdtls', command: 'jdtls')),
      _FoundProvider(),
      paths: p.Context(style: p.Style.posix, current: '/workspace'),
      pathExists: (path) => path == '/workspace/pom.xml',
      startProcess: (_) async => process,
      watchDirectory: (_) => const Stream.empty(),
    );
    addTearDown(manager.dispose);
    final messages = <LspServerMessage>[];
    final subscription = manager.serverMessages.listen(messages.add);
    addTearDown(subscription.cancel);
    const path = '/workspace/src/Main.java';
    const pomUri = 'file:///workspace/pom.xml';
    manager.openDocument(path, 'class Main {}');
    await pumpMicrotasks();
    final diagnostic = {
      'range': {
        'start': {'line': 3, 'character': 0},
        'end': {'line': 3, 'character': 10},
      },
      'message': 'Non-resolvable parent POM',
      'severity': 1,
      'source': 'Java',
    };
    void publish(String uri, List<Object?> diagnostics) =>
        process.sendNotification('textDocument/publishDiagnostics', {
          'uri': uri,
          'diagnostics': diagnostics,
        });

    // A compiler error in Java code stays in Problems, with no project toast.
    publish('file:///workspace/src/Main.java', [diagnostic]);
    await pumpMicrotasks();
    expect(messages, isEmpty);
    expect(manager.statusFor(path).single.error, isNull);

    publish(pomUri, [diagnostic]);
    await pumpMicrotasks();
    expect(messages.single.message, 'Non-resolvable parent POM');
    expect(manager.statusFor(path).single.error, 'Non-resolvable parent POM');
    expect(
      manager.statusFor(path).single.severity,
      LanguageServerSeverity.error,
    );
    expect(manager.allDiagnostics['/workspace/pom.xml'], hasLength(1));
    expect(
      manager.logFor('jdtls'),
      contains('[project] /workspace/pom.xml: Non-resolvable parent POM'),
    );

    // Repeated diagnostics and the server becoming ready are not recovery.
    publish(pomUri, [diagnostic]);
    process.sendNotification('language/status', {
      'type': 'Started',
      'message': 'Ready',
    });
    await pumpMicrotasks();
    expect(messages, hasLength(1));
    expect(manager.statusFor(path).single.error, 'Non-resolvable parent POM');

    publish(pomUri, []);
    await pumpMicrotasks();
    expect(manager.statusFor(path).single.error, isNull);
    expect(manager.statusFor(path).single.severity, isNull);
    expect(manager.allDiagnostics.containsKey('/workspace/pom.xml'), isFalse);

    // The same failure after a successful repair is a new error to surface.
    publish(pomUri, [diagnostic]);
    await pumpMicrotasks();
    expect(messages, hasLength(2));
  });
}

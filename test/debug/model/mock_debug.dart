// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0): src/vs/workbench/contrib/debug/test/common/mockDebug.ts
// and src/vs/workbench/contrib/debug/test/browser/mockDebugModel.ts
//
// Test doubles shared by the debug model tests: a model over memory
// storage, sessions that never talk to an adapter (`createTestSession`),
// a raw session answering a canned call stack (`MockRawSession`) and an
// adapter that echoes evaluations (`MockDebugAdapter`).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show CancellationToken;
import 'package:baocode/debug/base/event.dart';
import 'package:baocode/debug/common/debug_model.dart';
import 'package:baocode/debug/common/debug_storage.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/debug/session/debug_adapter.dart';
import 'package:baocode/debug/session/debug_session.dart';
import 'package:baocode/debug/session/raw_debug_session.dart';

import '../support/fake_debug_adapter.dart' show FakeDebugHost;

/// `createMockDebugModel`: a model over memory storage, no file dirty.
DebugModel createMockDebugModel() =>
    DebugModel(DebugStorage(MemoryDebugStorageBackend()), isDirty: (_) => false);

/// A service for sessions to ask settings, the host and the view model of.
DebugService createMockDebugService() =>
    DebugService(host: FakeDebugHost(), storage: MemoryDebugStorageBackend());

/// `createTestSession`: a `node` launch session that has not started.
DebugSession createTestSession(
  DebugModel model,
  DebugService service, {
  String name = 'mockSession',
  DebugSessionOptions? options,
}) => DebugSession(
  generateUuid(),
  (resolved: {'name': name, 'type': 'node', 'request': 'launch'}, unresolved: null),
  null,
  model,
  options,
  service,
);

/// A transport that never answers.
final class _SilentTransport extends EmitterDebugAdapterTransport {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void send(Json message) {}
}

final class _NullDebugger implements RawDebugger {
  const _NullDebugger();

  @override
  String get type => 'mock';

  @override
  Future<int?> runInTerminal(Json args, String sessionId) async => null;

  @override
  Future<bool> startDebugging(Json config, String parentSessionId) async => false;
}

/// `MockRawSession`: one frame for any `stackTrace`, nothing for
/// `evaluate`, the rest not implemented.
class MockRawSession extends RawDebugSession {
  MockRawSession() : super(DebugAdapter(_SilentTransport()), const _NullDebugger(), 'mock', 'mock');

  /// How often `stackTrace` was asked (the upstream test's sinon spy).
  int stackTraceCallCount = 0;

  @override
  Future<Json?> stackTrace(Json args, CancellationToken? token) {
    stackTraceCallCount++;
    return Future.value({
      'seq': 1,
      'type': 'response',
      'request_seq': 1,
      'success': true,
      'command': 'stackTrace',
      'body': {
        'stackFrames': [
          {'id': 1, 'name': 'mock', 'line': 5, 'column': 6},
        ],
      },
    });
  }

  @override
  Future<Json?> evaluate(Json args) => Future.value(null);

  @override
  Future<Json?> scopes(Json args, CancellationToken? token) => throw UnimplementedError('not implemented');

  @override
  Future<Json?> variables(Json args, CancellationToken? token) => throw UnimplementedError('not implemented');

  @override
  Future<Json?> threads() => throw UnimplementedError('not implemented');
}

/// `MockDebugAdapter`: answers every request on the next turn of the event
/// loop; `evaluate` echoes `=expression`, with an `output` event before
/// the response for `before.*` and after it for `after.*`.
class MockDebugAdapter extends EmitterDebugAdapterTransport {
  int _seq = 0;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void send(Json message) {
    if (message['type'] != 'request') return;
    Timer.run(() {
      if (message['command'] == 'evaluate') {
        _evaluate(message, message.obj('arguments') ?? const {});
        return;
      }
      sendResponseBody(message, {});
    });
  }

  void sendResponseBody(Json request, Json body) => acceptMessage({
    'seq': ++_seq,
    'type': 'response',
    'request_seq': request['seq'],
    'command': request['command'],
    'success': true,
    'body': body,
  });

  void sendEventBody(String event, Json body) =>
      acceptMessage({'seq': ++_seq, 'type': 'event', 'event': event, 'body': body});

  void _evaluate(Json request, Json args) {
    final expression = args.str('expression') ?? '';
    if (expression.startsWith('before.')) sendEventBody('output', {'output': expression});
    sendResponseBody(request, {'result': '=$expression', 'variablesReference': 0});
    if (expression.startsWith('after.')) sendEventBody('output', {'output': expression});
  }
}

/// A raw session over [MockDebugAdapter].
RawDebugSession createMockAdapterRawSession(MockDebugAdapter adapter) =>
    RawDebugSession(DebugAdapter(adapter), const _NullDebugger(), '', '');

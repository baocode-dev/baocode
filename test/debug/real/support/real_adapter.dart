// Shared pieces of the real debug adapter tests: a service with one debug
// type whose adapter is a real process, a transport that keeps the DAP
// traffic for assertions and failure logs, and waits on the model.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:baocode/debug/base/event.dart';
import 'package:baocode/debug/common/debug_model.dart';
import 'package:baocode/debug/common/debug_storage.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/service/debug_configuration_manager.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/debug/service/debugger.dart';
import 'package:baocode/debug/session/debug_adapter.dart';
import 'package:baocode/debug/session/debug_session.dart';

import '../../support/fake_debug_adapter.dart';

/// Wraps a transport and keeps every message both ways.
final class TracingTransport implements DebugAdapterTransport {
  TracingTransport(this.inner, this.log) {
    inner.onMessage((m) => log.add('<- ${jsonEncode(m)}'));
  }

  final DebugAdapterTransport inner;
  final List<String> log;

  @override
  Future<void> start() => inner.start();

  @override
  void send(Json message) {
    log.add('-> ${jsonEncode(message)}');
    inner.send(message);
  }

  @override
  Future<void> stop() => inner.stop();

  @override
  DebugDisposable onMessage(void Function(Json message) listener) => inner.onMessage(listener);

  @override
  DebugDisposable onError(void Function(Object error) listener) => inner.onError(listener);

  @override
  DebugDisposable onExit(void Function(int? code) listener) => inner.onExit(listener);

  @override
  void dispose() => inner.dispose();
}

/// Makes a real adapter's transport for each session, traced.
class RealAdapterFactory implements DebugAdapterFactory {
  RealAdapterFactory(this.make);

  final DebugAdapterTransport Function(DebugSession session) make;

  /// DAP traffic and adapter stderr, for failure messages.
  final List<String> log = [];

  @override
  DebugAdapterTransport createDebugAdapter(DebugSession session) =>
      TracingTransport(make(session), log);

  @override
  Future<Json> substituteVariables(DebugWorkspaceFolder? folder, Json config) async => config;

  @override
  Future<int?> runInTerminal(Json args, String sessionId) async => null;

  /// The messages the adapter sent, parsed.
  List<Json> get received => [
    for (final line in log)
      if (line.startsWith('<- ')) (jsonDecode(line.substring(3)) as Map).cast<String, Object?>(),
  ];

  /// The adapter's events named [event].
  List<Json> events(String event) => [
    for (final m in received)
      if (m['type'] == 'event' && m['event'] == event) m,
  ];

  /// The last [lines] lines of the log.
  String tail([int lines = 60]) =>
      log.length <= lines ? log.join('\n') : log.sublist(log.length - lines).join('\n');
}

typedef RealDebug = ({DebugService service, FakeDebugHost host, RealAdapterFactory factory});

/// A service whose only debug type is [type], served by [factory], with
/// [folder] as the workspace.
Future<RealDebug> createRealDebugService({
  required String type,
  required String label,
  required RealAdapterFactory factory,
  required String folder,
  List<String> languages = const [],
}) async {
  final host = FakeDebugHost(
    folders: [DebugWorkspaceFolder(uri: VsUri.file(folder), name: 'real', index: 0)],
  );
  final service = DebugService(
    host: host,
    storage: MemoryDebugStorageBackend(),
    fileStore: MemoryLaunchFileStore(),
  );
  service.registry.setExtensions([
    DebuggerExtension(
      id: 'test.$type',
      debuggers: [
        {'type': type, 'label': label, 'languages': languages},
      ],
      breakpoints: [
        for (final language in languages) {'language': language},
      ],
    ),
  ]);
  service.registry.registerDebugAdapterFactory([type], factory);
  await service.configurationManager.initialize();
  return (service: service, host: host, factory: factory);
}

/// The 1-based line of [file] holding `BP:<marker>`.
int markerLine(String file, String marker) {
  final lines = File(file).readAsLinesSync();
  final tag = 'BP:$marker';
  for (var i = 0; i < lines.length; i++) {
    final at = lines[i].indexOf(tag);
    if (at >= 0 && !lines[i].substring(at + tag.length).startsWith(RegExp(r'[\w-]'))) return i + 1;
  }
  throw StateError('no $tag in $file');
}

/// Waits until [condition] holds, with the adapter's traffic in the error.
Future<void> waitFor(
  RealDebug d,
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  try {
    await until(condition, timeout: timeout);
  } on TimeoutException {
    throw TimeoutException('$what\n--- adapter log ---\n${d.factory.tail()}\n--- errors ---\n${d.host.errors}');
  }
}

/// Waits for the focused thread to stop for [reason] at [line] (and,
/// when given, in a frame whose name contains [function]).
Future<StackFrame> waitForStop(
  RealDebug d, {
  required int line,
  String? reason,
  String? function,
  Duration timeout = const Duration(seconds: 30),
}) async {
  await waitFor(d, () {
    final frame = d.service.viewModel.focusedStackFrame;
    final thread = d.service.viewModel.focusedThread;
    return frame != null &&
        thread != null &&
        thread.stopped &&
        frame.range.startLineNumber == line &&
        (reason == null || thread.stoppedDetails?.reason == reason) &&
        (function == null || frame.name.contains(function));
  }, 'a stop at line $line${reason == null ? '' : ' ($reason)'}', timeout: timeout);
  return d.service.viewModel.focusedStackFrame!;
}

/// The variables of [frame]'s first scope whose name matches [scope], as
/// name to value.
Future<Map<String, String>> scopeValues(StackFrame frame, Pattern scope) async {
  final scopes = await frame.getScopes();
  final match = scopes.firstWhere(
    (s) => s.name.contains(scope),
    orElse: () => throw StateError('no scope $scope in ${scopes.map((s) => s.name).toList()}'),
  );
  final children = await match.getChildren();
  return {for (final v in children) v.name: v.value};
}

/// Ends every session and waits for them to go.
Future<void> shutDown(RealDebug d) async {
  if (d.service.model.getSessions().isNotEmpty) {
    await d.service.stopSession(null);
    try {
      await until(() => d.service.model.getSessions().isEmpty, timeout: const Duration(seconds: 15));
    } on TimeoutException {
      // Disposed below anyway.
    }
  }
  d.service.dispose();
}

/// The first executable among [candidates] that exists, else null.
String? firstExisting(Iterable<String?> candidates) {
  for (final c in candidates) {
    if (c != null && c.isNotEmpty && File(c).existsSync()) return c;
  }
  return null;
}

/// `which`-like lookup on PATH plus [extra] directories.
String? findExecutable(String name, [List<String> extra = const []]) {
  final path = Platform.environment['PATH'] ?? '';
  return firstExisting([
    for (final dir in [...path.split(':'), ...extra]) '$dir/$name',
  ]);
}

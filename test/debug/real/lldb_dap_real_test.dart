// Sessions against a real lldb-dap (Xcode's, or one on PATH, or
// $LLDB_DAP): a C program built with clang at test time, breakpoints
// (line, conditional, function, logpoint), the call stack, locals, a step,
// REPL evaluation, and the run to exit. Opt in with
// `flutter test --run-skipped -t exthost test/debug/real`.
@Tags(['exthost'])
library;

import 'dart:async';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:baocode/debug/common/debug_model.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/common/repl_model.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/debug/session/debug_session.dart';
import 'package:baocode/debug/session/stream_debug_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/real_adapter.dart';

String? _xcrun(String tool) {
  if (!Platform.isMacOS) return null;
  try {
    final r = Process.runSync('xcrun', ['-f', tool]);
    return r.exitCode == 0 ? (r.stdout as String).trim() : null;
  } on ProcessException {
    return null;
  }
}

final String? _lldbDap = firstExisting([
  Platform.environment['LLDB_DAP'],
  _xcrun('lldb-dap'),
  '/Applications/Xcode.app/Contents/Developer/usr/bin/lldb-dap',
  findExecutable('lldb-dap'),
]);

// The PATH clang (on macOS, the /usr/bin shim that finds the SDK).
final String? _clang = findExecutable('clang');

final String _source = File('test/debug/real/fixtures/lldb/program.c').absolute.path;

void main() {
  final skip = _lldbDap == null
      ? 'lldb-dap not found (set LLDB_DAP)'
      : _clang == null
      ? 'clang not found'
      : false;

  late Directory dir;
  late String program;

  setUpAll(() async {
    if (skip != false) return;
    dir = await Directory.systemTemp.createTemp('baocode-lldb-dap-');
    program = '${dir.path}/program';
    final r = await Process.run(_clang!, ['-g', '-O0', '-o', program, _source]);
    if (r.exitCode != 0) fail('clang failed: ${r.stderr}');
  });

  tearDownAll(() async {
    if (skip != false) return;
    await dir.delete(recursive: true);
  });

  Future<RealDebug> start(Future<void> Function(DebugService service) breakpoints) async {
    late final RealAdapterFactory factory;
    factory = RealAdapterFactory(
      (_) => StdioDebugAdapterTransport(_lldbDap!, const [], onStderr: (t) => factory.log.add('stderr: $t')),
    );
    final d = await createRealDebugService(
      type: 'lldb-dap',
      label: 'LLDB DAP',
      factory: factory,
      folder: dir.path,
      languages: const ['c'],
    );
    addTearDown(() => shutDown(d));
    await breakpoints(d.service);
    final launch = d.service.configurationManager.getLaunches().firstOrNull;
    final ok = await d.service.startDebugging(launch, {
      'type': 'lldb-dap',
      'request': 'launch',
      'name': 'Debug program',
      'program': program,
      'cwd': dir.path,
      'stopOnEntry': false,
    });
    expect(ok, isTrue, reason: '${d.host.errors}\n${factory.tail()}');
    return d;
  }

  Future<DebugSessionEndEvent> runToExit(RealDebug d, DebugSession session) async {
    final ended = Completer<DebugSessionEndEvent>();
    d.service.onDidEndSession((e) {
      if (!ended.isCompleted) ended.complete(e);
    });
    await d.service.viewModel.focusedThread!.continue_();
    final e = await ended.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('no end of session\n${d.factory.tail()}'),
    );
    await waitFor(d, () => d.service.model.getSessions().isEmpty, 'the session to go');
    expect(d.service.state, DebugState.inactive);
    return e;
  }

  test('line breakpoint: stop, call stack, locals, step, REPL, run to exit', () async {
    final addLine = markerLine(_source, 'add');
    final d = await start(
      (service) => service.addBreakpoints(VsUri.file(_source), [BreakpointData(lineNumber: addLine)]),
    );
    final session = d.service.model.getSessions().single;

    var frame = await waitForStop(d, line: addLine, reason: 'breakpoint', function: 'add');
    expect(session.state, DebugState.stopped);
    expect(session.capabilities.flag('supportsConfigurationDoneRequest'), isTrue);
    expect(frame.source.uri.fsPath(), _source);
    final bp = d.service.model.getBreakpoints().single;
    expect(bp.verified, isTrue, reason: bp.message);
    expect(bp.lineNumber, addLine);
    expect(d.host.breaks, greaterThanOrEqualTo(1));

    // The stack: add called from main.
    final thread = d.service.viewModel.focusedThread!;
    await waitFor(d, () => thread.getCallStack().any((f) => f.name.contains('main')), 'main on the stack');
    final names = thread.getCallStack().map((f) => f.name).toList();
    expect(names.first, contains('add'));
    expect(names.indexWhere((n) => n.contains('main')), greaterThan(0), reason: '$names');

    final locals = await scopeValues(frame, 'Locals');
    expect(locals['a'], '40');
    expect(locals['b'], '2');

    // One step, to the next line, with the sum computed.
    await thread.next();
    frame = await waitForStop(d, line: markerLine(_source, 'add-next'), reason: 'step', function: 'add');
    expect((await scopeValues(frame, 'Locals'))['sum'], '42');

    // The REPL evaluates in the focused frame.
    await session.addReplExpression(frame, 'sum * 2');
    final result = session.getReplElements().whereType<ReplEvaluationResult>().last;
    expect(result.value, '84');

    // A watch expression too.
    d.service.addWatchExpression('a - b');
    final watch = d.service.model.getWatchExpressions().single;
    await watch.evaluate(session, frame, 'watch');
    expect(watch.value, '38');

    final end = await runToExit(d, session);
    expect(end.session, session);
    expect(d.factory.events('exited').single.obj('body')!['exitCode'], 0);
    final output = session.getReplElements().whereType<ReplOutputElement>().map((e) => e.value).join();
    expect(output, contains('answer=42 total=10'), reason: d.factory.tail());
  });

  test('function, conditional and log point breakpoints', () async {
    final entryLine = markerLine(_source, 'accumulate-entry');
    final loopLine = markerLine(_source, 'loop');
    final returnLine = markerLine(_source, 'accumulate-return');
    final d = await start((service) async {
      await service.addFunctionBreakpoint(FunctionBreakpoint(name: 'accumulate'));
      await service.addBreakpoints(VsUri.file(_source), [
        BreakpointData(lineNumber: loopLine, condition: 'i == 3'),
        BreakpointData(lineNumber: returnLine, logMessage: 'total is {total}'),
      ]);
    });
    final session = d.service.model.getSessions().single;

    // Stopped on entry to accumulate.
    var frame = await waitForStop(d, line: entryLine, function: 'accumulate');
    final caps = session.capabilities;
    expect(caps.flag('supportsFunctionBreakpoints'), isTrue);
    expect(caps.flag('supportsConditionalBreakpoints'), isTrue);
    expect(caps.flag('supportsLogPoints'), isTrue);
    expect(d.service.viewModel.focusedThread!.stoppedDetails!.reason, 'function breakpoint');
    expect(d.service.model.getFunctionBreakpoints().single.verified, isTrue);
    expect((await scopeValues(frame, 'Locals'))['limit'], '5');

    // The condition skips i = 0, 1, 2.
    await d.service.viewModel.focusedThread!.continue_();
    frame = await waitForStop(d, line: loopLine, reason: 'breakpoint', function: 'accumulate');
    final locals = await scopeValues(frame, 'Locals');
    expect(locals['i'], '3');
    expect(locals['total'], '3');

    // The log point logs and does not stop; the program runs to its end.
    await runToExit(d, session);
    final output = session.getReplElements().whereType<ReplOutputElement>().map((e) => e.value).join();
    expect(output, contains('total is 10'), reason: d.factory.tail());
    expect(d.factory.events('stopped').length, 2);
  });

  test('stopping a stopped session kills the program and the adapter', () async {
    final addLine = markerLine(_source, 'add');
    final d = await start(
      (service) => service.addBreakpoints(VsUri.file(_source), [BreakpointData(lineNumber: addLine)]),
    );
    final session = d.service.model.getSessions().single;
    await waitForStop(d, line: addLine, reason: 'breakpoint');

    final ended = Completer<DebugSessionEndEvent>();
    d.service.onDidEndSession(ended.complete);
    await d.service.stopSession(session);
    final e = await ended.future.timeout(const Duration(seconds: 15));
    expect(e.restart, isFalse);
    await waitFor(d, () => d.service.model.getSessions().isEmpty, 'the session to go');
    final sent = d.factory.log.where((l) => l.startsWith('-> ')).join('\n');
    expect(sent, anyOf(contains('"command":"terminate"'), contains('"command":"disconnect"')));
  });
}

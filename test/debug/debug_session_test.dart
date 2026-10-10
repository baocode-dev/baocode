// Sessions against the scripted adapter: the DAP sequence, stops and
// focus, call stacks, variables, watch, console, steps, child sessions,
// reverse requests, compounds, tasks and termination.

import 'dart:async';

import 'package:baocode/base/cancellation.dart' show CancellationTokenSource;
import 'package:baocode/base/uri.dart' show VsUri;
import 'package:baocode/debug/common/debug_model.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/common/repl_model.dart';
import 'package:baocode/debug/service/debug_host.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/debug/session/debug_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_debug_adapter.dart';

final _program = VsUri.file(fakeProgramPath);

Json _launch([Json? extra]) => {
  'type': 'fake',
  'request': 'launch',
  'name': 'Run main',
  'program': r'${workspaceFolder}/main.js',
  ...?extra,
};

Future<DebugSession> _startStopped(DebugService service) async {
  final launch = service.configurationManager.getLaunches().first;
  final ok = await service.startDebugging(launch, _launch());
  expect(ok, isTrue);
  final session = service.model.getSessions().single;
  await until(() => service.viewModel.focusedStackFrame != null);
  return session;
}

void main() {
  test('initialize, launch, breakpoints, configurationDone, threads in order', () async {
    final f = await createFakeDebugService();
    await f.service.addBreakpoints(_program, [const BreakpointData(lineNumber: 7)]);
    await f.service.addFunctionBreakpoint(FunctionBreakpoint(name: 'compute'));
    final session = await _startStopped(f.service);
    final adapter = f.factory.last;

    expect(adapter.started, isTrue);
    final commands = adapter.commands;
    expect(commands.first, 'initialize');
    expect(commands, containsAllInOrder(['initialize', 'launch']));
    final configurationDone = commands.indexOf('configurationDone');
    for (final c in ['setBreakpoints', 'setFunctionBreakpoints', 'setExceptionBreakpoints']) {
      expect(commands.indexOf(c), inInclusiveRange(0, configurationDone - 1), reason: c);
    }
    expect(commands.indexOf('threads'), greaterThan(configurationDone));

    // The initialize arguments are VS Code's.
    final init = adapter.requests.first.obj('arguments')!;
    expect(init['clientID'], 'vscode');
    expect(init['adapterID'], 'fake');
    expect(init['linesStartAt1'], isTrue);
    expect(init['supportsRunInTerminalRequest'], isTrue);
    expect(init['supportsStartDebuggingRequest'], isTrue);

    // Variables substituted, the session id passed on.
    expect(adapter.launchArgs!['program'], '/work/app/main.js');
    expect(adapter.launchArgs!['__sessionId'], session.getId());

    // Exception filters came from the capabilities; the default is on.
    final filters = f.service.model.getExceptionBreakpointsForSession(session.getId());
    expect(filters.map((e) => e.filter), ['uncaught', 'all']);
    expect(filters.first.enabled, isTrue);
    final setEx = adapter.requests.firstWhere((r) => r['command'] == 'setExceptionBreakpoints');
    expect(setEx.obj('arguments')!['filters'], ['uncaught']);

    // Verified with the adapter's ids.
    final bp = f.service.model.getBreakpoints().single;
    expect(bp.verified, isTrue);
    expect(bp.getIdFromAdapter(session.getId()), isNotNull);
    expect(f.service.model.getFunctionBreakpoints().single.verified, isTrue);
    await f.service.stopSession(null);
    f.service.dispose();
  });

  test('a stop focuses the top frame and opens its source', () async {
    final f = await createFakeDebugService();
    await f.service.addBreakpoints(_program, [const BreakpointData(lineNumber: 7)]);
    final session = await _startStopped(f.service);

    expect(session.state, DebugState.stopped);
    expect(f.service.state, DebugState.stopped);
    final frame = f.service.viewModel.focusedStackFrame!;
    expect(frame.name, 'compute');
    expect(frame.range.startLineNumber, 7);
    expect(f.service.viewModel.focusedThread!.threadId, 1);
    expect(f.service.viewModel.focusedThread!.stoppedDetails!.reason, 'breakpoint');
    expect(f.host.opened.last.$1.path, fakeProgramPath);
    expect(f.host.opened.last.$2!.startLineNumber, 7);
    expect(f.host.breaks, 1);

    // All threads stopped; the whole stack came.
    final threads = session.getAllThreads();
    expect(threads.map((t) => t.name), ['main', 'worker']);
    expect(threads.every((t) => t.stopped), isTrue);
    await until(() => threads.first.getCallStack().length == 3);
    expect(threads.first.getCallStack().last.deemphasized, isTrue);
    await f.service.stopSession(null);
    f.service.dispose();
  });

  test('scopes, lazy variables, set value, watch and the console', () async {
    final f = await createFakeDebugService();
    final session = await _startStopped(f.service);
    final frame = f.service.viewModel.focusedStackFrame!;

    final scopes = await frame.getScopes();
    expect(scopes.map((s) => s.name), ['Local', 'Global']);
    expect(scopes.last.expensive, isTrue);
    final locals = await scopes.first.getChildren();
    expect(locals.map((v) => v.toString()), ['count: 3', 'user: {name: "Ada", age: 36}', 'items: Array(3)']);
    final user = locals[1] as Variable;
    expect(user.hasChildren, isTrue);
    final fields = await user.getChildren();
    expect(fields.map((v) => v.toString()), ['name: "Ada"', 'age: 36']);

    final count = locals.first as Variable;
    await count.setVariable('41', frame);
    expect(count.value, '41');
    expect(f.factory.last.count, '41');

    f.service.addWatchExpression('count * 2');
    f.service.addWatchExpression('missing');
    final watches = f.service.model.getWatchExpressions();
    await watches[0].evaluate(session, frame, 'watch');
    await watches[1].evaluate(session, frame, 'watch');
    expect(watches[0].value, '82');
    expect(watches[1].value, 'missing is not defined');
    expect(watches[1].available, isFalse);

    await session.addReplExpression(frame, 'user');
    final elements = session.getReplElements();
    final input = elements.whereType<ReplEvaluationInput>().single;
    expect(input.value, 'user');
    final result = elements.whereType<ReplEvaluationResult>().single;
    expect(result.value, '{name: "Ada", age: 36}');
    expect((await result.getChildren()).length, 2);

    // Program output arrived in the console.
    final outputs = elements.whereType<ReplOutputElement>().map((e) => e.value).join();
    expect(outputs, contains('hello from the program'));

    final completions = await session.completions(frame.frameId, 1, 'co', (lineNumber: 1, column: 3), _never);
    expect(completions!.obj('body')!.objects('targets').map((t) => t['label']), ['count', 'console']);
    await f.service.stopSession(null);
    f.service.dispose();
  });

  test('steps continue and stop again; continue runs; terminate ends', () async {
    final f = await createFakeDebugService();
    final session = await _startStopped(f.service);
    final thread = f.service.viewModel.focusedThread!;
    final line = f.service.viewModel.focusedStackFrame!.range.startLineNumber;

    await thread.next();
    await until(() => f.service.viewModel.focusedStackFrame?.range.startLineNumber == line + 1);
    expect(thread.stoppedDetails!.reason, 'step');

    await thread.stepIn();
    await until(() => f.service.viewModel.focusedStackFrame?.range.startLineNumber == line + 2);

    final top = thread.getTopStackFrame()!;
    expect(top.canRestart, isTrue);
    await top.restart();
    await until(() => thread.stoppedDetails?.reason == 'restart');

    await thread.continue_();
    await until(() => session.state == DebugState.running);
    expect(thread.stopped, isFalse);

    final ended = Completer<DebugSessionEndEvent>();
    f.service.onDidEndSession(ended.complete);
    await f.service.stopSession(session);
    final e = await ended.future.timeout(const Duration(seconds: 5));
    expect(e.session, session);
    expect(e.restart, isFalse);
    expect(f.factory.last.commands, contains('terminate'));
    expect(f.factory.last.commands, contains('disconnect'));
    expect(f.factory.last.stopped, isTrue);
    expect(f.service.state, DebugState.inactive);
    f.service.dispose();
  });

  test('pause stops a running thread', () async {
    final f = await createFakeDebugService();
    final session = await _startStopped(f.service);
    final thread = f.service.viewModel.focusedThread!;
    await thread.continue_();
    await until(() => session.state == DebugState.running);
    await thread.pause();
    await until(() => thread.stoppedDetails?.reason == 'pause');
    expect(session.state, DebugState.stopped);
    await f.service.stopSession(null);
    f.service.dispose();
  });

  test('breakpoints changed during a session go to the adapter', () async {
    final f = await createFakeDebugService();
    final session = await _startStopped(f.service);
    final adapter = f.factory.last;

    final added = await f.service.addBreakpoints(_program, [
      const BreakpointData(lineNumber: 12, condition: 'count > 2'),
      const BreakpointData(lineNumber: 150),
    ]);
    expect(adapter.breakpointLines[fakeProgramPath], [12, 150]);
    final sent = adapter.requests.lastWhere((r) => r['command'] == 'setBreakpoints');
    expect(sent.obj('arguments')!.objects('breakpoints').first['condition'], 'count > 2');
    expect(added.first.verified, isTrue);
    expect(added.last.verified, isFalse);
    expect(added.last.message, 'No code at this line');

    await f.service.enableOrDisableBreakpoints(false, added.first);
    expect(adapter.breakpointLines[fakeProgramPath], [150]);
    await f.service.setBreakpointsActivated(false);
    expect(adapter.breakpointLines[fakeProgramPath], isEmpty);
    await f.service.setBreakpointsActivated(true);
    await f.service.removeBreakpoints();
    expect(adapter.breakpointLines[fakeProgramPath], isEmpty);

    final all = f.service.model.getExceptionBreakpointsForSession(session.getId()).last;
    await f.service.enableOrDisableBreakpoints(true, all);
    await f.service.setExceptionBreakpointCondition(all, 'err.code == 1');
    final ex = adapter.requests.lastWhere((r) => r['command'] == 'setExceptionBreakpoints');
    expect(ex.obj('arguments')!['filters'], ['uncaught', 'all']);

    // A data breakpoint on a variable.
    final info = await session.dataBreakpointInfo('count', variablesReference: 100);
    await f.service.addDataBreakpoint(
      DataBreakpoint(
        description: info!.str('description')!,
        src: DataBreakpointVariable(info.str('dataId')!),
        canPersist: false,
        accessType: 'write',
        accessTypes: const ['write', 'read'],
      ),
    );
    final data = adapter.requests.lastWhere((r) => r['command'] == 'setDataBreakpoints');
    expect(data.obj('arguments')!.objects('breakpoints').single['dataId'], 'data:count');
    await f.service.stopSession(null);
    await until(() => f.service.model.getSessions().isEmpty);
    // Data breakpoints that cannot persist go with the last session.
    expect(f.service.model.getDataBreakpoints(), isEmpty);
    f.service.dispose();
  });

  test('startDebugging reverse request makes a child session', () async {
    final f = await createFakeDebugService();
    final parent = await _startStopped(f.service);
    f.factory.adapters.first.reverseRequest('startDebugging', {
      'request': 'launch',
      'configuration': {'type': 'fake', 'name': 'child worker', 'request': 'launch'},
    });
    await until(() => f.service.model.getSessions().length == 2);
    final child = f.service.model.getSessions().last;
    expect(child.parentSession, parent);
    expect(child.name, 'child worker');
    await until(() => f.factory.adapters.first.responsesToReverse.isNotEmpty);
    expect(f.factory.adapters.first.responsesToReverse.single['success'], isTrue);

    f.factory.adapters.first.reverseRequest('runInTerminal', {
      'kind': 'integrated',
      'cwd': '/work/app',
      'args': ['node', 'main.js'],
    });
    await until(() => f.factory.terminalRequests.isNotEmpty);
    await until(() => f.factory.adapters.first.responsesToReverse.length == 2);
    expect(f.factory.adapters.first.responsesToReverse.last.obj('body')!['shellProcessId'], 4242);
    await f.service.stopSession(null);
    f.service.dispose();
  });

  test('compounds start every configuration; stopAll stops them together', () async {
    final f = await createFakeDebugService(
      launchFiles: {
        VsUri.file('/work/app/.vscode/launch.json').toString(): '''{
  // two programs
  "version": "0.2.0",
  "configurations": [
    {"type": "fake", "request": "launch", "name": "Server", "program": "server.js"},
    {"type": "fake", "request": "launch", "name": "Client", "program": "client.js"},
  ],
  "compounds": [
    {"name": "Both", "configurations": ["Server", "Client"], "stopAll": true, "preLaunchTask": "build"}
  ]
}''',
      },
    );
    final launch = f.service.configurationManager.getLaunches().first;
    expect(launch.getConfigurationNames(), ['Server', 'Client', 'Both']);
    expect(await f.service.startDebugging(launch, 'Both'), isTrue);
    expect(f.host.tasks, ['build']);
    final sessions = f.service.model.getSessions();
    expect(sessions.map((s) => s.name).toSet(), {'Server', 'Client'});
    expect(sessions.first.compoundRoot, isNotNull);
    await until(() => sessions.every((s) => s.state == DebugState.stopped));

    await f.service.stopSession(sessions.first);
    await until(() => f.service.model.getSessions().isEmpty, timeout: const Duration(seconds: 10));
    f.service.dispose();
  });

  test('a failing preLaunchTask stops the start; postDebugTask runs at the end', () async {
    final f = await createFakeDebugService();
    final launch = f.service.configurationManager.getLaunches().first;
    f.host.taskResult = TaskRunResult.failure;
    expect(await f.service.startDebugging(launch, _launch({'preLaunchTask': 'build'})), isFalse);
    expect(f.factory.adapters, isEmpty);
    expect(f.service.state, DebugState.inactive);

    f.host.taskResult = TaskRunResult.success;
    f.host.tasks.clear();
    expect(await f.service.startDebugging(launch, _launch({'postDebugTask': 'cleanup'})), isTrue);
    await until(() => f.service.viewModel.focusedStackFrame != null);
    await f.service.stopSession(null);
    await until(() => f.host.tasks.contains('cleanup'));
    f.service.dispose();
  });

  test('restart without supportsRestartRequest terminates and launches again', () async {
    final f = await createFakeDebugService();
    final session = await _startStopped(f.service);
    final ends = <DebugSessionEndEvent>[];
    f.service.onDidEndSession(ends.add);
    await f.service.restartSession(session);
    await until(() => f.factory.adapters.length == 2);
    expect(ends.single.restart, isTrue);
    await until(() => session.state == DebugState.stopped);
    expect(f.service.model.getSessions(), [session]);
    await f.service.stopSession(null);
    f.service.dispose();
  });

  test('an adapter that exits unexpectedly ends the session with an error', () async {
    final f = await createFakeDebugService();
    final session = await _startStopped(f.service);
    final ended = Completer<void>();
    f.service.onDidEndSession((_) => ended.complete());
    f.factory.last.crash(3);
    await ended.future.timeout(const Duration(seconds: 5));
    expect(f.host.errors.single, contains('terminated unexpectedly'));
    expect(session.state, DebugState.inactive);
    f.service.dispose();
  });

  test('unknown types and bad requests are reported', () async {
    final f = await createFakeDebugService();
    final launch = f.service.configurationManager.getLaunches().first;
    expect(
      await f.service.startDebugging(launch, {'type': 'nope', 'request': 'launch', 'name': 'x'}),
      isFalse,
    );
    expect(f.host.errors.last, "Configured debug type 'nope' is not supported.");
    expect(
      await f.service.startDebugging(launch, {'type': 'fake', 'request': 'run', 'name': 'x'}),
      isFalse,
    );
    expect(f.host.errors.last, contains("unsupported value 'run'"));
    f.service.dispose();
  });

  test('loaded sources and exception info', () async {
    final f = await createFakeDebugService();
    final session = await _startStopped(f.service);
    final sources = await session.getLoadedSources();
    expect(sources.map((s) => s.name), ['main.js', 'worker.js']);
    final info = await session.exceptionInfo(1);
    expect(info!.description, 'boom');
    await f.service.stopSession(null);
    f.service.dispose();
  });
}

final _never = CancellationTokenSource().token;

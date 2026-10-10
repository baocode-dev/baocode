// What the debugging acceptance tests drive: the workspace's debug service
// as the Run and Debug views use it.

import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:baocode/debug/common/debug_model.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/common/repl_model.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/debug/session/debug_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'open_vsx_workspace.dart';

/// The 1-based line of [source] holding `BP:<marker>`.
int bpLine(String source, String marker) {
  final lines = source.split('\n');
  final tag = RegExp('BP:${RegExp.escape(marker)}(?![\\w-])');
  final index = lines.indexWhere(tag.hasMatch);
  if (index < 0) throw StateError('no BP:$marker');
  return index + 1;
}

/// The workspace's debug service, as the Run and Debug views use it.
final class DebugDriver {
  DebugDriver(this.w) : service = w.extensions.debug!;

  final OpenVsxWorkspace w;
  final DebugService service;

  /// The focused session (js-debug's program runs in a child session).
  DebugSession get session => service.viewModel.focusedSession!;

  Thread get thread => service.viewModel.focusedThread!;

  /// Starts [configuration] from the folder's launch.
  Future<void> start(Map<String, Object?> configuration) async {
    final launch = service.configurationManager.getLaunch(
      VsUri.file(w.project),
    );
    final started = await service
        .startDebugging(launch, configuration)
        .timeout(const Duration(minutes: 2));
    expect(
      started,
      isTrue,
      reason:
          '${[for (final n in w.workspace.notifications.notifications) n.message]}'
          '\n${w.report()}',
    );
  }

  /// What the terminals show (an adapter's `runInTerminal`).
  String terminals() => [
    for (final instance in w.extensions.terminals.service.instances)
      [
        '--- ${instance.title}',
        for (var y = 0; y < instance.terminal.buffer.lines.length; y++)
          instance.terminal.buffer.lines.get(y)!.translateToString(true),
      ].join('\n').trimRight(),
  ].join('\n');

  /// The focused thread stopped at [line] (any line when null; for
  /// [reason], in [function]), in a stop after [past]'s.
  Future<StackFrame> stopped(
    int? line, {
    String? reason,
    String? function,
    StackFrame? past,
  }) async {
    String state() {
      final thread = service.viewModel.focusedThread;
      final frame = service.viewModel.focusedStackFrame;
      return 'thread ${thread?.name} stopped=${thread?.stopped} '
          '(${thread?.stoppedDetails?.reason}) at ${frame?.name}:'
          '${frame?.range.startLineNumber}';
    }

    return eventually('a stop at line $line', () {
      final thread = service.viewModel.focusedThread;
      final frame = service.viewModel.focusedStackFrame;
      if (thread == null || frame == null || !thread.stopped) return null;
      if (identical(frame, past)) return null;
      if (line != null && frame.range.startLineNumber != line) return null;
      if (reason != null && thread.stoppedDetails?.reason != reason) {
        return null;
      }
      if (function != null && !frame.name.contains(function)) return null;
      return frame;
    }, timeout: const Duration(minutes: 1)).catchError(
      (Object e) => fail('$e\n${state()}\n${console()}\n${terminals()}'),
    );
  }

  /// The names of the focused thread's top [count] frames, once fetched
  /// (the first comes with the stop, the rest after).
  Future<List<String>> callStack(int count) => eventually('$count frames', () {
    final names = [for (final f in thread.getCallStack()) f.name];
    return names.length >= count ? names.take(count).toList() : null;
  });

  /// [frame]'s variables in its first scope matching [scope].
  Future<Map<String, String>> variables(
    StackFrame frame, [
    Pattern scope = 'Locals',
  ]) async => {
    for (final v in await scopeVariables(frame, scope)) v.name: v.value,
  };

  /// The variables of [frame]'s first scope matching [scope].
  Future<List<DebugExpression>> scopeVariables(
    StackFrame frame,
    Pattern scope,
  ) async {
    final scopes = await frame.getScopes();
    final match = scopes.firstWhere(
      (s) => s.name.contains(scope),
      orElse: () => fail('No $scope in ${[for (final s in scopes) s.name]}'),
    );
    return match.getChildren();
  }

  /// Break on Value Change of [variable], as the Variables view's menu
  /// does.
  Future<void> breakOnValueChange(Variable variable) async {
    final info = await session.dataBreakpointInfo(
      variable.name,
      variablesReference: variable.parent.reference,
    );
    final dataId = info?['dataId'];
    expect(dataId, isA<String>(), reason: '$info');
    await service.addDataBreakpoint(
      DataBreakpoint(
        description: '${info!['description'] ?? variable.name}',
        src: DataBreakpointVariable(dataId! as String),
        canPersist: info['canPersist'] == true,
        accessTypes: (info['accessTypes'] as List?)?.cast<String>(),
        accessType: 'write',
      ),
    );
  }

  /// A watch expression's value in [frame], as the Watch view shows it.
  Future<String> watch(StackFrame frame, String expression) async {
    service.addWatchExpression(expression);
    final watch = service.model.getWatchExpressions().last;
    await watch.evaluate(session, frame, 'watch');
    return watch.value;
  }

  /// [expression] in the debug console.
  Future<String> evaluate(StackFrame frame, String expression) async {
    await session.addReplExpression(frame, expression);
    return session
        .getReplElements()
        .whereType<ReplEvaluationResult>()
        .last
        .value;
  }

  /// What the debug console shows of the program's and log points' output.
  String console() => [
    for (final s in service.model.getSessions(includeInactive: true))
      for (final e in s.getReplElements().whereType<ReplOutputElement>())
        e.value,
  ].join();

  /// The adapter's exception filter [filter], enabled.
  Future<void> breakOnExceptions(String filter) async {
    final breakpoint = await eventually('the $filter exception filter', () {
      for (final b in service.model.getExceptionBreakpoints()) {
        if (b.filter == filter) return b;
      }
      return null;
    });
    if (!breakpoint.enabled) {
      await service.enableOrDisableBreakpoints(true, breakpoint);
    }
  }

  /// Waits for every session to end.
  Future<void> ended() => eventually(
    'the session to end',
    () => service.model.getSessions().isEmpty ? true : null,
  );
}

/// The machine's Python, its real path (not a pyenv shim's).
String? pythonExecutable() {
  try {
    final result = Process.runSync('python3', [
      '-c',
      'import sys; print(sys.executable)',
    ]);
    return result.exitCode == 0 ? '${result.stdout}'.trim() : null;
  } on ProcessException {
    return null;
  }
}

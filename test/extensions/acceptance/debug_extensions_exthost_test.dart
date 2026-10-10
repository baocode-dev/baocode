// 九.4: debugging with the debuggers' extensions from Open VSX, in a fresh
// data folder, through the workbench's debug service as its views drive
// it: Python (debugpy). Breakpoints of each kind the adapter supports
// (hit count, conditional, log point, exception), set before and during
// the session; the call stack, variables, watch expressions, the debug
// console and stepping in, over and out.
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

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
int _line(String source, String marker) {
  final lines = source.split('\n');
  final tag = RegExp('BP:${RegExp.escape(marker)}(?![\\w-])');
  final index = lines.indexWhere(tag.hasMatch);
  if (index < 0) throw StateError('no BP:$marker');
  return index + 1;
}

/// The workspace's debug service, as the Run and Debug views use it.
final class _Debug {
  _Debug(this.w) : service = w.extensions.debug!;

  final OpenVsxWorkspace w;
  final DebugService service;

  DebugSession get session => service.model.getSessions().single;

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

  /// The focused thread stopped at [line] (for [reason], in [function]).
  Future<StackFrame> stopped(
    int line, {
    String? reason,
    String? function,
  }) async {
    String state() {
      final thread = service.viewModel.focusedThread;
      final frame = service.viewModel.focusedStackFrame;
      return 'thread ${thread?.name} stopped=${thread?.stopped} '
          '(${thread?.stoppedDetails?.reason}) at ${frame?.name}:'
          '${frame?.range.startLineNumber}';
    }

    return eventually(
      'a stop at line $line',
      () {
        final thread = service.viewModel.focusedThread;
        final frame = service.viewModel.focusedStackFrame;
        if (thread == null || frame == null || !thread.stopped) return null;
        if (frame.range.startLineNumber != line) return null;
        if (reason != null && thread.stoppedDetails?.reason != reason) {
          return null;
        }
        if (function != null && !frame.name.contains(function)) return null;
        return frame;
      },
      timeout: const Duration(minutes: 1),
    ).catchError((Object e) => fail('$e\n${state()}\n${console()}'));
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
  ]) async {
    final scopes = await frame.getScopes();
    final match = scopes.firstWhere(
      (s) => s.name.contains(scope),
      orElse: () => fail('No $scope in ${[for (final s in scopes) s.name]}'),
    );
    return {for (final v in await match.getChildren()) v.name: v.value};
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
    for (final s in service.model.getSessions())
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

const _python = '''
def add(a, b):
    total = a + b  # BP:add
    return total  # BP:add-return


def main():
    values = []
    for i in range(5):
        values.append(add(i, 10))  # BP:loop
    print("sum", sum(values))  # BP:log
    raise ValueError("boom")  # BP:raise


main()
''';

/// The machine's Python, its real path (not a pyenv shim's).
String? _pythonExecutable() {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final python = _pythonExecutable();
  test(
    '九.4: Python (debugpy): breakpoints, stepping, variables, watch, console',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['ms-python.python'],
        files: {'main.py': _python},
        settings: {'python.defaultInterpreterPath': python},
      );
      final d = _Debug(w);
      final source = VsUri.file(w.path('main.py'));
      // Before the start: the second call of add (a hit count).
      await d.service.addBreakpoints(source, [
        BreakpointData(lineNumber: _line(_python, 'add'), hitCondition: '2'),
      ]);
      await d.start({
        'type': 'debugpy',
        'request': 'launch',
        'name': 'Python: main',
        'program': w.path('main.py'),
        'cwd': w.project,
        'console': 'internalConsole',
        'justMyCode': true,
      });
      var frame = await d.stopped(
        _line(_python, 'add'),
        reason: 'breakpoint',
        function: 'add',
      );
      expect(
        d.session.capabilities.flag('supportsHitConditionalBreakpoints'),
        isTrue,
      );
      expect((await d.variables(frame))['a'], '1');
      expect(await d.callStack(3), ['add', 'main', '<module>']);
      expect(d.service.model.getBreakpoints().single.verified, isTrue);

      // During the session: a conditional breakpoint and a log point in
      // place of it, and the uncaught exceptions.
      await d.service.removeBreakpoints();
      await d.service.addBreakpoints(source, [
        BreakpointData(lineNumber: _line(_python, 'loop'), condition: 'i == 3'),
        BreakpointData(
          lineNumber: _line(_python, 'log'),
          logMessage: 'values={values}',
        ),
      ]);
      await d.breakOnExceptions('uncaught');
      await d.thread.continue_();
      frame = await d.stopped(_line(_python, 'loop'), function: 'main');
      expect((await d.variables(frame))['i'], '3');
      expect(await d.watch(frame, 'i * 2'), '6');
      expect(await d.evaluate(frame, 'len(values)'), '3');

      // In, over, out.
      await d.thread.stepIn();
      frame = await d.stopped(_line(_python, 'add'), function: 'add');
      expect((await d.variables(frame))['a'], '3');
      await d.thread.next();
      frame = await d.stopped(_line(_python, 'add-return'), function: 'add');
      expect((await d.variables(frame))['total'], '13');
      await d.thread.stepOut();
      frame = await d.stopped(_line(_python, 'loop'), function: 'main');

      // The log point's message and the program's output in the console,
      // then the uncaught exception.
      await d.service.removeBreakpoints([
        for (final b in d.service.model.getBreakpoints())
          if (b.condition != null) b.getId(),
      ]);
      await d.thread.continue_();
      frame = await d.stopped(_line(_python, 'raise'), reason: 'exception');
      expect(d.console(), contains('values=[10, 11, 12, 13, 14]'));
      expect(d.console(), contains('sum 60'));

      await d.service.stopSession(null);
      await d.ended();
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: openVsxSkip() == false && python == null
        ? 'No python3'
        : openVsxSkip(),
  );

  test(
    '九.4: Go (Delve): function breakpoint, stepping, variables, watch, '
    'console, panic',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['golang.go'],
        files: {
          'go.mod': 'module example.com/demo\n\ngo 1.22\n',
          'main.go': _go,
        },
      );
      final d = _Debug(w);
      final source = VsUri.file(w.path('main.go'));
      // Before the start: a function breakpoint.
      await d.service.addFunctionBreakpoint(
        FunctionBreakpoint(name: 'main.scale'),
      );
      await d.start({
        'type': 'go',
        'request': 'launch',
        'name': 'Go: main',
        'mode': 'debug',
        'program': w.project,
      });
      // Delve stops on the function's declaration.
      var frame = await d.stopped(
        _line(_go, 'scale-entry'),
        function: 'scale',
      );
      expect(d.thread.stoppedDetails?.reason, 'function breakpoint');
      expect(
        d.session.capabilities.flag('supportsFunctionBreakpoints'),
        isTrue,
      );
      expect(await d.callStack(2), [
        contains('main.scale'),
        contains('main.main'),
      ]);
      expect((await d.variables(frame))['k'], '2');

      // During the session: a conditional breakpoint and a log point in
      // place of it.
      await d.service.removeFunctionBreakpoints();
      await d.service.addBreakpoints(source, [
        BreakpointData(lineNumber: _line(_go, 'loop'), condition: 'i == 3'),
        BreakpointData(
          lineNumber: _line(_go, 'print'),
          logMessage: 'total={total}',
        ),
      ]);
      await d.thread.continue_();
      frame = await d.stopped(_line(_go, 'loop'), function: 'main');
      expect((await d.variables(frame))['i'], '3');
      expect(await d.watch(frame, 'i * 2'), '6');
      expect(await d.evaluate(frame, 'total'), '6');

      // In, over, out.
      await d.thread.stepIn();
      frame = await d.stopped(_line(_go, 'scale-entry'), function: 'scale');
      await d.thread.next();
      frame = await d.stopped(_line(_go, 'scale'), function: 'scale');
      await d.thread.next();
      frame = await d.stopped(_line(_go, 'scale-return'), function: 'scale');
      expect((await d.variables(frame))['r'], contains('x: 6'));
      await d.thread.stepOut();
      frame = await d.stopped(_line(_go, 'loop'), function: 'main');

      // The log point's message, the program's output, then its panic.
      await d.service.removeBreakpoints([
        for (final b in d.service.model.getBreakpoints())
          if (b.condition != null) b.getId(),
      ]);
      await d.thread.continue_();
      frame = await d.stopped(_line(_go, 'panic'), function: 'main');
      expect(d.thread.stoppedDetails?.reason, anyOf('panic', 'exception'));
      expect(d.console(), contains('total=20'));

      await d.service.stopSession(null);
      await d.ended();
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: openVsxSkip() == false && !_onPath('dlv') ? 'No dlv' : openVsxSkip(),
  );
}

const _go = '''
package main

import "fmt"

type point struct{ x, y int }

func scale(p point, k int) point { // BP:scale-entry
	r := point{p.x * k, p.y * k} // BP:scale
	return r // BP:scale-return
}

func main() {
	total := 0
	for i := 0; i < 5; i++ {
		total += scale(point{i, i + 1}, 2).x // BP:loop
	}
	fmt.Println("total", total) // BP:print
	var m map[string]int
	m["x"] = 1 // BP:panic
}
''';

/// Whether [tool] is on PATH or in GOPATH's bin.
bool _onPath(String tool) {
  final home = Platform.environment['HOME'] ?? '';
  final dirs = [...?Platform.environment['PATH']?.split(':'), '$home/go/bin'];
  return dirs.any((dir) => File('$dir/$tool').existsSync());
}

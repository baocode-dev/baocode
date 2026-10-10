// 九.4: debugging with the debuggers' extensions from Open VSX, in a fresh
// data folder, through the workbench's debug service as its views drive
// it: Python (debugpy), Go (Delve), C++ and Rust (CodeLLDB). Breakpoints
// of each kind the adapter supports (hit count, conditional, function,
// data, log point, exception), set before and during the session; the
// call stack, variables, watch expressions, the debug console, stepping
// in, over and out, preLaunchTask and the debuggee's terminal.
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
      var frame = await d.stopped(_line(_go, 'scale-entry'), function: 'scale');
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

  test(
    '九.4: C++ (CodeLLDB): preLaunchTask, hit count, data, function and log '
    'point breakpoints, stepping, variables, watch, console',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['vadimcn.vscode-lldb'],
        files: {'main.cpp': _cpp, '.vscode/tasks.json': _cppTasks},
      );
      final d = _Debug(w);
      final source = VsUri.file(w.path('main.cpp'));
      // Before the start: the third pass of the loop (a hit count).
      await d.service.addBreakpoints(source, [
        BreakpointData(lineNumber: _line(_cpp, 'loop'), hitCondition: '3'),
      ]);
      // CodeLLDB fetches its platform package (its debugger) on first use,
      // then installs it with Install Extension VSIX.
      await d.start({
        'type': 'lldb',
        'request': 'launch',
        'name': 'C++: main',
        'program': r'${workspaceFolder}/main',
        'cwd': r'${workspaceFolder}',
        'preLaunchTask': 'build',
      });
      expect(
        File(w.path('main')).existsSync(),
        isTrue,
        reason: 'built by the preLaunchTask',
      );
      var frame = await d.stopped(_line(_cpp, 'loop'), function: 'main');
      expect((await d.variables(frame, 'Local'))['i'], '2');

      // Break on Value Change of c.count: the next bump writes it.
      final c = (await d.scopeVariables(
        frame,
        'Local',
      )).firstWhere((v) => v.name == 'c');
      final count = (await c.getChildren()).firstWhere(
        (v) => v.name == 'count',
      );
      await d.breakOnValueChange(count as Variable);
      await d.service.removeBreakpoints();
      await d.thread.continue_();
      frame = await eventually('the data breakpoint', () {
        final thread = d.service.viewModel.focusedThread;
        final frame = d.service.viewModel.focusedStackFrame;
        return thread != null &&
                thread.stopped &&
                frame != null &&
                frame.name.contains('bump')
            ? frame
            : null;
      });
      expect(d.thread.stoppedDetails?.reason, isNot('breakpoint'));
      expect(await d.callStack(2), [contains('bump'), contains('main')]);
      await d.service.removeDataBreakpoints();

      // A function breakpoint, a log point; stepping out and in.
      await d.service.addFunctionBreakpoint(FunctionBreakpoint(name: 'bump'));
      await d.service.addBreakpoints(source, [
        BreakpointData(
          lineNumber: _line(_cpp, 'print'),
          logMessage: 'count={c.count}',
        ),
      ]);
      // Back in the loop (past the call: on its line or the loop's end).
      await d.thread.stepOut();
      frame = await d.stopped(
        null,
        reason: 'step',
        function: 'main',
        past: frame,
      );
      expect(
        frame.range.startLineNumber,
        greaterThanOrEqualTo(_line(_cpp, 'loop')),
      );
      expect(await d.watch(frame, 'c.count * 2'), '6');
      // The console runs LLDB commands; `?` evaluates.
      expect(await d.evaluate(frame, '?i * 10'), '20');
      await d.thread.continue_();
      // LLDB stops past the function's prologue.
      frame = await d.stopped(_line(_cpp, 'bump'), function: 'bump');
      expect(d.thread.stoppedDetails?.reason, contains('breakpoint'));
      await d.service.removeFunctionBreakpoints();
      await d.thread.next();
      frame = await d.stopped(_line(_cpp, 'bump-return'), function: 'bump');
      expect((await d.variables(frame, 'Local'))['by'], '3');

      // The log point's message and the program's output, then its end.
      await d.thread.continue_();
      await eventually(
        'the log point and the output',
        () =>
            d.console().contains('count=10') &&
                d.terminals().contains('count 10')
            ? true
            : null,
      ).catchError((Object e) => fail('$e\n${d.console()}\n${d.terminals()}'));
      await d.ended();
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: openVsxSkip() == false && !_onPath('clang++')
        ? 'No clang++'
        : openVsxSkip(),
  );
  test(
    '九.4: Rust (CodeLLDB): cargo build, conditional breakpoint, panic '
    'filter, stepping, variables, watch, console',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['vadimcn.vscode-lldb'],
        files: {'Cargo.toml': _cargoToml, 'src/main.rs': _rust},
      );
      final d = _Debug(w);
      final source = VsUri.file(w.path('src/main.rs'));
      await d.service.addBreakpoints(source, [
        BreakpointData(lineNumber: _line(_rust, 'loop'), condition: 'i == 2'),
      ]);
      // CodeLLDB builds with cargo and runs the binary it reports.
      await d.start({
        'type': 'lldb',
        'request': 'launch',
        'name': 'Rust: demo',
        'cargo': {
          'args': ['build', '--bin=demo', '--package=demo'],
        },
        'cwd': r'${workspaceFolder}',
      });
      var frame = await d.stopped(_line(_rust, 'loop'), function: 'main');
      var locals = await d.variables(frame, 'Local');
      expect(locals['i'], '2');
      expect(locals['total'], '6');
      expect(await d.watch(frame, 'total * 2'), '12');
      expect(await d.evaluate(frame, '?total + 1'), '7');
      await d.breakOnExceptions('rust_panic');

      await d.thread.stepIn();
      frame = await d.stopped(_line(_rust, 'scale'), function: 'scale');
      locals = await d.variables(frame, 'Local');
      expect((locals['v'], locals['k']), ('3', '2'));
      expect(await d.callStack(2), [contains('scale'), contains('main')]);
      await d.thread.next();
      frame = await d.stopped(
        _line(_rust, 'scale-return'),
        function: 'scale',
        past: frame,
      );
      expect((await d.variables(frame, 'Local'))['r'], '6');
      await d.thread.stepOut();
      frame = await d.stopped(
        null,
        reason: 'step',
        function: 'main',
        past: frame,
      );

      // The panic: CodeLLDB's filter is a breakpoint on `rust_panic`,
      // under main.
      await d.service.removeBreakpoints();
      await d.thread.continue_();
      await eventually('the panic', () {
        final thread = d.service.viewModel.focusedThread;
        final frame = d.service.viewModel.focusedStackFrame;
        return thread != null &&
                thread.stopped &&
                frame != null &&
                frame.name.contains('rust_panic')
            ? true
            : null;
      }).catchError(
        (Object e) => fail(
          '$e\n${d.service.viewModel.focusedThread?.stoppedDetails?.reason} '
          '${d.service.viewModel.focusedStackFrame?.name}\n${d.console()}\n'
          '${d.terminals()}',
        ),
      );
      await d.thread.fetchCallStack(40);
      expect([
        for (final f in d.thread.getCallStack()) f.name,
      ], contains(contains('demo::main')));
      expect(d.terminals(), contains('i 3 total 20'));

      await d.service.stopSession(null);
      await d.ended();
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: openVsxSkip() == false && !_onPath('cargo')
        ? 'No cargo'
        : openVsxSkip(),
  );
}

const _cargoToml = '''
[package]
name = "demo"
version = "0.1.0"
edition = "2021"

[dependencies]
''';

const _rust = '''
fn scale(v: i32, k: i32) -> i32 {
    let r = v * k; // BP:scale
    eprintln!("scaled {}", r); // BP:scale-return
    r
}

fn main() {
    let values = vec![1, 2, 3, 4];
    let mut total = 0;
    for (i, v) in values.iter().enumerate() {
        total += scale(*v, 2); // BP:loop
        println!("i {} total {}", i, total);
    }
    let empty: Vec<i32> = Vec::new();
    println!("first {}", empty[values.len()]); // BP:panic
}
''';

const _cpp = '''
#include <cstdio>

struct Counter {
  int count;
};

int bump(Counter &c, int by) {
  c.count += by; // BP:bump
  return c.count; // BP:bump-return
}

int main() {
  Counter c{0};
  for (int i = 0; i < 5; i++) {
    bump(c, i); // BP:loop
  }
  std::printf("count %d\\n", c.count); // BP:print
  return 0;
}
''';

const _cppTasks = '''
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "type": "shell",
      "command": "clang++",
      "args": ["-g", "-O0", "-std=c++17", "main.cpp", "-o", "main"],
      "problemMatcher": []
    }
  ]
}
''';

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

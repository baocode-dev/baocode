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
import 'package:flutter_test/flutter_test.dart';

import 'debug_driver.dart';
import 'open_vsx_workspace.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final python = pythonExecutable();
  test(
    '九.4: Python (debugpy): breakpoints, stepping, variables, watch, console',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['ms-python.python'],
        files: {'main.py': _python},
        settings: {'python.defaultInterpreterPath': python},
      );
      final d = DebugDriver(w);
      final source = VsUri.file(w.path('main.py'));
      // Before the start: the second call of add (a hit count).
      await d.service.addBreakpoints(source, [
        BreakpointData(lineNumber: bpLine(_python, 'add'), hitCondition: '2'),
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
        bpLine(_python, 'add'),
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
        BreakpointData(lineNumber: bpLine(_python, 'loop'), condition: 'i == 3'),
        BreakpointData(
          lineNumber: bpLine(_python, 'log'),
          logMessage: 'values={values}',
        ),
      ]);
      await d.breakOnExceptions('uncaught');
      await d.thread.continue_();
      frame = await d.stopped(bpLine(_python, 'loop'), function: 'main');
      expect((await d.variables(frame))['i'], '3');
      expect(await d.watch(frame, 'i * 2'), '6');
      expect(await d.evaluate(frame, 'len(values)'), '3');

      // In, over, out.
      await d.thread.stepIn();
      frame = await d.stopped(bpLine(_python, 'add'), function: 'add');
      expect((await d.variables(frame))['a'], '3');
      await d.thread.next();
      frame = await d.stopped(bpLine(_python, 'add-return'), function: 'add');
      expect((await d.variables(frame))['total'], '13');
      await d.thread.stepOut();
      frame = await d.stopped(bpLine(_python, 'loop'), function: 'main');

      // The log point's message and the program's output in the console,
      // then the uncaught exception.
      await d.service.removeBreakpoints([
        for (final b in d.service.model.getBreakpoints())
          if (b.condition != null) b.getId(),
      ]);
      await d.thread.continue_();
      frame = await d.stopped(bpLine(_python, 'raise'), reason: 'exception');
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
      final d = DebugDriver(w);
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
      var frame = await d.stopped(bpLine(_go, 'scale-entry'), function: 'scale');
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
        BreakpointData(lineNumber: bpLine(_go, 'loop'), condition: 'i == 3'),
        BreakpointData(
          lineNumber: bpLine(_go, 'print'),
          logMessage: 'total={total}',
        ),
      ]);
      await d.thread.continue_();
      frame = await d.stopped(bpLine(_go, 'loop'), function: 'main');
      expect((await d.variables(frame))['i'], '3');
      expect(await d.watch(frame, 'i * 2'), '6');
      expect(await d.evaluate(frame, 'total'), '6');

      // In, over, out.
      await d.thread.stepIn();
      frame = await d.stopped(bpLine(_go, 'scale-entry'), function: 'scale');
      await d.thread.next();
      frame = await d.stopped(bpLine(_go, 'scale'), function: 'scale');
      await d.thread.next();
      frame = await d.stopped(bpLine(_go, 'scale-return'), function: 'scale');
      expect((await d.variables(frame))['r'], contains('x: 6'));
      await d.thread.stepOut();
      frame = await d.stopped(bpLine(_go, 'loop'), function: 'main');

      // The log point's message, the program's output, then its panic.
      await d.service.removeBreakpoints([
        for (final b in d.service.model.getBreakpoints())
          if (b.condition != null) b.getId(),
      ]);
      await d.thread.continue_();
      frame = await d.stopped(bpLine(_go, 'panic'), function: 'main');
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
      final d = DebugDriver(w);
      final source = VsUri.file(w.path('main.cpp'));
      // Before the start: the third pass of the loop (a hit count).
      await d.service.addBreakpoints(source, [
        BreakpointData(lineNumber: bpLine(_cpp, 'loop'), hitCondition: '3'),
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
      var frame = await d.stopped(bpLine(_cpp, 'loop'), function: 'main');
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
          lineNumber: bpLine(_cpp, 'print'),
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
        greaterThanOrEqualTo(bpLine(_cpp, 'loop')),
      );
      expect(await d.watch(frame, 'c.count * 2'), '6');
      // The console runs LLDB commands; `?` evaluates.
      expect(await d.evaluate(frame, '?i * 10'), '20');
      await d.thread.continue_();
      // LLDB stops past the function's prologue.
      frame = await d.stopped(bpLine(_cpp, 'bump'), function: 'bump');
      expect(d.thread.stoppedDetails?.reason, contains('breakpoint'));
      await d.service.removeFunctionBreakpoints();
      await d.thread.next();
      frame = await d.stopped(bpLine(_cpp, 'bump-return'), function: 'bump');
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
      final d = DebugDriver(w);
      final source = VsUri.file(w.path('src/main.rs'));
      await d.service.addBreakpoints(source, [
        BreakpointData(lineNumber: bpLine(_rust, 'loop'), condition: 'i == 2'),
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
      var frame = await d.stopped(bpLine(_rust, 'loop'), function: 'main');
      var locals = await d.variables(frame, 'Local');
      expect(locals['i'], '2');
      expect(locals['total'], '6');
      expect(await d.watch(frame, 'total * 2'), '12');
      expect(await d.evaluate(frame, '?total + 1'), '7');
      await d.breakOnExceptions('rust_panic');

      await d.thread.stepIn();
      frame = await d.stopped(bpLine(_rust, 'scale'), function: 'scale');
      locals = await d.variables(frame, 'Local');
      expect((locals['v'], locals['k']), ('3', '2'));
      expect(await d.callStack(2), [contains('scale'), contains('main')]);
      await d.thread.next();
      frame = await d.stopped(
        bpLine(_rust, 'scale-return'),
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

  test(
    '九.4: Node (js-debug): preLaunchTask, hit count, conditional and log '
    'point breakpoints, exceptions, stepping, variables, watch, console',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const [],
        files: {'main.js': _node, '.vscode/tasks.json': _nodeTasks},
      );
      final d = DebugDriver(w);
      final source = VsUri.file(w.path('main.js'));
      await d.service.addBreakpoints(source, [
        BreakpointData(lineNumber: bpLine(_node, 'add'), hitCondition: '2'),
      ]);
      await d.start({
        'type': 'node',
        'request': 'launch',
        'name': 'Node: main',
        'program': r'${workspaceFolder}/main.js',
        'cwd': r'${workspaceFolder}',
        'preLaunchTask': 'prepare',
      });
      expect(
        File(w.path('ready.txt')).existsSync(),
        isTrue,
        reason: 'written by the preLaunchTask',
      );
      var frame = await d.stopped(bpLine(_node, 'add'), function: 'add');
      expect((await d.variables(frame, 'Local'))['a'], '1');
      expect(await d.callStack(2), [endsWith('add'), endsWith('main')]);

      // During the session: a conditional breakpoint and a log point in
      // place of it, and the uncaught exceptions.
      await d.service.removeBreakpoints();
      await d.service.addBreakpoints(source, [
        BreakpointData(lineNumber: bpLine(_node, 'loop'), condition: 'i === 3'),
        BreakpointData(
          lineNumber: bpLine(_node, 'log'),
          logMessage: "values={values.join(',')}",
        ),
      ]);
      await d.breakOnExceptions('uncaught');
      await d.thread.continue_();
      frame = await d.stopped(
        bpLine(_node, 'loop'),
        function: 'main',
        past: frame,
      );
      expect((await d.variables(frame, 'Block'))['i'], '3');
      expect(await d.watch(frame, 'i * 2'), '6');
      expect(await d.evaluate(frame, 'values.length'), '3');

      // In, over, out.
      await d.thread.stepIn();
      frame = await d.stopped(bpLine(_node, 'add'), function: 'add');
      expect((await d.variables(frame, 'Local'))['a'], '3');
      await d.thread.next();
      frame = await d.stopped(bpLine(_node, 'add-return'), function: 'add');
      expect((await d.variables(frame, 'Local'))['total'], '13');
      await d.thread.stepOut();
      frame = await d.stopped(null, function: 'main', past: frame);

      // The log point's message and the program's output, then the
      // uncaught exception.
      await d.service.removeBreakpoints([
        for (final b in d.service.model.getBreakpoints())
          if (b.condition != null) b.getId(),
      ]);
      await d.thread.continue_();
      frame = await d.stopped(bpLine(_node, 'raise'), reason: 'exception');
      expect(d.console(), contains('values=10,11,12,13,14'));
      expect(d.console(), contains('sum 60'));

      await d.service.stopSession(null);
      await d.ended();
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: openVsxSkip() == false && !_onPath('node')
        ? 'No node'
        : openVsxSkip(),
  );
}

const _node = '''
function add(a, b) {
  const total = a + b; // BP:add
  return total; // BP:add-return
}

function main() {
  const values = [];
  for (let i = 0; i < 5; i++) {
    values.push(add(i, 10)); // BP:loop
  }
  console.log('sum', values.reduce((x, y) => x + y, 0)); // BP:log
  throw new Error('boom'); // BP:raise
}

main();
''';

const _nodeTasks = '''
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "prepare",
      "type": "shell",
      "command": "echo ready > ready.txt",
      "problemMatcher": []
    }
  ]
}
''';

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

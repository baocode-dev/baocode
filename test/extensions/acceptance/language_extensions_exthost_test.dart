// 九.2: real Open VSX language extensions in a real extension host, each in
// a fresh data folder, installed through the workspace's management:
// Python with basedpyright, rust-analyzer, Go and clangd. Each gives the
// open document diagnostics, completions, a hover and a definition from
// its own language server (the machine's Python, cargo, go/gopls and
// clangd, as a user would have them).
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'open_vsx_workspace.dart';

/// The first of [names] on the PATH, resolved; null when none is.
String? _tool(String name) {
  final which = Process.runSync('which', [name]);
  if (which.exitCode != 0) return null;
  return '${which.stdout}'.trim();
}

/// The Python interpreter itself (pyenv's shim resolved).
String? _python() {
  final pyenv = Process.runSync('sh', ['-c', 'pyenv which python3']);
  if (pyenv.exitCode == 0) return '${pyenv.stdout}'.trim();
  return _tool('python3');
}

Object _needs(List<String> tools) {
  final skip = openVsxSkip();
  if (skip != false) return skip;
  final missing = [
    for (final t in tools)
      if (_tool(t) == null) t,
  ];
  return missing.isEmpty ? false : 'Not on the PATH: ${missing.join(', ')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(minutes: 10));

  test(
    '九.2: Python with basedpyright',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['ms-python.python', 'detachhead.basedpyright'],
        settings: {'python.defaultInterpreterPath': _python()},
        files: {
          'app.py': [
            'import os',
            '',
            'def greet(name: str) -> str:',
            '    return "hi " + name',
            '',
            'greet(1)',
            'print(os.getcwd())',
            '',
          ].join('\n'),
        },
      );
      final file = await w.open('app.py');
      await w.activated('detachhead.basedpyright');
      await _features(
        w,
        file,
        diagnostic: (d) =>
            d.source == 'basedpyright' && d.message.contains('"Literal[1]"'),
        completionAt: const LspPosition(6, 12),
        completion: 'getcwd',
        hoverAt: const LspPosition(5, 1),
        hover: 'def greet(name: str) -> str',
        definitionAt: const LspPosition(5, 1),
        definitionLine: 2,
      );
      // The Python extension runs too (its interpreter, its commands).
      await w.activated('ms-python.python');
    },
    timeout: timeout,
    skip: _needs(['python3']),
  );

  test(
    '九.2: rust-analyzer',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['rust-lang.rust-analyzer'],
        files: {
          'Cargo.toml': [
            '[package]',
            'name = "accept"',
            'version = "0.1.0"',
            'edition = "2021"',
            '',
          ].join('\n'),
          'src/main.rs': [
            'fn add(a: i32, b: i32) -> i32 {',
            '    a + b',
            '}',
            '',
            'fn main() {',
            '    let s: String = add(1, 2);',
            '    let v = vec![s];',
            '    v.len();',
            '}',
            '',
          ].join('\n'),
        },
      );
      final file = await w.open('src/main.rs');
      await w.activated('rust-lang.rust-analyzer');
      await _features(
        w,
        file,
        diagnostic: (d) => d.message.contains('expected `String`, found `i32`'),
        completionAt: const LspPosition(7, 6),
        completion: 'len',
        hoverAt: const LspPosition(5, 21),
        hover: 'fn add(a: i32, b: i32) -> i32',
        definitionAt: const LspPosition(5, 21),
        definitionLine: 0,
      );
    },
    timeout: timeout,
    skip: _needs(['cargo']),
  );

  test(
    '九.2: Go',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['golang.go'],
        files: {
          'go.mod': 'module example.com/accept\n\ngo 1.22\n',
          'main.go': [
            'package main',
            '',
            'import "fmt"',
            '',
            'func add(a, b int) int { return a + b }',
            '',
            'func main() {',
            '\tvar s string = add(1, 2)',
            '\tfmt.Println(s)',
            '}',
            '',
          ].join('\n'),
        },
      );
      final file = await w.open('main.go');
      await w.activated('golang.go');
      await _features(
        w,
        file,
        diagnostic: (d) => d.message.contains('as string value'),
        completionAt: const LspPosition(8, 6),
        completion: 'Println',
        hoverAt: const LspPosition(7, 16),
        hover: 'func add(a int, b int) int',
        definitionAt: const LspPosition(7, 16),
        definitionLine: 4,
      );
    },
    timeout: timeout,
    skip: _needs(['go', 'gopls']),
  );

  test(
    '九.2: clangd',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['llvm-vs-code-extensions.vscode-clangd'],
        files: {
          'area.cpp': [
            'struct Point { int x; int y; };',
            '',
            'int area(Point p) { return p.x * p.y; }',
            '',
            'int main() {',
            '  Point p{1, 2};',
            '  int r = area(p);',
            '  return p.x + undefined_name;',
            '}',
            '',
          ].join('\n'),
        },
      );
      final file = await w.open('area.cpp');
      await w.activated('llvm-vs-code-extensions.vscode-clangd');
      await _features(
        w,
        file,
        diagnostic: (d) => d.message.contains("'undefined_name'"),
        completionAt: const LspPosition(7, 11),
        completion: 'y',
        hoverAt: const LspPosition(6, 11),
        hover: 'int area(Point p)',
        definitionAt: const LspPosition(6, 11),
        definitionLine: 2,
      );
    },
    timeout: timeout,
    skip: _needs(['clangd']),
  );
}

/// The language server's diagnostic, completion, hover and definition for
/// [file], waited for while it starts and indexes.
Future<void> _features(
  OpenVsxWorkspace w,
  String file, {
  required bool Function(LspDiagnostic) diagnostic,
  required LspPosition completionAt,
  required String completion,
  required LspPosition hoverAt,
  required String hover,
  required LspPosition definitionAt,
  required int definitionLine,
}) async {
  final languages = w.extensions.languageRoot.language;
  const wait = Duration(minutes: 4);
  await eventually('the diagnostic', () {
    final found = languages.diagnosticsFor(file);
    return found.any(diagnostic) ? true : null;
  }, timeout: wait).catchError((Object e) {
    fail(
      '$e\nDiagnostics: ${[for (final d in languages.diagnosticsFor(file)) '${d.source}: ${d.message}']}\n${w.report()}',
    );
  });
  // clangd puts a space (or a •, for an include it adds) before labels.
  bool named(LspCompletionItem item) => item.label.trim() == completion;
  var labels = <String>[];
  await eventually('the completion', () async {
    final list = await languages.completion(file, completionAt);
    labels = [for (final i in list.items) i.label];
    return list.items.any(named) ? true : null;
  }, timeout: wait).catchError((Object e) {
    fail('$e\nCompletions: ${labels.take(30)}');
  });
  final hovered = await eventually('the hover', () async {
    final found = await languages.hover(file, hoverAt);
    return found != null && found.markdown.contains(hover) ? found : null;
  }, timeout: wait);
  expect(hovered.markdown, contains(hover));
  final definition = await eventually('the definition', () async {
    final found = await languages.definition(file, definitionAt);
    return found.isEmpty ? null : found;
  }, timeout: wait);
  expect(definition.first.range.start.line, definitionLine);
  expect(definition.first.uri, Uri.file(file).toString());
  expect(w.unsupported, isEmpty, reason: w.report());
}

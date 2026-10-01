// Measures the editor's TextMate highlighting against its Monarch
// highlighting on a large TypeScript file, in the build mode it runs in, and
// prints the results as JSON:
// - the worker (a background isolate): time to the first colored lines
//   (the top, and a viewport in the middle) and to the whole file, cold and
//   warm; the delay from a one-line edit to its new tokens; what an edit
//   costs the UI isolate. Monarch: the same, all on the UI isolate.
// - the editor: frame build and raster times while the file opens, scrolls
//   and is typed into, with each highlighter.
//
// Not part of the test suite. For AOT numbers run, from the repository
// root:
//   flutter run --profile -d macos -t tool/textmate_perf_app.dart \
//     --dart-define=TEXTMATE_PERF_SAMPLE=$PWD/packages/bao_editor/test/fixtures/textmate/samples/bench/textModel.ts
// It opens a window, and quits when done.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/monaco_syntax.dart';
import 'package:bao_editor/textmate/textmate_syntax.dart';
import 'package:bao_editor/textmate/textmate_worker.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/theme/workbench_theme.dart';

/// The app does not run in the repository: pass the absolute path with
/// `--dart-define=TEXTMATE_PERF_SAMPLE=...`.
const _sample = String.fromEnvironment(
  'TEXTMATE_PERF_SAMPLE',
  defaultValue:
      'packages/bao_editor/test/fixtures/textmate/samples/bench/textModel.ts',
);
const _copies = 10;

class _MemoryFiles implements IdeFileService {
  _MemoryFiles(this.contents);

  final Map<String, String> contents;

  @override
  Future<List<IdeFile>> list(String directory) async => [];

  @override
  Future<String> read(String path, {bool force = false}) async =>
      contents[path]!;

  @override
  Future<void> write(String path, String text, {String? expectedText}) async =>
      contents[path] = text;

  @override
  Future<void> create(String path, {bool directory = false}) async {}

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<void> copy(String from, String to) async {}

  @override
  Future<void> delete(String path) async {}
}

double _ms(Duration d) => d.inMicroseconds / 1000;

/// Progress, on stderr (flutter run echoes it).
void _log(String message) => stderr.writeln('TEXTMATE_PERF_LOG $message');

Map<String, double> _stats(List<double> values) {
  if (values.isEmpty) return const {};
  final sorted = [...values]..sort();
  double at(double q) => sorted[((sorted.length - 1) * q).round()];
  return {
    'n': sorted.length.toDouble(),
    'p50': at(0.5),
    'p90': at(0.9),
    'p99': at(0.99),
    'max': sorted.last,
  };
}

/// The offset of the first code token (not comment, string or blank) on
/// [line] or after it: `"x"` inserted there certainly changes the line's
/// tokens, so the worker's answer is seen.
int _codeOffset(
  TextMateDocument document,
  DocumentSnapshot snapshot,
  int line,
) {
  for (; ; line++) {
    final lineStart = snapshot.lineStarts[line - 1];
    final tokens = document.lineTokens(line)!;
    var start = 0;
    for (var t = 0; t < tokens.length; t += 2) {
      final type = (tokens[t + 1] >> 8) & 3;
      final text = snapshot.text.substring(
        lineStart + start,
        lineStart + tokens[t],
      );
      if (type == 0 && text.trim().isNotEmpty) return lineStart + start;
      start = tokens[t];
    }
  }
}

/// When [document] last changed, once it has not for a second; [since] when
/// it has not changed since then.
Future<Duration> _settled(
  TextMateDocument document,
  Stopwatch watch,
  Duration since,
) async {
  var last = since;
  void changed() => last = watch.elapsed;
  document.addListener(changed);
  Duration seen;
  do {
    seen = last;
    await Future<void>.delayed(const Duration(seconds: 1));
  } while (last != seen);
  document.removeListener(changed);
  return last;
}

/// Waits until [done] holds after one of [document]'s notifications; fails
/// after a minute.
Future<Duration> _until(
  TextMateDocument document,
  Stopwatch watch,
  bool Function() done,
  String what,
) {
  final result = Completer<Duration>();
  void check() {
    if (!result.isCompleted && done()) result.complete(watch.elapsed);
  }

  document.addListener(check);
  check();
  return result.future
      .timeout(
        const Duration(minutes: 1),
        onTimeout: () => throw TimeoutException('waiting for $what'),
      )
      .whenComplete(() => document.removeListener(check));
}

Future<Map<String, Object>> _service(String text) async {
  final results = <String, Object>{};
  final syntax = TextMateSyntax(
    themes: WorkbenchThemeService.instance,
    launch: spawnTextMateWorker,
  );
  var watch = Stopwatch()..start();
  await syntax.theme;
  results['workerStartMs'] = _ms(watch.elapsed);
  _log('worker started: ${results['workerStartMs']}ms');
  final snapshot = DocumentSnapshot(text);
  final lineCount = snapshot.lineCount;
  final middle = lineCount ~/ 2;
  // One-line edits, the same for both highlighters: offsets in [snapshot].
  final edits = <int>[];

  for (final run in ['cold', 'warm']) {
    watch = Stopwatch()..start();
    final document = syntax.open('typescript', snapshot)!;
    final openMs = _ms(watch.elapsed);
    document.setViewport(middle, middle + 60);
    final top = _until(document, watch, () {
      for (var line = 1; line <= 60; line++) {
        if (document.lineTokens(line) == null) return false;
      }
      return true;
    }, 'the top lines');
    final viewport = _until(
      document,
      watch,
      () => document.lineTokens(middle + 30) != null,
      'the viewport',
    );
    final all = _until(
      document,
      watch,
      () => document.lineTokens(lineCount) != null,
      'the last line',
    );
    results[run] = {
      'openOnUiIsolateMs': openMs,
      'top60LinesMs': _ms(await top),
      'middleViewportMs': _ms(await viewport),
      'wholeFileMs': _ms(await all),
    };
    _log('$run: ${results[run]}');
    if (run == 'cold') {
      document.dispose();
      continue;
    }

    // One-line edits in a tokenized file: from the edit to its tokens.
    for (var i = 0; i < 40; i++) {
      edits.add(_codeOffset(document, snapshot, 2000 + i * 500));
    }
    var current = snapshot;
    final latencies = <double>[];
    final uiCosts = <double>[];
    final diffCosts = <double>[];
    var previousSnapshot = current;
    for (final (i, original) in edits.indexed) {
      final offset = original + 3 * i;
      final line = current.positionAtOffset(offset).lineNumber;
      current = DocumentSnapshot(
        current.text.replaceRange(offset, offset, '"x"'),
      );
      final edit = Stopwatch()..start();
      document.update(current);
      uiCosts.add(_ms(edit.elapsed));
      // What finding the edit costs: the text diff Monarch makes too.
      final diff = Stopwatch()..start();
      MonacoSyntaxService.unchangedLines(previousSnapshot, current);
      diffCosts.add(_ms(diff.elapsed));
      previousSnapshot = current;
      final edited = document.lineTokens(line);
      latencies.add(
        _ms(
          await _until(
            document,
            edit,
            () => !identical(document.lineTokens(line), edited),
            'edit $i',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    results['editToTokensMs'] = _stats(latencies);
    results['editUiIsolateMs'] = _stats(uiCosts);
    results['editTextDiffMs'] = _stats(diffCosts);

    // Opening a block comment: the lines after it are comment up to the
    // next `*/`, then the states converge again.
    final before = [
      for (var line = 1; line <= lineCount; line++) document.lineTokens(line),
    ];
    final offset = current.lineStarts[99];
    current = DocumentSnapshot(current.text.replaceRange(offset, offset, '/*'));
    final comment = Stopwatch()..start();
    document.update(current);
    final line101 = await _until(document, comment, () {
      final tokens = document.lineTokens(101);
      return tokens != null && tokens.length == 2;
    }, 'the comment');
    final settled = await _settled(document, comment, line101);
    var lastChanged = 0;
    for (var line = 1; line <= lineCount; line++) {
      if (!listEquals(before[line - 1], document.lineTokens(line))) {
        lastChanged = line;
      }
    }
    results['blockComment'] = {
      'line101Ms': _ms(line101),
      'settledMs': _ms(settled),
      'lastRetokenizedLine': lastChanged,
    };
    document.dispose();
  }
  syntax.dispose();

  // Monarch, on the UI isolate.
  final monarch = MonacoSyntaxService();
  await monarch.tokenizerFor('typescript');
  watch = Stopwatch()..start();
  final tokenized = await monarch.tokenizeIncremental(snapshot, 'typescript');
  final monarchWhole = _ms(watch.elapsed);
  final monarchEdits = <double>[];
  var previous = tokenized;
  var current = snapshot;
  for (final (i, original) in edits.indexed) {
    final offset = original + 3 * i;
    current = DocumentSnapshot(
      current.text.replaceRange(offset, offset, '"x"'),
    );
    final edit = Stopwatch()..start();
    previous = await monarch.tokenizeIncremental(
      current,
      'typescript',
      previous: previous,
    );
    monarchEdits.add(_ms(edit.elapsed));
    // Idle between edits as in the TextMate loop: the same CPU state.
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  _log('edits: ${results['editToTokensMs']}');
  results['monarch'] = {
    'wholeFileMs': monarchWhole,
    'editToTokensMs': _stats(monarchEdits),
  };
  return results;
}

EditorSurface? _surface() {
  EditorSurface? found;
  void visit(Element element) {
    if (element.widget case final EditorSurface surface) {
      found = surface;
    } else {
      element.visitChildren(visit);
    }
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

/// The next frame; or a second, when no frame comes (the window hidden).
Future<void> _frame() {
  final done = Completer<void>();
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (!done.isCompleted) done.complete();
  });
  SchedulerBinding.instance.scheduleFrame();
  return done.future.timeout(
    const Duration(seconds: 1),
    onTimeout: () => _log('no frame within a second'),
  );
}

/// Opens [text] in an [IdeEditor], scrolls through it and types into it;
/// the frame times meanwhile, and when the first lines were colored.
Future<Map<String, Object>> _editor(
  String text, {
  required bool textMate,
}) async {
  textMateWorkerLauncher = textMate ? spawnTextMateWorker : () async => null;
  final path = '/perf/big${textMate ? 1 : 2}.ts';
  final workspace = IdeWorkspace('/perf', files: _MemoryFiles({path: text}));
  await workspace.open(path);
  final key = GlobalKey<IdeEditorState>();
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> list) => timings.addAll(list);
  SchedulerBinding.instance.addTimingsCallback(collect);

  final watch = Stopwatch()..start();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: IdeEditor(
          key: key,
          workspace: workspace,
          active: workspace.active!,
          nativeEditorEnabled: true,
          onError: (error) => stderr.writeln('editor error: $error'),
          onLspStatus: (_) {},
          onPositionChanged: (_) {},
        ),
      ),
    ),
  );
  double? firstColored;
  while (watch.elapsed < const Duration(seconds: 20)) {
    await _frame();
    final spans = _surface()?.styledLines?[1];
    if (spans != null && spans.any((span) => span.style?.color != null)) {
      firstColored = _ms(watch.elapsed);
      break;
    }
  }

  final lineCount = DocumentSnapshot(text).lineCount;
  // Scroll through the file, a jump per frame.
  for (var line = 1; line < lineCount; line += lineCount ~/ 60) {
    key.currentState!.revealRange(
      LspRange(LspPosition(line, 0), LspPosition(line, 0)),
    );
    await _frame();
  }
  // Type 40 characters, one every 50ms.
  final controller = _surface()!.controller;
  controller.select(
    DocumentSnapshot(text).lineStarts[5000],
    DocumentSnapshot(text).lineStarts[5000],
  );
  for (var i = 0; i < 40; i++) {
    controller.replaceSelection('x');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  SchedulerBinding.instance.removeTimingsCallback(collect);
  runApp(const SizedBox());
  await _frame();
  workspace.dispose();
  return {
    'firstColoredMs': ?firstColored,
    'frames': timings.length,
    'buildMs': _stats([for (final t in timings) _ms(t.buildDuration)]),
    'rasterMs': _stats([for (final t in timings) _ms(t.rasterDuration)]),
    'framesOver16ms': timings
        .where((t) => t.totalSpan > const Duration(microseconds: 16667))
        .length,
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _run();
  } catch (error, stack) {
    _log('failed: $error\n$stack');
    exit(1);
  }
}

Future<void> _run() async {
  _log('reading $_sample');
  final text = List.filled(
    _copies,
    File(_sample).readAsStringSync(),
  ).join('\n');
  final results = <String, Object>{
    'mode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    'lines': DocumentSnapshot(text).lineCount,
  };
  results['service'] = await _service(text);
  _log('service done');
  results['editorTextMate'] = await _editor(text, textMate: true);
  _log('editor (TextMate) done');
  results['editorMonarch'] = await _editor(text, textMate: false);
  stdout.writeln(
    'TEXTMATE_PERF ${const JsonEncoder.withIndent('  ').convert(results)}',
  );
  exit(0);
}

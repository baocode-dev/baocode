// The perf app's scenarios: what the user and the agents do in each, and
// which parts of it are measured (its phases). Each runs in a BaoCodeApp of
// its own, on a Workspace whose agents are PerfTransport's.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/workspace/chat_grid.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/workspace/workspace.dart';

import 'perf_content.dart';
import 'perf_input.dart';
import 'perf_hands.dart';
import 'perf_interaction.dart';
import 'perf_probe.dart';
import 'perf_stress.dart';
import 'perf_trace.dart';
import 'perf_transcript.dart';
import 'perf_transport.dart';

/// The files the IDE's scenarios open, in the project's folder.
class PerfProject {
  PerfProject(this.root);

  final String root;

  /// About 9,000 lines of real TypeScript (VS Code's text model, three
  /// times).
  String get bigFile => '$root/src/textModel.ts';

  /// Each file's length as written, to tell when the editor shows it.
  final Map<String, int> lengths = {};

  /// Smaller files, to switch between.
  List<String> get files => [
    for (var i = 0; i < 12; i++) '$root/src/part_$i.dart',
  ];

  /// About 90,000 lines: the same TypeScript, thirty times.
  String get hugeFile => '$root/src/huge/textModelHuge.ts';

  /// 600 lines of over 2,000 characters each, as bundled code has.
  String get longLinesFile => '$root/src/bundle.min.js';

  /// Forty files of 1,200 lines, to switch between fast.
  List<String> get manyFiles => [
    for (var i = 0; i < 40; i++) '$root/src/many/module_$i.ts',
  ];
}

typedef PerfScenarioBody = Future<void> Function(PerfContext context);

class PerfScenario {
  const PerfScenario(this.name, this.description, this.run);

  final String name;
  final String description;
  final PerfScenarioBody run;
}

class PerfContext {
  PerfContext({
    required this.scenario,
    required this.workspace,
    required this.project,
    required this.input,
    this.trace,
    this.shots,
    this.shotKey,
  });

  final String scenario;
  final Workspace workspace;
  final PerfProject project;
  final PerfInput input;
  final PerfTrace? trace;

  /// Where a picture of the window goes after each phase, if anywhere.
  final String? shots;
  final GlobalKey? shotKey;

  final PerfContent content = PerfContent(42);
  final Map<String, Object> results = {};

  /// What the scenario saw not happen that should have: the app failing
  /// the user, whatever its figures (see [check]).
  final List<String> failedChecks = [];

  /// Checks that what the user did had its effect ([ok]); [what] it
  /// should have been, kept with the results when it was not.
  void check(bool ok, String what) {
    if (ok) return;
    log('check failed: $what');
    failedChecks.add(what);
  }

  int _prompts = 0;

  /// How many times the app asked for its window to grow (to make room
  /// for a pane dropped): not done, the window being the installed app's
  /// too (see perf_app.dart).
  static int windowGrowths = 0;

  /// What the app last copied, kept from the clipboard (see perf_app.dart).
  static String? copied;

  /// What the engine's pointer data went to before the perf app took it
  /// away from the desktop (see perf_app.dart): given back while a hand is
  /// recorded (`record.hands`).
  static ui.PointerDataPacketCallback? desktopPointers;

  static void log(String message) =>
      stderr.writeln('BAOCODE_PERF_LOG $message');

  /// Measures [body] as the phase [name].
  Future<void> phase(
    String name,
    Future<void> Function(PerfRecording recording) body,
  ) async {
    log('$scenario.$name');
    await trace?.begin();
    final recording = PerfProbe.instance.start('$scenario.$name');
    Map<String, Object> result;
    try {
      await body(recording);
    } finally {
      result = await recording.stop();
      results[name] = result;
    }
    if (trace case final trace?) {
      result['trace'] = await trace.end('$scenario.$name');
    }
    await PerfHeap.log('$scenario.$name');
    if (shots case final directory?) {
      await _shot('$directory/$scenario.$name.png');
    }
  }

  Future<void> _shot(String path) async {
    final boundary = shotKey?.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return;
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes.buffer.asUint8List());
  }

  /// Lets the app come to rest: [time] of frames, whatever they show.
  Future<void> settle([
    Duration time = const Duration(milliseconds: 800),
  ]) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < time) {
      await nextFrame();
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> until(
    bool Function() done,
    String what, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final watch = Stopwatch()..start();
    while (!done()) {
      if (watch.elapsed > timeout) throw TimeoutException('waiting for $what');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  // --- Agents ----------------------------------------------------------------

  /// The agent shown, or a new one in the project.
  AgentThread get agent => workspace.selected;

  /// [count] agents in the project, each sent a message already (a new
  /// agent untouched is reused, not made anew).
  Future<List<AgentThread>> agents(int count, {int history = 1}) async {
    final made = <AgentThread>[];
    for (var i = 0; i < count; i++) {
      final thread = workspace.create(project: workspace.projects.first);
      await this.history(thread, history);
      made.add(thread);
    }
    return made;
  }

  /// Sends [thread] a message it answers with [turn]; done as the turn
  /// begins.
  Future<void> start(
    AgentThread thread,
    PerfTurn turn, {
    String? prompt,
  }) async {
    prompt = 'perf ${++_prompts}: ${prompt ?? content.paragraph()}';
    PerfTurns.register(prompt, turn);
    final session = thread.session;
    await until(() => session.canSend, 'the agent to take a message');
    session.send(ComposerMessage(text: prompt));
  }

  /// Sends [thread] [turn], and waits for it to end.
  Future<void> run(AgentThread thread, PerfTurn turn, {String? prompt}) async {
    final ended = thread.session.lastTurnEndSeq;
    await start(thread, turn, prompt: prompt);
    await until(
      () =>
          thread.session.lastTurnEndSeq > ended && !thread.session.isStreaming,
      'the turn to end',
    );
  }

  /// Waits until the agents have streamed [chars] more characters than
  /// [since] (a [PerfTransport.streamed] read before).
  Future<void> untilStreamed(int since, int chars) => until(
    () => PerfTransport.streamed - since >= chars,
    '$chars characters streamed',
  );

  /// Gives [thread] [turns] turns of history, each written at once.
  Future<void> history(AgentThread thread, int turns) async {
    for (var i = 0; i < turns; i++) {
      await run(thread, historyTurn());
    }
  }

  // --- Turns -----------------------------------------------------------------

  PerfTool read(int lines) => PerfTool('Read', {
    'file_path': '${project.root}/${content.filePath()}',
  }, result: content.numberedFile(lines));

  PerfTool grep() => PerfTool(
    'Grep',
    {'pattern': content.identifier(), 'path': 'lib', 'output_mode': 'content'},
    result: [
      for (var i = 0; i < 24; i++)
        '${content.filePath()}:${i * 7 + 3}:  final ${content.identifier()} = ${content.identifier()};',
    ].join('\n'),
  );

  PerfTool bash(int lines) {
    final output = content.commandOutput(lines);
    return PerfTool(
      'Bash',
      {'command': 'flutter test test/chat', 'description': 'Run the tests'},
      result: output,
      structured: {'stdout': output, 'stderr': '', 'interrupted': false},
    );
  }

  PerfTool edit() {
    final path = content.filePath();
    final removed = content.code('dart', 4).split('\n');
    final added = content.code('dart', 7).split('\n');
    return PerfTool(
      'Edit',
      {
        'file_path': path,
        'old_string': removed.join('\n'),
        'new_string': added.join('\n'),
      },
      result: 'The file $path has been updated successfully.',
      structured: {
        'filePath': path,
        'structuredPatch': [
          {
            'oldStart': 40,
            'oldLines': removed.length,
            'newStart': 40,
            'newLines': added.length,
            'lines': [
              for (final l in removed) '-$l',
              for (final l in added) '+$l',
            ],
          },
        ],
      },
    );
  }

  /// A turn as one of a long session's: a thought, a few tools, an answer.
  PerfTurn historyTurn() => PerfTurn([
    PerfThink(content.thought(300)),
    read(80),
    grep(),
    edit(),
    bash(30),
    PerfSay(content.reply(1500)),
  ], pace: PerfPace.instant);

  /// A thought, a look at the code and a reply of [chars] characters, at
  /// [pace].
  PerfTurn reply(int chars, PerfPace pace, {bool heavy = false}) => PerfTurn([
    PerfThink(content.thought(600)),
    read(120),
    grep(),
    PerfSay(content.reply(chars, heavy: heavy)),
  ], pace: pace);

  // --- The view ---------------------------------------------------------------

  /// The first element of a [T] (that [where] takes) in the app.
  Element? find<T extends Widget>({bool Function(T widget)? where}) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget case final T widget when where?.call(widget) ?? true) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  /// [find], but the element found last while it is still a [T] in the
  /// app: what is looked for in a phase, at each frame or jump, without
  /// walking the whole tree (thousands of elements) each time, which the
  /// phase would count.
  Element? findKept<T extends Widget>() {
    if (_kept[T] case final kept? when kept.mounted && kept.widget is T) {
      return kept;
    }
    final element = find<T>();
    if (element == null) {
      _kept.remove(T);
    } else {
      _kept[T] = element;
    }
    return element;
  }

  final Map<Type, Element> _kept = {};

  /// Every element whose widget is of the class [name] (a private one,
  /// say, which cannot be named here), in tree order.
  List<Element> findNamed(String name) {
    final found = <Element>[];
    void visit(Element element) {
      if (element.widget.runtimeType.toString() == name) found.add(element);
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  /// The element keyed [key] (a ValueKey's value).
  Element? findKeyed(Object key) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key case ValueKey(:final value) when value == key) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  /// The first element under [root] whose widget is a [T] (that [where]
  /// takes), [root] itself not.
  Element? findIn<T extends Widget>(
    Element root, {
    bool Function(T widget)? where,
  }) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget case final T widget when where?.call(widget) ?? true) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
  }

  /// The first scrollable along [axis] under [root]: the outermost.
  ScrollableState? scrollableIn(Element root, {Axis axis = Axis.vertical}) {
    ScrollableState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element case StatefulElement(:final ScrollableState state)
          when state.position.axis == axis) {
        found = state;
        return;
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
  }

  /// Where [root]'s scrollable is, in pixels from its start.
  double scrolledIn(Element root) => scrollableIn(root)?.position.pixels ?? 0;

  /// The element keyed [key], where it is on screen; null when it is not
  /// there.
  Rect? rectKeyed(Object key) => switch (findKeyed(key)) {
    final element? => rectOf(element),
    null => null,
  };

  /// What a press of Cmd+C (the focus where it is) copies; null when
  /// nothing is.
  Future<String?> copy() async {
    copied = null;
    input.press(LogicalKeyboardKey.keyC, meta: true);
    await settle(const Duration(milliseconds: 100));
    return copied;
  }

  Rect rectOf(Element element) {
    final box = element.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Where the shown conversation is: the middle of its history.
  Offset get chatCenter {
    final history = find<ChatHistoryView>();
    if (history == null) throw StateError('no conversation shows');
    return rectOf(history).center;
  }

  // --- The IDE ----------------------------------------------------------------

  /// Shows the IDE on the project, and waits for its workbench.
  Future<IdeWorkbench> openIde() async {
    workspace.openIdeFolder(project.root);
    workspace.layout = WorkspaceLayout.ide;
    await until(() => find<IdeWorkbench>() != null, 'the IDE');
    await settle();
    return find<IdeWorkbench>()!.widget as IdeWorkbench;
  }

  EditorSurface? get editor =>
      findKept<EditorSurface>()?.widget as EditorSurface?;

  /// Moves the editor to [line] (from 1) as going to a definition or a
  /// search result does: the caret there, the line centered.
  void jumpTo(int line) {
    final element = findKept<IdeEditor>()! as StatefulElement;
    final position = LspPosition(line - 1, 0);
    (element.state as IdeEditorState).revealRange(
      LspRange(position, position),
      center: true,
    );
  }

  /// Whether the editor shows lines in their colors (any of those it has
  /// styled: the first may be blank).
  bool get editorColored =>
      editor?.styledLines?.values.any(
        (spans) => spans.any((span) => span.style?.color != null),
      ) ??
      false;

  /// Opens [path] in the IDE's editor (or brings it to the front); how
  /// long until the end of the first frame that shows it colored.
  Future<Duration> openFile(IdeWorkbench workbench, String path) async {
    bool shown() =>
        workbench.workspace.active?.path == path &&
        editor?.controller.value.text.length == project.lengths[path] &&
        editorColored;
    final watch = Stopwatch()..start();
    PerfProbe.instance.mark(PerfMark.action);
    unawaited(workbench.workspace.open(path));
    do {
      if (watch.elapsed > const Duration(seconds: 30)) {
        throw TimeoutException('waiting for $path to show');
      }
      await nextFrame();
    } while (!shown());
    return watch.elapsed;
  }

  /// Where the editor is on screen.
  Rect get editorRect => rectOf(findKept<EditorSurface>()!);

  /// The editor's geometry: where its lines and caret are.
  EditorSurfaceView get editorView =>
      (findKept<EditorSurface>()! as StatefulElement).state
          as EditorSurfaceView;

  /// The editor's selection.
  TextSelection get editorSelection => editor!.controller.value.selection;

  /// The line (from 1) of [offset] in the editor's text.
  int lineAt(int offset) {
    final text = editor!.controller.value.text;
    var line = 1;
    for (
      var i = text.indexOf('\n');
      i >= 0 && i < offset;
      i = text.indexOf('\n', i + 1)
    ) {
      line++;
    }
    return line;
  }

  /// Whether the editor shows the caret's line.
  bool get caretShown {
    final range = editorView.visibleLineRange;
    final line = lineAt(editorSelection.extentOffset);
    return range != null && line >= range.first && line <= range.last;
  }

  /// The text offset at [global], a point on screen over the editor's
  /// text; null off the text of a line.
  int? editorOffsetAt(Offset global) =>
      editorView.textOffsetAt(global - editorRect.topLeft);

  /// Clicks into the editor, and puts the caret at [column] of [line].
  Future<void> focusEditor(int line, {int column = 0}) async {
    await input.click(editorRect.center);
    await settle(const Duration(milliseconds: 300));
    final controller = editor!.controller;
    final text = controller.value.text;
    var offset = 0;
    for (var i = 1; i < line && offset >= 0; i++) {
      offset = text.indexOf('\n', offset) + 1;
    }
    controller.select(offset + column, offset + column);
    await settle(const Duration(milliseconds: 300));
    if (!input.canType) throw StateError('the editor has no text input');
  }
}

/// What is typed in the editor: code, with brackets the editor closes
/// itself and lines it indents.
const typedCode =
    'function perfProbe(value: number, limit = 10) {\n'
    'const doubled = value * 2;\n'
    'if (doubled > limit) {\n'
    'return doubled - limit;\n'
    '}\n'
    'return [doubled, limit].reduce((a, b) => a + b, 0);\n'
    '}\n';

/// Every scenario: these, the stress scenarios (perf_stress.dart), then
/// those of the hands: dragging, selecting, the caret, scrolling
/// (perf_interaction.dart).
final List<PerfScenario> perfScenarios = [
  ..._scenarios,
  ...stressScenarios,
  ...interactionScenarios,
  ...handScenarios,
];

final List<PerfScenario> _scenarios = [
  // --- The chat ----------------------------------------------------------------
  PerfScenario(
    'chat.stream',
    'One agent answers at a model\'s usual speed (400 chars/s): a thought, '
        'two tools, 4k characters of markdown with code and tables.',
    (c) async {
      await c.history(c.agent, 1);
      await c.settle();
      final turn = c.reply(4000, PerfPace.typical);
      await c.phase('stream', (r) async {
        await c.run(c.agent, turn);
        r.extra['streamedChars'] = turn.streamedChars;
      });
    },
  ),
  PerfScenario(
    'chat.stream_fast',
    'A fast model (1500 chars/s), code-heavy: long code blocks and tables.',
    (c) async {
      await c.history(c.agent, 1);
      await c.settle();
      final turn = c.reply(14000, PerfPace.fast, heavy: true);
      await c.phase('stream', (r) async {
        await c.run(c.agent, turn);
        r.extra['streamedChars'] = turn.streamedChars;
      });
    },
  ),
  PerfScenario(
    'chat.stream_flood',
    'More than any model writes (6000 chars/s in 24-char deltas): what the '
        'chat must keep up with when it falls behind.',
    (c) async {
      await c.history(c.agent, 1);
      await c.settle();
      final turn = c.reply(36000, PerfPace.flood, heavy: true);
      await c.phase('stream', (r) async {
        await c.run(c.agent, turn);
        r.extra['streamedChars'] = turn.streamedChars;
      });
    },
  ),
  PerfScenario(
    'chat.long_history',
    'A session of 40 turns comes in at once, then a reply streams below it.',
    (c) async {
      await c.settle();
      await c.phase('load', (r) async {
        await c.history(c.agent, 40);
        await c.settle();
      });
      final turn = c.reply(4000, PerfPace.typical);
      await c.phase('stream', (r) async {
        await c.run(c.agent, turn);
      });
    },
  ),
  // --- With the semantics tree on -------------------------------------------
  // As when an accessibility client reads the window (a screen reader, an
  // input method, a translator's or a password manager's UI Automation).
  PerfScenario(
    'a11y.long_history',
    'chat.long_history with the semantics tree on.',
    (c) async {
      final semantics = SemanticsBinding.instance.ensureSemantics();
      try {
        await c.settle();
        await c.phase('load', (r) async {
          await c.history(c.agent, 40);
          await c.settle();
        });
        final turn = c.reply(4000, PerfPace.typical);
        await c.phase('stream', (r) async {
          await c.run(c.agent, turn);
        });
      } finally {
        semantics.dispose();
      }
    },
  ),
  PerfScenario(
    'a11y.huge_history',
    'A 150-turn conversation with the semantics tree on: loaded, the wheel '
        'spun through it, an answer streamed below it.',
    (c) async {
      final semantics = SemanticsBinding.instance.ensureSemantics();
      try {
        await c.settle();
        await c.phase('load', (r) async {
          await c.history(c.agent, 150);
          await c.settle();
        });
        PerfContext.log('after load: ${treeCounts()}');
        final at = c.chatCenter;
        await c.phase('spin', (r) async {
          for (var i = 0; i < 3; i++) {
            await c.input.spin(
              at,
              -200,
              400,
              every: const Duration(milliseconds: 16),
            );
            await c.settle(const Duration(milliseconds: 300));
            await c.input.spin(
              at,
              200,
              400,
              every: const Duration(milliseconds: 16),
            );
            await c.settle(const Duration(milliseconds: 300));
            PerfContext.log('after spin $i: ${treeCounts()}');
          }
          r.extra.addAll(treeCounts());
        });
        await c.phase('stream', (r) async {
          await c.run(c.agent, c.reply(6000, PerfPace.fast, heavy: true));
          r.extra.addAll(treeCounts());
        });
        PerfContext.log('after stream: ${treeCounts()}');
      } finally {
        semantics.dispose();
      }
    },
  ),
  PerfScenario(
    'real.history',
    'A real session, a Claude Code transcript (BAOCODE_PERF_TRANSCRIPT; '
        'BAOCODE_PERF_TRANSCRIPT_TURNS, its first turns only), loaded turn '
        'by turn, the wheel spun through it, an answer streamed below it.',
    (c) async {
      final path = Platform.environment['BAOCODE_PERF_TRANSCRIPT'];
      c.check(path != null, 'BAOCODE_PERF_TRANSCRIPT names a transcript');
      if (path == null) return;
      final turns = readTranscript(
        path,
        limit: int.tryParse(
          Platform.environment['BAOCODE_PERF_TRANSCRIPT_TURNS'] ?? '',
        ),
      );
      await c.settle();
      await c.phase('load', (r) async {
        for (final (:prompt, :turn) in turns) {
          await c.run(c.agent, turn, prompt: prompt);
        }
        await c.settle();
        r.extra['turns'] = turns.length;
        r.extra.addAll(treeCounts());
      });
      PerfContext.log('after load: ${treeCounts()}');
      final at = c.chatCenter;
      await c.phase('spin', (r) async {
        await c.input.spin(
          at,
          -200,
          400,
          every: const Duration(milliseconds: 16),
        );
        await c.settle(const Duration(milliseconds: 300));
        await c.input.spin(
          at,
          200,
          400,
          every: const Duration(milliseconds: 16),
        );
        await c.settle(const Duration(milliseconds: 300));
      });
      await c.phase('stream', (r) async {
        await c.run(c.agent, c.reply(6000, PerfPace.fast, heavy: true));
        r.extra.addAll(treeCounts());
      });
    },
  ),
  PerfScenario(
    'bench.text_layout',
    'Paragraphs laid out in the styles the app draws text in, each new '
        '(no cache): what a line of text costs, font by font.',
    (c) async {
      await c.settle();
      await c.phase('layout', (r) async {
        r.extra.addAll(_textLayoutBench());
      });
    },
  ),
  PerfScenario(
    'hang.ui',
    'The UI thread held 7 s in _holdUiThread, past the hang watchdog\'s 6 '
        '(Windows) or 4 (macOS): its report in the logs\' hangs/ (Windows: '
        'the data folder\'s; macOS: the event log\'s, beside the [hang] '
        'lines), whose Dart frames the build\'s symbols should name so; and '
        'the event log\'s slow frame.',
    (c) async {
      await c.settle();
      await c.phase('hang', (r) async {
        final done = Completer<void>();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _holdUiThread(const Duration(seconds: 7));
          done.complete();
        });
        WidgetsBinding.instance.scheduleFrame();
        await done.future;
        await c.settle();
      });
      // macOS' sample of it, begun 4 s in, written before the app goes.
      if (Platform.isMacOS)
        await Future<void>.delayed(const Duration(seconds: 8));
    },
  ),
  PerfScenario(
    'chat.tools',
    'An agent at work: 120 tool calls in quick succession (reads, greps, '
        'edits, commands with long output), a line of text between them.',
    (c) async {
      await c.history(c.agent, 1);
      await c.settle();
      final steps = <PerfStep>[
        for (var i = 0; i < 30; i++) ...[
          c.read(150),
          PerfSay(c.content.paragraph()),
          c.grep(),
          c.edit(),
          c.bash(100),
        ],
        PerfSay(c.content.reply(1200)),
      ];
      await c.phase('tools', (r) async {
        await c.run(c.agent, PerfTurn(steps, pace: PerfPace.fast));
      });
    },
  ),
  PerfScenario(
    'chat.grid',
    'Four agents side by side (2×2), all answering at once.',
    (c) async {
      final agents = await c.agents(4);
      final [a, b, d, e] = agents;
      c.workspace
        ..select(a)
        ..openBeside(b, a, PaneSide.right)
        ..openBeside(d, a, PaneSide.bottom)
        ..openBeside(e, b, PaneSide.bottom);
      await c.settle();
      await c.phase('stream', (r) async {
        final ends = [for (final t in agents) t.session.lastTurnEndSeq];
        for (final thread in agents) {
          await c.start(thread, c.reply(3000, PerfPace.typical));
        }
        await c.until(
          () => [
            for (final (i, t) in agents.indexed)
              t.session.lastTurnEndSeq > ends[i] && !t.session.isStreaming,
          ].every((ended) => ended),
          'the four turns',
        );
        r.extra['panes'] = c.workspace.grid.panes.length;
      });
    },
  ),
  PerfScenario(
    'chat.background',
    'Six agents answer out of sight, fast, while an idle one shows: what '
        'they cost the view in front (the sidebar\'s states aside, nothing).',
    (c) async {
      final idle = c.agent;
      await c.history(idle, 6);
      final busy = await c.agents(6);
      c.workspace.select(idle);
      await c.settle();
      await c.phase('background', (r) async {
        final ends = [for (final t in busy) t.session.lastTurnEndSeq];
        for (final thread in busy) {
          await c.start(thread, c.reply(9000, PerfPace.fast));
        }
        await c.until(
          () => [
            for (final (i, t) in busy.indexed)
              t.session.lastTurnEndSeq > ends[i],
          ].every((ended) => ended),
          'the six turns',
        );
      });
    },
  ),
  PerfScenario(
    'chat.scroll',
    'Scrolling a 40-turn conversation: a mouse wheel spun up and down, then '
        'trackpad swipes that fling.',
    (c) async {
      await c.history(c.agent, 40);
      await c.settle(const Duration(seconds: 1));
      final at = c.chatCenter;
      await c.phase('wheel', (r) async {
        await c.input.spin(at, -120, 60);
        await c.settle(const Duration(milliseconds: 500));
        await c.input.spin(at, 120, 60);
        await c.settle(const Duration(milliseconds: 500));
      });
      await c.phase('trackpad', (r) async {
        for (var i = 0; i < 4; i++) {
          await c.input.swipe(at, List.filled(24, 30));
          await c.settle(const Duration(milliseconds: 700));
        }
        for (var i = 0; i < 4; i++) {
          await c.input.swipe(at, List.filled(24, -30));
          await c.settle(const Duration(milliseconds: 700));
        }
      });
    },
  ),

  // --- Fast Ide ----------------------------------------------------------------
  PerfScenario(
    'ide.open',
    'Opening a 9,000-line TypeScript file in the IDE until it is colored, '
        'then switching between twelve open files.',
    (c) async {
      final workbench = await c.openIde();
      await c.phase('open', (r) async {
        final took = await c.openFile(workbench, c.project.bigFile);
        r.extra['coloredMs'] = took.inMilliseconds;
        await c.settle();
      });
      for (final path in c.project.files) {
        await c.openFile(workbench, path);
      }
      await c.settle();
      await c.phase('switch', (r) async {
        final took = <double>[];
        for (var round = 0; round < 2; round++) {
          for (final path in [...c.project.files, c.project.bigFile]) {
            took.add((await c.openFile(workbench, path)).inMicroseconds / 1000);
            await c.settle(const Duration(milliseconds: 150));
          }
        }
        r.extra['switchMs'] = stats(took);
      });
    },
  ),
  PerfScenario(
    'ide.typing',
    'Typing code in the middle of the 9,000-line file, a key every 33ms '
        '(a key held down), then deleting it a key at a time.',
    (c) async {
      final workbench = await c.openIde();
      await c.openFile(workbench, c.project.bigFile);
      await c.settle(const Duration(seconds: 2));
      await c.focusEditor(4500);
      final before = c.editor!.controller.value.text.length;
      await c.phase('type', (r) async {
        await c.input.type(typedCode);
        await c.settle(const Duration(milliseconds: 500));
        r.extra['typedChars'] = c.editor!.controller.value.text.length - before;
      });
      await c.phase('delete', (r) async {
        for (var i = 0; i < 80; i++) {
          c.input.press(LogicalKeyboardKey.backspace);
          await Future<void>.delayed(const Duration(milliseconds: 33));
        }
        await c.settle(const Duration(milliseconds: 500));
      });
    },
  ),
  PerfScenario(
    'ide.scroll',
    'Scrolling the 9,000-line file: a mouse wheel spun, then trackpad '
        'swipes that fling.',
    (c) async {
      final workbench = await c.openIde();
      await c.openFile(workbench, c.project.bigFile);
      await c.settle(const Duration(seconds: 2));
      final at = c.editorRect.center;
      await c.phase('wheel', (r) async {
        await c.input.spin(at, 120, 80);
        await c.settle(const Duration(milliseconds: 500));
        await c.input.spin(at, -120, 40);
        await c.settle(const Duration(milliseconds: 500));
      });
      await c.phase('trackpad', (r) async {
        for (var i = 0; i < 4; i++) {
          await c.input.swipe(at, List.filled(24, -40));
          await c.settle(const Duration(milliseconds: 700));
        }
        for (var i = 0; i < 2; i++) {
          await c.input.swipe(at, List.filled(24, 40));
          await c.settle(const Duration(milliseconds: 700));
        }
      });
    },
  ),

  // --- Both at once ------------------------------------------------------------
  PerfScenario(
    'mix.type_while_streaming',
    'Typing in the IDE while its chat\'s agent answers fast beside it, and '
        'two more agents answer out of sight.',
    (c) async {
      final workbench = await c.openIde();
      await c.openFile(workbench, c.project.bigFile);
      final chat = c.workspace.ideChat(c.project.root)!;
      await c.history(chat, 2);
      final others = await c.agents(2);
      await c.settle(const Duration(seconds: 1));
      await c.focusEditor(3000);
      await c.phase('type', (r) async {
        for (final thread in [chat, ...others]) {
          // Outlasting the typing (about 13s).
          await c.start(thread, c.reply(20000, PerfPace.fast, heavy: true));
        }
        await c.input.type(typedCode * 2);
        await c.settle(const Duration(milliseconds: 500));
        r.extra['agentStillStreaming'] = chat.session.isStreaming;
      });
    },
  ),
  PerfScenario(
    'mix.layout_switch',
    'Switching between the chat and the IDE, each with plenty on show: a '
        '20-turn conversation, the big file open.',
    (c) async {
      final chatAgent = c.agent;
      await c.history(chatAgent, 20);
      final workbench = await c.openIde();
      await c.openFile(workbench, c.project.bigFile);
      c.workspace.layout = WorkspaceLayout.chat;
      await c.settle(const Duration(seconds: 1));
      await c.phase('switch', (r) async {
        for (var i = 0; i < 8; i++) {
          PerfProbe.instance.mark(PerfMark.action);
          c.workspace.layout = WorkspaceLayout.ide;
          await c.settle(const Duration(milliseconds: 400));
          PerfProbe.instance.mark(PerfMark.action);
          c.workspace.layout = WorkspaceLayout.chat;
          await c.settle(const Duration(milliseconds: 400));
        }
      });
    },
  ),
  PerfScenario(
    'mix.agent_switch',
    'Going through twelve agents\' conversations of five turns each.',
    (c) async {
      final agents = await c.agents(12, history: 5);
      c.workspace.select(agents.first);
      await c.settle(const Duration(seconds: 1));
      await c.phase('switch', (r) async {
        for (var round = 0; round < 2; round++) {
          for (final thread in agents) {
            PerfProbe.instance.mark(PerfMark.action);
            c.workspace.select(thread);
            await c.settle(const Duration(milliseconds: 250));
          }
        }
      });
    },
  ),
];

/// The semantics nodes of every view, and the children of the lazy lists:
/// laid out in them, and all (those kept alive besides).
Map<String, int> treeCounts() {
  var nodes = 0, inList = 0, all = 0, lists = 0, objects = 0;
  void visit(RenderObject object) {
    objects++;
    if (object is RenderSliverMultiBoxAdaptor) {
      lists++;
      for (var c = object.firstChild; c != null; c = object.childAfter(c)) {
        inList++;
      }
      object.visitChildren((_) => all++);
    }
    object.visitChildren(visit);
  }

  bool count(SemanticsNode node) {
    nodes++;
    node.visitChildren(count);
    return true;
  }

  for (final view in RendererBinding.instance.renderViews) {
    visit(view);
    if (view.owner?.semanticsOwner?.rootSemanticsNode case final root?) {
      count(root);
    }
  }
  return {
    'renderObjects': objects,
    'semanticsNodes': nodes,
    'lazyLists': lists,
    'listChildren': inList,
    'keptAlive': all - inList,
  };
}

/// Microseconds per paragraph of about 80 characters, for each of the
/// styles the app's text is in, a different text each time.
Map<String, int> _textLayoutBench() {
  final uiFallbacks = Platform.isWindows ? AppFonts.windowsFallbacks : null;
  final styles = <String, (TextStyle, String)>{
    'ui': (
      TextStyle(fontSize: 13, fontFamilyFallback: uiFallbacks),
      'The quick brown fox jumps over the lazy dog, then reads the file',
    ),
    'ui_cjk': (
      TextStyle(fontSize: 13, fontFamilyFallback: uiFallbacks),
      '先确认一下现有的实现，再运行分析器和测试，看看哪里需要修改和补充',
    ),
    'ui_symbols': (
      TextStyle(fontSize: 13, fontFamilyFallback: uiFallbacks),
      'Done ✓ → next ⚠ check 📁 lib/ide ★ “quoted” — dash … end',
    ),
    'code': (
      AppFonts.uiCodeStyle(13),
      'final tokens = WheelGlide.cache(63); // return a + b * c;',
    ),
    'code_cjk': (
      AppFonts.uiCodeStyle(13),
      'final label = "保存文件"; // 中文注释 and some ascii',
    ),
    'code_installed_only': (
      const TextStyle(
        fontSize: 13,
        fontFamily: 'Consolas',
        fontFamilyFallback: ['Microsoft YaHei UI'],
      ),
      'final tokens = WheelGlide.cache(63); // return a + b * c;',
    ),
  };
  final results = <String, int>{};
  var n = 0;
  for (final MapEntry(key: name, value: (style, text)) in styles.entries) {
    // Warmed, then measured.
    for (final round in [40, 300]) {
      final watch = Stopwatch()..start();
      for (var i = 0; i < round; i++) {
        final painter = TextPainter(
          text: TextSpan(text: '$text ${n++}', style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 600);
        painter.dispose();
      }
      results[name] = watch.elapsedMicroseconds ~/ round;
    }
  }
  PerfContext.log('text layout µs per paragraph: $results');
  return results;
}

/// Keeps the thread busy for [time]: a hang, by a function of its own name.
@pragma('vm:never-inline')
void _holdUiThread(Duration time) {
  final clock = Stopwatch()..start();
  while (clock.elapsed < time) {}
}

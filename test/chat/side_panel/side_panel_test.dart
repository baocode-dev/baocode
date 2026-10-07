import 'dart:async';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/side_panel/file_link.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/side_panel/file_preview.dart';
import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/chat/widgets/edit_step.dart';
import 'package:baocode/chat/widgets/fold_line.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/chat/widgets/tool_call_row.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/tab_strip_scroll.dart';
import 'package:baocode/chat/side_panel/terminal_preview.dart';
import 'package:baocode/chat/panels/activity_strip.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../workspace/chat_window_keys_test.dart' show press;
import '../../workspace_test.dart' show pumpLoaded;
import '../../kernel_ui_test.dart' show pumpScripted;

/// A project's files, in memory.
class _Files implements IdeFileService {
  _Files(this.texts);

  final Map<String, String> texts;
  final List<String> listed = [];
  Future<String> Function(String)? reader;

  @override
  Future<String> read(String path, {bool force = false}) async =>
      reader?.call(path) ??
      texts[path] ??
      (throw IdeFileNotFoundException(path));

  @override
  Future<List<IdeFile>> list(String directory) async {
    listed.add(directory);
    return [
      for (final path in texts.keys)
        if (p.dirname(path) == directory)
          IdeFile(path, p.basename(path), isDirectory: false),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

String _lines(int count, String prefix) =>
    [for (var i = 1; i <= count; i++) '$prefix $i'].join('\n');

final _main = _lines(40, 'main line');

void _bigWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home) => MaterialApp(
  theme: buildAppTheme(),
  localizationsDelegates: const [FlutterQuillLocalizations.delegate],
  home: Material(child: home),
);

/// A conversation in `/p` (the mock's turn: a read of lib/main.dart, a
/// search, an edit of it) with the side panel at its right.
Future<({AgentSidePanel panel, ChatSession session, _Files files})> _pumpChat(
  WidgetTester tester, {
  Map<String, String>? texts,
}) async {
  _bigWindow(tester);
  final session = ChatSession(
    historyCount: 8,
    kernelContext: const KernelContext(cwd: '/p'),
    openReview: (root, {session}) async => null,
  );
  addTearDown(session.dispose);
  final panel = AgentSidePanel();
  addTearDown(panel.dispose);
  final files = _Files(texts ?? {'/p/lib/main.dart': _main});
  await tester.pumpWidget(
    _app(
      AgentSidePanelArea(
        panel: panel,
        builder: (context) =>
            AgentSidePanelView(panel: panel, session: session, files: files),
        child: ChatScreen(
          session: session,
          fileLinks: FileLinkTarget(
            open: (request) => panel.open(session, request),
            exists: fileExistsIn(files),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The turn's work, and its run of steps, open.
  for (final fold in [WorkFoldLine, StepsFoldLine]) {
    if (find.byType(fold).evaluate().isNotEmpty) {
      await tester.tap(find.byType(fold).first);
      await tester.pumpAndSettle();
    }
  }
  return (panel: panel, session: session, files: files);
}

/// [markdown] as the agent's reply, its files in `/p`, with the side
/// panel at its right.
Future<({AgentSidePanel panel, ChatSession session})> _pumpReply(
  WidgetTester tester,
  String markdown, {
  Map<String, String> texts = const {},
}) async {
  _bigWindow(tester);
  final session = ChatSession(
    historyCount: 0,
    openReview: (root, {session}) async => null,
  );
  addTearDown(session.dispose);
  final panel = AgentSidePanel();
  addTearDown(panel.dispose);
  final files = _Files(texts);
  final existence = FileExistence(fileExistsIn(files));
  addTearDown(existence.dispose);
  await tester.pumpWidget(
    _app(
      AgentSidePanelArea(
        panel: panel,
        builder: (context) =>
            AgentSidePanelView(panel: panel, session: session, files: files),
        child: FileOpenScope(
          root: '/p',
          onOpen: (request) => panel.open(session, request),
          existence: existence,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 600, child: MarkdownView(markdown)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (panel: panel, session: session);
}

/// The span of the text shown that is [text], in any paragraph.
TextSpan? _span(WidgetTester tester, String text) {
  TextSpan? found;
  for (final paragraph in tester.widgetList<RichText>(find.byType(RichText))) {
    paragraph.text.visitChildren((span) {
      if (span is TextSpan && span.text?.trim() == text) found = span;
      return found == null;
    });
    if (found != null) break;
  }
  return found;
}

void _tapSpan(WidgetTester tester, String text) {
  final recognizer = _span(tester, text)?.recognizer;
  expect(recognizer, isA<TapGestureRecognizer>(), reason: text);
  (recognizer! as TapGestureRecognizer).onTap!();
}

SidePanelTab? _active(AgentSidePanel panel, ChatSession session) =>
    panel.tabsOf(session).active;

void main() {
  testWidgets('completion queues a final read; hiding cancels polling', (
    tester,
  ) async {
    final first = Completer<String>(), last = Completer<String>();
    var reads = 0;
    final files = _Files({})
      ..reader = (_) => ++reads == 1 ? first.future : last.future;
    final task = ValueNotifier(
      KernelTask(
        id: 'one',
        description: 'test',
        kind: KernelTaskKind.command,
        status: CommandStatus.running,
        startedAt: DateTime.now(),
        outputFile: '/tmp/one.output',
      ),
    );
    addTearDown(task.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder(
          valueListenable: task,
          builder: (_, value, _) =>
              TerminalPreview(task: value, files: files, onStop: () {}),
        ),
      ),
    );
    expect(reads, 1);
    task.value = task.value.copyWith(status: CommandStatus.succeeded);
    await tester.pump();
    expect(reads, 1);
    first.complete('before completion');
    await tester.pump();
    expect(reads, 2);
    last.complete('final output');
    await tester.pumpAndSettle();
    expect(find.textContaining('final output'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(reads, 2);
    task.value = task.value.copyWith(status: CommandStatus.running);
    await tester.pump();
    final beforeHide = reads;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(reads, beforeHide);
  });

  testWidgets('failed output reads show an error and can be retried', (
    tester,
  ) async {
    final files = _Files({});
    final task = KernelTask(
      id: 'missing',
      description: 'test',
      kind: KernelTaskKind.command,
      status: CommandStatus.failed,
      startedAt: DateTime.now(),
      outputFile: '/tmp/missing.output',
      summary: 'command failed',
    );
    await tester.pumpWidget(
      _app(TerminalPreview(task: task, files: files, onStop: () {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsOneWidget);
    expect(find.textContaining('Output unavailable:'), findsOneWidget);
    expect(find.textContaining('command failed'), findsOneWidget);
    files.texts['/tmp/missing.output'] = 'recovered output';
    await tester.tap(find.byIcon(Codicons.refresh));
    await tester.pumpAndSettle();
    expect(find.textContaining('recovered output'), findsOneWidget);
    expect(find.textContaining('Output unavailable:'), findsNothing);
  });

  test('sections and terminal selections belong to their conversation', () {
    final panel = AgentSidePanel();
    addTearDown(panel.dispose);
    final first = Object(), second = Object();
    panel.open(first, const FileOpenRequest('/p/a.dart'));
    panel.openTerminal(first, 'bash-1');
    expect(panel.tabsOf(first).section, SidePanelSection.terminal);
    expect(panel.tabsOf(second).section, SidePanelSection.changes);
    panel.showSection(first, SidePanelSection.files);
    expect(panel.tabsOf(first).active!.path, '/p/a.dart');
    panel.closeTerminal(first, 'bash-1');
    expect(panel.tabsOf(first).closedTerminals, contains('bash-1'));
    panel.openTerminal(first, 'bash-1');
    expect(panel.tabsOf(first).closedTerminals, isEmpty);
  });

  testWidgets('two levels keep the selected file when switching sections', (
    tester,
  ) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    panel.open(session, const FileOpenRequest('/p/lib/main.dart'));
    await tester.pumpAndSettle();
    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(SidePanelSection.changes)));
    await tester.pumpAndSettle();
    expect(find.byType(FilePreview), findsNothing);
    await tester.tap(find.byKey(const ValueKey(SidePanelSection.files)));
    await tester.pumpAndSettle();
    expect(find.byType(FilePreview), findsOneWidget);
    expect(_active(panel, session)!.path, '/p/lib/main.dart');
    panel.width = AgentSidePanel.minWidth;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'file tabs reveal the active tab, show a scrollbar and scroll with the wheel',
    (tester) async {
      final (:panel, :session, files: _) = await _pumpChat(tester);
      for (var i = 0; i < 10; i++) {
        panel.open(session, FileOpenRequest('/p/long_file_name_$i.dart'));
      }
      await tester.pumpAndSettle();
      final strip = find.byType(TabStripScroll);
      final controller = tester.widget<TabStripScroll>(strip).controller;
      expect(controller.offset, greaterThan(0));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(strip));
      await tester.pumpAndSettle();
      final scrollbar = tester.widget<RawScrollbar>(
        find.descendant(of: strip, matching: find.byType(RawScrollbar)),
      );
      expect(scrollbar.thumbVisibility, isTrue);
      expect(scrollbar.interactive, isTrue);
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: tester.getCenter(strip),
          scrollDelta: const Offset(0, -180),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, lessThan(controller.position.maxScrollExtent));
      await mouse.removePointer();
    },
  );

  testWidgets(
    'background rows open multiple terminal tabs, poll output and stop through the kernel',
    (tester) async {
      final (:session, :cli) = await pumpScripted(tester);
      final panel = AgentSidePanel();
      addTearDown(panel.dispose);
      final files = _Files({
        '/tmp/one.output': 'first output',
        '/tmp/two.output': 'second output',
      });
      await tester.pumpWidget(
        _app(
          AgentSidePanelArea(
            panel: panel,
            rail: SidePanelRail(
              onSelect: (section) => panel.showSection(session, section),
            ),
            builder: (_) => AgentSidePanelView(
              panel: panel,
              session: session,
              files: files,
            ),
            child: ChatScreen(
              session: session,
              onOpenTerminalTask: (task) =>
                  panel.openTerminal(session, task.id),
            ),
          ),
        ),
      );
      for (final id in ['one', 'two']) {
        cli.push({
          'type': 'system',
          'subtype': 'task_started',
          'task_id': id,
          'task_type': 'local_bash',
          'is_backgrounded': true,
          'description': 'command $id',
          'output_file': '/tmp/$id.output',
        });
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.descendant(
          of: find.byType(ActivityStrip),
          matching: find.text('command one'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(TerminalPreview), findsOneWidget);
      expect(panel.tabsOf(session).terminal, 'one');
      expect(find.textContaining('first output'), findsOneWidget);
      files.texts['/tmp/one.output'] = 'first output\nnew output';
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.textContaining('new output'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(TabStripScroll),
          matching: find.text('command two'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('second output'), findsOneWidget);
      final preview = find.byType(TerminalPreview);
      await tester.tap(
        find.descendant(of: preview, matching: find.byIcon(Codicons.debugStop)),
      );
      await tester.pump();
      expect(cli.requests('stop_task').single['task_id'], 'two');
      cli.push({
        'type': 'system',
        'subtype': 'task_notification',
        'task_id': 'two',
        'status': 'completed',
        'output_file': '/tmp/two.output',
        'summary': 'done',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Completed'), findsOneWidget);
      expect(session.terminalTasks, hasLength(2));
      expect(session.tasks!.map((task) => task.id), ['one']);
      expect(
        find.descendant(of: preview, matching: find.byIcon(Codicons.debugStop)),
        findsNothing,
      );
      panel.closeTerminal(session, 'two');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('first output'), findsOneWidget);
      panel.hide();
      await tester.pump();
      expect(find.byType(SidePanelRail), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('section keys open the right page and the IDE has no rail', (
    tester,
  ) async {
    final workspace = await pumpLoaded(tester);
    for (final (key, section, shift, alt) in [
      (LogicalKeyboardKey.keyG, SidePanelSection.changes, true, false),
      (LogicalKeyboardKey.keyE, SidePanelSection.files, true, false),
      (LogicalKeyboardKey.keyT, SidePanelSection.terminal, false, true),
    ]) {
      await press(tester, key, meta: true, shift: shift, alt: alt);
      await tester.pumpAndSettle();
      final segment = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(ValueKey(section)),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(segment.properties.selected, isTrue);
    }
    workspace.openInIde(workspace.current!);
    await tester.pumpAndSettle();
    expect(find.byType(SidePanelRail), findsNothing);
    expect(find.byType(AgentSidePanelView), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a file read opens in the side panel, at the lines read', (
    tester,
  ) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    expect(find.byType(AgentSidePanelView), findsNothing);
    final read = find.byWidgetPredicate(
      (widget) => widget is ToolCallRow && widget.kind == ToolKind.read,
    );
    await tester.tap(
      find.descendant(of: read.last, matching: find.byType(RichText)).first,
    );
    await tester.pumpAndSettle();

    expect(panel.shown, isTrue);
    final tab = _active(panel, session)!;
    expect(tab.path, '/p/lib/main.dart');
    expect(tab.diff, isFalse);
    expect(tab.request.range, const FileLineRange(1, 562));
    expect(find.byType(FilePreview), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FilePreview),
        matching: find.text('main line 3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an edit shows the file\'s changes in the side panel; its '
      'chevron still opens the diff in place', (tester) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    final edit = find.byType(EditStep).last;
    await tester.tap(
      find.descendant(of: edit, matching: find.byType(RichText)).first,
    );
    await tester.pumpAndSettle();

    final tab = _active(panel, session)!;
    expect(tab.path, '/p/lib/main.dart');
    expect(tab.diff, isTrue);
    // At its first change.
    expect(tab.request.range?.start, 143);
    // The text before the agent's edit is not known here: the file.
    expect(find.textContaining('not known'), findsOneWidget);
    expect(find.text('main line 1'), findsOneWidget);
    expect(tester.widget<EditStep>(edit).expanded, isFalse);
  });

  testWidgets('a search\'s match opens its file at its line', (tester) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    final search = find.byWidgetPredicate(
      (widget) => widget is ToolCallRow && widget.kind == ToolKind.grep,
    );
    await tester.tap(search.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('lib/main.dart:142'));
    await tester.pumpAndSettle();
    final tab = _active(panel, session)!;
    expect(tab.path, '/p/lib/main.dart');
    expect(tab.request.range, const FileLineRange(142));
  });

  testWidgets('the diff of a change whose text before is known', (
    tester,
  ) async {
    final (:panel, :session, files: _) = await _pumpChat(
      tester,
      texts: {'/p/lib/a.dart': 'one\nTWO\nthree\n'},
    );
    panel.open(
      session,
      FileOpenRequest(
        '/p/lib/a.dart',
        diff: true,
        original: () async => 'one\ntwo\nthree\n',
      ),
    );
    await tester.pumpAndSettle();
    final preview = find.byType(FilePreview);
    for (final line in ['one', 'two', 'TWO', 'three']) {
      expect(
        find.descendant(of: preview, matching: find.text(line)),
        findsOneWidget,
        reason: line,
      );
    }
    expect(
      find.descendant(of: preview, matching: find.text('-')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preview, matching: find.text('+')),
      findsOneWidget,
    );
  });

  testWidgets('a file that is not there says so', (tester) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    panel.open(session, const FileOpenRequest('/p/gone.dart'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(FilePreview),
        matching: find.textContaining('gone.dart'),
      ),
      findsWidgets,
    );
  });

  testWidgets('the same file opens in its tab again; tabs close', (
    tester,
  ) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    panel.open(session, const FileOpenRequest('/p/lib/main.dart'));
    panel.open(
      session,
      const FileOpenRequest('/p/lib/main.dart', range: FileLineRange(30)),
    );
    await tester.pumpAndSettle();
    final tabs = panel.tabsOf(session);
    expect(tabs.files, hasLength(1));
    expect(tabs.active!.reveal, 1);
    panel.close(session, tabs.active!);
    await tester.pumpAndSettle();
    expect(tabs.active, isNull);
    expect(tabs.section, SidePanelSection.files);
    expect(find.text('No open files'), findsOneWidget);
  });

  testWidgets('a link to a file in the project opens it in the side panel, '
      'at its lines', (tester) async {
    final (:panel, :session) = await _pumpReply(
      tester,
      'See [the screen](lib/chat_screen.dart#L4-L6) and '
      '[notes](<docs/release notes.md>).',
      texts: {'/p/lib/chat_screen.dart': _lines(10, 'screen line')},
    );
    _tapSpan(tester, 'the screen');
    await tester.pumpAndSettle();
    final tab = _active(panel, session)!;
    expect(tab.path, '/p/lib/chat_screen.dart');
    expect(tab.request.range, const FileLineRange(4, 6));
    expect(find.text('screen line 5'), findsOneWidget);

    _tapSpan(tester, 'notes');
    await tester.pumpAndSettle();
    expect(_active(panel, session)!.path, '/p/docs/release notes.md');
  });

  testWidgets('inline code naming a file is a link once the file is known '
      'to be there; other code is not', (tester) async {
    final (:panel, :session) = await _pumpReply(
      tester,
      'The entry point is `lib/main.dart:12`; `lib/missing.dart` is gone, '
      'and `setState()` is code.',
      texts: {'/p/lib/main.dart': _main},
    );
    expect(_span(tester, 'lib/missing.dart')?.recognizer, isNull);
    expect(_span(tester, 'setState()')?.recognizer, isNull);
    _tapSpan(tester, 'lib/main.dart:12');
    await tester.pumpAndSettle();
    final tab = _active(panel, session)!;
    expect(tab.path, '/p/lib/main.dart');
    expect(tab.request.range, const FileLineRange(12));
  });

  testWidgets('files outside the project do not open; web links stay the '
      'browser\'s', (tester) async {
    final (:panel, :session) = await _pumpReply(
      tester,
      '[secrets](../outside/key.pem), [passwd](/etc/passwd), '
      '`/etc/hosts` and [the site](https://baocode.dev).',
      texts: {'/etc/hosts': 'x', '/outside/key.pem': 'x'},
    );
    expect(_span(tester, 'secrets')?.recognizer, isNull);
    expect(_span(tester, 'passwd')?.recognizer, isNull);
    expect(_span(tester, '/etc/hosts')?.recognizer, isNull);
    // The web link keeps its own (the browser's), which no file takes.
    expect(_span(tester, 'the site')?.recognizer, isA<TapGestureRecognizer>());
    final scope = tester.element(find.byType(MarkdownView));
    expect(
      FileOpenScope.maybeOf(scope)!.linkRecognizer('https://baocode.dev'),
      isNull,
    );
    expect(panel.shown, isFalse);
    expect(_active(panel, session), isNull);
  });

  testWidgets('a read outside the project is not a link', (tester) async {
    final panel = AgentSidePanel();
    addTearDown(panel.dispose);
    final existence = FileExistence(null);
    addTearDown(existence.dispose);
    final opened = <FileOpenRequest>[];
    await tester.pumpWidget(
      _app(
        FileOpenScope(
          root: '/p',
          onOpen: opened.add,
          existence: existence,
          child: const Column(
            children: [
              ToolCallRow(
                kind: ToolKind.read,
                target: 'passwd',
                path: '/etc/passwd',
              ),
              ToolCallRow(
                kind: ToolKind.read,
                target: 'a.dart',
                path: '/p/a.dart',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ToolCallRow).first);
    expect(opened, isEmpty);
    await tester.tap(find.byType(ToolCallRow).last);
    expect([for (final request in opened) request.path], ['/p/a.dart']);
  });

  testWidgets('the side panel is toggled from the title bar, and kept shown '
      'and as wide as dragged between runs', (tester) async {
    final store = MemoryPreferenceStore();
    await pumpLoaded(tester, preferences: store);
    expect(find.byType(AgentSidePanelView), findsNothing);
    await tester.tap(find.byType(SidePanelToggle));
    await tester.pumpAndSettle();
    expect(find.byType(AgentSidePanelView), findsOneWidget);
    expect(store.preferences['sidePanel'], {
      'shown': true,
      'width': AgentSidePanel.defaultWidth,
    });

    await tester.drag(
      find.byKey(const ValueKey('side-panel-sash')),
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(AgentSidePanelView)).width,
      AgentSidePanel.defaultWidth + 100,
    );
    expect(
      (store.preferences['sidePanel']! as Map)['width'],
      AgentSidePanel.defaultWidth + 100,
    );

    // The next run.
    await tester.pumpWidget(const SizedBox());
    await pumpLoaded(
      tester,
      preferences: MemoryPreferenceStore({
        'sidePanel': {'shown': true, 'width': 520.0},
      }),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AgentSidePanelView)).width, 520);

    await tester.tap(find.byType(SidePanelToggle));
    await tester.pumpAndSettle();
    expect(find.byType(AgentSidePanelView), findsNothing);
  });

  testWidgets('Toggle Side Panel\'s keys, as upstream\'s secondary side '
      'bar\'s: Ctrl+Alt+B, ⌥⌘B on macOS', (tester) async {
    await pumpLoaded(tester);
    final meta = defaultTargetPlatform == TargetPlatform.macOS;
    await press(
      tester,
      LogicalKeyboardKey.keyB,
      alt: true,
      meta: meta,
      control: !meta,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AgentSidePanelView), findsOneWidget);
    await press(
      tester,
      LogicalKeyboardKey.keyB,
      alt: true,
      meta: meta,
      control: !meta,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AgentSidePanelView), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

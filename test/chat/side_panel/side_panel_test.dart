import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:bao_markdown/bao_markdown.dart';
import 'package:bao_editor/monaco/flutter/diff_editor.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';

import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/chat/composer/file_drop.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/side_panel/file_edit.dart';
import 'package:baocode/chat/side_panel/file_link.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/side_panel/file_preview.dart';
import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:baocode/chat/chat_column.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/chat/widgets/edit_step.dart';
import 'package:baocode/chat/widgets/fold_line.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/chat/widgets/tool_call_row.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/git/ide_git_commit_panel.dart';
import 'package:baocode/ide/git/commit_message.dart';
import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/git/ide_git_log_view.dart';
import 'package:baocode/ide/ide_code_diff.dart';
import 'package:baocode/ide/ide_code_editor.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/ide/ide_tab_bar.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_service.dart';
import 'package:baocode/ide/terminal/terminal_view.dart';
import 'package:baocode/ide/tab_strip_scroll.dart';
import 'package:baocode/chat/side_panel/terminal_preview.dart';
import 'package:baocode/chat/panels/activity_strip.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/material_file_icons.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../ide/git/fake_git.dart';
import '../../ide/terminal/fake_pty.dart';
import '../../ide/terminal/fake_terminal.dart';
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
  Future<void> write(String path, String text, {String? expectedText}) async {
    if (texts[path] != expectedText) throw IdeFileConflictException(path);
    texts[path] = text;
  }

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

/// [_Files] that copies files in too (as a paste or a drop does).
class _CopyingFiles extends _Files {
  _CopyingFiles(super.texts);

  final copied = <(String, String)>[];

  @override
  Future<void> copy(String from, String to) async {
    if (texts.containsKey(to)) throw IdeFileExistsException(to);
    copied.add((from, to));
    texts[to] = '';
  }
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
  home: Material(child: home),
);

/// A conversation in `/p` (the mock's turn: a read of lib/main.dart, a
/// search, an edit of it) with the side panel at its right.
Future<({AgentSidePanel panel, ChatSession session, _Files files})> _pumpChat(
  WidgetTester tester, {
  Map<String, String>? texts,
  TerminalService? terminals,
  IdeGitRepository? git,
  IdeCommitMessageModel? commitMessage,
  IdeGitWorktreeChoice Function(IdeGitRepository git)? worktreesOf,
  double titleBarInset = 0,
  Widget? leading,
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
        builder: (context) => AgentSidePanelView(
          notifications: IdeNotifications(),
          panel: panel,
          session: session,
          files: files,
          watchDirectory: (_) => const Stream.empty(),
          terminals: terminals,
          git: git,
          commitMessage: commitMessage,
          worktreesOf: worktreesOf,
          titleBarInset: titleBarInset,
          leading: leading,
        ),
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
        builder: (context) => AgentSidePanelView(
          notifications: IdeNotifications(),
          panel: panel,
          session: session,
          files: files,
        ),
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

/// The shade over the conversations while the panel is over them.
final _scrim = find.byWidgetPredicate(
  (widget) => widget is ColoredBox && widget.color == const Color(0x33000000),
);

/// What gives the window the resize cursor while the panel's edge is
/// dragged.
final _dragCover = find.byWidgetPredicate(
  (widget) =>
      widget is MouseRegion &&
      widget.cursor == SystemMouseCursors.resizeColumn &&
      widget.child == null,
);

SidePanelTab? _active(AgentSidePanel panel, ChatSession session) =>
    panel.tabsOf(session).current;

/// The side panel's editor's text and caret.
TextEditingValue _edited(WidgetTester tester) =>
    tester.widget<IdeCodeEditor>(find.byType(IdeCodeEditor)).controller.value;

/// The terminal a background command's output shows in.
TerminalInstance _previewTerminal(WidgetTester tester) => tester
    .widget<TerminalView>(
      find.descendant(
        of: find.byType(TerminalPreview),
        matching: find.byType(TerminalView),
      ),
    )
    .instance;

/// What that terminal shows, once what was printed is parsed: its lines,
/// wrapped ones joined.
Future<String> _previewScreen(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 20));
  final lines = _previewTerminal(tester).terminal.buffer.lines;
  final text = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final line = lines.get(i)!;
    if (i > 0 && !line.isWrapped) text.write('\n');
    text.write(line.translateToString(true));
  }
  return text.toString().trimRight();
}

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
    expect(await _previewScreen(tester), 'final output');
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
    expect(find.text('test  ·  Failed'), findsOneWidget);
    expect(find.textContaining('Output unavailable:'), findsOneWidget);
    expect(await _previewScreen(tester), 'command failed');
    files.texts['/tmp/missing.output'] = 'recovered output';
    await tester.tap(find.byIcon(Codicons.refresh));
    await tester.pumpAndSettle();
    // Not what it showed with more: printed again, on a reset screen.
    expect(await _previewScreen(tester), 'recovered output');
    expect(find.textContaining('Output unavailable:'), findsNothing);
  });

  testWidgets('a background command is colored as in the chat', (tester) async {
    final task = KernelTask(
      id: 'grep',
      description: 'Search',
      kind: KernelTaskKind.command,
      status: CommandStatus.succeeded,
      startedAt: DateTime.now(),
      summary: 'done',
    );
    await tester.pumpWidget(
      _app(
        TerminalPreview(
          task: task,
          command: 'grep -rn "x" .',
          files: _Files({}),
          onStop: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await _previewScreen(tester), '\$ grep -rn "x" .\ndone');
    // In the terminal's own yellow, cyan and magenta, which the chat's are.
    final line = _previewTerminal(tester).xterm.buffer.active.getLine(0)!;
    int? color(int x) {
      final cell = line.getCell(x)!;
      return cell.isFgPalette() ? cell.getFgColor() : null;
    }

    expect([color(2), color(7), color(11), color(15)], [3, 6, 5, null]);
  });

  testWidgets('a running command waits for output, then has only what '
      'it added printed', (tester) async {
    final files = _Files({'/tmp/run.output': ''});
    final task = KernelTask(
      id: 'run',
      description: 'Run',
      kind: KernelTaskKind.command,
      status: CommandStatus.running,
      startedAt: DateTime.now(),
      outputFile: '/tmp/run.output',
    );
    await tester.pumpWidget(
      _app(TerminalPreview(task: task, files: files, onStop: () {})),
    );
    expect(await _previewScreen(tester), 'Waiting for output');
    final printed = <String>[];
    final listening = _previewTerminal(tester).output
        .listen((data) => printed.add(utf8.decode(data)));
    addTearDown(listening.cancel);
    files.texts['/tmp/run.output'] = 'one\n';
    await tester.pump(const Duration(seconds: 1));
    expect(await _previewScreen(tester), 'one');
    files.texts['/tmp/run.output'] = 'one\n\x1b[31mtwo\x1b[0m\n';
    await tester.pump(const Duration(seconds: 1));
    expect(await _previewScreen(tester), 'one\ntwo');
    expect(printed.last, '\x1b[31mtwo\x1b[0m\n');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read-only file rows follow code size and interface size', (
    tester,
  ) async {
    final scale = ValueNotifier(1.0);
    final originalSize = CodeFont.size.value;
    addTearDown(scale.dispose);
    addTearDown(() => CodeFont.size.value = originalSize);
    final files = _Files({'/p/a.dart': 'one\nnew'});

    Future<void> check(FileOpenRequest request) async {
      scale.value = 1;
      CodeFont.size.value = CodeFont.defaultSize;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return SystemTextScale(
              scaler: media.textScaler,
              child: ValueListenableBuilder<double>(
                valueListenable: scale,
                child: child,
                builder: (context, value, child) => MediaQuery(
                  data: media.copyWith(textScaler: TextScaler.linear(value)),
                  child: child!,
                ),
              ),
            );
          },
          home: ValueListenableBuilder<double>(
            valueListenable: CodeFont.size,
            builder: (context, _, _) => Material(
              child: FilePreview(request: request, files: files),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: find.byType(FilePreview),
        matching: find.byType(ListView),
      );
      double lineHeight() => tester.widget<ListView>(list).itemExtent!;
      final initial = lineHeight();
      expect(initial, greaterThan(0));
      expect(MediaQuery.textScalerOf(tester.element(list)).scale(12), 12);

      scale.value = 1.5;
      await tester.pumpAndSettle();
      expect(lineHeight(), closeTo(initial * 1.5, 1e-9));
      expect(MediaQuery.textScalerOf(tester.element(list)).scale(12), 18);

      final zoomed = lineHeight();
      CodeFont.size.value = CodeFont.defaultSize + 6;
      await tester.pumpAndSettle();
      expect(lineHeight(), greaterThan(zoomed * 1.3));
    }

    // Changes asked for, without the text before them: the text.
    await check(const FileOpenRequest('/p/a.dart', diff: true));
  });

  testWidgets('file line numbers stay visible during horizontal scrolling', (
    tester,
  ) async {
    final ascii = 'x' * 175;
    final wide = '汉字' * 75;
    final files = _Files({'/p/a.dart': 'one\n$ascii\n$wide'});

    Future<void> check(FileOpenRequest request) async {
      await tester.pumpWidget(
        _app(FilePreview(request: request, files: files)),
      );
      await tester.pumpAndSettle();
      final horizontal = find.descendant(
        of: find.byType(FilePreview),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      );
      final controller = tester
          .widget<SingleChildScrollView>(horizontal)
          .controller!;
      expect(controller.position.maxScrollExtent, greaterThan(200));
      final wideText = find.text(wide);
      final painter = TextPainter(
        text: TextSpan(text: wide, style: tester.widget<Text>(wideText).style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(tester.element(wideText)),
      )..layout();
      expect(
        controller.position.maxScrollExtent +
            controller.position.viewportDimension,
        greaterThan(painter.width + 40),
      );
      final renderedWidth = painter.width;
      painter.dispose();
      final number = find.text('1').first;
      final before = tester.getTopLeft(number).dx;
      final textBefore = tester.getTopLeft(find.text('one')).dx;

      controller.jumpTo(200);
      await tester.pump();
      expect(tester.getTopLeft(number).dx, closeTo(before, 0.1));
      expect(
        tester.getTopLeft(find.text('one')).dx,
        lessThan(textBefore - 190),
      );
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(tester.getTopLeft(number).dx, closeTo(before, 0.1));
      expect(
        tester.getTopLeft(wideText).dx + renderedWidth,
        lessThan(tester.getTopRight(horizontal).dx),
      );
    }

    await check(const FileOpenRequest('/p/a.dart', diff: true));
  });

  testWidgets('short preview lines do not create horizontal overflow', (
    tester,
  ) async {
    final glyph = TextPainter(
      text: TextSpan(text: 'x', style: AppFonts.codeStyle(12)),
      textDirection: TextDirection.ltr,
    )..layout();
    final line = 'x' * ((500 - 90) / glyph.width).floor();
    glyph.dispose();
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 500,
            height: 300,
            child: FilePreview(
              request: const FileOpenRequest('/p/a.dart', diff: true),
              files: _Files({'/p/a.dart': line}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final horizontal = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    final controller = tester
        .widget<SingleChildScrollView>(horizontal)
        .controller!;
    expect(controller.position.maxScrollExtent, 0);
  });

  testWidgets('lines selected and copied keep the empty ones between', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    addTearDown(CopiedCode.clear);
    await tester.pumpWidget(
      _app(
        FilePreview(
          request: const FileOpenRequest('/p/a.dart', diff: true),
          files: _Files({'/p/a.dart': 'one\n\ntwo\n\n\nthree'}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final from = tester.getTopLeft(find.text('one')) - const Offset(1, -4);
    final to = tester.getTopRight(find.text('three')) + const Offset(1, 4);
    final drag = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await drag.moveTo(to);
    await tester.pump();
    await drag.up();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(copied, 'one\n\ntwo\n\n\nthree');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a diff shows in the IDE\'s diff editor; its lines copied '
      'paste into the composer as a reference to them', (tester) async {
    addTearDown(CopiedCode.clear);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      _app(
        FilePreview(
          request: FileOpenRequest(
            '/p/a.dart',
            diff: true,
            original: () async => 'one\ntwo\nthree',
          ),
          files: _Files({'/p/a.dart': 'one\nTWO\nthree'}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DiffEditor), findsOneWidget);
    final surface = find.byType(EditorSurface).last;
    await tester.tap(surface);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(copied, 'one\nTWO\nthree');
    final reference = CopiedCode.matching(copied!);
    expect(
      (reference?.path, reference?.start, reference?.end),
      ('/p/a.dart', 1, 3),
    );
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
    panel.openTerminal(first, 'bash-2');
    expect(panel.tabsOf(first).terminals, ['bash-1', 'bash-2']);
    panel.closeTerminal(first, 'bash-2');
    expect(panel.tabsOf(first).terminals, ['bash-1']);
    expect(panel.tabsOf(first).terminal, 'bash-1');
    expect(panel.tabsOf(second).terminals, isEmpty);
  });

  test('files and changes open on their own pages, each with its tabs', () {
    final panel = AgentSidePanel();
    addTearDown(panel.dispose);
    final chat = Object();
    final tabs = panel.tabsOf(chat);
    panel.open(chat, const FileOpenRequest('/p/a.dart'));
    panel.open(chat, const FileOpenRequest('/p/a.dart', diff: true));
    expect(tabs.section, SidePanelSection.changes);
    expect(tabs.files.single.diff, isFalse);
    expect(tabs.diffs.single.diff, isTrue);
    panel.activate(chat, tabs.files.single);
    expect(tabs.section, SidePanelSection.files);
    expect(tabs.current, same(tabs.files.single));
    panel.close(chat, tabs.diffs.single);
    expect(tabs.activeDiff, isNull);
    expect(tabs.active, isNotNull);
  });

  test('the plan opens on a page of its own, there while it is', () {
    final panel = AgentSidePanel();
    addTearDown(panel.dispose);
    final chat = Object();
    final tabs = panel.tabsOf(chat);
    // None yet: the page asked for shows the changes.
    panel.showSection(chat, SidePanelSection.plan);
    expect(tabs.shown, SidePanelSection.changes);

    const plan = '/home/me/.claude/plans/tall.md';
    panel.open(chat, const FileOpenRequest(plan, plan: true));
    expect(panel.shown, isTrue);
    expect(tabs.section, SidePanelSection.plan);
    expect(tabs.current?.path, plan);
    expect(tabs.files, isEmpty);
    // Written again: the same tab, read anew.
    final tab = tabs.plan!;
    panel.open(chat, const FileOpenRequest(plan, plan: true));
    expect(tabs.plan, same(tab));
    expect(tab.reveal, 1);

    panel.closeCurrent(chat);
    expect(tabs.plan, isNull);
    expect(tabs.section, SidePanelSection.changes);
    expect(panel.shown, isTrue);
  });

  testWidgets('the plan\'s page has no list; its tab\'s menu opens it on the '
      'files page', (tester) async {
    const plan = '/home/me/.claude/plans/tall.md';
    final (:panel, :session, files: _) = await _pumpChat(
      tester,
      texts: {'/p/lib/main.dart': _main, plan: '# Grow the input\n\n1. Do it'},
    );
    await tester.pumpAndSettle();
    expect(find.text('Plan'), findsNothing);

    panel.open(session, const FileOpenRequest(plan, plan: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(SidePanelSection.plan)), findsOneWidget);
    expect(find.byKey(const ValueKey('side-panel-list')), findsNothing);
    expect(find.byKey(const ValueKey('side-panel-list-toggle')), findsNothing);
    expect(find.byType(FilePreview), findsOneWidget);
    expect(find.text('Grow the input', findRichText: true), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(TabStripScroll),
        matching: find.text('tall.md'),
      ),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in Files'));
    await tester.pumpAndSettle();
    final tabs = panel.tabsOf(session);
    expect(tabs.section, SidePanelSection.files);
    expect(tabs.active?.path, plan);
    expect(tabs.active?.request.plan, isFalse);
    // The plan's page stays, to go back to.
    expect(tabs.plan?.path, plan);
    expect(find.byKey(const ValueKey('side-panel-list')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey(SidePanelSection.plan)));
    await tester.pumpAndSettle();
    expect(tabs.section, SidePanelSection.plan);
  });

  testWidgets('the rail counts what the pages\' bar counts: the changes, the '
      'commands running', (tester) async {
    final fake = FakeGit('/p')
      ..status =
          '## main...origin/main\x00'
          ' M lib/main.dart\x00'
          '?? notes.md\x00';
    final git = fake.repository();
    addTearDown(git.dispose);
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SidePanelRail(
              onSelect: (_) {},
              session: session,
              gits: [git],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rail = find.byKey(const ValueKey('side-panel-rail'));
    expect(find.descendant(of: rail, matching: find.text('2')), findsOneWidget);
    expect(
      find.byKey(const ValueKey(('rail', SidePanelSection.changes))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(('rail', SidePanelSection.terminal))),
      findsNothing,
    );

    // Committed, the count goes.
    fake.status = '## main...origin/main\x00';
    await git.refresh(force: true);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey(('rail', SidePanelSection.changes))),
      findsNothing,
    );
  });

  testWidgets('the terminal rail badge counts running background commands', (
    tester,
  ) async {
    final (:session, :cli) = await pumpScripted(tester);
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.topLeft,
          child: SidePanelRail(onSelect: (_) {}, session: session),
        ),
      ),
    );
    await tester.pump();

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
    final badge = ValueKey(('rail', SidePanelSection.terminal));
    expect(find.byKey(badge), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(badge), matching: find.text('2')),
      findsOneWidget,
    );

    cli.push({
      'type': 'system',
      'subtype': 'task_notification',
      'task_id': 'one',
      'status': 'completed',
      'output_file': '/tmp/one.output',
      'summary': 'done',
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.descendant(of: find.byKey(badge), matching: find.text('1')),
      findsOneWidget,
    );

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
    expect(find.byKey(badge), findsNothing);
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

  testWidgets('the files page lists the project as the IDE\'s explorer; a '
      'file opens in a tab beside it', (tester) async {
    final (:panel, :session, files: _) = await _pumpChat(
      tester,
      texts: {'/p/a.dart': 'alpha', '/p/b.dart': 'beta'},
    );
    panel.showSection(session, SidePanelSection.files);
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('side-panel-list'));
    expect(
      find.descendant(of: list, matching: find.byType(IdeExplorer)),
      findsOneWidget,
    );
    expect(find.text('Select a file to preview it'), findsOneWidget);
    await tester.tap(find.descendant(of: list, matching: find.text('b.dart')));
    await tester.pumpAndSettle();
    expect(_active(panel, session)!.path, '/p/b.dart');
    expect(_edited(tester).text, 'beta');

    // The list hides, and comes back as wide as dragged.
    final width = tester.getSize(list).width;
    await tester.drag(
      find.byKey(const ValueKey('side-panel-list-sash')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(list).width, width + 40);
    await tester.tap(find.byKey(const ValueKey('side-panel-list-toggle')));
    await tester.pumpAndSettle();
    expect(list, findsNothing);
    expect(panel.listShown, isFalse);
    expect(find.byType(FilePreview), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('side-panel-list-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(list).width, width + 40);

    // A file the conversation opens shows alone, the list out of the way
    // (not kept so); asked for, the list is back.
    panel.open(session, const FileOpenRequest('/p/a.dart'), listAway: true);
    await tester.pumpAndSettle();
    expect(list, findsNothing);
    expect(panel.toJson()['listShown'], isTrue);
    await tester.tap(find.byKey(const ValueKey('side-panel-list-toggle')));
    await tester.pumpAndSettle();
    expect(list, findsOneWidget);
    panel.open(session, const FileOpenRequest('/p/b.dart'), listAway: true);
    await tester.pumpAndSettle();
    expect(list, findsNothing);
    panel.showSection(session, SidePanelSection.files);
    await tester.pumpAndSettle();
    expect(list, findsOneWidget);
  });

  testWidgets('the changes page lists the local changes as JetBrains IDEs '
      'do, and opens their diffs against HEAD and the index', (tester) async {
    final fake = FakeGit('/p')
      ..status =
          '## main\x00'
          'M  lib/staged.dart\x00'
          ' M lib/main.dart\x00'
          '?? notes.md\x00'
      ..show['HEAD:lib/main.dart'] = 'head one\nmain line 2\n'
      ..show['HEAD:lib/staged.dart'] = 'before staging\n'
      ..show[':lib/staged.dart'] = 'staged text\n';
    final git = fake.repository();
    addTearDown(git.dispose);
    final (:panel, :session, files: _) = await _pumpChat(
      tester,
      git: git,
      texts: {
        '/p/lib/main.dart': 'main line 1\nmain line 2\n',
        '/p/lib/staged.dart': 'on disk\n',
        '/p/notes.md': 'note\n',
      },
    );
    panel.showSection(session, SidePanelSection.changes);
    await tester.pumpAndSettle();
    final list = find.byType(IdeGitCommitPanel);
    Color? colorOf(String name) => tester
        .widget<IdeResourceLabel>(
          find.descendant(
            of: list,
            matching: find.byWidgetPredicate(
              (widget) => widget is IdeResourceLabel && widget.name == name,
            ),
          ),
        )
        .nameColor;
    for (final group in ['Changes', 'Unversioned Files']) {
      expect(
        find.descendant(of: list, matching: find.text(group)),
        findsOneWidget,
      );
    }
    expect(colorOf('staged.dart'), IdeGitStatus.indexModified.color);
    expect(colorOf('main.dart'), IdeGitStatus.modified.color);
    expect(colorOf('notes.md'), IdeGitStatus.untracked.color);

    // The count of changes in the page's tab, in a badge as high as the
    // panel title's, not stretched to the bar's.
    final badges = find.byWidgetPredicate(
      (widget) => widget is IdeTitleBadge && widget.count == 3,
    );
    expect(badges, findsOneWidget);
    for (final badge in badges.evaluate()) {
      final size = tester.getSize(
        find.descendant(
          of: find.byWidget(badge.widget),
          matching: find.byType(Container),
        ),
      );
      expect(size.height, 16);
      expect(size.width, lessThan(32));
      expect(
        find.descendant(
          of: find.byWidget(badge.widget),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
    }

    // A row's menu puts its file in the composer; dragged there, so does
    // another.
    Finder row(String name) => find.descendant(
      of: list,
      matching: find.byWidgetPredicate(
        (widget) => widget is IdeResourceLabel && widget.name == name,
      ),
    );
    await tester.tap(row('notes.md'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Chat'));
    await tester.pumpAndSettle();
    final composer = find.byType(ChatComposer);
    String composed() => composerShownText(
      tester
          .widget<MarkdownEditor>(
            find.descendant(
              of: composer,
              matching: find.byType(MarkdownEditor),
            ),
          )
          .controller
          .text,
    );
    expect(composed(), '\uFFFC ');
    final drag = await tester.startGesture(
      tester.getCenter(row('staged.dart')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final target = tester.getCenter(composer);
    await drag.moveTo(target - const Offset(0, 10));
    await tester.pump();
    await drag.moveTo(target);
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(composed(), contains('\uFFFC \uFFFC'));

    // The working tree's change: HEAD against the file.
    await tester.tap(
      find.descendant(of: list, matching: find.text('main.dart')),
    );
    await tester.pumpAndSettle();
    final preview = find.byType(FilePreview);
    (String, String) compared() {
      final diff = tester.widget<IdeCodeDiff>(
        find.descendant(of: preview, matching: find.byType(IdeCodeDiff)),
      );
      return (diff.original, diff.modified);
    }

    expect(compared(), (
      'head one\nmain line 2\n',
      'main line 1\nmain line 2\n',
    ));
    // The staged one: HEAD against the index, not the file.
    await tester.tap(
      find.descendant(of: list, matching: find.text('staged.dart')),
    );
    await tester.pumpAndSettle();
    expect(compared(), ('before staging\n', 'staged text\n'));
    expect(panel.tabsOf(session).diffs, hasLength(2));

    // Not grouped by directory: each file with its folder, and the panel
    // remembers it.
    await tester.tap(
      find.descendant(of: list, matching: find.byIcon(Codicons.listFlat)),
    );
    await tester.pumpAndSettle();
    expect(panel.changesAsTree, isFalse);
    final main = tester.widget<IdeResourceLabel>(
      find.descendant(
        of: list,
        matching: find.byWidgetPredicate(
          (widget) => widget is IdeResourceLabel && widget.name == 'main.dart',
        ),
      ),
    );
    expect(main.description, 'lib');

    // A tab's menu closes the others.
    await tester.tap(
      find.descendant(
        of: find.byType(TabStripScroll),
        matching: find.text('staged.dart'),
      ),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Others'));
    await tester.pumpAndSettle();
    expect(
      [for (final tab in panel.tabsOf(session).diffs) tab.path],
      ['/p/lib/staged.dart'],
    );

    // An unversioned file's menu adds it to Git.
    await tester.tap(row('notes.md'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to VCS'));
    await tester.pumpAndSettle();
    expect(fake.callsTo('add').single, contains('notes.md'));
  });

  testWidgets('a changed folder\'s menu puts it in the chat, reveals it and '
      'copies its path; a click folds it; a file\'s menu opens it too', (
    tester,
  ) async {
    final fake = FakeGit('/p')
      ..status =
          '## main\x00'
          ' M lib/a/main.dart\x00'
          ' M lib/a/util.dart\x00';
    final git = fake.repository();
    addTearDown(git.dispose);
    final (:panel, :session, files: _) = await _pumpChat(
      tester,
      git: git,
      texts: {'/p/lib/a/main.dart': 'main\n', '/p/lib/a/util.dart': 'util\n'},
    );
    panel.showSection(session, SidePanelSection.changes);
    await tester.pumpAndSettle();
    final list = find.byType(IdeGitCommitPanel);
    Finder row(String name) => find.descendant(
      of: list,
      matching: find.byWidgetPredicate(
        (widget) => widget is IdeResourceLabel && widget.name == name,
      ),
    );

    await tester.tap(row('lib/a'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    for (final item in [
      'Rollback…',
      'Add to Chat',
      'Reveal in Files',
      'Copy Path',
      'Copy Relative Path',
    ]) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.tap(row('lib/a'));
    await tester.pumpAndSettle();
    expect(row('main.dart'), findsNothing);

    await tester.tap(row('lib/a'));
    await tester.pumpAndSettle();
    expect(row('main.dart'), findsOneWidget);

    // The folder itself, not its files.
    await tester.tap(row('lib/a'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Chat'));
    await tester.pumpAndSettle();
    final composed = tester
        .widget<MarkdownEditor>(
          find.descendant(
            of: find.byType(ChatComposer),
            matching: find.byType(MarkdownEditor),
          ),
        )
        .controller
        .text;
    expect(composed, contains('lib/a'));
    expect(composed, isNot(contains('main.dart')));

    await tester.tap(row('main.dart'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    for (final item in [
      'Show Diff',
      'Jump to Source',
      'Add to Chat',
      'Reveal in Files',
      'Copy Path',
      'Copy Relative Path',
    ]) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
  });

  testWidgets('the changes page is the Git log: a commit tapped shows its '
      'files, and a file its changes in the log\'s place', (tester) async {
    final fake = FakeGit('/p')
      ..status = '## main\x00 M lib/main.dart\x00'
      ..log =
          '${gitLogRecord('c2', ['c1'], 'Second', refs: 'HEAD -> refs/heads/main')}\n'
          '${gitLogRecord('c1', [], 'First')}';
    fake.refs['HEAD'] = 'c2';
    fake.show['c2'] = 'M\x00lib/main.dart\x00';
    fake.show['c1:lib/main.dart'] = 'first\n';
    fake.show['c2:lib/main.dart'] = 'second\n';
    final git = fake.repository();
    addTearDown(git.dispose);
    final (:panel, :session, files: _) = await _pumpChat(
      tester,
      git: git,
      texts: {'/p/lib/main.dart': 'main\n'},
    );
    panel.showSection(session, SidePanelSection.changes);
    await tester.pumpAndSettle();
    // The local changes first, selected: their commit box and groups.
    expect(find.text('Local Changes (1)'), findsOneWidget);
    expect(find.byType(IdeGitCommitPanel), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);

    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    expect(find.text('commit: c2'), findsOneWidget);
    final file = find.byWidgetPredicate(
      (widget) => widget is IdeResourceLabel && widget.name == 'main.dart',
    );
    await tester.tap(file.last);
    await tester.pumpAndSettle();
    final tab = panel.tabsOf(session).activeDiff!;
    expect(tab.path, '/p/lib/main.dart');
    expect(tab.request.readOnly, isTrue);
    final diff = tester.widget<IdeCodeDiff>(
      find.descendant(
        of: find.byType(FilePreview),
        matching: find.byType(IdeCodeDiff),
      ),
    );
    expect((diff.original, diff.modified), ('first\n', 'second\n'));

    // Back to the log, the change's tab kept.
    await tester.tap(find.byTooltip('Back to Log'));
    await tester.pumpAndSettle();
    expect(panel.tabsOf(session).activeDiff, isNull);
    expect(panel.tabsOf(session).diffs, hasLength(1));
    // In the table, and as the message of the commit still selected.
    expect(find.text('Second'), findsNWidgets(2));
  });

  testWidgets('in a worktree where the agent works: its name, its branch '
      'marked, the others to pick from', (tester) async {
    final fake = FakeGit('/p-wt')
      ..status = '## feature\x00 M lib/main.dart\x00'
      ..worktrees =
          'worktree /p\nHEAD ${'1' * 40}\nbranch refs/heads/main\n\n'
          'worktree /p-wt\nHEAD ${'2' * 40}\nbranch refs/heads/feature\n'
      ..log =
          '${gitLogRecord('c2', ['c1'], 'Second', refs: 'HEAD -> refs/heads/feature')}\n'
          '${gitLogRecord('c1', [], 'First', refs: 'refs/heads/main')}';
    fake.refs['HEAD'] = 'c2';
    final git = fake.repository();
    addTearDown(git.dispose);
    final picked = <String?>[];
    final (:panel, :session, files: _) = await _pumpChat(
      tester,
      git: git,
      texts: {'/p-wt/lib/main.dart': 'main\n'},
      worktreesOf: (_) => IdeGitWorktreeChoice(
        agentPath: '/p-wt/lib/main.dart',
        onSelect: picked.add,
      ),
    );
    panel.showSection(session, SidePanelSection.changes);
    await tester.pumpAndSettle();
    // Which worktree's changes, the agent's.
    expect(
      find.textContaining('p-wt · feature', findRichText: true),
      findsOneWidget,
    );
    expect(find.byTooltip('The agent works here'), findsWidgets);
    // main is checked out in the other.
    expect(find.byTooltip('Checked out in worktree p\n/p'), findsOneWidget);

    await tester.tap(find.text('p-wt'));
    await tester.pumpAndSettle();
    expect(find.text('Follow the Agent'), findsOneWidget);
    expect(find.text('p-wt  ✦ AI'), findsOneWidget);
    await tester.tap(find.text('p  (main worktree)'));
    await tester.pumpAndSettle();
    expect(picked, ['/p']);
  });

  testWidgets('the changes page commits as JetBrains IDEs do: a message '
      'wanted, written by the sparkle from the files checked, then those '
      'committed', (tester) async {
    final fake = FakeGit('/p')
      ..status =
          '## main\x00'
          'M  lib/staged.dart\x00'
          ' M lib/main.dart\x00'
      ..diff = 'diff --git a/lib/staged.dart b/lib/staged.dart\n+staged\n'
      ..log = '';
    final git = fake.repository();
    addTearDown(git.dispose);
    final prompts = <IdeCommitMessagePrompt>[];
    final (:panel, :session, files: _) = await _pumpChat(
      tester,
      git: git,
      commitMessage: (prompt, {cancel}) async {
        prompts.add(prompt);
        return 'Stage the staged file';
      },
    );
    panel.showSection(session, SidePanelSection.changes);
    await tester.pumpAndSettle();
    expect(find.byType(IdeGitCommitPanel), findsOneWidget);
    // The panel's own title, not the view's.
    expect(find.text('Source Control'), findsNothing);
    final commit = find.descendant(
      of: find.byType(IdeGitCommitPanel),
      matching: find.text('Commit'),
    );

    // No message: said so, nothing committed.
    await tester.tap(commit);
    await tester.pumpAndSettle();
    expect(find.text('Enter a commit message.'), findsOneWidget);
    expect(fake.callsTo('commit'), isEmpty);

    // The sparkle: the checked files' diff against HEAD to the model, its
    // message in.
    await tester.tap(find.byTooltip('Generate Commit Message'));
    await tester.pumpAndSettle();
    expect(prompts.single.user, contains('+staged'));
    expect(
      fake.callsTo('diff').single,
      containsAllInOrder(['HEAD', '--', 'lib/main.dart', 'lib/staged.dart']),
    );
    expect(panel.scmOf(git).message.text, 'Stage the staged file');

    await tester.tap(commit);
    await tester.pumpAndSettle();
    expect(fake.callsTo('commit').single, [
      'commit',
      '--quiet',
      '-m',
      'Stage the staged file',
      '--only',
      '--',
      'lib/main.dart',
      'lib/staged.dart',
    ]);
    expect(panel.scmOf(git).message.text, isEmpty);
  });

  testWidgets('dragging the panel\'s edge past where it goes over the '
      'conversations keeps the panel, and lets the window go', (tester) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    panel.open(session, const FileOpenRequest('/p/lib/main.dart'));
    // Too narrow for the panel beside the conversations: over them.
    tester.view.physicalSize = const Size(600, 800);
    await tester.pumpAndSettle();
    await tester.pump(AgentSidePanelArea.overlayDelay);
    expect(_scrim, findsOneWidget);
    final sash = find.byKey(const ValueKey('side-panel-sash'));
    final drag = await tester.startGesture(tester.getCenter(sash));
    await drag.moveBy(const Offset(-40, 0));
    await tester.pump();
    // The window made wide mid-drag: beside them.
    tester.view.physicalSize = const Size(1600, 800);
    await tester.pump();
    expect(_scrim, findsNothing);
    for (final dx in [-200.0, 300.0]) {
      await drag.moveBy(Offset(dx, 0));
      await tester.pump();
    }
    expect(_dragCover, findsOneWidget);
    await drag.up();
    await tester.pumpAndSettle();
    expect(_dragCover, findsNothing);
    expect(find.byType(FilePreview), findsOneWidget);
  });

  testWidgets('the panel\'s edge follows the pointer from where it shows, '
      'though it was made wider than there is room for', (tester) async {
    final (:panel, session: _, files: _) = await _pumpChat(tester);
    panel.show();
    // Room beside the conversations for 400; made 640, its default.
    tester.view.physicalSize = const Size(
      400 + AgentSidePanelArea.minChat + AgentSidePanelArea.sashWidth,
      800,
    );
    await tester.pumpAndSettle();
    expect(panel.width, AgentSidePanel.defaultWidth);
    final sash = find.byKey(const ValueKey('side-panel-sash'));
    final x = tester.getCenter(sash).dx;
    // Narrower at once, not once the pointer has gone the 240 between.
    await tester.drag(sash, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(tester.getCenter(sash).dx, moreOrLessEquals(x + 100));
    // Back as far as it shows, where it was; no further.
    await tester.drag(sash, const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(tester.getCenter(sash).dx, moreOrLessEquals(x));
    await tester.drag(sash, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(tester.getCenter(sash).dx, moreOrLessEquals(x + 60));
  });

  testWidgets('a room short a while only (the sidebar giving way) does not '
      'put the panel over the conversations', (tester) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    tester.view.physicalSize = const Size(1600, 800);
    panel.show();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(600, 800);
    await tester.pump();
    expect(_scrim, findsNothing);
    tester.view.physicalSize = const Size(1600, 800);
    await tester.pump();
    expect(_scrim, findsNothing);
    await tester.pumpAndSettle();
    expect(_scrim, findsNothing);

    // Narrowing frame by frame, as the sidebar's animation gives way, then
    // wide enough: never over them.
    for (final width in [500.0, 560.0, 600.0, 620.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_scrim, findsNothing);
    }
    tester.view.physicalSize = const Size(1600, 800);
    await tester.pump(AgentSidePanelArea.overlayDelay * 2);
    expect(_scrim, findsNothing);

    // Short for longer: over them.
    tester.view.physicalSize = const Size(600, 800);
    await tester.pump();
    expect(_scrim, findsNothing);
    await tester.pump(AgentSidePanelArea.overlayDelay);
    expect(_scrim, findsOneWidget);
  });

  testWidgets('moved to the conversations\' left: its page, tab and width '
      'kept, its edge toward them dragged; kept for the next run (#145)', (
    tester,
  ) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    panel.open(session, const FileOpenRequest('/p/lib/main.dart'));
    await tester.pumpAndSettle();
    final width = tester.getSize(find.byType(AgentSidePanelView)).width;
    expect(tester.getTopRight(find.byType(AgentSidePanelView)).dx, 1600);

    await tester.tap(find.byKey(const ValueKey('side-panel-move')));
    await tester.pumpAndSettle();
    expect(panel.atLeft, isTrue);
    final view = find.byType(AgentSidePanelView);
    expect(tester.getTopLeft(view).dx, 0);
    expect(tester.getSize(view).width, width);
    expect(find.byType(FilePreview), findsOneWidget);
    // The conversations at its right, up to the sash's line.
    expect(tester.getTopLeft(find.byType(ChatScreen)).dx, width + 1);

    // Its right edge dragged right: wider.
    final sash = find.byKey(const ValueKey('side-panel-sash'));
    expect(tester.getTopLeft(sash).dx, width);
    await tester.drag(sash, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(panel.width, closeTo(width + 100, 1));

    final kept = AgentSidePanel(state: panel.toJson());
    addTearDown(kept.dispose);
    expect(kept.atLeft, isTrue);

    panel.atLeft = false;
    await tester.pumpAndSettle();
    expect(tester.getTopRight(view).dx, 1600);
    expect(panel.toJson(), isNot(contains('atLeft')));
  });

  testWidgets('at the window\'s top left, its tabs clear of the traffic '
      'lights, the sidebar\'s toggle by them (#227)', (tester) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    panel
      ..atLeft = true
      ..open(session, const FileOpenRequest('/p/lib/main.dart'));
    await tester.pumpAndSettle();
    final files = tester.getTopLeft(find.text('Files')).dx;

    // The sidebar's toggle by them, the tabs after it.
    const toggle = ValueKey('sidebar-toggle');
    final (panel: inset, session: insetSession, files: _) = await _pumpChat(
      tester,
      titleBarInset: 78,
      leading: const SizedBox(key: toggle, width: 22, height: 22),
    );
    inset
      ..atLeft = true
      ..open(insetSession, const FileOpenRequest('/p/lib/main.dart'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(toggle)).dx, 78);
    expect(tester.getTopLeft(find.text('Files')).dx, files + 78 + 22 + 6);
  });

  testWidgets('hidden at their left, its rail is at the conversations\' top '
      'left, their column clear of it', (tester) async {
    _bigWindow(tester);
    final panel = AgentSidePanel()..atLeft = true;
    addTearDown(panel.dispose);
    const rail = SizedBox(key: ValueKey('my-rail'), width: 28, height: 80);
    await tester.pumpWidget(
      _app(
        AgentSidePanelArea(
          panel: panel,
          railTop: 40,
          rail: rail,
          builder: (context) => const SizedBox(),
          child: const SizedBox.expand(),
        ),
      ),
    );
    final at = tester.getTopLeft(find.byKey(const ValueKey('my-rail')));
    expect(at, const Offset(AgentSidePanelArea.railRight, 40));
    final inset = tester.widget<ChatColumnInset>(find.byType(ChatColumnInset));
    expect((inset.left, inset.right), (AgentSidePanelArea.railInset, 0));

    panel.atLeft = false;
    await tester.pump();
    expect(
      tester.getTopRight(find.byKey(const ValueKey('my-rail'))).dx,
      1600 - AgentSidePanelArea.railRight,
    );
  });

  testWidgets('where the panel is too wide beside the conversations, it is '
      'narrower beside them rather than over them', (tester) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    tester.view.physicalSize = const Size(900, 800);
    panel.show();
    await tester.pumpAndSettle();
    expect(_scrim, findsNothing);
    expect(
      tester.getSize(find.byType(AgentSidePanelView)).width,
      900 - AgentSidePanelArea.minChat - AgentSidePanelArea.sashWidth,
    );
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
              notifications: IdeNotifications(),
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
      // The first's tool call is known: its command shows over its output.
      cli.push({
        'type': 'assistant',
        'parent_tool_use_id': null,
        'message': {
          'id': 'msg-toolu-one',
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': 'toolu-one',
              'name': 'Bash',
              'input': {
                'command': 'sleep 120 && echo one',
                'description': 'command one',
                'run_in_background': true,
              },
            },
          ],
        },
      });
      for (final id in ['one', 'two']) {
        cli.push({
          'type': 'system',
          'subtype': 'task_started',
          'task_id': id,
          'task_type': 'local_bash',
          'is_backgrounded': true,
          'description': 'command $id',
          'output_file': '/tmp/$id.output',
          if (id == 'one') 'tool_use_id': 'toolu-one',
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
      expect(
        await _previewScreen(tester),
        '\$ sleep 120 && echo one\nfirst output',
      );
      files.texts['/tmp/one.output'] = 'first output\nnew output';
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
        await _previewScreen(tester),
        '\$ sleep 120 && echo one\nfirst output\nnew output',
      );
      // Each command is a row of the list; its output opens in a tab.
      final list = find.byKey(const ValueKey('side-panel-terminals'));
      expect(
        find.descendant(of: list, matching: find.text('Background Tasks')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: list, matching: find.text('command two')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(panel.tabsOf(session).terminals, ['one', 'two']);
      // Its command not known, its output alone.
      expect(await _previewScreen(tester), 'second output');
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
      expect(find.text('command two  ·  Completed'), findsOneWidget);
      expect(session.terminalTasks, hasLength(2));
      expect(session.tasks!.map((task) => task.id), ['one']);
      expect(
        find.descendant(of: preview, matching: find.byIcon(Codicons.debugStop)),
        findsNothing,
      );
      panel.closeTerminal(session, 'two');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(await _previewScreen(tester), contains('first output'));
      panel.hide();
      await tester.pump();
      expect(find.byType(SidePanelRail), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the terminal page lists the project\'s terminals beside the '
      'background tasks; each opens in a tab', (tester) async {
    final started = <FakePty>[];
    final terminals = TerminalService(
      root: '/p',
      backend: fakeTerminalBackend(started),
    );
    addTearDown(terminals.dispose);
    final (:panel, :session, files: _) = await _pumpChat(
      tester,
      terminals: terminals,
    );
    panel.showSection(session, SidePanelSection.terminal);
    await tester.pump();
    final list = find.byKey(const ValueKey('side-panel-terminals'));
    for (final group in ['Terminals', 'Background Tasks']) {
      expect(
        find.descendant(of: list, matching: find.text(group)),
        findsOneWidget,
      );
    }

    await tester.tap(find.byKey(const ValueKey('terminal-tabs-new')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('terminal-tabs-new')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final [first, second] = terminals.instances;
    expect(started, hasLength(2));
    expect(panel.tabsOf(session).terminals, [first, second]);
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).instance,
      second,
    );

    // A row of the list brings its terminal to the front.
    Finder row(TerminalInstance shell) =>
        find.descendant(of: list, matching: find.byKey(ObjectKey(shell)));
    await tester.tap(row(first));
    await tester.pump();
    expect(panel.tabsOf(session).terminal, first);
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).instance,
      first,
    );

    // Its tab closes and it runs on, in the list; killed, it is gone.
    panel.closeTerminal(session, first);
    await tester.pump();
    expect(terminals.instances, [first, second]);
    expect(
      tester.widget<TerminalView>(find.byType(TerminalView)).instance,
      second,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(row(second)));
    await tester.pump();
    await tester.tap(
      find.descendant(of: row(second), matching: find.byIcon(Codicons.trash)),
    );
    await tester.pump();
    expect(terminals.instances, [first]);
    expect(find.byType(TerminalView), findsNothing);
    expect(
      find.text('Select a background task to see its output'),
      findsOneWidget,
    );
  });

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
      expect(
        tester.widget<IdeEditorTab>(find.byKey(ValueKey(section))).active,
        isTrue,
      );
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
    expect(_edited(tester).text, _main);
  });

  testWidgets('an edit opens to its diff in place; the file\'s name over it '
      'shows its changes in the side panel', (tester) async {
    final (:panel, :session, files: _) = await _pumpChat(tester);
    final edit = find.byType(EditStep).last;
    await tester.tap(
      find.descendant(of: edit, matching: find.byType(RichText)).first,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<EditStep>(edit).expanded, isTrue);
    expect(_active(panel, session), isNull);

    await tester.tap(
      find.descendant(of: edit, matching: find.byType(FileIcon)),
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
    expect(tester.widget<EditStep>(edit).expanded, isTrue);
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
    final model = tester
        .widget<DiffEditor>(
          find.descendant(
            of: find.byType(FilePreview),
            matching: find.byType(DiffEditor),
          ),
        )
        .model;
    expect(model.originalSnapshot?.text, 'one\ntwo\nthree\n');
    expect(model.modified.text, 'one\nTWO\nthree\n');
    expect(
      [
        for (final change in model.mappings!)
          (change.original.startLineNumber, change.modified.startLineNumber),
      ],
      [(2, 2)],
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

  testWidgets('a file is edited in the side panel: its tab marks it unsaved, '
      'keeps the edit behind another, and Ctrl+S saves it', (tester) async {
    final (:panel, :session, :files) = await _pumpChat(
      tester,
      texts: {'/p/a.dart': 'alpha', '/p/b.dart': 'beta'},
    );
    panel.open(session, const FileOpenRequest('/p/a.dart'));
    await tester.pumpAndSettle();
    final tab = _active(panel, session)!;
    final dot = find.descendant(
      of: find.byType(TabStripScroll),
      matching: find.byIcon(Codicons.circleFilled),
    );
    await tester.tap(find.byType(IdeCodeEditor));
    await tester.pump();
    tester.widget<IdeCodeEditor>(find.byType(IdeCodeEditor)).controller
      ..selectAll()
      ..replaceSelection('alpha!');
    await tester.pump();
    expect(tab.dirty, isTrue);

    // Behind another tab, the edit is kept, and marked.
    panel.open(session, const FileOpenRequest('/p/b.dart'));
    await tester.pumpAndSettle();
    expect(dot, findsOneWidget);
    panel.activate(session, tab);
    await tester.pumpAndSettle();
    expect(_edited(tester).text, 'alpha!');

    await tester.tap(find.byType(IdeCodeEditor));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(files.texts['/p/a.dart'], 'alpha!');
    expect(tab.dirty, isFalse);
    expect(dot, findsNothing);
  });

  testWidgets('a file changed on disk since it was read is not saved over; '
      'closing its tab asks to save it', (tester) async {
    final (:panel, :session, :files) = await _pumpChat(
      tester,
      texts: {'/p/a.dart': 'alpha'},
    );
    panel.open(session, const FileOpenRequest('/p/a.dart'));
    await tester.pumpAndSettle();
    final tab = _active(panel, session)!;
    tester.widget<IdeCodeEditor>(find.byType(IdeCodeEditor)).controller
      ..selectAll()
      ..replaceSelection('mine');
    await tester.pump();
    files.texts['/p/a.dart'] = 'theirs';

    final close = find.descendant(
      of: find.byType(TabStripScroll),
      matching: find.byIcon(Codicons.close),
    );
    // Unsaved: a dot in place of its Close, there while hovered.
    expect(close, findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(
      location: tester.getCenter(
        find.descendant(
          of: find.byType(TabStripScroll),
          matching: find.text('a.dart'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(
      find.text('Do you want to save the changes you made to a.dart?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // Not saved over theirs: open still, saying why.
    expect(files.texts['/p/a.dart'], 'theirs');
    expect(_active(panel, session), same(tab));
    expect(find.textContaining('changed on disk'), findsOneWidget);

    await tester.tap(close);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't Save"));
    await tester.pumpAndSettle();
    expect(_active(panel, session), isNull);
    expect(files.texts['/p/a.dart'], 'theirs');
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
    expect(find.text('Select a file to preview it'), findsOneWidget);
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
    // The caret at the lines' start.
    final edited = _edited(tester);
    expect(edited.selection.baseOffset, edited.text.indexOf('screen line 4'));

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
      'listWidth': AgentSidePanel.defaultListWidth,
      'listShown': true,
      'changesAsTree': true,
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

  testWidgets(
    '⌘W (Ctrl+W elsewhere) closes the side panel\'s tab in '
    'front while the focus is in it, then the panel',
    (tester) async {
      await pumpLoaded(tester);
      final meta = defaultTargetPlatform == TargetPlatform.macOS;
      Future<void> closeKey() async {
        await press(
          tester,
          LogicalKeyboardKey.keyW,
          meta: meta,
          control: !meta,
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byType(SidePanelToggle));
      await tester.pumpAndSettle();
      final view = tester.widget<AgentSidePanelView>(
        find.byType(AgentSidePanelView),
      );
      final (panel, session) = (view.panel, view.session);
      panel
        ..open(session, const FileOpenRequest('/p/a.dart'))
        ..open(session, const FileOpenRequest('/p/b.dart'));
      await tester.pumpAndSettle();
      List<String> open() => [
        for (final tab in panel.tabsOf(session).files) p.basename(tab.path),
      ];

      // The focus elsewhere, the key is not the panel's.
      expect(panel.focusNode.hasFocus, isFalse);
      await closeKey();
      expect(open(), ['a.dart', 'b.dart']);

      // A click in the panel puts the focus there: its tab in front closes,
      // then the next, then the panel.
      await tester.tap(
        find.descendant(
          of: find.byType(TabStripScroll),
          matching: find.text('b.dart'),
        ),
      );
      await tester.pumpAndSettle();
      expect(panel.focusNode.hasFocus, isTrue);
      await closeKey();
      expect(open(), ['a.dart']);
      await closeKey();
      expect(open(), isEmpty);
      expect(find.byType(AgentSidePanelView), findsOneWidget);
      await closeKey();
      expect(find.byType(AgentSidePanelView), findsNothing);
    },
    variant: TargetPlatformVariant(const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'hidden, the panel leaves its rail over the conversation\'s '
    'top right: the conversation, its title bar and scrollbar, reach the '
    'edge; its column keeps clear of the rail',
    (tester) async {
      final workspace = await pumpLoaded(tester);
      await tester.pumpAndSettle();
      expect(find.byType(SidePanelRail), findsNothing);

      final existing = workspace.threads.firstWhere(
        (thread) => thread.record != null,
      );
      workspace.select(existing);
      await tester.pumpAndSettle();
      final chat = tester.getRect(find.byType(ChatScreen));
      final rail = tester.getRect(find.byType(SidePanelRail));
      final composer = tester.getRect(find.byType(ChatComposer));
      expect(chat.right, 1400);
      expect(rail.right, 1400 - AgentSidePanelArea.railRight);
      expect(composer.right, lessThan(rail.left));
      // Room enough: the column in the middle, as without the rail.
      expect(composer.center.dx, closeTo(chat.center.dx, 0.5));
      // Just under the conversation's title bar; at the top under
      // Windows' header.
      expect(
        rail.top - chat.top,
        defaultTargetPlatform == TargetPlatform.windows
            ? 12
            : AppMetrics.titleBarHeight + 4,
      );

      // A narrow window has no room to spare: no rail.
      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpAndSettle();
      expect(find.byType(SidePanelRail), findsNothing);
    },
    variant: TargetPlatformVariant(const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  test('closing the tab in front on the terminal page closes its terminal\'s '
      'or command\'s tab', () {
    final panel = AgentSidePanel();
    addTearDown(panel.dispose);
    final chat = Object();
    panel
      ..openTerminal(chat, 'one')
      ..openTerminal(chat, 'two')
      ..closeCurrent(chat);
    expect(panel.tabsOf(chat).terminals, ['one']);
    expect(panel.tabsOf(chat).terminal, 'one');
    panel.closeCurrent(chat);
    expect(panel.tabsOf(chat).terminals, isEmpty);
    expect(panel.shown, isTrue);
    panel.closeCurrent(chat);
    expect(panel.shown, isFalse);
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

  testWidgets('a markdown file is edited in its preview, as it shows, and '
      'saved with ⌘S; only shown, it is not', (tester) async {
    _bigWindow(tester);
    final files = _Files({'/p/notes.md': '# Notes\n\nhello\n'});
    SidePanelFileEdit? edit;
    await tester.pumpWidget(
      _app(
        FilePreview(
          request: const FileOpenRequest('/p/notes.md'),
          files: files,
          onEdit: (made) => edit = made,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preview = find.byType(MarkdownEditor);
    expect(tester.widget<MarkdownEditor>(preview).readOnly, isFalse);
    // Its text is the edit's: no other to keep in step.
    final controller = tester.widget<MarkdownEditor>(preview).controller;
    expect(controller.text, edit!.controller.document.text);

    tester.widget<MarkdownEditor>(preview).focusNode!.requestFocus();
    controller.selection = const TextSelection.collapsed(offset: 14);
    await tester.pump();
    final told = tester
        .state<MarkdownEditorState>(preview)
        .currentTextEditingValue!;
    final at = told.selection.extentOffset;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: told.text.replaceRange(at, at, ' world'),
        selection: TextSelection.collapsed(offset: at + 6),
      ),
    );
    await tester.pump();
    expect(edit!.controller.document.text, '# Notes\n\nhello world\n');
    expect(edit!.dirty, isTrue);
    expect(files.texts['/p/notes.md'], '# Notes\n\nhello\n');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(files.texts['/p/notes.md'], '# Notes\n\nhello world\n');
    expect(edit!.dirty, isFalse);

    // Its source, the same text, a click away.
    await tester.tap(find.text('Source'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownEditor), findsNothing);
    expect(find.byType(IdeCodeEditor), findsOneWidget);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    // Only shown (a revision's): not edited.
    await tester.pumpWidget(
      _app(
        FilePreview(
          key: const ValueKey('shown'),
          request: const FileOpenRequest('/p/notes.md', readOnly: true),
          files: files,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<MarkdownEditor>(preview).readOnly, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a markdown file\'s changes, the text before not known, show '
      'it rendered as it is', (tester) async {
    _bigWindow(tester);
    await tester.pumpWidget(
      _app(
        FilePreview(
          request: const FileOpenRequest('/p/notes.md', diff: true),
          files: _Files({'/p/notes.md': '# Notes\n\nhello\n'}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preview = find.byType(MarkdownEditor);
    expect(preview, findsOneWidget);
    expect(tester.widget<MarkdownEditor>(preview).readOnly, isTrue);

    // Its source a click away.
    await tester.tap(find.text('Source'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownEditor), findsNothing);
  });

  testWidgets('a markdown file\'s changes (Git\'s) show it rendered as it is '
      'after them, the changes a click away; a deleted one\'s, the '
      'changes', (tester) async {
    _bigWindow(tester);
    await tester.pumpWidget(
      _app(
        FilePreview(
          request: FileOpenRequest(
            '/p/notes.md',
            diff: true,
            original: () async => '# Notes\n\nbefore\n',
            readOnly: true,
          ),
          files: _Files({'/p/notes.md': '# Notes\n\nafter\n'}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preview = find.byType(MarkdownEditor);
    expect(preview, findsOneWidget);
    expect(tester.widget<MarkdownEditor>(preview).readOnly, isTrue);
    expect(
      tester.widget<MarkdownEditor>(preview).controller.text,
      '# Notes\n\nafter\n',
    );
    expect(find.byType(IdeCodeDiff), findsNothing);

    await tester.tap(find.text('Changes'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownEditor), findsNothing);
    expect(find.byType(IdeCodeDiff), findsOneWidget);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownEditor), findsOneWidget);

    await tester.pumpWidget(
      _app(
        FilePreview(
          key: const ValueKey('deleted'),
          request: FileOpenRequest(
            '/p/gone.md',
            diff: true,
            original: () async => '# Gone\n',
            readOnly: true,
          ),
          files: _Files({}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownEditor), findsNothing);
    expect(find.byType(IdeCodeDiff), findsOneWidget);
  });

  testWidgets('files dropped on a markdown file\'s preview are copied '
      'beside it and linked to, where they are let go', (tester) async {
    _bigWindow(tester);
    const text = '# Notes\n\nSome text here.\n';
    final files = _CopyingFiles({'/p/docs/notes.md': text});
    SidePanelFileEdit? edit;
    await tester.pumpWidget(
      _app(
        FilePreview(
          request: const FileOpenRequest('/p/docs/notes.md'),
          files: files,
          root: '/p',
          onEdit: (made) => edit = made,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shot = File(
      p.join(Directory.systemTemp.createTempSync('drop').path, 'shot.png'),
    )..writeAsBytesSync([1, 2, 3]);
    final region = tester.renderObject<RenderFileDropRegion>(
      find.byType(FileDropRegion).first,
    );
    final at = tester.getCenter(find.byType(MarkdownEditor));
    // Its size read from the disk.
    await tester.runAsync(() async {
      region.delegate.fileDrop(at, [ComposerFile(shot.path)]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(files.copied, [(shot.path, '/p/docs/shot.png')]);
    expect(edit!.controller.document.text, contains('![](shot.png)'));
  });

  testWidgets('a mark put on in the preview (at both ends) is one step '
      'Undo takes back whole', (tester) async {
    _bigWindow(tester);
    const text = '# Notes\n\nSome text here.\n';
    final files = _Files({'/p/notes.md': text});
    SidePanelFileEdit? edit;
    await tester.pumpWidget(
      _app(
        FilePreview(
          request: const FileOpenRequest('/p/notes.md'),
          files: files,
          onEdit: (made) => edit = made,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preview = find.byType(MarkdownEditor);
    final controller = tester.widget<MarkdownEditor>(preview).controller;
    tester.widget<MarkdownEditor>(preview).focusNode!.requestFocus();
    controller.selection = const TextSelection(
      baseOffset: 14,
      extentOffset: 23,
    );
    await tester.pumpAndSettle();

    Future<void> command(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byIcon(Codicons.code));
    await tester.pumpAndSettle();
    expect(edit!.controller.document.text, '# Notes\n\nSome `text here`.\n');
    expect(edit!.dirty, isTrue);
    await command(LogicalKeyboardKey.keyZ);
    expect(edit!.controller.document.text, text);

    await command(LogicalKeyboardKey.keyB);
    expect(edit!.controller.document.text, '# Notes\n\nSome **text here**.\n');
    await command(LogicalKeyboardKey.keyZ);
    expect(edit!.controller.document.text, text);
    expect(edit!.dirty, isFalse);

    // Typed on, a word: one step too, its source's editor told between.
    controller.selection = const TextSelection.collapsed(offset: 14);
    await tester.pump();
    for (final typed in ['a', 'b']) {
      final told = tester
          .state<MarkdownEditorState>(preview)
          .currentTextEditingValue!;
      final at = told.selection.extentOffset;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: told.text.replaceRange(at, at, typed),
          selection: TextSelection.collapsed(offset: at + 1),
        ),
      );
      await tester.pump();
    }
    expect(edit!.controller.document.text, '# Notes\n\nSome abtext here.\n');
    await command(LogicalKeyboardKey.keyZ);
    expect(edit!.controller.document.text, text);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

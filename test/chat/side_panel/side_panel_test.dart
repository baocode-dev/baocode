import 'package:baocode/chat/chat_models.dart';
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
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../workspace/chat_window_keys_test.dart' show press;
import '../../workspace_test.dart' show pumpLoaded;

/// A project's files, in memory.
class _Files implements IdeFileService {
  _Files(this.texts);

  final Map<String, String> texts;
  final List<String> listed = [];

  @override
  Future<String> read(String path, {bool force = false}) async =>
      texts[path] ?? (throw IdeFileNotFoundException(path));

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
    await tester.tap(find.descendant(of: edit, matching: find.byType(RichText)).first);
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
    // The changes, in front.
    expect(find.text('No changes yet'), findsOneWidget);
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

import 'package:bao_remote/claude.dart' show ClaudeHistoryPage, IndexedTurnHit;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_column.dart';
import 'package:baocode/chat/chat_find.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/ide/ide_find_widget.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/theme/app_theme.dart';

import '../kernel_test.dart' show FakeCli;

class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items);

  List<ChatItem> items;

  @override
  int get itemCount => items.length;

  @override
  ChatItem itemAt(int index) => items[index];

  @override
  bool get isStreaming => false;

  @override
  bool get isUnprompted => false;

  @override
  bool get canEditMessages => false;

  @override
  ({int index, ComposerDraft draft})? get editing => null;

  @override
  set editing(({int index, ComposerDraft draft})? value) {}

  @override
  void editMessage(int index, ComposerMessage message, {UserPlace? from}) {}

  @override
  VoidCallback? moveToBackgroundAt(int index) => null;

  @override
  VoidCallback? stopAt(int index) => null;
}

/// Turn [n]: its message, steps that each read and say a word (folded
/// away once done), and its answer.
List<ChatItem> _turn(int n) => [
  UserMessageItem(text: 'Question $n', worked: const Duration(seconds: 65)),
  for (var i = 0; i < 6; i++) ...[
    ToolCallItem(kind: ToolKind.read, target: 't${n}_$i.dart'),
    AssistantTextItem('Turn $n step $i.'),
  ],
  AssistantTextItem('Answer **$n**.'),
];

final _historyKey = GlobalKey();

const _railWidth = 40.0;

Future<void> _pump(
  WidgetTester tester,
  ChatFeed feed, {
  VoidCallback? onClosed,
  Widget? rail,
}) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final history = ChatHistoryView(
    key: _historyKey,
    feed: feed,
    onFindClosed: onClosed,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        // As the side panel's rail floats over the chat's top right.
        body: rail == null
            ? history
            : Stack(
                children: [
                  ChatColumnInset(right: _railWidth + 8, child: history),
                  Positioned(
                    top: 0,
                    right: 0,
                    width: _railWidth,
                    height: 200,
                    child: rail,
                  ),
                ],
              ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _text(String text) => find.textContaining(text, findRichText: true);

/// Whether [finder]'s text is within the history's view.
bool _inView(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final view = tester.getRect(find.byType(ChatHistoryView));
  final rect = tester.getRect(finder.first);
  return rect.top >= view.top && rect.bottom <= view.bottom;
}

void main() {
  test('markdown is searched as it shows', () {
    final text = ChatFind.markdownText(
      '# Title\n\nSome **bold** `code` text<!-- hidden -->\n\n'
      '- one\n- two\n\n```dart\nfoo();\n```',
    );
    expect(text, contains('Title'));
    expect(text, contains('Some bold code text'));
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('hidden')));
    expect(text, contains('foo();'));
    expect(RegExp('one.two').hasMatch(text), isFalse);
  });

  testWidgets('a match folded away in a turn far up is opened and shown', (
    tester,
  ) async {
    await _pump(tester, _Feed([for (var n = 0; n < 30; n++) ..._turn(n)]));
    expect(_text('Turn 3 step 4.'), findsNothing);

    ChatHistoryView.find(_historyKey, query: 'turn 3 step 4');
    await _settle(tester);

    expect(find.byType(IdeFindWidget), findsOneWidget);
    expect(_inView(tester, _text('Turn 3 step 4.')), isTrue);
  });

  testWidgets('steps through the matches, each brought into view', (
    tester,
  ) async {
    await _pump(tester, _Feed([for (var n = 0; n < 30; n++) ..._turn(n)]));
    ChatHistoryView.find(_historyKey);
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'answer');
    await _settle(tester);
    // As the markdown shows: bold without its stars.
    expect(_inView(tester, _text('Answer 0.')), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(_inView(tester, _text('Answer 1.')), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter, platform: 'macos');
    await _settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await _settle(tester);
    expect(_inView(tester, _text('Answer 1.')), isTrue);
  });

  testWidgets('a search shown before the conversation is read back finds '
      'it once there', (tester) async {
    final feed = _Feed([]);
    await _pump(tester, feed);
    ChatHistoryView.find(_historyKey, query: 'turn 3 step 4');
    await tester.pump();
    // Read back as a burst of changes, each turn folding as the next comes.
    for (var n = 0; n < 30; n++) {
      for (final item in _turn(n)) {
        feed.items = [...feed.items, item];
        feed.notifyListeners();
      }
    }
    await _settle(tester);

    expect(_inView(tester, _text('Turn 3 step 4.')), isTrue);
  });

  testWidgets('a long message shows all of it while it holds the match at '
      'hand', (tester) async {
    final long = [for (var i = 0; i < 9; i++) 'Line $i'].join('\n');
    await _pump(
      tester,
      _Feed([UserMessageItem(text: long), AssistantTextItem('Line 8 again.')]),
    );
    double height() =>
        tester.getSize(find.byType(UserMessageBubble).first).height;
    final collapsed = height();

    ChatHistoryView.find(_historyKey, query: 'line 8');
    await _settle(tester);
    expect(height(), greaterThan(collapsed + 50));

    // The next match is the answer's: the message folds back.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(height(), collapsed);
  });

  testWidgets('Escape closes the bar, the focus going on', (tester) async {
    var closed = 0;
    await _pump(tester, _Feed(_turn(0)), onClosed: () => closed++);
    ChatHistoryView.find(_historyKey, query: 'Question');
    await tester.pump();
    expect(find.byType(IdeFindWidget), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(IdeFindWidget), findsNothing);
    expect(closed, 1);
  });

  testWidgets('the bar is over the side panel\'s rail, not under it', (
    tester,
  ) async {
    var railTaps = 0;
    var closed = 0;
    await _pump(
      tester,
      _Feed(_turn(0)),
      onClosed: () => closed++,
      rail: GestureDetector(
        onTap: () => railTaps++,
        child: const ColoredBox(color: Color(0xFF00FF00)),
      ),
    );
    ChatHistoryView.find(_historyKey, query: 'Question');
    await tester.pump();
    final bar = tester.getRect(find.byType(IdeFindWidget));
    final rail = Rect.fromLTWH(1000 - _railWidth, 0, _railWidth, 200);
    expect(bar.overlaps(rail), isTrue);

    // Its keys its own still.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(IdeFindWidget), findsOneWidget);

    // A press where the two meet is the bar's: its close button, there.
    final where = Offset((bar.right + rail.left) / 2, bar.center.dy);
    expect(rail.contains(where) && bar.contains(where), isTrue);
    await tester.tapAt(where);
    await tester.pump();
    expect(railTaps, 0);
    expect(find.byType(IdeFindWidget), findsNothing);
    expect(closed, 1);
  });

  testWidgets('finds and jumps to a match in unloaded earlier history via '
      'the session index', (tester) async {
    List<Map<String, Object?>> rawTurns(int from, int to) => [
      for (var n = from; n <= to; n++) ...[
        {
          'type': 'user',
          'uuid': 'u$n',
          'timestamp': '2026-11-28T10:00:00.000Z',
          'message': {
            'role': 'user',
            'content': n == 2 ? 'Unique obsidian prompt' : 'Question $n',
          },
        },
        {
          'type': 'assistant',
          'uuid': 'a$n',
          'timestamp': '2026-11-28T10:00:05.000Z',
          'message': {
            'id': 'm$n',
            'role': 'assistant',
            'content': [
              {
                'type': 'text',
                'text': 'Answer $n.\n\n${'More of it. ' * 40}',
              },
            ],
          },
        },
      ],
    ];

    String? jumpedUntil;
    late final KernelDescriptor descriptor;
    descriptor = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      create: (context) => ClaudeCodeKernel(
        descriptor,
        context,
        start: (_) async => FakeCli(),
        readHistoryPage: (session, {required turns, before}) async =>
            before == null
            ? ClaudeHistoryPage(rawTurns(11, 15), earlier: 'u11')
            : ClaudeHistoryPage(rawTurns(1, 10)),
        readHistoryUntil: (session, {required turns, before, required until}) async {
          jumpedUntil = until;
          return ClaudeHistoryPage(rawTurns(2, 10), earlier: 'u2');
        },
        searchEarlierHistory:
            (session, patternSource, {required caseSensitive, before}) async {
              final re = RegExp(patternSource, caseSensitive: caseSensitive);
              if (re.hasMatch('Unique obsidian prompt')) {
                return const [IndexedTurnHit(promptUuid: 'u2', occurrences: 1)];
              }
              return const [];
            },
      ),
    );
    final session = ChatSession(
      kernel: descriptor,
      kernels: [descriptor, ...MockKernels.all.skip(1)],
      kernelContext: KernelContext(
        cwd: '/p',
        resume: SessionRecord(
          id: 's_find',
          title: 'find',
          updatedAt: DateTime(2026),
          cwd: '/p',
        ),
      ),
      historyCount: 0,
    );
    addTearDown(session.dispose);

    await _pump(tester, session);
    await tester.pump();
    expect(session.hasEarlierHistory, isTrue);
    expect(_text('Unique obsidian prompt'), findsNothing);

    ChatHistoryView.find(_historyKey, query: 'obsidian');
    await _settle(tester);

    expect(jumpedUntil, 'u2');
    expect(_inView(tester, _text('Unique obsidian prompt')), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}

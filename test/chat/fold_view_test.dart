import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/widgets/fold_line.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// A conversation held in a list, changed by hand.
class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items, {this.streaming = false});

  List<ChatItem> items;
  bool streaming;

  void update(List<ChatItem> next, {required bool streaming}) {
    items = next;
    this.streaming = streaming;
    notifyListeners();
  }

  @override
  int get itemCount => items.length;

  @override
  ChatItem itemAt(int index) => items[index];

  @override
  bool get isStreaming => streaming;

  @override
  bool get canEditMessages => false;

  @override
  ({int index, ComposerDraft draft})? get editing => null;

  @override
  set editing(({int index, ComposerDraft draft})? value) {}

  @override
  void editMessage(int index, ComposerMessage message) {}

  @override
  void cancelQueued(int index) {}

  @override
  VoidCallback? moveToBackgroundAt(int index) => null;

  @override
  VoidCallback? stopAt(int index) => null;
}

const _edit = CodeDiffItem(
  fileName: 'main.dart',
  directory: 'lib',
  lines: [
    DiffLine(DiffLineType.removed, 3, 'old'),
    DiffLine(DiffLineType.added, 3, 'new'),
  ],
);

/// A turn: a thought, a read and a search (a run), words, an edit, one more
/// read, and its answer.
List<ChatItem> _turn({Duration? worked, String words = 'Found it.'}) => [
  UserMessageItem(text: 'Fix the bug', worked: worked),
  const ThinkingItem(text: 'Where is it?', tokens: 4, seconds: 3),
  const ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
  const TerminalItem(command: 'grep -rn foo lib', output: 'lib/a.dart:1'),
  AssistantTextItem(words),
  _edit,
  const ToolCallItem(kind: ToolKind.read, target: 'b.dart'),
  const AssistantTextItem('Done, fixed.'),
];

Future<void> _pump(WidgetTester tester, ChatFeed feed) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ChatHistoryView(feed: feed)),
    ),
  );
  await tester.pump();
}

/// Taps [line] and lets what it opens or closes grow or shrink.
Future<void> _toggle(WidgetTester tester, Finder line) async {
  await tester.tap(line);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _text(String text) => find.textContaining(text, findRichText: true);

void main() {
  testWidgets('a finished turn folds its work before its answer', (
    tester,
  ) async {
    await _pump(tester, _Feed(_turn(worked: const Duration(seconds: 65))));

    expect(_text('Worked for 1m 5s · 1 file +1 -1'), findsOneWidget);
    expect(_text('Done, fixed.'), findsOneWidget);
    expect(_text('Found it.'), findsNothing);
    expect(_text('main.dart'), findsNothing);

    // Open: its words and edit, its run folded on its own.
    await _toggle(tester, find.byType(WorkFoldLine));
    expect(_text('Found it.'), findsOneWidget);
    expect(_text('main.dart'), findsOneWidget);
    expect(_text('b.dart'), findsOneWidget);
    expect(
      _text('Read 1 file, searched 1 pattern · thought 3s'),
      findsOneWidget,
    );
    expect(_text('a.dart'), findsNothing);

    await _toggle(tester, find.byType(StepsFoldLine));
    expect(_text('a.dart'), findsOneWidget);
    expect(_text('grep -rn foo lib'), findsOneWidget);

    await _toggle(tester, find.byType(WorkFoldLine));
    expect(_text('Found it.'), findsNothing);
    expect(_text('a.dart'), findsNothing);
    expect(_text('Done, fixed.'), findsOneWidget);
  });

  testWidgets('a run under way shows the step it is on, then folds', (
    tester,
  ) async {
    final feed = _Feed([
      const UserMessageItem(text: 'Fix the bug'),
      const ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
      const ThinkingItem(text: 'Hm.', tokens: 2, seconds: 2),
      const ToolCallItem(
        kind: ToolKind.grep,
        target: 'needle',
        status: ToolStatus.running,
      ),
      const LiveStatusItem('Planning next move', visible: false),
    ], streaming: true);
    await _pump(tester, feed);
    expect(_text('Read 1 file, searched 1 pattern'), findsOneWidget);
    expect(_text('a.dart'), findsNothing);
    expect(_text('needle'), findsOneWidget);

    // Done: the turn's work folds before its answer.
    feed.update([
      const UserMessageItem(text: 'Fix the bug', worked: Duration(seconds: 9)),
      const ToolCallItem(kind: ToolKind.read, target: 'a.dart'),
      const ThinkingItem(text: 'Hm.', tokens: 2, seconds: 2),
      const ToolCallItem(kind: ToolKind.grep, target: 'needle'),
      const AssistantTextItem('It was the needle.'),
    ], streaming: false);
    await tester.pump();
    expect(_text('Worked for 9s'), findsOneWidget);
    expect(_text('needle'), findsOneWidget, reason: 'in the answer only');
    expect(_text('It was the needle.'), findsOneWidget);
    expect(_text('Read 1 file'), findsNothing);
  });

  testWidgets('a turn ending while the user reads above folds once they '
      'are back at the bottom', (tester) async {
    final long = List.filled(60, 'A line of what was found.').join('\n\n');
    final feed = _Feed([
      ..._turn(words: long).take(7),
      const LiveStatusItem('Planning next move', visible: false),
    ], streaming: true);
    await _pump(tester, feed);
    final list = find.byType(SuperListView);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(list));
    for (var i = 0; i < 40; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -200)));
      await tester.pump();
    }
    expect(_text('Fix the bug'), findsWidgets);

    feed.update(
      _turn(worked: const Duration(seconds: 30), words: long),
      streaming: false,
    );
    await tester.pump();
    expect(_text('Worked for 30s'), findsOneWidget);
    expect(find.byType(StepsFoldLine), findsOneWidget, reason: 'kept open');

    for (var i = 0; i < 80; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 400)));
      await tester.pump();
    }
    await tester.pump();
    expect(_text('Worked for 30s'), findsOneWidget);
    expect(find.byType(StepsFoldLine), findsNothing);
    expect(_text('Done, fixed.'), findsOneWidget);
  });

  testWidgets('copying a fold copies its line', (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pump(tester, _Feed(_turn(worked: const Duration(seconds: 65))));
    await tester.tap(_text('Done, fixed.'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(
      copied,
      'Fix the bug\nWorked for 1m 5s · 1 file +1 -1\nDone, fixed.',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a finished turn\'s reply offers to copy it, a running '
      'one\'s not', (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final feed = _Feed([
      ..._turn(worked: const Duration(seconds: 5)),
      const UserMessageItem(text: 'And now?'),
      const AssistantTextItem('Now **this**.'),
    ]);
    await _pump(tester, feed);
    // The words in a turn are not its reply; its last are.
    expect(find.byIcon(Codicons.copy), findsNWidgets(2));
    await tester.tap(find.byIcon(Codicons.copy).last);
    await tester.pump();
    expect(copied, 'Now **this**.');
    expect(find.byIcon(Codicons.check), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    feed.update([
      ...feed.items,
      const UserMessageItem(text: 'More'),
      const AssistantTextItem('Working on it'),
    ], streaming: true);
    await tester.pump();
    expect(find.byIcon(Codicons.copy), findsNWidgets(2));
    // Nothing forks without a session to copy.
    expect(find.byIcon(Codicons.repoForked), findsNothing);
  });
}

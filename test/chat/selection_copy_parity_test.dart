// What an item copies as, built or not: a copy is of the text that shows
// and selects (as a web page's is), so what an item not built copies as is
// what it does once built.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/edit_detail.dart';
import 'package:baocode/chat/mock_conversation.dart';
import 'package:baocode/chat/selection/chat_selection.dart';
import 'package:baocode/theme/app_theme.dart';

class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items);

  final List<ChatItem> items;

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

/// Each of [items], built, against what it copies as unbuilt: the ones
/// that differ.
Future<List<String>> _mismatches(
  WidgetTester tester,
  List<ChatItem> items,
) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1000, 6000);
  addTearDown(tester.view.reset);
  final feed = _Feed(items);
  addTearDown(feed.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ChatHistoryView(feed: feed)),
    ),
  );
  await tester.pumpAndSettle();
  final controller = tester
      .renderObject<RenderChatSelectionItem>(
        find.byType(ChatSelectionItem).first,
      )
      .controller;
  final mismatches = <String>[];
  for (var index = 0; index < feed.itemCount; index++) {
    // Folded into the line of the steps before it: no row of its own.
    final item = controller.builtItems[index];
    if (item == null) continue;
    final shown = item.text().copy(null, null);
    final plain = controller.plainTextOf(index);
    if (shown != plain) {
      mismatches.add(
        '#$index ${items[index].runtimeType}\n'
        '  shown: ${shown.replaceAll('\n', r'\n')}\n'
        '  plain: ${plain.replaceAll('\n', r'\n')}',
      );
    }
  }
  return mismatches;
}

void main() {
  testWidgets('each item copies unbuilt as the text it shows', (tester) async {
    final mismatches = await _mismatches(tester, [
      for (var i = 0; i < 8; i++) MockConversation.itemAt(i),
      const NoticeItem(NoticeKind.error, 'Something went wrong.'),
      const KernelSwitchItem(
        fromKernel: 'claude-code',
        toKernel: 'antigravity-acp',
      ),
      const UserMessageItem(text: 'And `this` too?'),
      const AgentItem(
        description: 'Look around',
        agentType: 'Explore',
        status: CommandStatus.succeeded,
        result: 'Found it.',
      ),
      const PlanItem(
        path: '',
        round: 2,
        title: 'The plan',
        text: '# The plan\n\nFirst **this**, then that.\n\n- one\n- two',
        status: PlanStatus.approved,
      ),
      const PlanItem(
        path: 'plan.md',
        round: 1,
        title: 'The first plan',
        status: PlanStatus.sentBack,
        feedback: 'Smaller',
      ),
      const TerminalItem(
        command: 'sleep 9',
        output: '',
        status: CommandStatus.running,
        background: true,
      ),
      const ToolCallItem(
        kind: ToolKind.search,
        target: 'flutter selection',
        detail: '4 results',
      ),
    ]);
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });

  testWidgets('a reply copies unbuilt as its markdown shows', (tester) async {
    final mismatches = await _mismatches(tester, [
      const AssistantTextItem('Done.\n\n- one\n- two'),
      const AssistantTextItem(
        '## A heading\n\nSome **bold** and *slanted* text, a '
        '[link](https://example.com) and `code`.\n\n'
        '1. first\n2. second\n   - nested\n\n'
        '- [x] done\n- [ ] not yet\n\n'
        '```dart\nvoid main() {}\n```\n\n'
        '> quoted\n\n'
        '| Name | Count |\n| --- | --- |\n| a | 1 |\n| b | 2 |\n\n'
        '---\n\nLast.',
      ),
    ]);
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });

  testWidgets('a compact edit copies unbuilt as its line', (tester) async {
    EditDetail.current.value = EditDetail.compact;
    addTearDown(() => EditDetail.current.value = EditDetail.card);
    final mismatches = await _mismatches(tester, [
      const UserMessageItem(text: 'Change it'),
      MockConversation.itemAt(5),
    ]);
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });
}

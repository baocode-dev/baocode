import 'chat_models.dart';

/// Deterministic fake history so the virtual list can be arbitrarily long.
abstract final class MockConversation {
  static const itemCount = 100000;
  static const _turnLength = 8;

  /// Appended to every third user message, so some are long.
  static const _longRequest =
      '\n\n具体要求：\n'
      '1. 可见范围改为由 viewport 惰性提供，不再每帧遍历全部 block；\n'
      '2. 展开或折叠思考内容时，只重新测量当前条目；\n'
      '3. 滚动条总长度仍由完整列表决定，拖动时跳转要准确；\n'
      '4. 贴底时新内容追加不能抖动，离开底部后保持阅读位置；\n'
      '5. 跨越长对话的文字选择与复制要保持完整；\n'
      '6. 给以上行为补充 widget 测试，并确保全部通过；\n'
      '7. 改完后简要说明取舍，以及还有哪些已知限制。';

  static const _grepMatches = [
    'lib/main.dart:142',
    'lib/chat/chat_history_view.dart:88',
    'lib/chat/chat_history_view.dart:391',
    'lib/chat/chat_screen.dart:31',
    'test/widget_test.dart:52',
    'README.md:7',
  ];

  static ChatItem itemAt(int index) {
    final turn = index ~/ _turnLength;
    return switch (index % _turnLength) {
      0 => UserMessageItem(
        text:
            '第 ${turn + 1} 轮：列表滚动到很深的位置时会掉帧，帮我看一下 '
            '@lib/main.dart ${turn.isEven ? '和 @pubspec.yaml ' : ''}'
            '里 `SuperListView` 的用法，并把可见范围的计算换成惰性的。'
            '${turn % 3 == 2 ? _longRequest : ''}',
      ),
      1 => ThinkingItem(
        seconds: 3 + turn % 9,
        tokens: 180 + turn % 7 * 53,
        text: '我先估算当前 viewport 的可见范围，再把 block 索引映射为轻量的 widget。\n\n关键点是列表的 itemCount 可以很大，但 build 只会收到当前屏幕附近的 index。展开本身只影响这个条目的高度，滚动条总长度仍然由完整列表决定。',
      ),
      2 => const ToolCallItem(
        kind: ToolKind.read,
        target: 'main.dart',
        detail: 'L1-562',
        path: 'lib/main.dart',
      ),
      3 => ToolCallItem(
        kind: ToolKind.grep,
        target: 'SuperListView',
        detail: '${turn % 5 + 2} results',
        results: _grepMatches.sublist(0, turn % 5 + 2),
      ),
      4 => const AssistantTextItem(
        '问题出在每次滚动都会重新计算完整的可见范围。`calculateRange` 会遍历所有 block，在 100,000 条数据下这是 O(n) 的开销。\n\n我会改成使用 viewport 提供的惰性范围：\n- 只为可视区附近的 index 构建 widget\n- 展开思考只影响当前条目的高度\n- 滚动条总长度仍由完整列表决定',
      ),
      5 => const CodeDiffItem(
        fileName: 'main.dart',
        directory: 'lib',
        lines: [
          DiffLine(
            DiffLineType.context,
            142,
            'itemBuilder: (context, index) {',
          ),
          DiffLine(
            DiffLineType.removed,
            143,
            '  final visibleRange = calculateRange(scrollOffset);',
          ),
          DiffLine(
            DiffLineType.added,
            143,
            '  final visibleRange = viewport.lazyRange(scrollOffset);',
          ),
          DiffLine(
            DiffLineType.added,
            144,
            '  if (!visibleRange.contains(index)) return const SizedBox.shrink();',
          ),
          DiffLine(
            DiffLineType.context,
            145,
            '  return buildOnly(visibleRange, itemCount: 100000);',
          ),
          DiffLine(DiffLineType.context, 146, '},'),
        ],
      ),
      6 => const TerminalItem(
        command: 'flutter test',
        output: '00:03 +4: loading test/widget_test.dart\n00:04 +5: All tests passed!',
      ),
      _ => const AssistantTextItem(
        '已完成修改，测试全部通过。现在滚动时只会构建可视区附近的 block，拖动滚动条跳到任意位置也不会卡顿。',
      ),
    };
  }
}

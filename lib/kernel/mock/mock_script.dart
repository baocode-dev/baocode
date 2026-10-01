/// One story both mock kernels tell, each in its own protocol: think, look
/// at the code, ask (or ask leave), edit three files, run the tests, sum up.
abstract final class MockScript {
  /// Waits, in milliseconds, paced to read along.
  static const thinkingDelay = 400;
  static const thinkingChunk = 2;
  static const thinkingChunkMs = 50;
  static const textChunk = 3;
  static const textChunkMs = 16;

  static const thought =
      '用户想调整输入框，先确认需求涉及的文件：{target} 是入口，'
      '输入框本身在 composer 目录下，由 ChatComposer 管理编辑器、菜单和发送按钮。\n\n'
      '高度策略有几种做法：随内容自动增高、固定行数后滚动、可拖拽调整。'
      '自动增高最符合直觉，但要给一个上限，否则长文本会把历史记录挤没；'
      '固定行数实现最简单，只是短消息也会占着几行空白；'
      '可拖拽调整最灵活，但需要额外的拖拽手柄，还要记住用户调整后的高度。'
      '三种的交互差异不小，而且会影响发送按钮和工具栏的布局，'
      '直接选一种改下去风险偏高。\n\n'
      '快捷输入方面，@ 提及和 / 命令已经有菜单的基础实现，'
      '提及会变成不可拆分的标签，命令只在消息开头生效。'
      '粘贴图片还没有入口，需要额外处理剪贴板里的图片数据，'
      '在 web 上还要考虑浏览器的剪贴板权限。\n\n'
      '另外编辑已发送的消息也复用同一个输入框，改高度策略时要确认'
      '历史记录里的编辑框不会因此跳动。\n\n'
      '先读一下相关代码确认现状，再向用户确认高度策略和需要支持的快捷输入，'
      '避免改完之后返工。';

  static String thoughtFor(String target) =>
      thought.replaceAll('{target}', target);

  static const searchPattern = 'ChatComposer';
  static const searchMatches = [
    'lib/chat/chat_screen.dart:219:                      ChatComposer(',
    'lib/chat/composer/composer.dart:44:class ChatComposer extends StatefulWidget {',
    'test/composer_test.dart:22:import \'package:baocode/chat/composer/composer.dart\';',
  ];

  static const beforeQuestion = '我看了一下相关代码，开始修改之前需要先确认两点：';

  static const questions = [
    (
      question: '输入框的高度策略用哪一种？',
      header: '高度策略',
      options: ['随内容自动增高，最多 8 行', '固定 3 行，超出滚动', '可拖拽调整高度'],
      multiSelect: false,
    ),
    (
      question: '需要支持哪些快捷输入？',
      header: '快捷输入',
      options: ['@ 提及文件', '/ 命令', '粘贴图片'],
      multiSelect: true,
    ),
  ];

  static const plan =
      '计划：\n- 输入框改为随内容增高，最多 8 行后滚动\n- `@` 提及和 `/` 命令沿用现有菜单\n'
      '- 补充 widget 测试';

  static const askAnswer =
      '输入框在 `ChatComposer` 里，高度由 `_minEditorHeight` 和 `_maxEditorLines` 决定：'
      '\n- 空时保持一行半的高度\n- 超过 10 行后在框内滚动';

  /// Each edit: the file, where the hunk starts, and its lines (`+`, `-`
  /// or ` ` first, as in a unified diff).
  static const edits = [
    (
      path: 'lib/chat/composer/composer.dart',
      start: 88,
      lines: [
        ' child: QuillEditor(',
        '-  config: const QuillEditorConfig(),',
        '+  config: QuillEditorConfig(',
        '+    maxHeight: _maxEditorHeight,',
        '+    onKeyPressed: _handleKey,',
        '+  ),',
      ],
    ),
    (
      path: 'lib/chat/chat_screen.dart',
      start: 212,
      lines: [
        ' ChatComposer(',
        '-  key: _composerKey,',
        '+  key: _composerKey,',
        '+  maxLines: 8,',
      ],
    ),
    (
      path: 'test/widget_test.dart',
      start: 40,
      lines: [
        '+testWidgets(\'composer grows with its content\', (tester) async {',
        '+  await pumpScreen(tester);',
        '+});',
      ],
    ),
  ];

  static const testCommand = 'flutter test';
  static const testOutput =
      '00:03 +77: loading test/widget_test.dart\n00:05 +78: All tests passed!';

  /// How long the background test run takes.
  static const testRunMs = 4000;

  static const summary =
      '修改已完成：\n- 输入框使用 `QuillEditor`，随内容增高\n- 支持 `@` 提及和 `/` 命令\n'
      '- 测试正在后台运行，结束后会更新状态';

  static const codexSummary = '修改已完成：\n- 输入框随内容增高，最多 8 行\n- `flutter test` 已通过';

  static const codexDeclined = '好的，先不运行测试。改动已经写入，你可以稍后自己运行 `flutter test`。';

  static const keepPlanning = '好的，我们继续完善计划。';

  /// In Ask: an answer, and changes only suggested.
  static const discussion =
      '输入框的高度现在是固定的：`ChatComposer` 把编辑器包在一个定高的容器里。'
      '要随内容增高，可以改成按行数计算高度，超过上限后内部滚动。'
      '需要的话切到 Agent 模式，我来改。';
}

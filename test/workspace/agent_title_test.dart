import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/workspace/agent_title.dart';

void main() {
  test('images alone are titled after the first with a file name', () {
    ImageAttachment image([String? name]) => ImageAttachment(
      bytes: Uint8List(0),
      mediaType: 'image/png',
      name: name,
    );
    final l10n = englishLocalizations;
    expect(
      agentImageTitle('[Image #1] [Image #2]', [image(), image('b.png')], l10n),
      'Image: b.png',
    );
    expect(agentImageTitle('', [image('a.png')], l10n), 'Image: a.png');
    // Pasted, from no file.
    expect(agentImageTitle('[Image #1]', [image()], l10n), 'Image');
    // The text says more, or there is no image.
    expect(agentImageTitle('[Image #1] why?', [image('a.png')], l10n), isNull);
    expect(agentImageTitle('hi', const [], l10n), isNull);
  });

  test('a reply is cleaned into a title', () {
    expect(cleanAgentTitle('Fix flaky login test'), 'Fix flaky login test');
    expect(cleanAgentTitle('"Fix flaky login test."'), 'Fix flaky login test');
    expect(cleanAgentTitle('**修复登录样式**。'), '修复登录样式');
    expect(cleanAgentTitle('Title: Fix login\n\nBecause…'), 'Fix login');
    expect(cleanAgentTitle('\n# Fix login\n'), 'Fix login');
    expect(cleanAgentTitle('  \n '), isNull);
    final long = cleanAgentTitle('word ' * 40)!;
    expect(long.runes.length, 80);
    expect(long, endsWith('…'));
  });

  test('a title is summed up from the last 5 messages, in order', () {
    expect(
      summaryText(['1', '2', '[Image #1]', '3', '4', '5', '6', '7']),
      '3\n\n4\n\n5\n\n6\n\n7',
    );
    expect(summaryText(['Fix [Image #1] login']), 'Fix  login');
    expect(summaryText(['[Image #1]']), isEmpty);
    // A long one is cut to its share, the others kept.
    final long = summaryText(['a' * 1000, 'short']);
    expect(long, '${'a' * 400}…\n\nshort');
  });

  test('a tool call written out as text is no title', () {
    expect(cleanAgentTitle('<｜DSML｜function_calls>\n<｜DSML｜invoke>'), isNull);
    expect(cleanAgentTitle('<｜DSML｜ calls>'), isNull);
    expect(cleanAgentTitle('<tool_call>\n{"name": "WebFetch"}'), isNull);
    expect(cleanAgentTitle('<|tool_calls_begin|>fetch'), isNull);
    // Angle brackets inside words are kept.
    expect(cleanAgentTitle('重构 <Button> 组件'), '重构 <Button> 组件');
    expect(cleanAgentTitle('Fix a < b || c check'), 'Fix a < b || c check');
  });
}

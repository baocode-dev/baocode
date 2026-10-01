import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/workspace/agent_title.dart';

void main() {
  test('a message is worth a title when it says what it is about', () {
    expect(agentTitleWorthy('Fix the flaky login test'), isTrue);
    expect(agentTitleWorthy('修复登录页面的样式错乱问题'), isTrue);
    expect(agentTitleWorthy('/Users/leo/a.txt is empty, why?'), isTrue);
    // Short enough to be its own title.
    expect(agentTitleWorthy('hi'), isFalse);
    expect(agentTitleWorthy('  continue  '), isFalse);
    // Slash commands.
    expect(agentTitleWorthy('/review the last commit'), isFalse);
    expect(agentTitleWorthy('/plugin:command with arguments'), isFalse);
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
}

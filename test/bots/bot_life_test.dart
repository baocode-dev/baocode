import 'package:baocode/bots/bot_life.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("a timeline's line: when, where, who, the words on one line, cut", () {
    final at = DateTime(2026, 11, 12, 9, 5);
    expect(BotLife.dayFile(at), 'timeline/2026-11-12.md');
    expect(
      BotLife.line(at, '私聊', '板板', '在吗\n  人呢'),
      '- 09:05 [私聊] 板板: 在吗 / 人呢',
    );
    expect(
      BotLife.line(at, 'p', 'w', 'x' * 10, max: 4),
      '- 09:05 [p] w: xxxx…',
    );
    expect(
      BotLife.saysOf(
        '<bot_say>[laughs] 好</bot_say><bot_narrate>笑</bot_narrate>'
        '<bot_say>走</bot_say>',
      ),
      '好 / 走',
    );
  });

  test("a person's notes under their name; how it is now, its first line", () {
    var people = BotLife.withPersonNote('', '板板', '老板，脾气急');
    people = BotLife.withPersonNote(people, '周予', '爱抠口径');
    people = BotLife.withPersonNote(people, '板板', '讨厌刷屏');
    expect(people, '## 板板\n- 老板，脾气急\n- 讨厌刷屏\n\n## 周予\n- 爱抠口径');
    var self = BotLife.withNow('- 喜欢猫', '有点委屈');
    self = BotLife.withNow(self, '好多了');
    expect(self, 'Now: 好多了\n- 喜欢猫');
  });
}

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
}

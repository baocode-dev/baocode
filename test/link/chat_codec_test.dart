import 'dart:convert';
import 'dart:typed_data';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/link/chat_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ToolCallItem roundTrip(ToolCallItem item) =>
      ChatCodec.decode(jsonDecode(jsonEncode(ChatCodec.encode(item))))!
          as ToolCallItem;

  final picture = ImageAttachment(
    bytes: Uint8List.fromList([1, 2, 3]),
    mediaType: 'image/png',
    name: 'cat.png',
  );

  test('a tool\'s pictures go to the phone', () {
    final made = roundTrip(
      ToolCallItem(kind: ToolKind.image, target: 'a cat', images: [picture]),
    );
    expect(made.kind, ToolKind.image);
    expect(made.images.single.bytes, [1, 2, 3]);
    expect(made.images.single.name, 'cat.png');
    // A failed call's do not.
    expect(
      roundTrip(
        ToolCallItem(
          kind: ToolKind.image,
          target: 'a cat',
          status: ToolStatus.failed,
          images: [picture],
        ),
      ).images,
      isEmpty,
    );
  });

  test('pictures under way go with how many and of what shape', () {
    final making = ToolCallItem(
      kind: ToolKind.image,
      target: 'a cat',
      status: ToolStatus.running,
      input: const {
        'prompt': 'a cat on a mat',
        'count': 9,
        'size': '1536x1024',
        'model': '@openai/gpt-image-2',
      },
    );
    expect(ChatCodec.encode(making)['making'], {
      'count': 4,
      'size': '1536x1024',
    });
    // Not the prompt: the step's line says it.
    expect(roundTrip(making).input, {
      'prompt': '',
      'count': 4,
      'size': '1536x1024',
    });
    // Before its input has come: nothing yet.
    expect(
      ChatCodec.encode(
        const ToolCallItem(
          kind: ToolKind.image,
          target: '',
          status: ToolStatus.running,
        ),
      ),
      isNot(contains('making')),
    );
  });

  test('a browser\'s action and a turn\'s spending go too', () {
    final step =
        ChatCodec.decode(
              jsonDecode(
                jsonEncode(
                  ChatCodec.encode(
                    const ToolCallItem(
                      kind: ToolKind.browser,
                      target: 'example.com',
                      tool: 'browser_navigate',
                      input: {
                        'tabId': 3,
                        'url': 'https://example.com/a?token=x',
                      },
                    ),
                  ),
                ),
              ),
            )!
            as ToolCallItem;
    expect(step.tool, 'browser_navigate');
    // What it does, not where: the address is the step's target already.
    expect(step.input, {'url': ''});

    final prompt =
        ChatCodec.decode(
              ChatCodec.encode(
                const UserMessageItem(
                  text: 'go',
                  usage: TurnUsage(
                    inputTokens: 10,
                    outputTokens: 5,
                    costUsd: 0.5,
                  ),
                ),
              ),
            )!
            as UserMessageItem;
    expect(prompt.usage?.totalTokens, 15);
    expect(prompt.usage?.costUsd, 0.5);
    final sent = DateTime(2026, 10, 29, 14, 5);
    expect(
      (ChatCodec.decode(
                jsonDecode(
                  jsonEncode(
                    ChatCodec.encode(UserMessageItem(text: 'hi', sentAt: sent)),
                  ),
                ),
              )!
              as UserMessageItem)
          .sentAt,
      sent,
    );
  });

  group('a bot\'s', () {
    test('cards go to the phone with the agent they open', () {
      final card = roundTrip(
        const ToolCallItem(
          kind: ToolKind.other,
          tool: ChatCodec.botCardTool,
          target: 'Fix the tests',
          input: {'chat': 's-1'},
        ),
      );
      expect(ChatCodec.botCard(card), 's-1');
      expect(card.tool, ChatCodec.botCardTool);
      // Another tool's input is not a card's.
      expect(
        ChatCodec.botCard(
          roundTrip(
            const ToolCallItem(
              kind: ToolKind.other,
              tool: 'bot_read_chat',
              target: 'x',
              input: {'chat': 's-1'},
            ),
          ),
        ),
        isNull,
      );
    });

    test('pictures from the web go as they were sent', () {
      final url = roundTrip(
        const ToolCallItem(
          kind: ToolKind.other,
          tool: ChatCodec.botImageTool,
          target: 'x',
          input: {'url': 'https://example.com/a.png'},
        ),
      );
      expect(ChatCodec.botImageUrl(url), 'https://example.com/a.png');
      // Not one that failed, nor what is no web address.
      for (final item in [
        const ToolCallItem(
          kind: ToolKind.other,
          tool: ChatCodec.botImageTool,
          target: 'x',
          status: ToolStatus.failed,
          input: {'url': 'https://example.com/a.png'},
        ),
        const ToolCallItem(
          kind: ToolKind.other,
          tool: ChatCodec.botImageTool,
          target: 'x',
          input: {'url': 'file:///etc/passwd'},
        ),
      ]) {
        expect(ChatCodec.botImageUrl(roundTrip(item)), isNull);
      }
    });

    test('its messages are its reply\'s bot_say tags, once closed', () {
      final said = ChatCodec.decode(
        ChatCodec.encode(
          const AssistantTextItem(
            'notes <bot_say>哇 终于</bot_say>\n<bot_say> </bot_say>'
            '<bot_say>是 relay\n断线那个吗</bot_say> more <bot_say>还在',
          ),
        ),
      );
      expect(ChatCodec.botSays((said as AssistantTextItem).text), [
        '哇 终于',
        '是 relay\n断线那个吗',
      ]);
      expect(ChatCodec.botSays('Notes to itself.'), isEmpty);
      expect(ChatCodec.botSent(said), isFalse);
    });

    test('its narration, in order among its messages; not one of them', () {
      const text =
          '<bot_narrate>她揉了揉眼睛</bot_narrate>\n<bot_say>在呢</bot_say>'
          '<bot_narrate>把手机凑近了些</bot_say><bot_say>怎么啦</bot_say>'
          '<bot_narrate>还';
      expect(ChatCodec.botParts(text), [
        ('她揉了揉眼睛', true),
        ('在呢', false),
        ('怎么啦', false),
      ]);
      expect(ChatCodec.botSays(text), ['在呢', '怎么啦']);
    });

    test('the user\'s sticker is told by its text', () {
      expect(ChatCodec.sticker(ChatCodec.stickerText('love')), 'love');
      expect(ChatCodec.sticker('[Sticker: love]\n[Image #3]'), 'love');
      expect(ChatCodec.sticker('I [Sticker: love] it'), isNull);
      expect(ChatCodec.sticker('hi'), isNull);
    });

    test('notes from the app are told from the user\'s words', () {
      UserMessageItem user(String text) =>
          ChatCodec.decode(
                jsonDecode(
                  jsonEncode(ChatCodec.encode(UserMessageItem(text: text))),
                ),
              )!
              as UserMessageItem;
      final note = user(
        '<${ChatCodec.botEventTag}>\n- failed: "Build" in monad\n'
        '</${ChatCodec.botEventTag}>',
      );
      expect(ChatCodec.botEvent(note), '- failed: "Build" in monad');
      // With a picture, referred to after it.
      expect(
        ChatCodec.botEvent(
          user(
            '<${ChatCodec.botEventTag}>\nnew picture\n</${ChatCodec.botEventTag}>\n[Image #2]',
          ),
        ),
        'new picture',
      );
      // Taken up with the user's: theirs, without it.
      expect(
        ChatCodec.withoutBotEvents(
          '<${ChatCodec.botEventTag}>\nx\n</${ChatCodec.botEventTag}>\n你好',
        ),
        '你好',
      );
      expect(ChatCodec.botEvent(user('hi <${ChatCodec.botEventTag}>')), isNull);
    });
  });
}

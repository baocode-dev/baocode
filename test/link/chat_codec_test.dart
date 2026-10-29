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

    test('stickers and pictures from the web go as they were sent', () {
      final sticker = roundTrip(
        const ToolCallItem(
          kind: ToolKind.other,
          tool: ChatCodec.botStickerTool,
          target: 'happy',
          input: {'sticker': 'happy'},
        ),
      );
      expect(ChatCodec.botSticker(sticker), 'happy');
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

    test('messages go as it said them', () {
      final said = roundTrip(
        const ToolCallItem(
          kind: ToolKind.other,
          tool: ChatCodec.botSayTool,
          target: '等下 我看看',
          input: {'text': '等下 我看看'},
        ),
      );
      expect(ChatCodec.botSay(said), '等下 我看看');
      expect(ChatCodec.botSent(said), isTrue);
      expect(
        ChatCodec.botSay(
          roundTrip(
            const ToolCallItem(
              kind: ToolKind.other,
              tool: ChatCodec.botSayTool,
              target: 'x',
              status: ToolStatus.failed,
              input: {'text': 'x'},
            ),
          ),
        ),
        isNull,
      );
    });

    test('its own texts show only in a turn it sent nothing in', () {
      const say = ToolCallItem(
        kind: ToolKind.other,
        tool: ChatCodec.botSayTool,
        target: '在',
        input: {'text': '在'},
      );
      const look = ToolCallItem(
        kind: ToolKind.other,
        tool: 'bot_list_chats',
        target: '',
      );
      final items = <ChatItem>[
        const UserMessageItem(text: 'old'),
        const AssistantTextItem('Before it talked so: shown.'),
        const UserMessageItem(text: '在吗'),
        const AssistantTextItem('Notes to itself.'),
        say,
        // What the user wrote meanwhile, waiting: the turn goes on.
        const UserMessageItem(text: '?', queued: true),
        look,
        const AssistantTextItem('Done.'),
        const UserMessageItem(text: 'ok'),
        look,
      ];
      expect(ChatCodec.botQuiet(items.length, (i) => items[i]), {3, 7});
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
      expect(ChatCodec.botEvent(user('hi <${ChatCodec.botEventTag}>')), isNull);
    });
  });
}

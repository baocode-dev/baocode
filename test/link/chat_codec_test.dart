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

  test('why a conversation was compacted goes with its line', () {
    final item =
        ChatCodec.decode(
              jsonDecode(
                jsonEncode(
                  ChatCodec.encode(
                    const NoticeItem(
                      NoticeKind.compaction,
                      'Conversation compacted early',
                      compaction: CompactionNote(
                        auto: true,
                        tooLong: true,
                        before: 253000,
                        window: 500000,
                      ),
                    ),
                  ),
                ),
              ),
            )!
            as NoticeItem;
    expect(item.text, 'Conversation compacted early');
    final note = item.compaction!;
    expect((note.auto, note.tooLong), (true, true));
    expect((note.before, note.after, note.window), (253000, null, 500000));
  });

  test('conversations handed work go by the ids the phone knows', () {
    String phone(String id) => 'phone-$id';
    final step = ChatCodec.encode(
      const ToolCallItem(
        kind: ToolKind.other,
        target: 's1',
        tool: 'session_send',
        input: {'session': 's1', 'text': ' fix the login '},
      ),
      session: phone,
    );
    expect(step['sessions'], ['phone-s1']);
    expect(step['handed'], 'fix the login');
    expect(
      ChatCodec.encode(
        const ToolCallItem(
          kind: ToolKind.other,
          target: 'Login',
          tool: 'session_new',
          output: 'Started: s2 in app, on Sonnet 5.',
        ),
        session: phone,
      )['sessions'],
      ['phone-s2'],
    );
    expect(
      ChatCodec.encode(
        const UserMessageItem(
          text: 'done',
          fromAgent: 'Login',
          fromSession: 's2',
        ),
        session: phone,
      ),
      allOf(
        containsPair('agent', 'Login'),
        containsPair('agentSession', 'phone-s2'),
      ),
    );
    // Not another tool's.
    expect(
      ChatCodec.encode(
        const ToolCallItem(
          kind: ToolKind.read,
          target: 'a',
          input: {'text': 'x'},
        ),
      ),
      isNot(contains('sessions')),
    );
  });

  group('a bot\'s', () {
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
        (ChatCodec.botNarrateTag, '她揉了揉眼睛'),
        (ChatCodec.botSayTag, '在呢'),
        (ChatCodec.botSayTag, '怎么啦'),
      ]);
      expect(ChatCodec.botSays(text), ['在呢', '怎么啦']);
    });

    test('how its words sound, cued for them read aloud, not shown', () {
      const text =
          '<bot_narrate>[softly] 她笑了</bot_narrate>'
          '<bot_say>[laughs] 真的假的 [whispers]别告诉别人</bot_say>'
          '<bot_say>[sighs]</bot_say><bot_say>[Image #3]</bot_say>';
      expect(ChatCodec.botParts(text).first.$2, '[softly] 她笑了');
      expect(ChatCodec.botSays(text), ['真的假的 别告诉别人', '[Image #3]']);
      expect(ChatCodec.withoutVoiceCues('[softly] 她笑了'), '她笑了');
    });

    test('what it suggests the user say next: not among what it shows', () {
      const text =
          '<bot_say>早点睡</bot_say><bot_suggest>嗯晚安</bot_suggest>'
          '<bot_suggest> 再聊会 </bot_suggest><bot_suggest>你也';
      expect(ChatCodec.botParts(text), [(ChatCodec.botSayTag, '早点睡')]);
      expect(ChatCodec.botSuggestions(text), ['嗯晚安', '再聊会']);
    });

    test('the agents it shows, by their ids, among its messages', () {
      const text =
          '<bot_say>就一个在跑</bot_say>\n<bot_show_chat> s-1 </bot_show_chat>'
          '<bot_say>好了叫你</bot_say><bot_show_chat>s-2';
      expect(ChatCodec.botParts(text), [
        (ChatCodec.botSayTag, '就一个在跑'),
        (ChatCodec.botCardTag, 's-1'),
        (ChatCodec.botSayTag, '好了叫你'),
      ]);
      expect(ChatCodec.botSays(text), ['就一个在跑', '好了叫你']);
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

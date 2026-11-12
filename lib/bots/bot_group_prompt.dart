import 'package:bao_link/bao_link.dart' show linkGroupPasses;

import '../link/chat_codec.dart';
import 'bot.dart';

/// A group chat of the user and some of their bots: its [members] by
/// their ids, as they joined; [names], the names they had in it, those
/// gone from it too, for what they said there. Its conversation passed
/// on at most [passes] times after each of the user's messages (0, as
/// many as the bots like); each bot handed it waiting [gap] seconds
/// before it answers.
class BotGroup {
  const BotGroup({
    required this.id,
    required this.name,
    required this.members,
    this.created,
    this.names = const {},
    this.passes = linkGroupPasses,
    this.rules = '',
    this.gap = 0,
  });

  factory BotGroup.fromJson(Map<String, Object?> json) => BotGroup(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    members: [
      for (final member in (json['members'] as List?) ?? const [])
        if (member is String) member,
    ],
    created: switch (json['created']) {
      final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
      _ => null,
    },
    names: {
      if (json['names'] case final Map<String, Object?> names)
        for (final MapEntry(:key, :value) in names.entries)
          if (value is String) key: value,
    },
    passes: (json['passes'] as num?)?.toInt() ?? linkGroupPasses,
    rules: json['rules'] as String? ?? '',
    gap: (json['gap'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String name;
  final List<String> members;
  final DateTime? created;
  final Map<String, String> names;
  final int passes;

  /// Its rules, as the user (or the assistant) wrote them.
  final String rules;

  /// Seconds a bot handed the conversation by another waits before it
  /// answers: 0, at once.
  final int gap;

  BotGroup copyWith({
    String? name,
    List<String>? members,
    Map<String, String>? names,
    int? passes,
    String? rules,
    int? gap,
  }) => BotGroup(
    id: id,
    name: name ?? this.name,
    members: members ?? this.members,
    created: created,
    names: names ?? this.names,
    passes: passes ?? this.passes,
    rules: rules ?? this.rules,
    gap: gap ?? this.gap,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'members': members,
    'created': ?created?.millisecondsSinceEpoch,
    if (names.isNotEmpty) 'names': names,
    if (passes != linkGroupPasses) 'passes': passes,
    if (rules.isNotEmpty) 'rules': rules,
    if (gap > 0) 'gap': gap,
  };
}

/// One of a group's messages, as a bot is told it: its heading (number,
/// who, when), its lines, the lines of the chat's file it is at, and
/// whether it is new to the bot.
typedef BotGroupMessage = ({
  String heading,
  List<String> lines,
  (int, int) lineRange,
  bool fresh,
});

/// What the bot that has [group]'s conversation is told, plainly enough
/// for a simple model to follow: where it is (a group chat: who is in it,
/// [me] among them, [user] too), the time [now] and when it last looked
/// ([looked]), the latest [messages] (each cut past [longest] characters,
/// the rest in [chat]), how it came to have it ([by]); then what to do,
/// what `<bot_next>` means and when to use it, and that the conversation is
/// in its hands. Whether it may pass it on: [left] times more. Its first
/// line says the group's ([ChatCodec.botGroupOf]).
String botGroupTurn({
  required BotGroup group,
  required String chat,
  required String me,
  required List<String> members,
  required String user,
  required String now,
  String? looked,
  required List<BotGroupMessage> messages,
  int longest = 500,
  required String by,
  required int left,
  bool chinese = false,
}) {
  String shown(BotGroupMessage message) {
    final text = message.lines.join('\n');
    final head = '## ${message.heading}${message.fresh ? ' · new' : ''}';
    if (text.length <= longest) return '$head\n$text';
    return '$head\n${text.substring(0, longest)}… (cut: all of it at lines '
        '${message.lineRange.$1}–${message.lineRange.$2} of the chat\'s file)';
  }

  final first = messages.isEmpty
      ? null
      : messages.first.heading.split(' ').first;
  final last = messages.isEmpty ? null : messages.last.heading.split(' ').first;
  const next = ChatCodec.botNextTag;
  const narrate = ChatCodec.botNarrateTag;
  const say = ChatCodec.botSayTag;
  const ref = ChatCodec.botRefAttribute;
  final names = members.join(', ');
  final rules = group.rules.trim();
  // An example reply, with the last message's number and a member's name.
  final quoted = switch (last) {
    final last? => int.tryParse(last.replaceFirst('#', '')),
    null => null,
  };
  final someone = members.isEmpty ? user : members.first;
  final example = [
    '<$say${quoted == null ? '' : ' $ref="$quoted"'}>'
        '${chinese ? '哈哈 才不是我' : 'Ha, it was not me'}</$say>',
    '<$narrate>${chinese ? '她笑着把手机扣在桌上' : 'She laughs and puts her phone face down'}</$narrate>',
    '<$say>${chinese ? '$someone，你说呢' : '$someone, what do you think?'}</$say>',
    if (left > 0 && members.isNotEmpty) '<$next>$someone</$next>',
  ];
  return [
    '${ChatCodec.botGroupLine(group.id)} The group chat "${group.name}".',
    '',
    'Where you are: a group chat, on your phones. In it: you ($me), $user '
        '(the user)${members.isEmpty ? '' : ', $names'}. Everyone here sees '
        'every message.',
    'Who you are: $me, as always: who you are, how you talk, your own life. '
        'Talk the way you would to these people, in a group. This is people '
        'chatting: never speak of the app, the computer, turns, passing it '
        'on, or being told to answer.',
    if (rules.isNotEmpty) ...[
      "The group's rules, which everyone here keeps to:",
      rules,
    ],
    'Now: $now.${looked == null ? '' : ' You last looked at it: $looked.'}',
    '',
    if (messages.isNotEmpty) ...[
      'The latest messages ($first–$last), the new ones marked:',
      for (final message in messages) shown(message),
      '',
    ],
    'Earlier ones, and all of each: $chat.',
    '',
    'Why you are told now: $by.',
    '',
    'What to do now:',
    '1. Read the new messages. If you have something to say, say it as '
        'yourself: one or two short messages, as in a chat, not a speech. If '
        'you have nothing to say, say nothing.',
    '   Each message in its own <$say>…</$say>. To answer one message in '
        'particular, give its number: <$say $ref="74">…</$say> shows #74 '
        'quoted under yours. Only when it helps to say which one you answer; '
        'most need none.',
    '2. Narration (<$narrate>…</$narrate>: what you do, how you look, where '
        'you are) and pictures (generate_image) reach the group too: everyone '
        'sees them. Use them now and then, when they fit.',
    if (left > 0) ...[
      '3. Then decide who speaks next.',
      '   <$next>name</$next> hands the conversation to one member: they are '
          'told it is their turn, and they answer next. No one sees the tag. '
          'Write one name, as in this list: $names.',
      '   No <$next> means the conversation stops: the group goes quiet, and '
          'no one says anything more until $user speaks again. Only do that '
          'when you really mean it to stop: the topic has come to a natural '
          'end, or what was said is for $user alone to answer.',
      '   Otherwise hand it to whoever would naturally answer now: the one you '
          'spoke to, asked or spoke of; the one $user asked for; the one who '
          'plainly has something to add. Not to $user (they speak when they '
          'like), nor to yourself.',
    ] else
      '3. Hand it to no one now: after you, it is for $user to speak.',
    '',
    'A reply may look like this (the words are only an example; yours are '
        'your own, and most replies are shorter):',
    ...example,
    '',
    'The conversation in this group is in your hands until you hand it on or '
        'stop it. Keep it alive the way a good group chat is: do not let it '
        'die while someone would still answer; do not drag it on once it is '
        'done, nor hand it on just to keep things busy.',
  ].join('\n');
}

/// The bots' world, as their WORLD.md has it: the user ([user]), each of
/// [bots], [groups] with their chats' files. In the user's language
/// ([chinese]) where it is theirs; else plain.
String botWorld({
  required String user,
  required List<Bot> bots,
  required List<({BotGroup group, String chat})> groups,
  bool chinese = false,
}) {
  String nameOf(String id) =>
      bots.where((bot) => bot.id == id).firstOrNull?.name ?? id;
  String firstOf(String text) {
    final line = text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return line.length > 160 ? '${line.substring(0, 160)}…' : line;
  }

  String mayDo(Bot bot) => [
    if (bot.can(BotAbility.agents)) "looks after the user's agents",
    bot.chatOnly ? 'only chats' : 'works on the computer',
    if (bot.can(BotAbility.browser)) 'uses the browser',
  ].join(', ');

  return [
    '# The world',
    '',
    'Kept by the app as it is; read, not written. What is not here, nor in '
        'your files and the chats, did not happen.',
    '',
    '## The user',
    '$user: everyone talks with them from the BaoCode app on their phone; '
        'the app and everyone live on their computer.',
    '',
    '## Everyone',
    for (final bot in bots)
      [
        '- ${bot.name}',
        if (bot.gender.isNotEmpty) ' (${bot.gender})',
        if (bot.assistant) ', the assistant',
        if (bot.signature.isNotEmpty) ' — "${bot.signature}"',
        if (firstOf(bot.identity) case final who when who.isNotEmpty) ': $who',
        ' [${mayDo(bot)}]',
      ].join(),
    '',
    '## Groups',
    if (groups.isEmpty) 'None.',
    for (final (:group, :chat) in groups)
      '- "${group.name}": $user, ${[for (final id in group.members) nameOf(id)].join(', ')}. Its chat: $chat',
    '',
  ].join('\n');
}

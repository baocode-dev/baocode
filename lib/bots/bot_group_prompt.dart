import '../link/chat_codec.dart';
import 'bot.dart';

/// A group chat of the user and some of their bots: its [members] by
/// their ids, as they joined; [names], the names they had in it, those
/// gone from it too, for what they said there.
class BotGroup {
  const BotGroup({
    required this.id,
    required this.name,
    required this.members,
    this.created,
    this.names = const {},
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
  );

  final String id;
  final String name;
  final List<String> members;
  final DateTime? created;
  final Map<String, String> names;

  BotGroup copyWith({
    String? name,
    List<String>? members,
    Map<String, String>? names,
  }) => BotGroup(
    id: id,
    name: name ?? this.name,
    members: members ?? this.members,
    created: created,
    names: names ?? this.names,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'members': members,
    'created': ?created?.millisecondsSinceEpoch,
    if (names.isNotEmpty) 'names': names,
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

/// What the bot that has [group]'s conversation is told: who is in it
/// ([members], [user]), the time [now] and when it last looked ([looked]),
/// the latest [messages] (each cut past [longest] characters, the rest in
/// [chat]), how it came to have it ([by]) and how many times it may still
/// be passed ([left]). Its first line says the group's
/// ([ChatCodec.botGroupOf]).
String botGroupTurn({
  required BotGroup group,
  required String chat,
  required List<String> members,
  required String user,
  required String now,
  String? looked,
  required List<BotGroupMessage> messages,
  int longest = 500,
  required String by,
  required int left,
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
  return [
    '${ChatCodec.botGroupLine(group.id)} The group chat "${group.name}": '
        'you, $user (the user)${members.isEmpty ? '' : ', ${members.join(', ')}'}.',
    'Now: $now.${looked == null ? '' : ' You last looked at it: $looked.'}',
    '',
    if (messages.isNotEmpty) ...[
      'The latest messages ($first–$last), the new ones marked:',
      for (final message in messages) shown(message),
      '',
    ],
    'Earlier ones, and all of each: $chat.',
    '',
    'It is your turn: $by. '
        '${left > 0 ? 'It may be passed $left more times.' : 'It may not be passed on: after you, it is for $user to speak.'}',
    '',
    'The conversation in this group is in your hands now: once you have '
        'spoken, where it goes and who speaks next is yours to decide.',
    '- Say something if you want to, as you would in a group: a message or '
        'two. Or nothing, if you have nothing to say.',
    if (left > 0) ...[
      '- Then think who the conversation needs next: the one asked, the one '
          'who knows this best, the one $user wants to hear from; and pass '
          'it to them, by name: <${ChatCodec.botNextTag}>name</${ChatCodec.botNextTag}>.',
      '- If the topic is done, or it is for $user to speak, pass it to no '
          'one: it stops with you.',
      "Don't let the conversation drop where it shouldn't, and don't pass "
          'it on just to keep things busy.',
    ],
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

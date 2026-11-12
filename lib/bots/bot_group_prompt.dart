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
/// who, when) and its lines, as the chat's file has them.
typedef BotGroupMessage = ({String heading, List<String> lines});

/// The most of the new messages a bot is told with, in characters: past
/// it, the latest that fit, the rest in the file.
const botGroupToldMost = 4000;

/// What the app tells [group]'s bot of messages it has not seen: [from] to
/// [to], the lines of [chat] they are at ([lines]), and themselves
/// ([messages]); who else is in it ([members], [user]); whether it was
/// called on ([called]). [why] it is told now, as the world has it. Its
/// first line says the group's ([ChatCodec.botGroupOf]).
String botGroupWake({
  required BotGroup group,
  required String chat,
  required int from,
  required int to,
  required (int, int) lines,
  required List<BotGroupMessage> messages,
  required List<String> members,
  required String user,
  bool called = false,
  String why = '',
}) {
  final count = to - from + 1;
  final which = count == 1 ? 'message #$from' : 'messages #$from–#$to';
  // The latest that fit.
  final shown = <String>[];
  var size = 0;
  for (final message in messages.reversed) {
    final text = ['## ${message.heading}', ...message.lines].join('\n');
    if (shown.isNotEmpty && size + text.length > botGroupToldMost) break;
    size += text.length;
    shown.insert(0, text);
  }
  final cut = shown.length < messages.length;
  return [
    '${ChatCodec.botGroupLine(group.id)} The group chat "${group.name}": '
        'you, $user (the user)${members.isEmpty ? '' : ', ${members.join(', ')}'}.',
    'New in it: $which.',
    if (cut) '(The earlier of them in the file.)',
    '',
    ...shown,
    '',
    'All of it: $chat (these are lines ${lines.$1}–${lines.$2}). Read what '
        'came before if you need it.',
    'Reply to the group if you have something to say, or end your turn '
        'with nothing.',
    if (called) 'You were called on (@): answer.',
    if (why.isNotEmpty) 'Why you read it now: $why.',
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

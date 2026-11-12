import 'dart:convert';

import '../kernel/claude_code/claude_haiku.dart';
import 'bot.dart';

/// How much the user's message in a group draws each of its bots, and
/// why, by their ids: as a group's attention model has it ([scoreMessage]).
typedef BotPulls = Map<String, ({double pull, String why})>;

/// What the attention model is told: what it does, and how it answers.
String attentionModelSystem({required bool chinese}) =>
    'You score how much a message the user just sent in a group chat draws '
    'the attention of each member (bots, each with a life of its own). For '
    'each, a pull from 0 to 1: 1 when it is for them, by name or plainly, or '
    'for everyone, or something they would want to answer; about 0.5 when '
    'it could interest them; low (0.1 or less) for what is not theirs, or '
    'says little (haha, ok, an emoji) unless it answers what they said. You '
    'decide nothing else: each still decides whether to answer. Reply with '
    'JSON only, no other text: {"pulls": [{"name": "<member>", "pull": '
    '<0-1>, "why": "<a few words, in ${chinese ? 'Chinese' : 'English'}>"}]}';

/// What the attention model is asked of [said], the user's message
/// [seq] in [group] ([user]'s), with [recent] messages before it (each
/// who said it, and what), and [members] (each with who it is).
String attentionModelPrompt({
  required String group,
  required String user,
  required List<Bot> members,
  required List<(String, String)> recent,
  required int seq,
  required String said,
}) {
  String firstOf(String text) {
    final line = text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return line.length > 120 ? '${line.substring(0, 120)}…' : line;
  }

  return [
    'The group "$group": $user (the user) and its members:',
    for (final bot in members)
      '- ${bot.name}${switch (firstOf(bot.identity)) {
        '' => '',
        final who => ': $who',
      }}',
    '',
    if (recent.isNotEmpty) ...[
      'What was said before it, the latest last:',
      for (final (who, text) in recent) '$who: $text',
      '',
    ],
    'The user\'s message (#$seq):',
    said,
  ].join('\n');
}

/// [answer] read: each member's pull, by its id, of [members] (by name);
/// those it leaves out, none. Throws [FormatException] for what is not
/// such an answer.
BotPulls readAttentionAnswer(String answer, List<Bot> members) {
  final start = answer.indexOf('{');
  final end = answer.lastIndexOf('}');
  if (start < 0 || end < start) throw const FormatException('No JSON');
  final json = jsonDecode(answer.substring(start, end + 1));
  final pulls = switch (json) {
    {'pulls': final List pulls} => pulls,
    _ => throw const FormatException('No pulls'),
  };
  final byName = {for (final bot in members) bot.name: bot.id};
  return {
    for (final one in pulls)
      if (one case {'name': final String name, 'pull': final num pull})
        ?byName[name.trim()]: (
          pull: pull.toDouble().clamp(0, 1).toDouble(),
          why: switch (one['why']) {
            final String why => why.trim(),
            _ => '',
          },
        ),
  };
}

/// Asks [model] (a model option's id) how much the user's message [said]
/// draws each of [members]; as [readAttentionAnswer] gives.
Future<BotPulls> scoreMessage({
  required String model,
  required bool chinese,
  required String group,
  required String user,
  required List<Bot> members,
  required List<(String, String)> recent,
  required int seq,
  required String said,
}) async {
  final answer = await askClaudeHaiku(
    attentionModelSystem(chinese: chinese),
    attentionModelPrompt(
      group: group,
      user: user,
      members: members,
      recent: recent,
      seq: seq,
      said: said,
    ),
    model: model == 'haiku' ? null : model,
    exact: true,
  );
  return readAttentionAnswer(answer, members);
}

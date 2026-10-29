import 'dart:convert';

import 'package:path/path.dart' as p;

import 'bot.dart';
import 'bot_pacer.dart' show BotLater;

// What a bot is, kept as plain files in its folder, for a person to read
// and change, and to take to another computer: the folder is the bot.
//
//   bots/
//     USER.md            who the user is (their picture beside it)
//     <id>/
//       BOT.md           its card: a header of `key: value` lines, who it
//                        is below
//       STYLE.md         how it talks
//       MEMORY.md        what it remembers of the user
//       SELF.md          what it noted of itself
//       LATER.md         what it means to come back to, a line each
//       avatar-….png     its picture, if it has one
//
// A bot that works on the computer keeps these itself, with Claude Code's
// Read and Edit; the others through their tools.

abstract final class BotFiles {
  static const card = 'BOT.md';
  static const style = 'STYLE.md';
  static const memory = 'MEMORY.md';
  static const self = 'SELF.md';
  static const later = 'LATER.md';

  /// The user's, in the bots' folder.
  static const user = 'USER.md';

  /// [bot]'s card, BOT.md.
  static String cardText(Bot bot) => writeFrontMatter([
    ('name', bot.name),
    ('avatar', bot.avatar),
    ('gender', bot.gender),
    ('signature', bot.signature),
    for (final ability in shownAbilities) (ability.name, '${bot.can(ability)}'),
    ('model', bot.model),
    if (bot.assistant) ('assistant', 'true'),
    (
      'created',
      switch (bot.created) {
        final at? => _time(at),
        null => null,
      },
    ),
  ], bot.identity);

  /// The abilities a card says yes or no to: those the user turns on.
  static const shownAbilities = [
    BotAbility.agents,
    BotAbility.browser,
    BotAbility.proactive,
  ];

  /// The assistant's, as the app starts it, and for what its card does not
  /// say: all but being told of every agent ([BotAbility.proactive]), a
  /// turn of the model's each, which the user turns on.
  static const assistantAbilities = {BotAbility.agents, BotAbility.browser};

  /// The bot whose card is [card] and style [style], in [folder]; null
  /// for a card without a name.
  static Bot? read(String folder, String card, {String style = ''}) {
    final (:fields, :body) = readFrontMatter(card);
    final name = (fields['name'] ?? '').trim();
    if (name.isEmpty) return null;
    String text(String key) => (fields[key] ?? '').trim();
    final assistant = _yes(fields['assistant']) ?? false;
    return Bot(
      id: p.basename(folder),
      name: name,
      folder: folder,
      avatar: text('avatar').isEmpty ? null : text('avatar'),
      gender: text('gender'),
      signature: text('signature'),
      identity: body.trim(),
      style: style.trim(),
      abilities: {
        for (final ability in shownAbilities)
          // Not said: the assistant's own on, another's off.
          if (_yes(fields[ability.name]) ??
              (assistant && assistantAbilities.contains(ability)))
            ability,
      },
      model: text('model').isEmpty ? null : text('model'),
      assistant: assistant,
      created:
          DateTime.tryParse(text('created')) ?? createdIn(p.basename(folder)),
    );
  }

  /// When a bot named [id] was made, as its id says (`b` and the time in
  /// microseconds, base 36, see Bots); null for one whose does not.
  static DateTime? createdIn(String id) {
    final match = RegExp(r'^b([0-9a-z]+)(?:-\d+)?$').firstMatch(id);
    final micros = match == null ? null : int.tryParse(match[1]!, radix: 36);
    return micros == null ? null : DateTime.fromMicrosecondsSinceEpoch(micros);
  }

  /// Who the user is, USER.md.
  static String userText(BotUser user) => writeFrontMatter([
    ('name', user.name),
    ('gender', user.gender),
    ('signature', user.signature),
    ('picture', user.picture),
  ], '');

  static BotUser readUser(String text) {
    final (:fields, body: _) = readFrontMatter(text);
    String value(String key) => (fields[key] ?? '').trim();
    return BotUser(
      name: value('name'),
      gender: value('gender'),
      signature: value('signature'),
      picture: value('picture').isEmpty ? null : value('picture'),
    );
  }

  /// What a bot means to come back to, LATER.md: a line each, the time
  /// (this computer's) and what.
  static String laterText(List<BotLater> laters) =>
      [for (final later in laters) laterLine(later)]
          .map((line) => '$line\n')
          .join();

  /// [later]'s line: `- 2026-10-30 09:00 ask how the interview went`.
  static String laterLine(BotLater later) =>
      '- ${_time(later.at)} ${later.note.replaceAll('\n', ' ').trim()}';

  /// The lines of [text] that say when and what, soonest first; any other
  /// line is the bot's own.
  static List<BotLater> readLaters(String text) {
    final laters = <BotLater>[];
    for (final line in const LineSplitter().convert(text)) {
      if (laterOf(line) case final later?) laters.add(later);
    }
    return laters..sort((a, b) => a.at.compareTo(b.at));
  }

  /// [line] as a time to come back and what, if it is one.
  static BotLater? laterOf(String line) {
    final match = _laterLine.firstMatch(line.trim());
    if (match == null) return null;
    final at = DateTime.tryParse('${match[1]} ${match[2]}');
    final note = match[3]!.trim();
    if (at == null || note.isEmpty) return null;
    return BotLater(at: at, note: note);
  }

  static final _laterLine = RegExp(
    r'^[-*]\s+(\d{4}-\d{2}-\d{2})[ T](\d{1,2}:\d{2})\s+(.+)$',
  );

  /// [text] without the lines of [laters] (those come due).
  static String withoutLaters(String text, List<BotLater> laters) {
    final kept = [
      for (final line in const LineSplitter().convert(text))
        if (!laters.any((later) {
          final of = laterOf(line);
          return of != null && of.at == later.at && of.note == later.note;
        }))
          line,
    ];
    final joined = kept.join('\n').trim();
    return joined.isEmpty ? '' : '$joined\n';
  }

  /// [at], to the minute, as a person writes it: `2026-10-30 09:00`.
  static String _time(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }

  static bool? _yes(String? value) => switch (value?.trim().toLowerCase()) {
    'true' || 'yes' || 'on' => true,
    'false' || 'no' || 'off' => false,
    _ => null,
  };
}

/// [text]'s header (`key: value` lines between `---` lines, at its top,
/// as YAML front matter has them), and the rest.
({Map<String, String> fields, String body}) readFrontMatter(String text) {
  final lines = const LineSplitter().convert(text.replaceFirst('﻿', ''));
  if (lines.isEmpty || lines.first.trim() != '---') {
    return (fields: const {}, body: text);
  }
  final end = lines.indexWhere((line) => line.trim() == '---', 1);
  if (end < 0) return (fields: const {}, body: text);
  final fields = <String, String>{};
  for (final line in lines.sublist(1, end)) {
    final colon = line.indexOf(':');
    if (colon <= 0 || line.startsWith('#')) continue;
    fields[line.substring(0, colon).trim()] = _unquoted(
      line.substring(colon + 1).trim(),
    );
  }
  final body = lines.sublist(end + 1).join('\n');
  return (fields: fields, body: body.replaceFirst(RegExp(r'^\n+'), ''));
}

/// [fields] (those with a value) as a header over [body].
String writeFrontMatter(List<(String, String?)> fields, String body) {
  final out = StringBuffer('---\n');
  for (final (key, value) in fields) {
    final text = value?.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
    if (text == null || text.isEmpty) continue;
    out.writeln('$key: ${_quoted(text)}');
  }
  out.writeln('---');
  final rest = body.trim();
  if (rest.isNotEmpty) out.write('\n$rest\n');
  return out.toString();
}

/// [value] as YAML reads it back the same: bare where it can be, else in
/// double quotes (JSON's, which YAML's are).
String _quoted(String value) {
  final bare =
      !_special.hasMatch(value) &&
      !value.contains(': ') &&
      !value.contains(' #') &&
      !value.endsWith(':');
  return bare ? value : jsonEncode(value);
}

/// What a bare YAML value cannot start with.
final _special = RegExp(r'''^[-?:,\[\]{}#&*!|>'"%@`]''');

String _unquoted(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    try {
      return jsonDecode(value) as String;
    } on FormatException {
      return value.substring(1, value.length - 1);
    }
  }
  if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
    return value.substring(1, value.length - 1).replaceAll("''", "'");
  }
  // A comment after it, as YAML has them.
  final comment = value.indexOf(' #');
  return (comment < 0 ? value : value.substring(0, comment)).trim();
}

import 'dart:convert';

import 'bot_pacer.dart';

// What a bot is told of, kept in its folder as WATCH.md: a rule a line,
// the first that fits an event deciding what comes of it. The app matches
// them, not the model: what fits no rule wakes no one, and is only kept in
// EVENTS.md, for the bot to look at when it wants to know.
//
//   - waiting -> tell
//   - failed -> tell
//   - done mine -> tell
//   - done project:monad -> notify
//   - running -> ignore
//
// Each line: what happened (`waiting`, `failed`, `done`, `running`, a few
// of them as `waiting,failed`, or `any`); then, if only some agents, which
// (`project:<name>`, `chat:<id>`, `mine`: those the bot started or wrote
// to); then `->` and what comes of it: `tell` (the bot is woken, to write
// to the user or not), `notify` (the phone says so, the bot not woken),
// `ignore`. Any other line is the bot's own, kept as it is.

/// What comes of an event a rule fits.
enum BotWatchAction {
  /// The bot is woken with it, to write to the user, or not.
  tell,

  /// The phone notifies the user of it, on the bot's behalf: the bot is
  /// not woken (no turn of the model's).
  notify,

  /// Nothing; only kept in the bot's events.
  ignore,
}

/// One line of WATCH.md: which events, and what comes of them.
class BotWatchRule {
  const BotWatchRule({
    this.kinds = const {},
    this.project,
    this.chat,
    this.mine = false,
    required this.action,
  });

  /// What happened; none for any.
  final Set<BotEventKind> kinds;

  /// Only this project's agents (its name, or its path).
  final String? project;

  /// Only this agent.
  final String? chat;

  /// Only the agents the bot started or wrote to.
  final bool mine;

  final BotWatchAction action;

  /// Whether [event] is one of these; [mine], whether its agent is one the
  /// bot started or wrote to.
  bool fits(BotEvent event, {required bool mine}) {
    if (kinds.isNotEmpty && !kinds.contains(event.kind)) return false;
    if (this.mine && !mine) return false;
    if (chat case final chat? when chat != event.chat) return false;
    if (project case final project?) {
      final wanted = project.toLowerCase();
      if (event.project.toLowerCase() != wanted &&
          event.projectPath?.toLowerCase() != wanted) {
        return false;
      }
    }
    return true;
  }

  /// As WATCH.md has it.
  String get line {
    final what = kinds.isEmpty
        ? 'any'
        : [
            for (final kind in BotEventKind.values)
              if (kinds.contains(kind)) kind.name,
          ].join(',');
    return [
      '-',
      what,
      if (project case final project?) 'project:${_word(project)}',
      if (chat case final chat?) 'chat:$chat',
      if (mine) 'mine',
      '->',
      action.name,
    ].join(' ');
  }

  @override
  bool operator ==(Object other) => other is BotWatchRule && other.line == line;

  @override
  int get hashCode => line.hashCode;

  /// A project's name as one word of a line: quoted when it has spaces.
  static String _word(String text) =>
      text.contains(RegExp(r'\s')) ? jsonEncode(text) : text;
}

abstract final class BotWatch {
  /// What a bot is told of before it set anything: its agents' every
  /// turn, and any agent that asks the user or failed. The rest (any
  /// agent done, or running long) only kept.
  static const defaults = [
    BotWatchRule(
      kinds: {BotEventKind.waiting, BotEventKind.failed},
      action: BotWatchAction.tell,
    ),
    BotWatchRule(mine: true, action: BotWatchAction.tell),
  ];

  /// The rules of [text] (WATCH.md), in order; any other line is the
  /// bot's own.
  static List<BotWatchRule> read(String text) => [
    for (final line in const LineSplitter().convert(text)) ?ruleOf(line),
  ];

  /// [line] as a rule, if it is one.
  static BotWatchRule? ruleOf(String line) {
    final match = _rule.firstMatch(line.trim());
    if (match == null) return null;
    final action = BotWatchAction.values.asNameMap()[match[2]!.toLowerCase()];
    if (action == null) return null;
    final words = _words(match[1]!);
    if (words.isEmpty) return null;
    final kinds = <BotEventKind>{};
    final what = words.first.toLowerCase();
    if (what != 'any' && what != '*') {
      for (final name in what.split(',')) {
        final kind = BotEventKind.values.asNameMap()[name.trim()];
        if (kind == null) return null;
        kinds.add(kind);
      }
    }
    String? project, chat;
    var mine = false;
    for (final word in words.skip(1)) {
      if (word.toLowerCase() == 'mine') {
        mine = true;
      } else if (word.startsWith('project:') && word.length > 8) {
        project = word.substring(8);
      } else if (word.startsWith('chat:') && word.length > 5) {
        chat = word.substring(5);
      } else {
        return null;
      }
    }
    return BotWatchRule(
      kinds: kinds,
      project: project,
      chat: chat,
      mine: mine,
      action: action,
    );
  }

  /// `- <what> [which…] -> <action>` (or `→`).
  static final _rule = RegExp(r'^[-*]\s+(.+?)\s*(?:->|→)\s*(\w+)\s*$');

  /// [text]'s words: by spaces, a quoted one (`project:"my app"`) whole.
  static List<String> _words(String text) {
    final words = <String>[];
    for (final match in RegExp(
      r'(\S*?)"((?:[^"\\]|\\.)*)"|\S+',
    ).allMatches(text)) {
      if (match[2] case final quoted?) {
        String value;
        try {
          value = jsonDecode('"$quoted"') as String;
        } on FormatException {
          value = quoted;
        }
        words.add('${match[1]}$value');
      } else {
        words.add(match[0]!);
      }
    }
    return words;
  }

  /// What comes of [event] by [rules]: the first that fits it; ignored
  /// when none does.
  static BotWatchAction actionFor(
    List<BotWatchRule> rules,
    BotEvent event, {
    required bool mine,
  }) {
    for (final rule in rules) {
      if (rule.fits(event, mine: mine)) return rule.action;
    }
    return BotWatchAction.ignore;
  }

  /// [text] (WATCH.md) with [rules] as its rules: the bot's own lines
  /// kept, at the top; the rules after, in order.
  static String withRules(String text, List<BotWatchRule> rules) {
    final own = [
      for (final line in const LineSplitter().convert(text))
        if (ruleOf(line) == null) line,
    ].join('\n').trim();
    return [
      own.isEmpty ? header : own,
      '',
      for (final rule in rules) rule.line,
    ].join('\n');
  }

  /// What a new WATCH.md says of itself, over its rules.
  static const header =
      '# What I am told of: the first line that fits an event decides.\n'
      '# what (waiting, failed, done, running, any) · which (project:<name>, '
      'chat:<id>, mine) -> tell | notify | ignore';
}

/// What happened to the agents, as a bot's EVENTS.md keeps it: the latest
/// [BotEvents.most], none older than [BotEvents.longest].
abstract final class BotEvents {
  static const most = 50;
  static const longest = Duration(hours: 24);

  /// [text] (EVENTS.md) with [events] after it: the oldest dropped, past
  /// the most, or older than [longest] at [now].
  static String withEvents(
    String text,
    List<(BotEvent, BotWatchAction)> events,
    DateTime now,
  ) {
    final lines = [
      for (final line in const LineSplitter().convert(text))
        if (_at(line) case final at? when now.difference(at) < longest) line,
      for (final (event, action) in events) lineOf(event, action),
    ];
    final kept = lines.length > most
        ? lines.sublist(lines.length - most)
        : lines;
    return kept.join('\n');
  }

  /// [event]'s line, and what came of it: `- 2026-11-02 12:50 done: "Fix
  /// the build" in monad (chat 3f2a…) -> ignore`.
  static String lineOf(BotEvent event, BotWatchAction action) {
    String two(int n) => n.toString().padLeft(2, '0');
    final at = event.at;
    final time =
        '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
    return '- $time ${event.line.substring(2)} -> ${action.name}';
  }

  /// The latest [count] of [text]'s lines, oldest first.
  static List<String> latest(String text, int count) {
    final lines = [
      for (final line in const LineSplitter().convert(text))
        if (_at(line) != null) line,
    ];
    return lines.length > count ? lines.sublist(lines.length - count) : lines;
  }

  static DateTime? _at(String line) {
    final match = RegExp(r'^- (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) ')
        .firstMatch(line);
    return match == null ? null : DateTime.tryParse(match[1]!);
  }
}

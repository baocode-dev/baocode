import 'dart:math' as math;

import 'bot.dart';

/// What happened to one of the user's agents, for a bot to tell of.
enum BotEventKind {
  /// It asks the user: a question, a permission, a plan.
  waiting,

  /// Its turn ended on an error.
  failed,

  /// It has been at work a long while (see [BotEvent.detail]).
  running,

  /// Its turn is done.
  done,
}

class BotEvent {
  const BotEvent({
    required this.chat,
    required this.title,
    required this.project,
    required this.kind,
    required this.at,
    this.detail,
  });

  /// The agent's id, as the bot's tools take it.
  final String chat;
  final String title;
  final String project;
  final BotEventKind kind;
  final DateTime at;

  /// A line more: what it asks, the error, how long it has run.
  final String? detail;

  String get line {
    final detail = this.detail?.trim() ?? '';
    return '- ${kind.name}: "$title" in $project (chat $chat)'
        '${detail.isEmpty ? '' : ' — $detail'}';
  }
}

/// When a bot writes first, of what happened: what comes close together is
/// told at once, at most [BotProactive.perDay] times a day, [gap] apart,
/// never in its quiet hours; what waits meanwhile is told then, together.
class BotPacer {
  BotPacer({
    this.gather = const Duration(seconds: 90),
    this.gap = const Duration(minutes: 20),
    this.stale = const Duration(hours: 6),
  });

  /// How long after the first of them the events are told, for those
  /// that follow to be told with it.
  final Duration gather;

  /// The least time between two of its messages.
  final Duration gap;

  /// How old a [BotEventKind.done] may get before it is not worth telling.
  final Duration stale;

  /// The events not told yet, one an agent (its latest).
  final Map<String, BotEvent> _pending = {};

  /// When it wrote first, the last day's.
  final List<DateTime> _sent = [];

  bool get hasPending => _pending.isNotEmpty;

  void add(BotEvent event) {
    _pending.remove(event.chat);
    _pending[event.chat] = event;
  }

  /// Forgets what was not told: the user is talking to it, say.
  void clear() => _pending.clear();

  /// When what waits may be told, by [settings]; null when nothing waits,
  /// or it never writes first.
  DateTime? dueAt(BotProactive settings, DateTime now) {
    if (settings.perDay <= 0 || _pending.isEmpty) return null;
    _sent.removeWhere((at) => now.difference(at) >= const Duration(days: 1));
    final first = _pending.values.map((e) => e.at).reduce(_earlier);
    var due = first.add(gather);
    if (_sent.isNotEmpty) due = _later(due, _sent.last.add(gap));
    if (_sent.length >= settings.perDay) {
      // Once the oldest of the day's is a day old.
      final freed = _sent[_sent.length - settings.perDay];
      due = _later(due, freed.add(const Duration(days: 1)));
    }
    return _later(_outOfQuiet(settings, due), now);
  }

  /// What is due at [now], told together; null when nothing is.
  List<BotEvent>? take(BotProactive settings, DateTime now) {
    final due = dueAt(settings, now);
    if (due == null || due.isAfter(now)) return null;
    final events =
        _pending.values
            .where(
              (e) =>
                  e.kind != BotEventKind.done || now.difference(e.at) < stale,
            )
            .toList()
          // What needs the user first.
          ..sort((a, b) {
            final kind = a.kind.index.compareTo(b.kind.index);
            return kind != 0 ? kind : a.at.compareTo(b.at);
          });
    _pending.clear();
    if (events.isEmpty) return null;
    _sent.add(now);
    return events;
  }

  /// [at], or the end of the quiet hours it falls in.
  static DateTime outOfQuiet(BotProactive settings, DateTime at) =>
      _outOfQuiet(settings, at);

  static DateTime _outOfQuiet(BotProactive settings, DateTime at) {
    final minute = at.hour * 60 + at.minute;
    if (!settings.isQuiet(minute)) return at;
    final day = DateTime(at.year, at.month, at.day);
    var end = day.add(Duration(minutes: settings.quietTo));
    if (!end.isAfter(at)) end = end.add(const Duration(days: 1));
    return end;
  }

  static DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
}

/// [events] as the app's message to a bot.
String botEventText(List<BotEvent> events) {
  final shown = events.take(math.min(events.length, 12)).toList();
  return [
    'Since you last heard:',
    for (final event in shown) event.line,
    if (events.length > shown.length)
      '- and ${events.length - shown.length} more.',
  ].join('\n');
}

/// What a bot meant to come back to (its bot_later tool): when, and its
/// note to itself of what.
class BotLater {
  const BotLater({required this.at, required this.note});

  final DateTime at;
  final String note;

  Map<String, Object?> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'note': note,
  };

  static BotLater? fromJson(Object? json) => switch (json) {
    {'at': final int at, 'note': final String note} => BotLater(
      at: DateTime.fromMillisecondsSinceEpoch(at),
      note: note,
    ),
    _ => null,
  };
}

/// The app's message waking a bot at [now]: what happened to the agents
/// ([events]), what it meant to come back to ([laters]), and the time.
String botWakeText(
  DateTime now, {
  List<BotEvent> events = const [],
  List<BotLater> laters = const [],
}) => [
  if (events.isNotEmpty) botEventText(events),
  if (laters.isNotEmpty) ...[
    'You meant to come back to this now:',
    for (final later in laters) '- ${later.note}',
  ],
  'Now: ${botTime(now)}.',
].join('\n');

/// [at] as a bot is told the time: its day and the hour.
String botTime(DateTime at) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[at.weekday - 1]} ${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}:${two(at.minute)}';
}

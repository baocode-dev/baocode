import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/ids.dart';
import '../util/json.dart';

/// A five-field cron expression (minute, hour, day of month, month, day of
/// week), in local time.
class CronExpression {
  CronExpression._(
    this.source,
    this._minutes,
    this._hours,
    this._days,
    this._months,
    this._weekdays, {
    required this.anyDay,
    required this.anyWeekday,
  });

  /// [text] read; [FormatException] when it is not one.
  factory CronExpression.parse(String text) {
    final fields = text.trim().split(RegExp(r'\s+'));
    if (fields.length != 5) {
      throw const FormatException(
        'A cron expression has five fields: minute hour day-of-month month '
        'day-of-week',
      );
    }
    final weekdays = _field(fields[4], 0, 7, 'day of week');
    if (weekdays.remove(7)) weekdays.add(0);
    return CronExpression._(
      text.trim(),
      _field(fields[0], 0, 59, 'minute'),
      _field(fields[1], 0, 23, 'hour'),
      _field(fields[2], 1, 31, 'day of month'),
      _field(fields[3], 1, 12, 'month'),
      weekdays,
      anyDay: fields[2] == '*',
      anyWeekday: fields[4] == '*',
    );
  }

  final String source;
  final Set<int> _minutes;
  final Set<int> _hours;
  final Set<int> _days;
  final Set<int> _months;
  final Set<int> _weekdays;
  final bool anyDay;
  final bool anyWeekday;

  static Set<int> _field(String text, int min, int max, String what) {
    final out = <int>{};
    for (final part in text.split(',')) {
      final slash = part.split('/');
      if (slash.length > 2) throw FormatException('Bad $what: $text');
      final step = slash.length == 2 ? int.tryParse(slash[1]) : 1;
      if (step == null || step < 1) throw FormatException('Bad $what: $text');
      int from;
      int to;
      if (slash[0] == '*') {
        from = min;
        to = max;
      } else if (slash[0].contains('-')) {
        final ends = slash[0].split('-');
        final a = ends.length == 2 ? int.tryParse(ends[0]) : null;
        final b = ends.length == 2 ? int.tryParse(ends[1]) : null;
        if (a == null || b == null || a > b) {
          throw FormatException('Bad $what: $text');
        }
        from = a;
        to = b;
      } else {
        final n = int.tryParse(slash[0]);
        if (n == null) throw FormatException('Bad $what: $text');
        from = n;
        to = slash.length == 2 ? max : n;
      }
      if (from < min || to > max) {
        throw FormatException('The $what must be from $min to $max: $text');
      }
      for (var i = from; i <= to; i += step) {
        out.add(i);
      }
    }
    return out;
  }

  bool matches(DateTime time) {
    if (!_minutes.contains(time.minute) ||
        !_hours.contains(time.hour) ||
        !_months.contains(time.month)) {
      return false;
    }
    final day = _days.contains(time.day);
    final weekday = _weekdays.contains(time.weekday % 7);
    // Both days given: either will do, as cron has it.
    if (!anyDay && !anyWeekday) return day || weekday;
    return day && weekday;
  }

  /// The first minute after [after] it matches; null when none within
  /// about four years (a 30th of February).
  DateTime? next(DateTime after) {
    var time = DateTime(
      after.year,
      after.month,
      after.day,
      after.hour,
      after.minute,
    ).add(const Duration(minutes: 1));
    final end = after.add(const Duration(days: 1500));
    while (time.isBefore(end)) {
      if (!_months.contains(time.month)) {
        time = DateTime(time.year, time.month + 1);
        continue;
      }
      if (!_dayCouldMatch(time)) {
        time = DateTime(time.year, time.month, time.day + 1);
        continue;
      }
      if (!_hours.contains(time.hour)) {
        time = DateTime(time.year, time.month, time.day, time.hour + 1);
        continue;
      }
      if (matches(time)) return time;
      time = time.add(const Duration(minutes: 1));
    }
    return null;
  }

  bool _dayCouldMatch(DateTime time) {
    final day = _days.contains(time.day);
    final weekday = _weekdays.contains(time.weekday % 7);
    if (!anyDay && !anyWeekday) return day || weekday;
    return day && weekday;
  }
}

/// A prompt scheduled to be sent at the times of a cron expression.
class CronJob {
  CronJob({
    required this.id,
    required this.cron,
    required this.prompt,
    required this.recurring,
    required this.durable,
    required this.createdAt,
    this.lastFiredAt,
  });

  factory CronJob.fromJson(Map<String, Object?> json) => CronJob(
    id: '${json['id']}',
    cron: '${json['cron']}',
    prompt: '${json['prompt']}',
    recurring: json['recurring'] != false,
    durable: true,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      asInt(json['createdAt']) ?? DateTime.now().millisecondsSinceEpoch,
    ),
    lastFiredAt: switch (asInt(json['lastFiredAt'])) {
      final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
      null => null,
    },
  );

  final String id;
  final String cron;
  final String prompt;
  final bool recurring;
  final bool durable;
  final DateTime createdAt;
  DateTime? lastFiredAt;

  /// When it fires next, its jitter in.
  DateTime? due;

  late final CronExpression expression = CronExpression.parse(cron);

  Map<String, Object?> toJson() => {
    'id': id,
    'cron': cron,
    'prompt': prompt,
    'recurring': recurring,
    'createdAt': createdAt.millisecondsSinceEpoch,
    if (lastFiredAt case final at?) 'lastFiredAt': at.millisecondsSinceEpoch,
  };
}

/// The session's scheduled prompts: those of CronCreate (kept in
/// `.claude/scheduled_tasks.json` when durable) and the one wake-up of
/// ScheduleWakeup. A prompt due is handed to [onFire], which sends it once
/// the agent is idle.
class Scheduler {
  Scheduler({required this.cwd, this.onFire});

  final String cwd;

  /// Sends a prompt that came due.
  void Function(String prompt)? onFire;

  /// How long a recurring job lives.
  static const lifetime = Duration(days: 7);

  /// The most jobs at once.
  static const maxJobs = 50;

  final Map<String, CronJob> jobs = {};
  Timer? _timer;

  /// The wake-up asked for, if any: when, and the prompt.
  ({DateTime at, String prompt, String? reason})? wakeup;

  String get file => p.join(cwd, '.claude', 'scheduled_tasks.json');

  /// Reads the durable jobs, and fires those of one shot missed while no
  /// session ran.
  void load() {
    try {
      final f = File(file);
      if (!f.existsSync()) return;
      final json = asMap(jsonDecode(f.readAsStringSync()));
      final now = DateTime.now();
      for (final raw in asList(json['tasks'])) {
        final job = CronJob.fromJson(asMap(raw));
        try {
          job.expression;
        } on FormatException {
          continue;
        }
        jobs[job.id] = job;
        if (!job.recurring) {
          final at = job.expression.next(job.createdAt);
          if (at != null && at.isBefore(now)) {
            job.due = now;
            continue;
          }
        }
        _schedule(job, now);
      }
    } on Object {
      // None kept, or not readable.
    }
    _arm();
  }

  void _save() {
    final durable = [
      for (final job in jobs.values)
        if (job.durable) job.toJson(),
    ];
    final f = File(file);
    try {
      if (durable.isEmpty) {
        if (f.existsSync()) f.writeAsStringSync('{"tasks": []}\n');
        return;
      }
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'tasks': durable})}\n',
      );
    } on FileSystemException {
      // Kept for this session only.
    }
  }

  /// Schedules [prompt] at [cron]. Throws [FormatException] for an
  /// expression that is not one, or never matches.
  CronJob add({
    required String cron,
    required String prompt,
    required bool recurring,
    required bool durable,
  }) {
    if (jobs.length >= maxJobs) {
      throw const FormatException(
        'There are 50 scheduled jobs already: delete one first.',
      );
    }
    final job = CronJob(
      id: randomHex(4),
      cron: cron,
      prompt: prompt,
      recurring: recurring,
      durable: durable,
      createdAt: DateTime.now(),
    );
    final now = DateTime.now();
    if (job.expression.next(now) == null) {
      throw FormatException('"$cron" matches no time in the next years.');
    }
    jobs[job.id] = job;
    _schedule(job, now);
    if (durable) _save();
    _arm();
    return job;
  }

  bool remove(String id) {
    final job = jobs.remove(id);
    if (job == null) return false;
    if (job.durable) _save();
    return true;
  }

  /// When [job] fires next after [after], with its jitter.
  void _schedule(CronJob job, DateTime after) {
    final next = job.expression.next(after);
    if (next == null) {
      job.due = null;
      return;
    }
    final hash = job.id.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0xffff);
    if (job.recurring) {
      final following = job.expression.next(next);
      final period = following == null
          ? Duration.zero
          : following.difference(next);
      var late = period * 0.1;
      if (late > const Duration(minutes: 15)) {
        late = const Duration(minutes: 15);
      }
      job.due = next.add(late * (hash / 0xffff));
    } else if (next.minute == 0 || next.minute == 30) {
      job.due = next.subtract(Duration(seconds: (90 * hash / 0xffff).round()));
    } else {
      job.due = next;
    }
  }

  /// Wakes the agent with [prompt] in [delay].
  void wake(Duration delay, String prompt, {String? reason}) {
    wakeup = (at: DateTime.now().add(delay), prompt: prompt, reason: reason);
    _arm();
  }

  void cancelWakeup() => wakeup = null;

  void _arm() {
    if (_timer != null) return;
    if (jobs.isEmpty && wakeup == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  /// Fires what is due by [now].
  void tick([DateTime? now]) {
    now ??= DateTime.now();
    if (wakeup case final wake? when !wake.at.isAfter(now)) {
      wakeup = null;
      onFire?.call(wake.prompt);
    }
    var changed = false;
    for (final job in [...jobs.values]) {
      final due = job.due;
      if (due == null || due.isAfter(now)) continue;
      job.lastFiredAt = now;
      onFire?.call(job.prompt);
      final expired = now.difference(job.createdAt) >= lifetime;
      if (!job.recurring || expired) {
        jobs.remove(job.id);
      } else {
        _schedule(job, now);
      }
      changed |= job.durable;
    }
    if (changed) _save();
    if (jobs.isEmpty && wakeup == null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

import '../engine/scheduler.dart';
import '../engine/session.dart';
import '../permissions/decision.dart';
import '../util/json.dart';
import 'tool.dart';

/// Schedules a prompt at the times of a cron expression.
class CronCreateTool extends Tool {
  const CronCreateTool();

  @override
  String get name => 'CronCreate';

  @override
  String get description => '''Schedules a prompt to be sent at a later time: once, as a reminder, or again and again. It is sent as if the user typed it, when you are not busy with a turn.

The time is a cron expression of five fields, in the user's local time: minute, hour, day of the month, month, day of the week. "0 9 * * *" is 9 in the morning wherever the user is.

## Once (recurring: false)
For "remind me at …" or "at …, do …": pin the minute, hour, day and month, and it fires once and is gone.
  "at 2:30pm today, check the deploy" → "30 14 <today's day> <this month> *", recurring false
  "first thing tomorrow, rerun the flaky suite" → "52 8 <tomorrow's day> <its month> *", recurring false

## Again and again (recurring: true, the default)
For "every N minutes", "hourly", "weekdays at 9": "*/10 * * * *", "13 * * * *", "4 9 * * 1-5".

## Stay off :00 and :30 when you can
Everyone who asks for "9 o'clock" or "hourly" lands on minute 0, and all those requests reach the API in the same instant. When the user's time is loose ("around 9", "every hour", "in an hour or so"), pick a minute that is neither 0 nor 30: "56 8 * * *" or "4 9 * * *", "13 * * * *". Keep 0 or 30 for when the user means that very time ("9:00 sharp", "at half past").

## Kept or not
A job lives in this session only, unless durable is true: then it is written to .claude/scheduled_tasks.json and goes on in later sessions. Make it durable only when the user asks for it to last ("every day from now on", "set it up for good").

## How it runs
- A job fires only between turns, never in the middle of one.
- A small fixed jitter is added: a recurring job fires up to a tenth of its period late (15 minutes at most); a one-off at :00 or :30 up to 90 seconds early.
- A recurring job ends after 7 days: it fires one last time and is deleted. Tell the user so when you schedule one.
- A durable one-off missed while no session ran fires when the next one starts.

It answers with the job's ID, for CronDelete.''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'cron': {
        'type': 'string',
        'description':
            'Five cron fields in local time: "M H DoM Mon DoW" ("*/5 * * * *" '
            'every five minutes; "30 14 28 2 *" on 28 February at 14:30)',
      },
      'prompt': {
        'type': 'string',
        'description': 'The prompt to send each time it fires',
      },
      'recurring': {
        'type': 'boolean',
        'description':
            'true (the default): fire at every match until deleted, or '
            'until it ends after 7 days. false: fire once, at the next '
            'match, then delete itself',
      },
      'durable': {
        'type': 'boolean',
        'description':
            'true: kept in .claude/scheduled_tasks.json, going on in later '
            'sessions. false (the default): kept in this session only',
      },
    },
    'required': ['cron', 'prompt'],
    'additionalProperties': false,
  };

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAllow();

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    try {
      CronExpression.parse('${input['cron'] ?? ''}');
    } on FormatException catch (error) {
      return 'Invalid cron expression: ${error.message}';
    }
    if ('${input['prompt'] ?? ''}'.trim().isEmpty) {
      return 'The prompt must not be empty.';
    }
    return null;
  }

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final scheduler = context.session.scheduler;
    final recurring = input['recurring'] != false;
    final durable = input['durable'] == true;
    final CronJob job;
    try {
      job = scheduler.add(
        cron: '${input['cron']}'.trim(),
        prompt: '${input['prompt']}',
        recurring: recurring,
        durable: durable,
      );
    } on FormatException catch (error) {
      return ToolOutput.error(error.message);
    }
    final due = job.due;
    return ToolOutput(
      'Scheduled job ${job.id} (${job.cron}, '
      '${recurring ? 'recurring' : 'once'}, '
      '${durable ? 'kept in .claude/scheduled_tasks.json' : 'this session only'})'
      '${due == null ? '' : '. Next: ${_time(due)}'}'
      '${recurring ? '. It ends after 7 days.' : '.'}',
      result: {
        'id': job.id,
        'humanSchedule': job.cron,
        'recurring': recurring,
        'durable': durable,
      },
    );
  }

  static String _time(DateTime time) =>
      '${time.year}-${_two(time.month)}-${_two(time.day)} '
      '${_two(time.hour)}:${_two(time.minute)}';

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// Deletes a scheduled job.
class CronDeleteTool extends Tool {
  const CronDeleteTool();

  @override
  String get name => 'CronDelete';

  @override
  String get description =>
      'Deletes a job scheduled with CronCreate: from '
      '.claude/scheduled_tasks.json for a durable one, from this session for '
      'the others.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'id': {
        'type': 'string',
        'description': 'The job\'s ID, as CronCreate gave it',
      },
    },
    'required': ['id'],
    'additionalProperties': false,
  };

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAllow();

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final id = '${input['id']}'.trim();
    if (!context.session.scheduler.remove(id)) {
      return ToolOutput.error('No scheduled job with ID $id.');
    }
    return ToolOutput('Deleted job $id.', result: {'id': id});
  }
}

/// Lists the scheduled jobs.
class CronListTool extends Tool {
  const CronListTool();

  @override
  String get name => 'CronList';

  @override
  String get description =>
      'Lists the jobs scheduled with CronCreate, durable ones '
      '(.claude/scheduled_tasks.json) and those of this session alike.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
    'additionalProperties': false,
  };

  @override
  bool isReadOnly(Map<String, Object?> input) => true;

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAllow();

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final jobs = context.session.scheduler.jobs.values.toList();
    if (jobs.isEmpty) {
      return const ToolOutput('No jobs are scheduled.', result: {'jobs': []});
    }
    return ToolOutput(
      [
        for (final job in jobs)
          '- ${job.id}: "${job.cron}" '
              '(${job.recurring ? 'recurring' : 'once'}, '
              '${job.durable ? 'durable' : 'this session'}'
              '${job.due == null ? '' : ', next ${CronCreateTool._time(job.due!)}'}): '
              '${job.prompt}',
      ].join('\n'),
      result: {
        'jobs': [
          for (final job in jobs)
            {
              'id': job.id,
              'cron': job.cron,
              'prompt': job.prompt,
              'recurring': job.recurring,
              'durable': job.durable,
            },
        ],
      },
    );
  }
}

/// Wakes the agent later, in a loop it paces itself (`/loop` without an
/// interval).
class ScheduleWakeupTool extends Tool {
  const ScheduleWakeupTool();

  /// The prompt that stands for the loop's own instructions, when the loop
  /// was started without a prompt of the user's.
  static const autonomousLoop = '<<autonomous-loop-dynamic>>';

  static const minDelay = Duration(seconds: 60);
  static const maxDelay = Duration(seconds: 3600);

  @override
  String get name => 'ScheduleWakeup';

  @override
  String get description =>
      '''Says when to wake for the next round of a loop you pace yourself: the user started /loop with no interval, for you to repeat a task at the pace it needs.

Do not wake soon just to see whether work you started in the background is done: you are woken when it ends. Set a long wake-up instead (1200 seconds or more), in case it hangs and never tells. Wake soon only for what nothing tells you of (a CI run, a deploy, a queue elsewhere), as often as it can change.

Give back the same /loop prompt in `prompt` each round, so the next round does the task again. For a loop with no prompt of the user's, pass `$autonomousLoop` instead: it stands for the loop's own instructions. To end the loop, call it with `stop: true` alone; no wake-up follows.

Set `noop: true` when nothing changed this round (checked, nothing new), `false` when something did (a file edited, a message sent, a finding). Rounds with nothing new are folded together for the user. Leave it out with `stop`.

## How long
The cache of the conversation lasts about 5 minutes: wake within 270 seconds and it is still warm; later, the next round reads everything afresh, slower and dearer. So either poll something that changes fast at 60 to 270 seconds, or wait 20 minutes and more (1200 to 1800 seconds) when there is no point looking sooner. Never 300: it pays for the cold cache without the long wait. Think of what you wait for: a CI run of about 8 minutes is two waits of 270 seconds, not eight of 60.

The delay is kept between 60 and 3600 seconds whatever you ask.

## reason
One short sentence on why this delay, shown to the user: "waiting on the CI run" says more than "waiting".''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'delaySeconds': {
        'type': 'number',
        'description':
            'Seconds from now to wake, kept between 60 and 3600. Needed '
            'unless `stop` is true',
      },
      'reason': {
        'type': 'string',
        'description':
            'Why this delay, in one short sentence the user is shown. '
            'Needed unless `stop` is true',
      },
      'prompt': {
        'type': 'string',
        'description':
            'The /loop prompt to run on waking: the same each round, or '
            '`<<autonomous-loop-dynamic>>` for a loop without one. Needed '
            'unless `stop` is true',
      },
      'stop': {
        'type': 'boolean',
        'description':
            'true ends the loop now: no wake-up follows, and the other '
            'fields are not read',
      },
      'noop': {
        'type': 'boolean',
        'description':
            'true: nothing changed this round. false: something did. '
            'Needed unless `stop` is true',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAllow();

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    if (input['stop'] == true) return null;
    if (input['delaySeconds'] == null) return 'delaySeconds is required';
    if (asText(input['prompt']) == null) return 'prompt is required';
    return null;
  }

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final scheduler = context.session.scheduler;
    if (input['stop'] == true) {
      scheduler.cancelWakeup();
      return const ToolOutput(
        'The loop has ended: no wake-up is scheduled.',
        result: {'stopped': true},
      );
    }
    final asked =
        asInt(input['delaySeconds']) ?? (input['delaySeconds'] as num).round();
    final delay = Duration(
      seconds: asked.clamp(minDelay.inSeconds, maxDelay.inSeconds),
    );
    final prompt = '${input['prompt']}';
    scheduler.wake(
      delay,
      prompt == autonomousLoop ? autonomousLoopPrompt : prompt,
      reason: asText(input['reason']),
    );
    final at = DateTime.now().add(delay);
    return ToolOutput(
      'Waking in ${delay.inSeconds} seconds (at '
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}). End your turn now.',
      result: {
        'delaySeconds': delay.inSeconds,
        'reason': ?asText(input['reason']),
        'noop': ?input['noop'],
      },
    );
  }

  /// What a round of a loop without a prompt of the user's asks.
  static const autonomousLoopPrompt =
      'This is a round of a loop you pace yourself, started '
      'without a task of its own. Look at the state of the work this '
      'session is about (the repository, the tasks running, what the user '
      'asked for last) and do the next useful thing, if there is one. Then '
      'call ScheduleWakeup for the next round, with prompt '
      '"$autonomousLoop", or with stop true when there is nothing left to '
      'watch.';

  @override
  bool isEnabled(AgentSession session) => true;
}

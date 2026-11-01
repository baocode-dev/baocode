import 'dart:io';

import 'package:baocode/usage/usage_capture.dart';
import 'package:baocode/usage/usage_ledger.dart';
import 'package:baocode/usage/usage_query.dart';
import 'package:baocode/usage/usage_record.dart';
import 'package:baocode/usage/usage_storage_io.dart';
import 'package:baocode/usage/usage_trace.dart';
import 'package:flutter_test/flutter_test.dart';

UsageCall _call(
  DateTime at, {
  String provider = 'gw',
  String model = 'gpt-5',
  String? session = 's1',
  UsageClass kind = UsageClass.main,
  String? agent,
  int input = 100,
  int output = 10,
  int cacheRead = 0,
  int status = 200,
  Map<String, int> results = const {},
  String? prompt,
}) => UsageCall(
  at: at,
  duration: const Duration(seconds: 2),
  firstToken: const Duration(milliseconds: 400),
  status: status,
  provider: provider,
  providerName: provider.toUpperCase(),
  model: model,
  session: session,
  requestClass: kind,
  agentId: agent,
  input: input,
  output: output,
  cacheRead: cacheRead,
  toolResults: results,
  toolCalls: results.map((key, _) => MapEntry(key, 1)),
  promptId: prompt,
  context: const UsageContext(system: 10, toolResult: 50),
);

void main() {
  test('a call reads back as it was kept, in brief without the details', () {
    final call = _call(
      DateTime(2026, 11, 1, 9),
      agent: 'a1',
      kind: UsageClass.subagent,
      results: {'Read': 300},
    );
    final back = UsageCall.decode(call.encode())!;
    expect(back.toJson(), call.toJson());
    expect(back.brief.context, isNull);
    expect(back.brief.toolResults, isEmpty);
    expect(UsageCall.decode('{"t":1'), isNull);
  });

  test('tool durations are read as Claude Code writes them', () {
    expect(parseToolDurations('Read=12;Bash=40;Read=8;bad;x=y'), {
      'Read': 20,
      'Bash': 40,
    });
    expect(parseToolDurations(null), isEmpty);
  });

  test('a request is told apart by its headers, else by what it is', () {
    final compaction = analyzeRequest({
      'messages': [
        {
          'role': 'user',
          'content': 'Your task is to create a detailed summary of the conversation so far.',
        },
      ],
      'tools': [{}],
    }, (_) => null);
    expect(compaction.requestClass, UsageClass.compaction);
    final aside = analyzeRequest({
      'messages': [
        {'role': 'user', 'content': 'Title this'},
      ],
    }, (_) => null);
    expect(aside.requestClass, UsageClass.auxiliary);
    final agent = analyzeRequest({
      'messages': [
        {'role': 'user', 'content': 'Look around'},
      ],
      'tools': [{}],
    }, (name) => name == UsageHeaders.agentId ? 'a9' : null);
    expect(agent.requestClass, UsageClass.subagent);
    expect(agent.task, 'Look around');
  });

  test('a context is told apart: CLAUDE.md, the skills, MCP servers and '
      'each tool', () {
    final info = analyzeRequest({
      'system': [
        {'type': 'text', 'text': 'You are Claude Code.'},
        {
          'type': 'text',
          'text':
              'Rules.\n\n# MCP Server Instructions\n\nThe following MCP '
              'servers have provided instructions:\n\n## claude.ai Docs\n'
              '${'Use the docs. ' * 40}\n\n## baocode\nDo not scrape.\n\n'
              '# Environment\nYou run on macOS.',
        },
      ],
      'tools': [
        {
          'name': 'Read',
          'description': 'Reads a file. ' * 20,
          'input_schema': {'type': 'object'},
        },
        {
          'name': 'mcp__claude_ai_Docs__batch',
          'description': 'Many docs at once. ' * 30,
          'input_schema': {'type': 'object'},
        },
      ],
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text':
                  '<system-reminder>\nAs you answer, use this context:\n'
                  '# claudeMd\nContents of /a/CLAUDE.md (project):\n\n'
                  '${'Run the tests. ' * 30}\n\nContents of /b/rules.md:\n\n'
                  'Speak Chinese.\n</system-reminder>',
            },
            {
              'type': 'text',
              'text':
                  '<system-reminder>\nThe following skills are available '
                  'for use with the Skill tool:\n\n- dataviz: Charts. '
                  '${'More. ' * 30}\n- plugin:deploy: Deploys.\n'
                  '</system-reminder>',
            },
            {
              'type': 'text',
              'text':
                  '<system-reminder>\nThe following deferred tools are now '
                  'available via ToolSearch:\nCronCreate\n'
                  'mcp__github__search\n</system-reminder>',
            },
            {'type': 'text', 'text': 'Make the chart stacked.'},
          ],
        },
        {
          'role': 'assistant',
          'content': [
            {'type': 'tool_use', 'id': 't1', 'name': 'Read', 'input': {}},
          ],
        },
        {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 't1', 'content': 'x' * 800},
          ],
        },
      ],
    }, (_) => null);
    final context = info.context!;
    final shape = context.detail!.shape!;
    expect(shape.memory.keys, ['/a/CLAUDE.md', '/b/rules.md']);
    expect(
      shape.memory['/a/CLAUDE.md'],
      greaterThan(shape.memory['/b/rules.md']!),
    );
    expect(shape.skills.keys, ['dataviz', 'plugin:deploy']);
    expect(shape.mcpNotes.keys, ['claude.ai Docs', 'baocode']);
    expect(shape.tools.keys, [
      'CronCreate',
      'mcp__github__search',
      'Read',
      'mcp__claude_ai_Docs__batch',
    ]);
    expect(UsageShape.mcpTool('mcp__claude_ai_Docs__batch'), (
      server: 'claude_ai_Docs',
      tool: 'batch',
    ));
    expect(context.memory, greaterThan(100));
    expect(context.skills, greaterThan(40));
    expect(
      context.mcp,
      greaterThan(shape.tools['mcp__claude_ai_Docs__batch']!),
    );
    // What was left of the user's own words, and the system's.
    expect(context.user, lessThan(20));
    expect(context.system, lessThan(40));
    expect(context.detail!.results, {'Read': 200});
    expect(context.detail!.uses.keys, ['Read']);
  });

  group('ledger', () {
    late DateTime now;
    late MemoryUsageStorage storage;
    late UsageLedger ledger;

    setUp(() {
      now = DateTime(2026, 11, 1, 15);
      storage = MemoryUsageStorage();
      ledger = UsageLedger(storage, clock: () => now);
      UsageLedger.titleOf = (session) => 'Title of $session';
      UsageLedger.projectOf = (_) => 'monad';
    });

    tearDown(() {
      UsageLedger.titleOf = null;
      UsageLedger.projectOf = null;
      ledger.dispose();
    });

    test('keeps calls by day, the session labeled once a day', () async {
      ledger
        ..record(_call(DateTime(2026, 10, 30, 10)))
        ..record(_call(DateTime(2026, 11, 1, 10)))
        ..record(_call(DateTime(2026, 11, 1, 11), session: 's2'))
        ..record(_call(DateTime(2026, 11, 1, 12)))
        ..flush();
      expect(storage.lines.keys, ['2026-10-30', '2026-11-01']);
      final today = await ledger.range(from: DateTime(2026, 11, 1));
      expect(today, hasLength(3));
      expect(today.first.sessionTitle, 'Title of s1');
      expect(today.last.sessionTitle, isNull);
      expect((await ledger.ofSession('s1')), hasLength(3));
      expect((await ledger.ofSession('s2')), hasLength(1));
      final space = await ledger.space();
      expect(space.days, 2);
      expect(space.oldest, '2026-10-30');
    });

    test('labels a conversation once it is named, and again as renamed; '
        'its group by its last name', () async {
      String? title;
      UsageLedger.titleOf = (_) => title;
      ledger.record(_call(DateTime(2026, 11, 1, 10)));
      title = 'Fix the parser';
      ledger
        ..record(_call(DateTime(2026, 11, 1, 11)))
        ..record(_call(DateTime(2026, 11, 1, 12)));
      title = 'Parser rewrite';
      ledger
        ..record(_call(DateTime(2026, 11, 1, 13)))
        ..flush();
      final today = await ledger.range(from: DateTime(2026, 11, 1));
      expect(
        [for (final call in today) call.sessionTitle],
        [null, 'Fix the parser', null, 'Parser rewrite'],
      );
      final summary = UsageSummary.of(
        today,
        UsageFilter(from: DateTime(2026, 11, 1)),
        now: now,
      );
      expect(summary.bySession['s1']?.label, 'Parser rewrite');
    });

    test('keeps what stays of a context once a day, read back with each '
        'call', () async {
      final shape = UsageShape(
        tools: {'Read': 300, 'mcp__gh__search': 120},
        skills: {'dataviz': 80},
      );
      UsageCall withShape(DateTime at) => UsageCall(
        at: at,
        duration: Duration.zero,
        status: 200,
        provider: 'gw',
        model: 'm',
        session: 's1',
        input: 900,
        context: UsageContext(
          tools: 300,
          mcp: 120,
          skills: 80,
          user: 400,
          detail: UsageContextDetail(shape: shape, results: {'Read': 50}),
        ),
      );
      ledger
        ..record(withShape(DateTime(2026, 11, 1, 9)))
        ..record(withShape(DateTime(2026, 11, 1, 10)))
        ..flush();
      final lines = storage.lines['2026-11-01']!;
      expect(lines, hasLength(3));
      expect(
        lines.where((line) => line.contains('"sh":"${shape.id}","td"')),
        hasLength(1),
      );
      // Read again, from the lines.
      final again = UsageLedger(storage, clock: () => now);
      addTearDown(again.dispose);
      final calls = await again.range();
      expect(calls, hasLength(2));
      for (final call in calls) {
        expect(call.context!.detail!.shape!.tools, shape.tools);
        expect(call.context!.detail!.shape!.skills, shape.skills);
        expect(call.context!.detail!.results, {'Read': 50});
      }
      // Its calls gone, the shape goes with them.
      await again.clear(UsageClearSpec(session: 's1'));
      expect(storage.lines, isEmpty);
    });

    test('keeps a trace apart from its call, and deletes it with it', () async {
      final trace = UsageTrace('tr1', at: now)
        ..asked(
          method: 'POST',
          url: '/p/gw/v1/messages',
          headers: {'authorization': 'Bearer ••••'},
          body: '{"model":"m"}',
        );
      UsageCall traced(String session, String? id) => UsageCall(
        at: now,
        duration: Duration.zero,
        status: 200,
        provider: 'gw',
        model: 'm',
        session: session,
        traceId: id,
      );
      ledger
        ..record(traced('s1', 'tr1'), trace: trace)
        ..record(traced('s2', null))
        ..flush();
      final call = (await ledger.ofSession('s1')).single;
      expect(call.traceId, 'tr1');
      final back = await ledger.traceOf(call);
      expect(back!.request!.body, '{"model":"m"}');
      expect((await ledger.space()).traces, 1);
      await ledger.clear(const UsageClearSpec(session: 's1'));
      expect(storage.traces['2026-11-01'], isEmpty);
      expect(await ledger.traceOf(call), isNull);
      // The traces alone.
      ledger
        ..record(traced('s3', 'tr1'), trace: trace)
        ..flush();
      await ledger.clearTraces();
      expect((await ledger.space()).traces, 0);
      expect(await ledger.ofSession('s3'), hasLength(1));
    });

    test('keeps only the brief of a call without details, nothing when '
        'off', () async {
      ledger.detailed = false;
      ledger.record(_call(now, results: {'Read': 1}));
      ledger.enabled = false;
      ledger.record(_call(now));
      ledger.flush();
      final calls = await ledger.range();
      expect(calls, hasLength(1));
      expect(calls.single.context, isNull);
      expect(calls.single.toolResults, isEmpty);
    });

    test('clears by time, upstream and conversation', () async {
      for (var day = 1; day <= 5; day++) {
        ledger.record(_call(DateTime(2026, 10, 26 + day, 9)));
        ledger.record(_call(DateTime(2026, 10, 26 + day, 10), provider: 'b'));
      }
      expect(ledger.hasCalls('s9'), isFalse);
      ledger.record(_call(now, session: 's9'));
      ledger.flush();
      // Whether a conversation has any: its usage page offered.
      expect(ledger.hasCalls('s9'), isTrue);
      await ledger.clear(UsageClearSpec(until: DateTime(2026, 10, 29)));
      expect(await storage.days(), [
        '2026-10-29',
        '2026-10-30',
        '2026-10-31',
        '2026-11-01',
      ]);
      await ledger.clear(const UsageClearSpec(providers: {'b'}));
      final left = await ledger.range();
      expect(left.every((call) => call.provider == 'gw'), isTrue);
      expect(left, hasLength(4));
      await ledger.clear(const UsageClearSpec(session: 's9'));
      expect(await ledger.ofSession('s9'), isEmpty);
      expect(ledger.hasCalls('s9'), isFalse);
      expect(ledger.hasCalls('s1'), isTrue);
      await ledger.clear(const UsageClearSpec());
      expect(await ledger.range(), isEmpty);
      expect(ledger.hasCalls('s1'), isFalse);
    });

    test('deletes what is kept longer than the retention', () async {
      ledger
        ..record(_call(DateTime(2026, 9, 1)))
        ..record(_call(DateTime(2026, 10, 20)))
        ..record(_call(now))
        ..flush();
      ledger.retentionDays = 30;
      await ledger.prune();
      expect(await storage.days(), ['2026-10-20', '2026-11-01']);
      ledger.retentionDays = 0;
      await ledger.prune();
      expect(await storage.days(), hasLength(2));
    });
  });

  test('a summary counts by bucket, model, kind, agent, tool and turn', () {
    final start = DateTime(2026, 11, 1, 10);
    final calls = [
      _call(start, cacheRead: 900, results: {'Read': 200}, prompt: 'p1'),
      _call(
        start.add(const Duration(minutes: 30)),
        kind: UsageClass.subagent,
        agent: 'a1',
        model: 'glm',
        results: {'Grep': 50},
        prompt: 'p1',
      ),
      _call(start.add(const Duration(hours: 2)), status: 500, prompt: 'p2'),
      _call(start.add(const Duration(hours: 3)), provider: 'other'),
    ];
    final summary = UsageSummary.of(
      calls,
      UsageFilter(
        from: start,
        until: start.add(const Duration(hours: 4)),
        providers: const {'gw'},
      ),
    );
    expect(summary.step, UsageStep.hour);
    expect(summary.buckets, hasLength(4));
    expect(summary.buckets[0].totals.calls, 2);
    expect(summary.buckets[3].totals.calls, 0);
    expect(summary.totals.calls, 3);
    expect(summary.totals.failed, 1);
    expect(summary.totals.cacheRead, 900);
    expect(summary.totals.cacheHitRate, closeTo(900 / 1200, 1e-9));
    expect(summary.byModel.keys, unorderedEquals(['gpt-5', 'glm']));
    expect(summary.byClass[UsageClass.subagent]!.calls, 1);
    expect(summary.byAgent.keys, unorderedEquals(['', 'a1']));
    expect(summary.byTool['Read']!.resultTokens, 200);
    expect(summary.byTool['Grep']!.calls, 1);
    expect(summary.byPrompt['p1']!.totals.calls, 2);
    // The filters' choices: every upstream of the time, not just those
    // picked.
    expect(summary.providers.keys, unorderedEquals(['gw', 'other']));
    expect(summary.context, hasLength(2));
  });

  test('the files keep a day a file, read off the UI isolate', () async {
    final folder = await Directory.systemTemp.createTemp('usage');
    addTearDown(() => folder.delete(recursive: true));
    final files = UsageFiles(folder.path);
    final ledger = UsageLedger(files);
    addTearDown(ledger.dispose);
    ledger
      ..record(_call(DateTime(2026, 10, 31, 9)))
      ..record(_call(DateTime(2026, 11, 1, 9), session: 's2'))
      ..flush();
    expect(File('${folder.path}/2026-10-31.jsonl').existsSync(), isTrue);
    expect(File('${folder.path}/index.json').existsSync(), isTrue);
    // Another run: read back from the files, the index too.
    final again = UsageLedger(UsageFiles(folder.path));
    addTearDown(again.dispose);
    expect(await again.range(), hasLength(2));
    expect(await again.ofSession('s2'), hasLength(1));
    await again.clear(const UsageClearSpec(session: 's2'));
    expect(File('${folder.path}/2026-11-01.jsonl').existsSync(), isFalse);
    expect((await again.space()).days, 1);
  });

  test('the files keep a trace squeezed, a file each', () async {
    final folder = await Directory.systemTemp.createTemp('usage');
    addTearDown(() => folder.delete(recursive: true));
    final files = UsageFiles(folder.path);
    files.writeTrace('2026-11-01', 'abc', {
      'id': 'abc',
      't': 0,
      'request': {'body': 'x' * 10000},
    });
    // Written off the UI isolate.
    final file = File('${folder.path}/traces/2026-11-01/abc.json.gz');
    for (var i = 0; i < 50 && !file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(file.lengthSync(), lessThan(1000));
    final trace = await files.readTrace('2026-11-01', 'abc');
    expect(trace!.request!.body, hasLength(10000));
    expect((await files.traceSizes())['2026-11-01']!.count, 1);
    await files.deleteTraces('2026-11-01', {'abc'});
    expect(file.existsSync(), isFalse);
  });

  test('a header\'s secret is kept by its ends only', () {
    expect(
      UsageTraceMessage.redact('authorization', 'Bearer sk-abcdefghijklmnop'),
      'Bearer sk-a••••mnop',
    );
    expect(UsageTraceMessage.redact('x-api-key', 'short'), '••••');
    expect(
      UsageTraceMessage.redact('content-type', 'text/plain'),
      'text/plain',
    );
  });
}

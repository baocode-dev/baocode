import 'dart:io';

import 'package:baocode/usage/usage_capture.dart';
import 'package:baocode/usage/usage_ledger.dart';
import 'package:baocode/usage/usage_query.dart';
import 'package:baocode/usage/usage_record.dart';
import 'package:baocode/usage/usage_storage_io.dart';
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
      ledger.record(_call(now, session: 's9'));
      ledger.flush();
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
      await ledger.clear(const UsageClearSpec());
      expect(await ledger.range(), isEmpty);
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
}

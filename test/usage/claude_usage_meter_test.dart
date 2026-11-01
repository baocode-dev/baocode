import 'package:baocode/usage/claude_usage_meter.dart';
import 'package:baocode/usage/usage_prices.dart';
import 'package:baocode/usage/usage_quota.dart';
import 'package:baocode/usage/usage_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 11, 1, 10);
  late DateTime now;
  late List<UsageCall> kept;
  late ClaudeUsageMeter meter;

  void at(int ms) => now = start.add(Duration(milliseconds: ms));
  Map<String, Object?> event(Map<String, Object?> event, [String? parent]) => {
    'type': 'stream_event',
    'event': event,
    'parent_tool_use_id': parent,
  };
  Map<String, Object?> assistant(
    String id,
    Map<String, Object?> usage, {
    String? parent,
    List<Map<String, Object?>> content = const [],
    String model = 'claude-opus-5-5',
  }) => {
    'type': 'assistant',
    'parent_tool_use_id': parent,
    'message': {'id': id, 'model': model, 'usage': usage, 'content': content},
  };

  setUp(() {
    at(0);
    kept = [];
    meter = ClaudeUsageMeter(
      record: kept.add,
      session: () => 's1',
      providerName: 'Claude Max',
      quota: () => {'five_hour': 0.25, 'seven_day': 0.4},
      clock: () => now,
    );
  });

  test('a streamed call timed from its asking, its tokens, cache and '
      'calls as told', () {
    meter
      ..receive({'type': 'system', 'subtype': 'init', 'model': 'opus[1m]'})
      ..receive({
        'type': 'system',
        'subtype': 'status',
        'status': 'requesting',
      });
    at(1000);
    meter.receive(
      event({
        'type': 'message_start',
        'message': {
          'id': 'msg_1',
          'model': 'claude-opus-5-5[1m]',
          'usage': {
            'input_tokens': 10,
            'cache_read_input_tokens': 1000,
            'cache_creation_input_tokens': 200,
            'cache_creation': {'ephemeral_1h_input_tokens': 50},
            'output_tokens': 1,
          },
        },
      }),
    );
    at(1500);
    meter
      ..receive(event({'type': 'content_block_start', 'index': 0}))
      ..receive(event({'type': 'content_block_delta', 'index': 0}));
    at(2000);
    final read = {'type': 'tool_use', 'id': 'toolu_1', 'name': 'Read'};
    meter
      ..receive(
        event({
          'type': 'content_block_start',
          'index': 1,
          'content_block': read,
        }),
      )
      // The whole message as the CLI tells it: its call counted once.
      ..receive(assistant('msg_1', {'output_tokens': 1}, content: [read]))
      ..receive(
        event({
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'output_tokens': 300},
        }),
      );
    at(4000);
    meter.receive(event({'type': 'message_stop'}));
    // Told again after: not kept twice.
    meter.receive(assistant('msg_1', {'output_tokens': 300}));

    expect(kept, hasLength(1));
    final call = kept.single;
    expect(call.at, start);
    expect(call.headers, const Duration(seconds: 1));
    expect(call.firstToken, const Duration(milliseconds: 1500));
    expect(call.duration, const Duration(seconds: 4));
    expect(call.provider, 'claude-code');
    expect(call.providerName, 'Claude Max');
    expect(call.model, 'claude-opus-5-5');
    expect(call.session, 's1');
    expect(
      (call.input, call.cacheRead, call.cacheWrite, call.cacheWriteLong),
      (10, 1000, 200, 50),
    );
    expect(call.output, 300);
    expect(call.stopReason, 'tool_use');
    expect(call.toolCalls, {'Read': 1});
    expect(call.quota, {'five_hour': 0.25, 'seven_day': 0.4});
    expect(call.speed, closeTo(300 / 2.5, 1e-9));
    // Kept and read back as it was.
    final read2 = UsageCall.decode(call.encode())!;
    expect(read2.cacheWriteLong, 50);
    expect(read2.quota, {'five_hour': 0.25, 'seven_day': 0.4});
  });

  test("a subagent's calls, seen whole, counted as its kind's and task's, "
      'not timed; kept at the turn\'s end, the output its messages did not '
      'tell spread over them', () {
    meter.receive(
      assistant(
        'msg_main',
        {'input_tokens': 5, 'output_tokens': 40},
        content: [
          {
            'type': 'tool_use',
            'id': 'toolu_agent',
            'name': 'Agent',
            'input': {'subagent_type': 'Explore', 'description': 'Find it'},
          },
        ],
      ),
    );
    at(3000);
    for (final id in ['msg_sub1', 'msg_sub2']) {
      meter
        ..receive(
          assistant(
            id,
            {'input_tokens': 800, 'output_tokens': 1},
            parent: 'toolu_agent',
            model: 'claude-haiku-5-5',
          ),
        )
        // Its calls answered: the call is done.
        ..receive({'type': 'user', 'parent_tool_use_id': 'toolu_agent'});
    }
    expect(kept, isEmpty);
    // The CLI's totals: 41 more output than told, and no more input: the
    // calls seen whole (the main agent's here too) share it.
    meter.receive({
      'type': 'result',
      'modelUsage': {
        'claude-haiku-5-5': {'inputTokens': 1605, 'outputTokens': 83},
      },
    });
    expect(kept.map((c) => c.requestClass), [
      UsageClass.subagent,
      UsageClass.subagent,
      UsageClass.main,
    ]);
    final sub = kept.first;
    expect(sub.agentId, 'toolu_agent');
    expect(sub.agentType, 'Explore');
    expect(sub.task, 'Find it');
    expect(sub.firstToken, isNull);
    expect(sub.duration, Duration.zero);
    expect(kept.map((c) => c.output), [15, 15, 53]);
    expect(kept.fold(0, (sum, c) => sum + c.output), 83);
  });

  test("the CLI's totals past the calls seen kept as its own call, once; "
      'totals started over taken as they are', () {
    meter.receive(
      assistant('msg_1', {'input_tokens': 100, 'output_tokens': 10}),
    );
    Map<String, Object?> result(int haikuIn) => {
      'type': 'result',
      'modelUsage': {
        'claude-opus-5-5': {'inputTokens': 100, 'outputTokens': 10},
        'claude-haiku-5-5': {'inputTokens': haikuIn, 'outputTokens': 30},
      },
    };
    meter.receive(result(500));
    expect(kept, hasLength(2));
    final own = kept.last;
    expect(own.requestClass, UsageClass.auxiliary);
    expect(own.model, 'claude-haiku-5-5');
    expect((own.input, own.output), (500, 30));
    meter.receive(result(500));
    expect(kept, hasLength(2));
    // A /clear: the totals fell. Nothing kept for it, counted from there.
    meter.receive({
      'type': 'result',
      'modelUsage': {
        'claude-haiku-5-5': {'inputTokens': 20, 'outputTokens': 2},
      },
    });
    expect(kept, hasLength(2));
    meter.receive({
      'type': 'result',
      'modelUsage': {
        'claude-haiku-5-5': {'inputTokens': 70, 'outputTokens': 2},
      },
    });
    expect(kept.last.input, 50);
  });

  test('a request tried again kept as failed', () {
    meter.receive({
      'type': 'system',
      'subtype': 'init',
      'model': 'claude-opus-5-5',
    });
    meter.requested();
    at(2000);
    meter.receive({
      'type': 'system',
      'subtype': 'api_retry',
      'error_status': 529,
      'error': 'overloaded',
      'retry_delay_ms': 1000,
    });
    final failed = kept.single;
    expect(failed.failed, isTrue);
    expect(failed.status, 529);
    expect(failed.duration, const Duration(seconds: 2));
  });

  test("Claude Code's own models priced at Anthropic's where not set", () {
    final prices = UsagePrices();
    final opus = prices.of('claude-code', 'claude-opus-5-5')!;
    expect((opus.input, opus.output, opus.cacheRead), (4, 20, 0.2));
    expect(prices.of('relay', 'claude-opus-5-5'), isNull);
    expect(ClaudePrices.of('claude-sonnet-5-5-20260901')?.input, 2);
    UsageCall call({
      int input = 0,
      int write = 0,
      int long = 0,
      bool fast = false,
      String model = 'claude-opus-5-5',
    }) => UsageCall(
      at: start,
      duration: Duration.zero,
      status: 200,
      provider: 'claude-code',
      model: model,
      input: input,
      cacheWrite: write,
      cacheWriteLong: long,
      fast: fast,
    );
    // A million written, a quarter of it kept an hour: 0.75 × 5 + 0.25 × 8.
    expect(opus.cost(call(write: 1000000, long: 250000)), closeTo(5.75, 1e-9));
    expect(opus.cost(call(input: 1000000, fast: true)), closeTo(8, 1e-9));
    final haiku = prices.of('claude-code', 'claude-haiku-5-5')!;
    expect(haiku.cost(call(input: 100000)), closeTo(0.01, 1e-9));
    // Past 100K, all of it at the long prompts' price.
    expect(haiku.cost(call(input: 200000)), closeTo(0.1, 1e-9));
    // The user's own price first.
    final own = UsagePrices({
      'claude-code/claude-opus-5-5': const ModelPrice(input: 1, output: 1),
    });
    expect(own.of('claude-code', 'claude-opus-5-5')?.input, 1);
  });

  test("a plan's limits over the calls: what each rise took, a fall its "
      'starting over, what 1% of the week came to', () {
    UsageCall call(int hour, double five, double week) => UsageCall(
      at: start.add(Duration(hours: hour)),
      duration: Duration.zero,
      status: 200,
      provider: 'claude-code',
      model: 'claude-sonnet-5-5',
      input: 1000000,
      quota: {'seven_day': week, 'five_hour': five},
    );
    final quota = UsageQuota.of([
      call(0, 0.2, 0.1),
      call(1, 0.5, 0.12),
      call(6, 0.1, 0.13),
    ], prices: UsagePrices());
    expect(quota.windows.map((w) => w.type), ['five_hour', 'seven_day']);
    final five = quota.windows.first;
    expect((five.now, five.peak, five.resets), (0.1, 0.5, 1));
    expect(five.used, closeTo(0.3, 1e-9));
    final week = quota.windows.last;
    expect(week.used, closeTo(0.03, 1e-9));
    // The 2M tokens after the first reading took 3% of the week.
    expect(quota.tokensPerPercent, closeTo(2000000 / 3, 1e-6));
    expect(quota.costPerPercent!.byCurrency['USD'], closeTo(4 / 3, 1e-9));
    expect(UsageQuota.of([call(0, 0.2, 0.1)]).tokensPerPercent, isNull);
  });
}

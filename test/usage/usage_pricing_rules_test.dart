import 'dart:convert';

import 'package:baocode/usage/claude_usage_meter.dart';
import 'package:baocode/usage/usage_capture.dart';
import 'package:baocode/usage/usage_ledger.dart';
import 'package:baocode/usage/usage_prices.dart';
import 'package:baocode/usage/usage_record.dart';
import 'package:baocode/usage/usage_tools.dart';
import 'package:flutter_test/flutter_test.dart';

UsageCall _call({
  DateTime? at,
  String provider = 'gw',
  String model = 'm',
  int input = 1000000,
  int cacheRead = 0,
  int cacheWrite = 0,
  int output = 1000000,
  bool fast = false,
  String? serviceTier,
  String? geo,
  Map<String, int> serverTools = const {},
  int status = 200,
}) => UsageCall(
  at: at ?? DateTime.utc(2026, 11, 2, 12),
  duration: const Duration(seconds: 1),
  status: status,
  provider: provider,
  model: model,
  input: input,
  cacheRead: cacheRead,
  cacheWrite: cacheWrite,
  output: output,
  fast: fast,
  serviceTier: serviceTier,
  geo: geo,
  serverTools: serverTools,
);

void main() {
  tearDown(() => UsagePrices.current = UsagePrices());

  group('tiers by the prompt', () {
    // Qwen's: the band the request is in prices all of it.
    const price = ModelPrice(
      input: 4,
      output: 16,
      cacheRead: 0.8,
      currency: 'CNY',
      tiers: [
        PriceTier(over: 32000, upTo: 128000, input: 6, output: 24),
        PriceTier(over: 128000, upTo: 256000, input: 10, output: 40),
        PriceTier(over: 256000, input: 20, output: 200),
      ],
    );

    test('the band of all the input, the cache too, prices all of it', () {
      final small = _call(input: 20000, output: 1000);
      expect(price.cost(small), closeTo((20000 * 4 + 1000 * 16) / 1e6, 1e-9));
      expect(price.applied(small).tier, isNull);
      // 100K, 80K of it read from the cache: the second band, its cache
      // price as its input is to the first's.
      final mid = _call(input: 20000, cacheRead: 80000, output: 1000);
      expect(price.applied(mid).tier?.label, '32K–128K');
      expect(
        price.cost(mid),
        closeTo((20000 * 6 + 80000 * 0.8 * 1.5 + 1000 * 24) / 1e6, 1e-9),
      );
      final long = _call(input: 300000, output: 1000);
      expect(price.applied(long).tier?.label, '>256K');
      expect(price.cost(long), closeTo((300000 * 20 + 1000 * 200) / 1e6, 1e-9));
    });

    test("by the answer's length too, the last band it is in", () {
      // Doubao's: a short prompt with a short answer is cheaper.
      const doubao = ModelPrice(
        input: 0.8,
        output: 8,
        tiers: [
          PriceTier(upTo: 32000, outputUpTo: 200, input: 0.8, output: 2),
          PriceTier(over: 32000, input: 1.2, output: 16),
        ],
      );
      expect(
        doubao.applied(_call(input: 1000, output: 100)).tier?.label,
        '≤32K · out ≤200',
      );
      expect(doubao.applied(_call(input: 1000, output: 1000)).tier, isNull);
      expect(
        doubao.applied(_call(input: 50000, output: 100)).tier?.label,
        '>32K',
      );
    });

    test('kept as JSON and read back', () {
      expect(ModelPrice.fromJson(jsonDecode(jsonEncode(price))), price);
    });
  });

  group('hours of the week', () {
    // DeepSeek's: peak hours on weekdays (UTC), half price else and on
    // Chinese holidays.
    final price = ModelPrice(
      input: 2,
      output: 8,
      schedule: PriceSchedule.fromJson(const {
        'timezone': 'UTC',
        'windows': [
          {
            'days': [1, 2, 3, 4, 5],
            'from': '01:00',
            'to': '04:00',
            'factor': 1,
          },
          {
            'days': [1, 2, 3, 4, 5],
            'from': '06:00',
            'to': '10:00',
            'factor': 1,
          },
        ],
        'otherwise': 0.5,
        'except': ['2026-10-01'],
      }),
    );

    double time(DateTime at) => price.applied(_call(at: at)).time;

    test('in a window at its factor, else at the rest', () {
      expect(time(DateTime.utc(2026, 11, 2, 2)), 1);
      expect(time(DateTime.utc(2026, 11, 2, 9, 59)), 1);
      expect(time(DateTime.utc(2026, 11, 2, 10)), 0.5);
      expect(time(DateTime.utc(2026, 11, 2, 5)), 0.5);
      // Saturday, and a holiday on a Thursday.
      expect(time(DateTime.utc(2026, 11, 7, 2)), 0.5);
      expect(time(DateTime.utc(2026, 10, 1, 2)), 0.5);
      expect(
        price.cost(_call(at: DateTime.utc(2026, 11, 7, 2))),
        closeTo((2 + 8) * 0.5, 1e-9),
      );
    });

    test('in its timezone; a window past midnight goes on into the next '
        'day', () {
      // A plan's off-peak hours in Beijing: weekdays 18:00 to 14:00.
      final schedule = PriceSchedule.fromJson(const {
        'timezone': 'Asia/Shanghai',
        'windows': [
          {
            'days': [1, 2, 3, 4, 5],
            'from': '18:00',
            'to': '14:00',
            'factor': 0.5,
          },
        ],
        'otherwise': 1,
      })!;
      // Monday 19:00 and Tuesday 08:00 in Beijing; Monday 15:00 not.
      expect(schedule.factorAt(DateTime.utc(2026, 11, 2, 11)), 0.5);
      expect(schedule.factorAt(DateTime.utc(2026, 11, 3)), 0.5);
      expect(schedule.factorAt(DateTime.utc(2026, 11, 2, 7)), 1);
      // Saturday 08:00: Friday's window, into Saturday.
      expect(schedule.factorAt(DateTime.utc(2026, 11, 7)), 0.5);
      // Sunday 08:00: Saturday has none.
      expect(schedule.factorAt(DateTime.utc(2026, 11, 8)), 1);
    });

    test('timezones read as offsets or zones without summer time', () {
      expect(PriceSchedule.parseOffset('UTC'), Duration.zero);
      expect(PriceSchedule.parseOffset('UTC+8'), const Duration(hours: 8));
      expect(
        PriceSchedule.parseOffset('GMT-05:30'),
        -const Duration(hours: 5, minutes: 30),
      );
      expect(PriceSchedule.parseOffset('+0900'), const Duration(hours: 9));
      expect(
        PriceSchedule.parseOffset('Asia/Shanghai'),
        const Duration(hours: 8),
      );
      expect(PriceSchedule.parseOffset('America/New_York'), isNull);
      expect(PriceSchedule.fromJson(const {'timezone': 'Mars'}), isNull);
    });
  });

  test('fast mode, the service tier, the region and a multiplier times '
      'the tokens; fees a call and a tool use besides', () {
    const price = ModelPrice(
      input: 1,
      output: 1,
      fast: 2,
      serviceTiers: {'priority': 2, 'flex': 0.5},
      geo: {'us': 1.1},
      multiplier: 0.5,
      perCall: 0.01,
      tools: {'web_search': 0.01},
    );
    expect(price.cost(_call()), closeTo(2 * 0.5 + 0.01 * 0.5, 1e-9));
    final call = _call(
      fast: true,
      serviceTier: 'priority',
      geo: 'us',
      serverTools: {'web_search': 3, 'web_fetch': 1},
    );
    final applied = price.applied(call);
    expect(
      (applied.fast, applied.service, applied.geo, applied.multiplier),
      (2, 2, 1.1, 0.5),
    );
    final parts = price.parts(call);
    expect(parts.input + parts.output, closeTo(2 * 2 * 2 * 1.1 * 0.5, 1e-9));
    expect(parts.fees, closeTo((0.01 + 0.03) * 0.5, 1e-9));
    expect(parts.total, closeTo(4.4 + 0.02, 1e-9));
    // A failed call pays no fee.
    expect(price.parts(_call(status: 500)).fees, 0);
    expect(price.serviceTiers['standard'], isNull);
    expect(price.applied(_call(serviceTier: 'standard')).service, 1);
  });

  test("Claude's built-in prices: US-only inference at 1.1, a web search "
      r'$10 a thousand, Haiku 5.5 over 100K at five times', () {
    final opus = ClaudePrices.of('claude-opus-5-5')!;
    expect(
      opus.cost(_call(geo: 'us', input: 1000000, output: 0)),
      closeTo(4.4, 1e-9),
    );
    expect(
      opus.parts(_call(serverTools: {'web_search': 2})).fees,
      closeTo(0.02, 1e-9),
    );
    final haiku = ClaudePrices.of('claude-haiku-5-5')!;
    expect(
      haiku.cost(_call(input: 50000, cacheRead: 60000, output: 0)),
      closeTo((50000 * 0.5 + 60000 * 0.05) / 1e6, 1e-9),
    );
  });

  group('prices by date', () {
    final before = DateTime(2026, 10, 20);
    final after = DateTime(2026, 11, 5);
    final prices = UsagePrices();

    test("a price from a date prices the calls since; the one before, those "
        'before', () async {
      await prices.update({'gw/m': const ModelPrice(input: 1, output: 1)});
      await prices.put(
        'gw/m',
        ModelPrice(input: 2, output: 2, from: DateTime(2026, 11)),
      );
      expect(prices.versions('gw/m'), hasLength(2));
      expect(prices.priceOf(_call(at: before))!.input, 1);
      expect(prices.priceOf(_call(at: after))!.input, 2);
      expect(prices.all['gw/m']!.input, 2);
      // Kept as a list, read back the same.
      final json = jsonDecode(
        jsonEncode({
          'gw/m': [for (final price in prices.versions('gw/m')) price.toJson()],
        }),
      );
      expect(UsagePrices.parseVersions(json)['gw/m'], prices.versions('gw/m'));
      // Only dated ones: the earliest prices the calls before it.
      final dated = UsagePrices.parseVersions({
        'gw/m': [
          {'input': 3, 'output': 3, 'from': '2026-12-01'},
          {'input': 2, 'output': 2, 'from': '2026-11-01'},
        ],
      });
      expect(dated['gw/m']!.map((p) => p.input), [2, 3]);

      await prices.removeVersion('gw/m', DateTime(2026, 11));
      expect(prices.priceOf(_call(at: after))!.input, 1);
      await prices.update({'gw/m': null});
      expect(prices.all, isEmpty);
    });
  });

  test("an upstream's rate prices its models as theirs elsewhere, times it, "
      'in its currency; a price of its own first', () {
    final prices = UsagePrices(
      {
        '*/glm-5': const ModelPrice(input: 1, output: 4),
        'relay/own': const ModelPrice(input: 9, output: 9),
      },
      {
        'relay': const UpstreamRate(
          multiplier: 0.3,
          currency: 'CNY',
          perCall: 0.01,
        ),
      },
    );
    final glm = prices.of('relay', 'glm-5')!;
    expect(glm.currency, 'CNY');
    expect(
      glm.cost(_call(provider: 'relay', model: 'glm-5')),
      closeTo((1 + 4) * 0.3 + 0.01, 1e-9),
    );
    // Claude's at Anthropic's, on an upstream of a rate.
    final opus = prices.of('relay', 'claude-opus-5-5')!;
    expect(opus.multiplier, 0.3);
    expect(prices.of('other', 'claude-opus-5-5'), isNull);
    expect(prices.of('relay', 'own')!.input, 9);
    expect(prices.basisOf('relay', 'own')!.rate, isNull);
    expect(prices.basisOf('relay', 'glm-5')!.key, '*/glm-5');
    expect(prices.basisOf('relay', 'claude-opus-5-5')!.key, isNull);
    expect(prices.of('relay', 'unknown'), isNull);
  });

  group('the tool', () {
    final now = DateTime(2026, 11, 2, 12);
    late UsageLedger ledger;

    setUp(() {
      ledger = UsageLedger(MemoryUsageStorage(), clock: () => now)
        ..record(
          _call(
            at: now,
            serviceTier: 'priority',
            geo: 'us',
            serverTools: {'web_search': 2},
          ),
        )
        ..flush();
    });

    tearDown(() => ledger.dispose());

    test('sets every rule, dated prices and rates; says what does not read; '
        'lists what the calls had', () async {
      final prices = UsagePrices();
      final set = await UsageTools.pricesOf(
        const {
          'set': [
            {
              'model': 'm',
              'upstream': 'gw',
              'input': 4,
              'output': 16,
              'cache_write_1h': 8,
              'currency': 'CNY',
              'tiers': [
                {'over': 32000, 'input': 6, 'output': 24, 'cache_read': 1.2},
              ],
              'schedule': {
                'timezone': 'UTC+8',
                'windows': [
                  // At 1: the test's call priced the same in any timezone.
                  {'from': '00:30', 'to': '08:30', 'factor': 1},
                ],
              },
              'fast': 2,
              'service_tiers': {'priority': 2},
              'geo': {'us': 1.1},
              'multiplier': 0.9,
              'per_call': 0.001,
              'tools': {'web_search': 0.05},
              'source': 'https://example.com/pricing',
            },
            {
              'model': 'm',
              'upstream': 'gw',
              'input': 5,
              'output': 20,
              'from': '2026-12-01',
            },
            {
              'model': 'bad',
              'input': 1,
              'output': 1,
              'schedule': {'timezone': 'Mars', 'windows': []},
            },
            {
              'model': 'bad2',
              'input': 1,
              'output': 1,
              'tiers': [
                {'over': 1000},
              ],
            },
          ],
          'set_upstream_rates': [
            {'upstream': 'relay', 'multiplier': 0.3, 'currency': 'CNY'},
            {'upstream': 'zero', 'multiplier': 0},
          ],
        },
        ledger: ledger,
        prices: prices,
        now: now,
      );
      expect(set['changed'], 3);
      expect(set['errors'], hasLength(3));
      final price = prices.of('gw', 'm', at: now)!;
      expect(price.cacheWriteLong, 8);
      expect(price.tiers.single.cacheRead, 1.2);
      expect(price.schedule!.offset, const Duration(hours: 8));
      expect(price.fast, 2);
      expect(price.serviceTiers, {'priority': 2});
      expect(price.geo, {'us': 1.1});
      expect(price.multiplier, 0.9);
      expect(price.perCall, 0.001);
      expect(price.tools, {'web_search': 0.05});
      expect(price.updated, now);
      expect(prices.of('gw', 'm', at: DateTime(2026, 12, 2))!.input, 5);
      expect(prices.rates['relay']!.multiplier, 0.3);

      final listed = await UsageTools.pricesOf(
        const {},
        ledger: ledger,
        prices: prices,
        now: now,
      );
      final model = (listed['modelsCalledLast30Days']! as List).single as Map;
      expect(model['serviceTiersSeen'], ['priority']);
      expect(model['geosSeen'], ['us']);
      expect(model['serverToolsSeen'], ['web_search']);
      expect(model['pricedAs'], 'own');
      expect((listed['prices']! as Map)['gw/m'], hasLength(2));
      expect((listed['upstreamRates']! as Map).keys, ['relay']);

      // A call's report says what priced it.
      UsagePrices.current = prices;
      final report = await UsageTools.reportOf(
        const {'session': 'all'},
        current: null,
        ledger: ledger,
        prices: prices,
        now: now,
      );
      final call = (report['latestCalls']! as List).single as Map;
      expect(call['serviceTier'], 'priority');
      expect(call['pricedBy'], {
        'tier': '>32K',
        'serviceTier': 2.0,
        'geo': 1.1,
        'multiplier': 0.9,
        'fees': closeTo((0.001 + 0.1) * 0.9, 1e-6),
      });

      await UsageTools.pricesOf(
        const {
          'remove': [
            {'model': 'm', 'upstream': 'gw', 'from': '2026-12-01'},
          ],
          'remove_upstream_rates': ['relay'],
        },
        ledger: ledger,
        prices: prices,
        now: now,
      );
      expect(prices.versions('gw/m'), hasLength(1));
      expect(prices.rates, isEmpty);
    });
  });

  group('captured', () {
    test("Anthropic's usage: the service tier, the region and the tools "
        'run', () {
      final meter = UsageMeter(
        provider: 'gw',
        model: 'm',
        info: const UsageRequestInfo(requestClass: UsageClass.main),
      );
      String line(Map<String, Object?> event) => 'data: ${jsonEncode(event)}\n';
      meter
        ..events(
          line({
            'type': 'message_start',
            'message': {
              'usage': {
                'input_tokens': 10,
                'service_tier': 'priority',
                'inference_geo': 'us',
              },
            },
          }),
        )
        ..events(
          line({
            'type': 'content_block_start',
            'content_block': {'type': 'server_tool_use', 'name': 'web_fetch'},
          }),
        )
        ..events(
          line({
            'type': 'message_delta',
            'usage': {
              'output_tokens': 5,
              'server_tool_use': {'web_search_requests': 2},
            },
          }),
        );
      final call = meter.finish(200)!;
      expect(call.serviceTier, 'priority');
      expect(call.geo, 'us');
      expect(call.serverTools, {'web_search': 2, 'web_fetch': 1});
      final read = UsageCall.decode(call.encode())!;
      expect((read.serviceTier, read.geo), ('priority', 'us'));
      expect(read.serverTools, {'web_search': 2, 'web_fetch': 1});
      expect(read.brief.serverTools, call.serverTools);
    });

    test("an OpenAI upstream's service tier and web searches", () {
      final meter =
          UsageMeter(
              provider: 'gw',
              model: 'm',
              info: const UsageRequestInfo(requestClass: UsageClass.main),
            )
            ..upstreamLine(
              'data: {"id":"x","service_tier":"flex","choices":[]}',
            )
            ..upstreamLine(
              'data: {"type":"response.output_item.added","item":'
              '{"type":"web_search_call"}}',
            )
            ..upstreamLine(
              'data: {"type":"response.output_item.done","item":'
              '{"type":"web_search_call"}}',
            )
            ..upstreamLine(
              'data: {"type":"response.output_item.done","item":'
              '{"type":"web_search_call"}}',
            )
            ..upstreamLine(
              'data: {"type":"response.completed","response":{"output":'
              '[{"type":"web_search_call"},{"type":"web_search_call"}]}}',
            );
      final call = meter.finish(200)!;
      expect(call.serviceTier, 'flex');
      expect(call.serverTools, {'web_search': 2});
    });

    test("Claude Code's own: as its usage tells", () {
      final kept = <UsageCall>[];
      ClaudeUsageMeter(
          record: (call, {trace}) => kept.add(call),
          session: () => 's1',
          clock: () => DateTime(2026, 11, 2),
        )
        ..receive({
          'type': 'system',
          'subtype': 'status',
          'status': 'requesting',
        })
        ..receive({
          'type': 'stream_event',
          'event': {
            'type': 'message_start',
            'message': {
              'id': 'msg_1',
              'model': 'claude-opus-5-5',
              'usage': {
                'input_tokens': 10,
                'service_tier': 'standard',
                'inference_geo': 'us',
              },
            },
          },
        })
        ..receive({
          'type': 'stream_event',
          'event': {
            'type': 'message_delta',
            'usage': {
              'output_tokens': 5,
              'server_tool_use': {'web_search_requests': 3},
            },
          },
        })
        ..receive({
          'type': 'stream_event',
          'event': {'type': 'message_stop'},
        });
      final call = kept.single;
      expect(call.serviceTier, 'standard');
      expect(call.geo, 'us');
      expect(call.serverTools, {'web_search': 3});
    });
  });
}

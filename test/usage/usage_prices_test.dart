import 'package:baocode/usage/usage_ledger.dart';
import 'package:baocode/usage/usage_prices.dart';
import 'package:baocode/usage/usage_query.dart';
import 'package:baocode/usage/usage_record.dart';
import 'package:baocode/usage/usage_skill.dart';
import 'package:baocode/usage/usage_tools.dart';
import 'package:flutter_test/flutter_test.dart';

UsageCall _call(
  DateTime at, {
  String provider = 'gw',
  String model = 'glm-5',
  String session = 's1',
  int input = 1000000,
  int cacheRead = 2000000,
  int cacheWrite = 0,
  int output = 100000,
}) => UsageCall(
  at: at,
  duration: const Duration(seconds: 3),
  firstToken: const Duration(milliseconds: 500),
  status: 200,
  provider: provider,
  providerName: provider.toUpperCase(),
  model: model,
  session: session,
  input: input,
  cacheRead: cacheRead,
  cacheWrite: cacheWrite,
  output: output,
  context: const UsageContext(system: 100, toolResult: 400),
);

void main() {
  final now = DateTime(2026, 11, 1, 15);

  tearDown(() => UsagePrices.current = UsagePrices());

  test('a price costs each kind a million tokens, the cache at the '
      "input's where not given", () {
    const price = ModelPrice(input: 2, output: 8, cacheRead: 0.5);
    // 1M input, 2M read from the cache, 0.1M out.
    expect(price.cost(_call(now)), closeTo(2 + 1 + 0.8, 1e-9));
    const plain = ModelPrice(input: 2, output: 8);
    expect(plain.cost(_call(now, cacheWrite: 1000000)), closeTo(8.8, 1e-9));
    expect(
      ModelPrice.fromJson(const {
        'input': '1.5',
        'output': 6,
        'currency': 'cny',
      }),
      const ModelPrice(input: 1.5, output: 6, currency: 'CNY'),
    );
    expect(ModelPrice.fromJson(const {'input': 1}), isNull);
  });

  test("a model's own upstream's price first, else any upstream's", () {
    final prices = UsagePrices({
      'gw/glm-5': const ModelPrice(input: 4, output: 16, currency: 'CNY'),
      '*/glm-5': const ModelPrice(input: 1, output: 2),
    });
    expect(prices.of('gw', 'glm-5')?.currency, 'CNY');
    expect(prices.of('other', 'glm-5')?.input, 1);
    expect(prices.of('gw', 'gpt-5'), isNull);
    expect(UsagePrices.parseKey('*/glm-5'), (upstream: null, model: 'glm-5'));
    expect(UsagePrices.money(1.234, 'USD'), r'$1.23');
    expect(UsagePrices.money(0.0042, 'CNY'), '¥0.0042');
  });

  test('a summary counts the costs by currency, the unpriced apart', () {
    UsagePrices.current = UsagePrices({
      'gw/glm-5': const ModelPrice(input: 4, output: 16, currency: 'CNY'),
      '*/gpt-5': const ModelPrice(input: 1, output: 10),
    });
    final summary = UsageSummary.of([
      _call(now),
      _call(now, model: 'gpt-5', cacheRead: 0),
      _call(now, model: 'kimi'),
    ], const UsageFilter());
    // glm-5: 4 + 2×4 (the cache at the input's) + 1.6.
    expect(summary.totals.cost.byCurrency['CNY'], closeTo(13.6, 1e-9));
    expect(summary.totals.cost.byCurrency['USD'], closeTo(2, 1e-9));
    expect(summary.totals.cost.unpriced, 1);
    expect(summary.byModel['kimi']!.totals.cost.text, isNull);
  });

  test('a cost in parts by the kind of token, and what the cache saved', () {
    UsagePrices.current = UsagePrices({
      'gw/glm-5': const ModelPrice(input: 2, output: 8, cacheRead: 0.5),
    });
    final summary = UsageSummary.of([
      _call(now),
      _call(now, cacheWrite: 1000000),
    ], const UsageFilter());
    final parts = summary.totals.cost.parts['USD']!;
    expect(parts.input, closeTo(4, 1e-9));
    expect(parts.cacheRead, closeTo(2, 1e-9));
    // Written at the input's: no price of its own.
    expect(parts.cacheWrite, closeTo(2, 1e-9));
    expect(parts.output, closeTo(1.6, 1e-9));
    expect(parts.total, closeTo(summary.totals.cost.byCurrency['USD']!, 1e-9));
    // 4M read at 0.5 in place of 2.
    expect(parts.saved, closeTo(6, 1e-9));
    expect(summary.totals.cost.savedText, r'$6.00');
    expect(
      summary.buckets.fold(
        0.0,
        (sum, b) => sum + (b.totals.cost.parts['USD']?.output ?? 0),
      ),
      closeTo(1.6, 1e-9),
    );
  });

  group('the agents\' tools', () {
    late UsageLedger ledger;

    setUp(() {
      ledger = UsageLedger(MemoryUsageStorage(), clock: () => now);
      UsageLedger.titleOf = (session) => 'Title of $session';
      ledger
        ..record(_call(DateTime(2026, 11, 1, 10)))
        ..record(_call(DateTime(2026, 11, 1, 11), session: 's2'))
        ..record(_call(DateTime(2026, 11, 1, 12), model: 'gpt-5'))
        ..flush();
    });

    tearDown(() {
      UsageLedger.titleOf = null;
      ledger.dispose();
    });

    test('report this conversation, another, or all of them', () async {
      final prices = UsagePrices({
        '*/glm-5': const ModelPrice(input: 1, output: 2),
      });
      final mine = await UsageTools.reportOf(
        const {},
        current: 's1',
        ledger: ledger,
        prices: prices,
        now: now,
      );
      expect(mine['title'], 'Title of s1');
      final totals = mine['totals']! as Map;
      expect(totals['calls'], 2);
      expect(totals['avgFirstTokenMs'], 500);
      expect(totals['cost'], {'USD': closeTo(3.2, 1e-9)});
      expect(totals['unpricedCalls'], 1);
      expect(mine['latestContext'], isNotNull);
      expect((mine['latestCalls']! as List).first['model'], 'gpt-5');

      final all = await UsageTools.reportOf(
        const {'session': 'all', 'days': 3},
        current: null,
        ledger: ledger,
        prices: prices,
        now: now,
      );
      expect((all['totals']! as Map)['calls'], 3);
      expect((all['byConversation']! as List), hasLength(2));

      final none = await UsageTools.reportOf(
        const {},
        current: null,
        ledger: ledger,
        prices: prices,
        now: now,
      );
      expect(none['error'], isNotNull);
    });

    test("a Claude plan's limits reported with its calls", () async {
      for (final (hour, week) in [(13, 0.2), (14, 0.25)]) {
        ledger.record(
          UsageCall(
            at: DateTime(2026, 11, 1, hour),
            duration: Duration.zero,
            status: 200,
            provider: 'claude-code',
            model: 'claude-opus-5-5',
            session: 's1',
            input: 1000000,
            quota: {'seven_day': week},
          ),
        );
      }
      ledger.flush();
      final report = await UsageTools.reportOf(
        const {},
        current: 's1',
        ledger: ledger,
        prices: UsagePrices(),
        now: now,
      );
      final limits = report['claudePlanLimits']! as Map;
      expect(limits['seven_day'], {
        'nowPercent': 25,
        'usedPercentInPeriod': 5,
        'peakPercent': 25,
        'resets': 0,
      });
      expect(limits['tokensPerPercentOfWeek'], 200000);
      expect(limits['apiPriceCostPerPercentOfWeek'], {
        'USD': closeTo(0.8, 1e-9),
      });
    });

    test('prices listed with the models called, set and removed', () async {
      final prices = UsagePrices();
      final listed = await UsageTools.pricesOf(
        const {},
        ledger: ledger,
        prices: prices,
        now: now,
      );
      expect([
        for (final m in listed['modelsCalledLast30Days']! as List) m['model'],
      ], unorderedEquals(['glm-5', 'gpt-5']));

      final set = await UsageTools.pricesOf(
        const {
          'set': [
            {
              'model': 'glm-5',
              'upstream': 'gw',
              'input': 4,
              'output': 16,
              'cache_read': 1,
              'currency': 'CNY',
              'source': 'https://example.com/pricing',
            },
            {'model': 'bad'},
          ],
        },
        ledger: ledger,
        prices: prices,
        now: now,
      );
      expect(set['changed'], 1);
      expect(set['errors'], hasLength(1));
      final price = prices.of('gw', 'glm-5')!;
      expect(price.cacheRead, 1);
      expect(price.source, 'https://example.com/pricing');
      expect(price.updated, now);

      await UsageTools.pricesOf(
        const {
          'remove': [
            {'model': 'glm-5', 'upstream': 'gw'},
          ],
        },
        ledger: ledger,
        prices: prices,
        now: now,
      );
      expect(prices.all, isEmpty);
    });
  });

  test("the skill is written where there is none or it is BaoCode's", () {
    final text = UsageSkill.text();
    expect(text, contains('mcp__baocode__usage_report'));
    expect(text, contains('mcp__baocode__model_prices'));
    expect(UsageSkill.stale(null, text), isTrue);
    expect(UsageSkill.stale(text, text), isFalse);
    expect(UsageSkill.stale('${UsageSkill.marker}\nold', text), isTrue);
    expect(UsageSkill.stale('my own skill', text), isFalse);
  });
}

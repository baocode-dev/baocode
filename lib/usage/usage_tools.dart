import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;

import '../kernel/claude_code/claude_environment.dart';
import '../kernel/claude_code/claude_sdk_tools.dart';
import '../models/model_providers.dart';
import 'usage_ledger.dart';
import 'usage_prices.dart';
import 'usage_query.dart';
import 'usage_quota.dart';
import 'usage_record.dart';
import 'usage_skill.dart';

/// The agents' tools for the calls BaoCode keeps (UsageLedger) and the
/// models' prices (UsagePrices): `mcp__baocode__usage_report` and
/// `mcp__baocode__model_prices`, which the baocode-usage skill tells of.
abstract final class UsageTools {
  static const report = 'usage_report';
  static const prices = 'model_prices';

  static void start() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    unawaited(_installSkill());
    ClaudeSdkTools.register(
      ClaudeSdkTool(
        name: report,
        description: _reportDescription,
        inputSchema: _reportSchema,
        summary: (input, _) => switch (input['session']) {
          final String id when id.isNotEmpty && id != 'current' => id,
          _ => 'usage',
        },
        run: (input, call) async => jsonEncode(
          await reportOf(
            input,
            current: call.sessionId,
            ledger: UsageLedger.current,
            prices: UsagePrices.current,
          ),
        ),
      ),
    );
    ClaudeSdkTools.register(
      ClaudeSdkTool(
        name: prices,
        description: _pricesDescription,
        inputSchema: _pricesSchema,
        summary: (input, _) =>
            switch ((input['set'], input['set_upstream_rates'])) {
              (final List set, _) when set.isNotEmpty => 'set ${set.length}',
              (_, final List rates) when rates.isNotEmpty => 'rates',
              _ => 'prices',
            },
        run: (input, call) async => jsonEncode(
          await pricesOf(
            input,
            ledger: UsageLedger.current,
            prices: UsagePrices.current,
            upstreams: ModelProviders.current,
          ),
        ),
      ),
    );
  }

  /// Writes the skill (UsageSkill) into Claude Code's skills on this
  /// machine: where there is none, or BaoCode's is not the same.
  static Future<void> _installSkill() async {
    try {
      final path = p.join(
        await ClaudeEnvironment.configDir(),
        'skills',
        UsageSkill.name,
        'SKILL.md',
      );
      final file = File(path);
      final existing = await file.exists() ? await file.readAsString() : null;
      final text = UsageSkill.text();
      if (!UsageSkill.stale(existing, text)) return;
      await file.parent.create(recursive: true);
      await file.writeAsString(text);
    } on Object catch (error) {
      debugPrint('The usage skill was not written: $error');
    }
  }

  static const _reportDescription =
      "Reports the model calls BaoCode kept for the user's conversations, "
      "on Claude Code's own models (a Claude plan, with its limits as they "
      'stood after each call) and on custom upstreams: tokens (input, cache read, cache write, '
      'output), cache hit rate, time to first token, duration, output speed '
      '(tok/s), failures and cost (at the prices in Settings → Usage), by '
      'model and by agent, what filled the latest context, and the latest '
      'calls one by one. Without `session` it reports this conversation; '
      'give another conversation\'s id, or `"all"` for every conversation '
      'over the last `days`.';

  static const _reportSchema = <String, Object?>{
    'type': 'object',
    'properties': {
      'session': {
        'type': 'string',
        'description':
            '"current" (the default), a conversation\'s id, or "all".',
      },
      'days': {
        'type': 'integer',
        'description': 'With "all": how many days back (default 7).',
      },
      'calls': {
        'type': 'integer',
        'description':
            'How many of the latest calls to list (default 10, '
            'at most 50).',
      },
    },
  };

  static const _pricesDescription =
      'Reads or sets the models\' prices BaoCode works out costs with '
      '(Settings → Usage → Model prices), each a million tokens: input, '
      'output, cache read and cache write, in a currency; and the rules '
      'upstreams price by beyond that: prices by the prompt\'s length '
      '(`tiers`), by the time of the week (`schedule`: peak and off-peak), '
      'fast mode, service tiers and regions (`fast`, `service_tiers`, '
      '`geo`), a multiplier, a fee a call and a fee a use of the '
      'upstream\'s own tools (`per_call`, `tools`), and the date a price is '
      'from (`from`). `set_upstream_rates` prices every model of an upstream '
      '(a relay, its group\'s rate) as the same model\'s price elsewhere '
      'times a multiplier. Without any of `set`, `remove`, '
      '`set_upstream_rates` or `remove_upstream_rates` it lists the models '
      'called lately, the upstream each is called on (its name and base '
      'URL, for its pricing page), what their calls had (service tiers, '
      'regions, tools run), their prices and the upstreams\' rates. Set a '
      'price only as read from the upstream\'s own pricing page, with that '
      'page as `source`; a cache price left out is taken as the input\'s.';

  static const _tierSchema = <String, Object?>{
    'type': 'object',
    'description':
        'Prices for the calls within it: their prompt (all input tokens, '
        'cache reads and writes too) more than `over` and at most `up_to`, '
        'their output more than `output_over` and at most `output_up_to` '
        '(each optional). The last tier a call is within prices all of its '
        'tokens; one within none is at the price\'s own.',
    'properties': {
      'over': {'type': 'integer'},
      'up_to': {'type': 'integer'},
      'output_over': {'type': 'integer'},
      'output_up_to': {'type': 'integer'},
      'input': {'type': 'number'},
      'output': {'type': 'number'},
      'cache_read': {'type': 'number'},
      'cache_write': {'type': 'number'},
      'cache_write_1h': {'type': 'number'},
    },
    'required': ['input', 'output'],
  };

  static const _scheduleSchema = <String, Object?>{
    'type': 'object',
    'description':
        'Prices by the time of the week: a call in one of `windows` (the '
        'first) is at its `factor` times, any other at `otherwise` (default '
        '1); on the dates of `except` (e.g. public holidays) at `otherwise` '
        'all day.',
    'properties': {
      'timezone': {
        'type': 'string',
        'description':
            'The page\'s: "UTC", an offset ("UTC+8", "-05:00"), or '
            'Asia/Shanghai, Asia/Tokyo, Asia/Seoul, Asia/Singapore, '
            'Asia/Hong_Kong, Asia/Taipei, Asia/Kolkata, Asia/Dubai. Zones '
            'with summer time: give the offset in force.',
      },
      'windows': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'days': {
              'type': 'array',
              'items': {'type': 'integer'},
              'description': '1 Monday … 7 Sunday; left out, every day.',
            },
            'from': {'type': 'string', 'description': '"HH:MM"'},
            'to': {
              'type': 'string',
              'description':
                  '"HH:MM" ("24:00" the day\'s end); one not after `from` '
                  'goes on past midnight.',
            },
            'factor': {'type': 'number'},
          },
          'required': ['from', 'to', 'factor'],
        },
      },
      'otherwise': {'type': 'number'},
      'except': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Dates, "YYYY-MM-DD", in `timezone`.',
      },
    },
    'required': ['timezone', 'windows'],
  };

  static const _pricesSchema = <String, Object?>{
    'type': 'object',
    'properties': {
      'set': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'model': {'type': 'string'},
            'upstream': {
              'type': 'string',
              'description':
                  'The upstream\'s id as listed; left out, the model\'s '
                  'price on any upstream.',
            },
            'input': {'type': 'number'},
            'output': {'type': 'number'},
            'cache_read': {'type': 'number'},
            'cache_write': {
              'type': 'number',
              'description': 'The cache written (Anthropic\'s 5 minutes).',
            },
            'cache_write_1h': {
              'type': 'number',
              'description': 'The cache written to be kept an hour.',
            },
            'currency': {
              'type': 'string',
              'description': 'ISO 4217, e.g. USD or CNY (default USD).',
            },
            'tiers': {'type': 'array', 'items': _tierSchema},
            'schedule': _scheduleSchema,
            'fast': {
              'type': 'number',
              'description': 'Fast mode\'s prices, times (e.g. 2).',
            },
            'service_tiers': {
              'type': 'object',
              'additionalProperties': {'type': 'number'},
              'description':
                  'By the service tier a call was answered at, as listed '
                  '(e.g. {"priority": 2, "flex": 0.5}): its prices times.',
            },
            'geo': {
              'type': 'object',
              'additionalProperties': {'type': 'number'},
              'description':
                  'By where a call was answered, as listed (e.g. '
                  '{"us": 1.1}): its prices times.',
            },
            'multiplier': {
              'type': 'number',
              'description': 'All of it times (a discount, a group rate).',
            },
            'per_call': {
              'type': 'number',
              'description': 'A fee each call, in the currency.',
            },
            'tools': {
              'type': 'object',
              'additionalProperties': {'type': 'number'},
              'description':
                  'A fee each use of the upstream\'s own tools, by the name '
                  'listed (e.g. {"web_search": 0.01} for \$10 a thousand).',
            },
            'from': {
              'type': 'string',
              'description':
                  '"YYYY-MM-DD": the price from that day on, the model\'s '
                  'others kept for the calls before. Left out, it is the '
                  'model\'s only price, for all of its calls.',
            },
            'source': {
              'type': 'string',
              'description': 'The pricing page it was read on.',
            },
          },
          'required': ['model', 'input', 'output'],
        },
      },
      'remove': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'model': {'type': 'string'},
            'upstream': {'type': 'string'},
            'from': {
              'type': 'string',
              'description': 'Only the price from that date.',
            },
          },
          'required': ['model'],
        },
      },
      'set_upstream_rates': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'upstream': {'type': 'string'},
            'multiplier': {
              'type': 'number',
              'description':
                  'Its models\' prices, those elsewhere (any upstream\'s, '
                  'or Anthropic\'s for Claude\'s), times: e.g. 0.3 for a '
                  'relay at 30%; with its own currency, the exchange too.',
            },
            'currency': {
              'type': 'string',
              'description': 'What it charges in, where not the prices\'.',
            },
            'per_call': {'type': 'number'},
            'source': {'type': 'string'},
          },
          'required': ['upstream', 'multiplier'],
        },
      },
      'remove_upstream_rates': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
  };

  static int _int(Object? raw, int fallback, {int min = 0, int max = 1000}) {
    final value = raw is num ? raw.toInt() : int.tryParse('$raw') ?? fallback;
    return value.clamp(min, max);
  }

  static Map<String, Object?> _totals(UsageTotals t) => {
    'calls': t.calls,
    if (t.failed > 0) 'failed': t.failed,
    'input': t.input,
    'cacheRead': t.cacheRead,
    'cacheWrite': t.cacheWrite,
    'output': t.output,
    if (t.reasoning > 0) 'reasoning': t.reasoning,
    'cacheHitRate': double.parse(t.cacheHitRate.toStringAsFixed(4)),
    'avgFirstTokenMs': ?t.averageFirstToken?.inMilliseconds,
    'avgDurationMs': ?t.averageDuration?.inMilliseconds,
    if (t.averageSpeed case final speed?)
      'avgOutputTokensPerSecond': double.parse(speed.toStringAsFixed(1)),
    if (t.cost.byCurrency.isNotEmpty)
      'cost': {
        for (final MapEntry(:key, :value) in t.cost.byCurrency.entries)
          key: double.parse(value.toStringAsFixed(6)),
      },
    if (t.cost.unpriced > 0) 'unpricedCalls': t.cost.unpriced,
  };

  static Map<String, Object?> _call(UsageCall call, UsagePrices prices) {
    final price = prices.priceOf(call);
    return {
      'at': call.at.toIso8601String(),
      'model': call.model,
      'upstream': call.providerName ?? call.provider,
      'kind': call.requestClass.name,
      'agent': ?call.agentType,
      if (call.failed) 'status': call.status,
      'error': ?call.error,
      'input': call.input,
      'cacheRead': call.cacheRead,
      'cacheWrite': call.cacheWrite,
      'output': call.output,
      'serviceTier': ?call.serviceTier,
      'geo': ?call.geo,
      if (call.serverTools.isNotEmpty) 'serverTools': call.serverTools,
      'firstTokenMs': ?call.firstToken?.inMilliseconds,
      'durationMs': call.duration.inMilliseconds,
      if (call.speed case final speed?)
        'outputTokensPerSecond': double.parse(speed.toStringAsFixed(1)),
      if (price != null) ...{
        'cost': {
          price.currency: double.parse(price.cost(call).toStringAsFixed(6)),
        },
        if (pricedBy(price, call) case final rules when rules.isNotEmpty)
          'pricedBy': rules,
      },
      if (call.toolCalls.isNotEmpty) 'toolCalls': call.toolCalls,
    };
  }

  /// What priced [call] at [price] beyond its tokens' own prices: the tier
  /// its prompt is in, the factors not 1, the fees.
  static Map<String, Object?> pricedBy(ModelPrice price, UsageCall call) {
    final applied = price.applied(call);
    double round(double value) => double.parse(value.toStringAsFixed(6));
    return {
      if (applied.tier case final tier?) 'tier': tier.label,
      if (applied.time != 1) 'time': applied.time,
      if (applied.fast != 1) 'fast': applied.fast,
      if (applied.service != 1) 'serviceTier': applied.service,
      if (applied.geo != 1) 'geo': applied.geo,
      if (applied.multiplier != 1) 'multiplier': applied.multiplier,
      if (applied.fees > 0) 'fees': round(applied.fees),
    };
  }

  /// The report [input] asks for ([report]'s schema), [current] the
  /// calling agent's session.
  @visibleForTesting
  static Future<Map<String, Object?>> reportOf(
    Map<String, Object?> input, {
    required String? current,
    required UsageLedger ledger,
    required UsagePrices prices,
    DateTime? now,
  }) async {
    final asked = switch (input['session']) {
      final String id when id.trim().isNotEmpty => id.trim(),
      _ => 'current',
    };
    final all = asked == 'all';
    final session = asked == 'current' ? current : asked;
    final at = now ?? DateTime.now();
    final days = _int(input['days'], 7, min: 1, max: 365);
    final listed = _int(input['calls'], 10, max: 50);
    if (!all && session == null) {
      return {'error': 'No conversation to report: give its id, or "all".'};
    }
    final calls = all
        ? await ledger.range(from: at.subtract(Duration(days: days)))
        : await ledger.ofSession(session!);
    if (calls.isEmpty) {
      return {
        'scope': all ? 'all, last $days days' : 'conversation $session',
        'calls': 0,
        'note':
            'No calls kept: Settings → Usage keeps them while it is on, '
            'from the sessions started since.',
      };
    }
    final summary = UsageSummary.of(
      calls,
      const UsageFilter(),
      now: at,
      prices: prices,
    );
    final latest = summary.calls.lastOrNull;
    final title = session == null ? null : UsageLedger.titleOf?.call(session);
    return {
      'scope': all
          ? 'all conversations, last $days days'
          : 'conversation $session',
      'title': ?(title ?? summary.bySession[session]?.label),
      'from': summary.totals.first?.toIso8601String(),
      'until': summary.totals.last?.toIso8601String(),
      'totals': _totals(summary.totals),
      'byModel': [
        for (final group in UsageSummary.ranked(summary.byModel))
          {
            'model': group.key,
            'upstream': group.detail,
            ..._totals(group.totals),
          },
      ],
      if (!all)
        'byAgent': [
          for (final group in UsageSummary.ranked(summary.byAgent))
            {
              'agent': group.key.isEmpty ? 'main' : group.label ?? group.key,
              'task': ?group.detail,
              ..._totals(group.totals),
            },
        ],
      if (all)
        'byConversation': [
          for (final group in UsageSummary.ranked(summary.bySession).take(20))
            {
              'session': group.key,
              'title': ?(UsageLedger.titleOf?.call(group.key) ?? group.label),
              ..._totals(group.totals),
            },
        ],
      if (latest?.context case final context? when !all)
        'latestContext': {
          'promptTokens': latest!.prompt,
          'estimatedParts': {
            for (final (key, value) in context.parts)
              if (value > 0) key: value,
          },
        },
      if (UsageQuota.of(summary.calls, prices: prices) case final quota
          when !quota.isEmpty)
        'claudePlanLimits': {
          for (final window in quota.windows)
            window.type: {
              'nowPercent': (window.now * 100).round(),
              'usedPercentInPeriod': (window.used * 100).round(),
              'peakPercent': (window.peak * 100).round(),
              'resets': window.resets,
            },
          if (quota.tokensPerPercent case final tokens?)
            'tokensPerPercentOfWeek': tokens.round(),
          'apiPriceCostPerPercentOfWeek': ?quota.costPerPercent?.byCurrency,
        },
      'latestCalls': [
        for (final call in summary.calls.reversed.take(listed))
          _call(call, prices),
      ],
    };
  }

  /// [raw] (a `set` item of [_pricesSchema], or a tier of it) as
  /// [ModelPrice.fromJson] reads it.
  static Map<String, Object?> _priceJson(Map<Object?, Object?> raw) => {
    'input': raw['input'],
    'output': raw['output'],
    'cacheRead': raw['cache_read'],
    'cacheWrite': raw['cache_write'],
    'cacheWriteLong': raw['cache_write_1h'],
    'currency': raw['currency'],
    'source': raw['source'],
    'fast': raw['fast'],
    'over': raw['over'],
    'upTo': raw['up_to'],
    'outputOver': raw['output_over'],
    'outputUpTo': raw['output_up_to'],
    if (raw['tiers'] case final List<Object?> tiers)
      'tiers': [
        for (final tier in tiers)
          if (tier is Map) _priceJson(tier) else tier,
      ],
    'schedule': raw['schedule'],
    'serviceTiers': raw['service_tiers'],
    'geo': raw['geo'],
    'multiplier': raw['multiplier'],
    'perCall': raw['per_call'],
    'tools': raw['tools'],
    'from': raw['from'],
  };

  /// What of [raw] (a `set` item) does not read, as [ModelPrice.fromJson]
  /// would leave it out.
  static List<String> _unread(Map<Object?, Object?> raw) => [
    if (raw['tiers'] case final List<Object?> tiers)
      for (final tier in tiers)
        if (tier is! Map || PriceTier.fromJson(_priceJson(tier)) == null)
          'a tier without an input and an output price: $tier',
    if (raw['schedule'] case final Object schedule?) ...[
      if (PriceSchedule.fromJson(schedule) == null)
        'a schedule whose timezone does not read: $schedule',
      if (schedule case {'windows': final List<Object?> windows})
        for (final window in windows)
          if (PriceWindow.fromJson(window) == null)
            'a window without "HH:MM" `from` and `to` and a factor: $window',
    ],
    if (raw['from'] case final Object from?
        when from is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(from.trim()))
      '`from` is not a date ("YYYY-MM-DD"): $from',
  ];

  /// What [input] asks of the prices ([prices]' schema): set, removed,
  /// else listed with the models called in the last 30 days.
  @visibleForTesting
  static Future<Map<String, Object?>> pricesOf(
    Map<String, Object?> input, {
    required UsageLedger ledger,
    required UsagePrices prices,
    ModelProviders? upstreams,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    var changed = 0;
    final errors = <String>[];
    String? text(Object? raw) =>
        raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
    final replaced = <String, ModelPrice?>{};
    final dated = <(String, ModelPrice)>[];
    for (final raw in (input['set'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final model = text(raw['model']);
      final read = ModelPrice.fromJson(_priceJson(raw));
      if (model == null || read == null) {
        errors.add('Not set (a model, an input and an output price): $raw');
        continue;
      }
      final unread = _unread(raw);
      if (unread.isNotEmpty) {
        errors.add('Not set ($model): ${unread.join('; ')}');
        continue;
      }
      final price = ModelPrice.fromJson({...read.toJson(), 'updated': '$at'})!;
      final key = UsagePrices.key(text(raw['upstream']), model);
      if (price.from == null) {
        replaced[key] = price;
      } else {
        dated.add((key, price));
      }
    }
    for (final raw in (input['remove'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final model = text(raw['model']);
      if (model == null) continue;
      final key = UsagePrices.key(text(raw['upstream']), model);
      if (text(raw['from']) case final from?) {
        if (DateTime.tryParse(from) case final date?) {
          await prices.removeVersion(key, date);
          changed++;
        }
      } else {
        replaced[key] = null;
      }
    }
    if (replaced.isNotEmpty) await prices.update(replaced);
    for (final (key, price) in dated) {
      await prices.put(key, price);
    }
    changed += replaced.length + dated.length;
    final rates = <String, UpstreamRate?>{};
    for (final raw in (input['set_upstream_rates'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final upstream = text(raw['upstream']);
      final rate = UpstreamRate.fromJson({
        'multiplier': raw['multiplier'],
        'currency': raw['currency'],
        'perCall': raw['per_call'],
        'source': raw['source'],
        'updated': '$at',
      });
      if (upstream == null || rate == null) {
        errors.add('Not set (an upstream and a multiplier above 0): $raw');
        continue;
      }
      rates[upstream] = rate;
    }
    for (final raw in (input['remove_upstream_rates'] as List?) ?? const []) {
      if (text(raw) case final upstream?) rates[upstream] = null;
    }
    if (rates.isNotEmpty) await prices.updateRates(rates);
    changed += rates.length;

    final calls = await ledger.range(
      from: at.subtract(const Duration(days: 30)),
    );
    final used =
        <
          String,
          ({
            String upstream,
            String model,
            int calls,
            Set<String> tiers,
            Set<String> geos,
            Set<String> tools,
          })
        >{};
    for (final call in calls) {
      final key = UsagePrices.key(call.provider, call.model);
      final seen = used[key];
      used[key] = (
        upstream: call.provider,
        model: call.model,
        calls: (seen?.calls ?? 0) + 1,
        tiers: {...?seen?.tiers, ?call.serviceTier},
        geos: {...?seen?.geos, ?call.geo},
        tools: {...?seen?.tools, ...call.serverTools.keys},
      );
    }
    Map<String, Object?> upstreamOf(String id) {
      // Claude Code's own: Anthropic's, its prices known here.
      if (id == ClaudePrices.upstream) {
        return {
          'upstream': id,
          'upstreamName': "Claude Code's own (Anthropic)",
          'pricingPage': ClaudePrices.source,
        };
      }
      final upstream = upstreams?.provider(id);
      return {
        'upstream': id,
        'upstreamName': ?upstream?.name,
        'baseUrl': ?upstream?.baseUrl,
      };
    }

    String? pricedAs(String upstream, String model) {
      if (prices.all.containsKey(UsagePrices.key(upstream, model))) {
        return 'own';
      }
      final rated = prices.rates.containsKey(upstream);
      if (prices.all.containsKey(UsagePrices.key(null, model))) {
        return rated
            ? "any upstream's, at the upstream's rate"
            : "any upstream's";
      }
      if (ClaudePrices.of(model) != null &&
          (rated || upstream == ClaudePrices.upstream)) {
        return rated
            ? "Anthropic's (built in), at the upstream's rate"
            : "Anthropic's (built in)";
      }
      return null;
    }

    return {
      if (changed > 0) 'changed': changed,
      if (errors.isNotEmpty) 'errors': errors,
      'modelsCalledLast30Days': [
        for (final entry in used.values)
          {
            'model': entry.model,
            ...upstreamOf(entry.upstream),
            'calls': entry.calls,
            if (entry.tiers.isNotEmpty) 'serviceTiersSeen': [...entry.tiers],
            if (entry.geos.isNotEmpty) 'geosSeen': [...entry.geos],
            if (entry.tools.isNotEmpty) 'serverToolsSeen': [...entry.tools],
            'price': ?prices.of(entry.upstream, entry.model)?.toJson(),
            'pricedAs': ?pricedAs(entry.upstream, entry.model),
          },
      ],
      'prices': {
        for (final MapEntry(:key, :value) in prices.all.entries)
          key: prices.versions(key).length == 1
              ? value.toJson()
              : [for (final price in prices.versions(key)) price.toJson()],
      },
      if (prices.rates.isNotEmpty)
        'upstreamRates': {
          for (final MapEntry(:key, :value) in prices.rates.entries)
            key: value.toJson(),
        },
    };
  }
}

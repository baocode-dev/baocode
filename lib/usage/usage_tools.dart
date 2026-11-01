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
        summary: (input, _) => switch (input['set']) {
          final List set when set.isNotEmpty => 'set ${set.length}',
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
      'output, cache read and cache write, in a currency. Without `set` or '
      '`remove` it lists the models called lately, the upstream each is '
      'called on (its name and base URL, for its pricing page) and their '
      'prices. Set a price only as read from the upstream\'s own pricing '
      'page, with that page as `source`; a cache price left out is taken '
      'as the input\'s.';

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
            'cache_write': {'type': 'number'},
            'currency': {
              'type': 'string',
              'description': 'ISO 4217, e.g. USD or CNY (default USD).',
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
          },
          'required': ['model'],
        },
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

  static Map<String, Object?> _call(UsageCall call, UsagePrices prices) => {
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
    'firstTokenMs': ?call.firstToken?.inMilliseconds,
    'durationMs': call.duration.inMilliseconds,
    if (call.speed case final speed?)
      'outputTokensPerSecond': double.parse(speed.toStringAsFixed(1)),
    if (prices.priceOf(call) case final price?)
      'cost': {
        price.currency: double.parse(price.cost(call).toStringAsFixed(6)),
      },
    if (call.toolCalls.isNotEmpty) 'toolCalls': call.toolCalls,
  };

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
    final changes = <String, ModelPrice?>{};
    final errors = <String>[];
    String? text(Object? raw) =>
        raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
    for (final raw in (input['set'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final model = text(raw['model']);
      final price = ModelPrice.fromJson({
        'input': raw['input'],
        'output': raw['output'],
        'cacheRead': raw['cache_read'],
        'cacheWrite': raw['cache_write'],
        'currency': raw['currency'],
        'source': raw['source'],
      });
      if (model == null || price == null) {
        errors.add('Not set (a model, an input and an output price): $raw');
        continue;
      }
      changes[UsagePrices.key(text(raw['upstream']), model)] = ModelPrice(
        input: price.input,
        output: price.output,
        cacheRead: price.cacheRead,
        cacheWrite: price.cacheWrite,
        currency: price.currency,
        source: price.source,
        updated: at,
      );
    }
    for (final raw in (input['remove'] as List?) ?? const []) {
      if (raw is! Map) continue;
      if (text(raw['model']) case final model?) {
        changes[UsagePrices.key(text(raw['upstream']), model)] = null;
      }
    }
    if (changes.isNotEmpty) await prices.update(changes);
    final calls = await ledger.range(
      from: at.subtract(const Duration(days: 30)),
    );
    final used = <String, ({String upstream, String model, int calls})>{};
    for (final call in calls) {
      final key = UsagePrices.key(call.provider, call.model);
      final seen = used[key];
      used[key] = (
        upstream: call.provider,
        model: call.model,
        calls: (seen?.calls ?? 0) + 1,
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

    return {
      if (changes.isNotEmpty) 'changed': changes.length,
      if (errors.isNotEmpty) 'errors': errors,
      'modelsCalledLast30Days': [
        for (final entry in used.values)
          {
            'model': entry.model,
            ...upstreamOf(entry.upstream),
            'calls': entry.calls,
            'price': ?prices.of(entry.upstream, entry.model)?.toJson(),
            if (entry.upstream == ClaudePrices.upstream &&
                prices.all[UsagePrices.key(entry.upstream, entry.model)] ==
                    null &&
                prices.all[UsagePrices.key(null, entry.model)] == null)
              'priceIsBuiltInDefault': true,
          },
      ],
      'prices': {
        for (final MapEntry(:key, :value) in prices.all.entries)
          key: value.toJson(),
      },
    };
  }
}

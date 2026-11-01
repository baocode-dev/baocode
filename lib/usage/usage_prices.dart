import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/user_settings.dart';
import 'usage_record.dart';

/// What a model's calls cost: a price a million tokens of each kind, in
/// [currency]. The cache's, where not given, are the input's.
@immutable
class ModelPrice {
  const ModelPrice({
    required this.input,
    required this.output,
    this.cacheRead,
    this.cacheWrite,
    this.cacheWriteLong,
    this.currency = 'USD',
    this.source,
    this.updated,
    this.fast = 1,
    this.longPrompt,
  });

  final double input;
  final double output;
  final double? cacheRead;
  final double? cacheWrite;

  /// Of the cache written, that kept an hour's; [cacheWrite]'s where not
  /// given.
  final double? cacheWriteLong;

  /// What a call in fast mode costs, times its price.
  final double fast;

  /// Its price for prompts of more than so many tokens, where it has one.
  final ({int over, ModelPrice price})? longPrompt;

  /// ISO 4217: USD, CNY…
  final String currency;

  /// Where it was read: its page.
  final String? source;
  final DateTime? updated;

  /// What [call] cost.
  double cost(UsageCall call) => parts(call).total;

  /// What [call]'s tokens of each kind cost; and what its cache reads
  /// saved, against paying the input's price for them.
  UsageCostParts parts(UsageCall call) {
    if (longPrompt case (:final over, :final price) when call.prompt > over) {
      return price.parts(call);
    }
    final long = call.cacheWriteLong.clamp(0, call.cacheWrite);
    final written = cacheWrite ?? input;
    final times = (call.fast ? fast : 1) / 1e6;
    return UsageCostParts()
      ..input = call.input * input * times
      ..cacheRead = call.cacheRead * (cacheRead ?? input) * times
      ..cacheWrite =
          ((call.cacheWrite - long) * written +
              long * (cacheWriteLong ?? written)) *
          times
      ..output = call.output * output * times
      ..saved = call.cacheRead * (input - (cacheRead ?? input)) * times;
  }

  Map<String, Object?> toJson() => {
    'input': input,
    'output': output,
    'cacheRead': ?cacheRead,
    'cacheWrite': ?cacheWrite,
    'cacheWriteLong': ?cacheWriteLong,
    'currency': currency,
    'source': ?source,
    'updated': ?updated?.toIso8601String(),
  };

  static ModelPrice? fromJson(Object? json) {
    if (json is! Map) return null;
    double? number(Object? raw) => switch (raw) {
      final num n when n >= 0 => n.toDouble(),
      final String s => double.tryParse(s.trim()),
      _ => null,
    };
    final input = number(json['input']);
    final output = number(json['output']);
    if (input == null || output == null) return null;
    final currency = json['currency'];
    return ModelPrice(
      input: input,
      output: output,
      cacheRead: number(json['cacheRead']),
      cacheWrite: number(json['cacheWrite']),
      cacheWriteLong: number(json['cacheWriteLong']),
      currency: currency is String && currency.trim().isNotEmpty
          ? currency.trim().toUpperCase()
          : 'USD',
      source: switch (json['source']) {
        final String s when s.trim().isNotEmpty => s.trim(),
        _ => null,
      },
      updated: switch (json['updated']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ModelPrice &&
      other.input == input &&
      other.output == output &&
      other.cacheRead == cacheRead &&
      other.cacheWrite == cacheWrite &&
      other.cacheWriteLong == cacheWriteLong &&
      other.fast == fast &&
      other.currency == currency &&
      other.source == source &&
      other.updated == updated;

  @override
  int get hashCode => Object.hash(
    input,
    output,
    cacheRead,
    cacheWrite,
    cacheWriteLong,
    fast,
    currency,
    source,
    updated,
  );
}

/// What tokens of each kind cost, in one currency.
class UsageCostParts {
  double input = 0;
  double cacheRead = 0;
  double cacheWrite = 0;
  double output = 0;

  /// What reading from the cache saved, against the input's price: not in
  /// [total].
  double saved = 0;

  double get total => input + cacheRead + cacheWrite + output;

  void addAll(UsageCostParts other) {
    input += other.input;
    cacheRead += other.cacheRead;
    cacheWrite += other.cacheWrite;
    output += other.output;
    saved += other.saved;
  }
}

/// Amounts by currency: what calls priced in more than one came to.
class UsageCost {
  final Map<String, double> byCurrency = {};

  /// Each currency's, by the kind of token: those of the calls added with
  /// [addCall].
  final Map<String, UsageCostParts> parts = {};

  /// Calls without a price, not in it.
  int unpriced = 0;

  bool get isEmpty => byCurrency.isEmpty;

  /// The currency it leads with: the first priced in.
  String? get currency => byCurrency.keys.firstOrNull;

  void add(String currency, double amount) =>
      byCurrency[currency] = (byCurrency[currency] ?? 0) + amount;

  /// Adds [call], at [price].
  void addCall(UsageCall call, ModelPrice price) {
    final of = price.parts(call);
    add(price.currency, of.total);
    (parts[price.currency] ??= UsageCostParts()).addAll(of);
  }

  void addAll(UsageCost other) {
    for (final MapEntry(:key, :value) in other.byCurrency.entries) {
      add(key, value);
    }
    for (final MapEntry(:key, :value) in other.parts.entries) {
      (parts[key] ??= UsageCostParts()).addAll(value);
    }
    unpriced += other.unpriced;
  }

  /// What reading from the cache saved, by currency; null when nothing.
  String? get savedText {
    final saved = [
      for (final MapEntry(:key, :value) in parts.entries)
        if (value.saved > 0) UsagePrices.money(value.saved, key),
    ];
    return saved.isEmpty ? null : saved.join(' + ');
  }

  /// $1.23 · ¥4.56; null when nothing was priced.
  String? get text => isEmpty
      ? null
      : [
          for (final MapEntry(:key, :value) in byCurrency.entries)
            UsagePrices.money(value, key),
        ].join(' + ');
}

/// The models' prices, as the user (or an agent for them) keeps them:
/// settings.json's `usage.prices`, `{"<upstream>/<model>": {...}}`, a
/// model of any upstream as `*/<model>`. The calls' costs are worked out
/// from them as they are now, so a price set later prices the calls before
/// it too.
class UsagePrices extends ChangeNotifier {
  UsagePrices([Map<String, ModelPrice>? prices]) : _prices = {...?prices};

  static UsagePrices current = UsagePrices();

  static const settingKey = 'usage.prices';

  /// Any upstream's, in a key.
  static const anyUpstream = '*';

  Map<String, ModelPrice> _prices;
  UserSettings? _settings;

  Map<String, ModelPrice> get all => Map.unmodifiable(_prices);

  static String key(String? upstream, String model) =>
      '${upstream == null || upstream.isEmpty ? anyUpstream : upstream}/$model';

  /// The upstream and the model [key] is of (null upstream: any).
  static ({String? upstream, String model}) parseKey(String key) {
    final at = key.indexOf('/');
    if (at < 0) return (upstream: null, model: key);
    final upstream = key.substring(0, at);
    return (
      upstream: upstream == anyUpstream ? null : upstream,
      model: key.substring(at + 1),
    );
  }

  /// [model]'s price on [upstream]: its own, else any upstream's; Claude
  /// Code's own models at Anthropic's ([ClaudePrices]) where not set.
  ModelPrice? of(String upstream, String model) =>
      _prices[key(upstream, model)] ??
      _prices[key(null, model)] ??
      (upstream == ClaudePrices.upstream ? ClaudePrices.of(model) : null);

  ModelPrice? priceOf(UsageCall call) => of(call.provider, call.model);

  /// What [calls] cost, by currency.
  UsageCost costOf(Iterable<UsageCall> calls) {
    final cost = UsageCost();
    for (final call in calls) {
      if (priceOf(call) case final price?) {
        cost.addCall(call, price);
      } else if (call.total > 0) {
        cost.unpriced++;
      }
    }
    return cost;
  }

  /// Takes the prices from [settings], as they change.
  void follow(UserSettings settings) {
    _settings?.removeListener(_read);
    _settings = settings;
    settings.addListener(_read);
    _read();
  }

  void _read() {
    final read = parse(_settings?[settingKey]);
    if (mapEquals(read, _prices)) return;
    _prices = read;
    notifyListeners();
  }

  static Map<String, ModelPrice> parse(Object? json) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String && key.isNotEmpty) key: ?ModelPrice.fromJson(value),
  };

  /// Sets [prices] by key ([key]), a null one removing it; kept in
  /// settings.json where it is followed.
  Future<void> update(Map<String, ModelPrice?> prices) async {
    final next = {..._prices};
    for (final MapEntry(:key, :value) in prices.entries) {
      if (value == null) {
        next.remove(key);
      } else {
        next[key] = value;
      }
    }
    _prices = next;
    notifyListeners();
    final settings = _settings;
    if (settings == null) return;
    try {
      await settings.update(
        settingKey,
        next.isEmpty
            ? null
            : {
                for (final MapEntry(:key, :value) in next.entries)
                  key: value.toJson(),
              },
      );
    } on Object catch (error) {
      debugPrint('$settingKey not kept: $error');
    }
  }

  /// [amount] in [currency]: $1.23, ¥4.56, 7.89 EUR; small amounts with
  /// more digits.
  static String money(double amount, String currency) {
    final digits = amount == 0
        ? 2
        : amount < 0.01
        ? 4
        : amount < 1
        ? 3
        : 2;
    final number = amount.toStringAsFixed(digits);
    return switch (currency) {
      'USD' => '\$$number',
      'CNY' || 'RMB' => '¥$number',
      'EUR' => '€$number',
      'GBP' => '£$number',
      'JPY' => '¥${amount.toStringAsFixed(0)}',
      _ => '$number $currency',
    };
  }
}

/// What Anthropic's API asks for Claude's models, a million tokens: Claude
/// Code's own calls priced at it where the user set no price of theirs
/// (what a Claude plan's use would have cost on the API). As listed on
/// [source] in October 2026; the cache written five minutes at 1.25 times
/// the input, an hour at twice.
abstract final class ClaudePrices {
  /// Claude Code's own (builtinProviderId).
  static const upstream = 'claude-code';

  static const source =
      'https://platform.claude.com/docs/en/about-claude/pricing';

  static ModelPrice _price(
    double input,
    double output,
    double cacheRead, {
    double fast = 1,
    ({int over, ModelPrice price})? longPrompt,
  }) => ModelPrice(
    input: input,
    output: output,
    cacheRead: cacheRead,
    cacheWrite: input * 1.25,
    cacheWriteLong: input * 2,
    source: source,
    fast: fast,
    longPrompt: longPrompt,
  );

  /// By the model's name as Anthropic gives it, without a date.
  static final Map<String, ModelPrice> prices = {
    'claude-fable-5-1': _price(10, 50, 0.25),
    'claude-mythos-5-1': _price(10, 50, 0.25),
    'claude-fable-5': _price(10, 50, 1),
    'claude-mythos-5': _price(10, 50, 1),
    'claude-opus-5-5': _price(4, 20, 0.2, fast: 2),
    'claude-opus-5': _price(5, 25, 0.5, fast: 2),
    'claude-opus-4-8': _price(5, 25, 0.5, fast: 2),
    'claude-opus-4-7': _price(5, 25, 0.5),
    'claude-opus-4-6': _price(5, 25, 0.5),
    'claude-sonnet-5-5': _price(2, 10, 0.2),
    'claude-sonnet-5': _price(2, 10, 0.2),
    'claude-sonnet-4-6': _price(3, 15, 0.3),
    'claude-haiku-5-5': _price(
      0.1,
      0.5,
      0.01,
      longPrompt: (over: 100000, price: _price(0.5, 2.5, 0.05)),
    ),
    'claude-haiku-4-5': _price(1, 5, 0.1),
  };

  /// [model]'s, by its name without what may follow it (`[1m]`, a date).
  static ModelPrice? of(String model) =>
      prices[model
          .replaceFirst(RegExp(r'\[[^\]]*\]$'), '')
          .replaceFirst(RegExp(r'-\d{8}$'), '')];
}

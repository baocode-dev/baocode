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
    this.currency = 'USD',
    this.source,
    this.updated,
  });

  final double input;
  final double output;
  final double? cacheRead;
  final double? cacheWrite;

  /// ISO 4217: USD, CNY…
  final String currency;

  /// Where it was read: its page.
  final String? source;
  final DateTime? updated;

  /// What [call] cost.
  double cost(UsageCall call) =>
      (call.input * input +
          call.cacheRead * (cacheRead ?? input) +
          call.cacheWrite * (cacheWrite ?? input) +
          call.output * output) /
      1e6;

  Map<String, Object?> toJson() => {
    'input': input,
    'output': output,
    'cacheRead': ?cacheRead,
    'cacheWrite': ?cacheWrite,
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
      other.currency == currency &&
      other.source == source &&
      other.updated == updated;

  @override
  int get hashCode => Object.hash(
    input,
    output,
    cacheRead,
    cacheWrite,
    currency,
    source,
    updated,
  );
}

/// Amounts by currency: what calls priced in more than one came to.
class UsageCost {
  final Map<String, double> byCurrency = {};

  /// Calls without a price, not in it.
  int unpriced = 0;

  bool get isEmpty => byCurrency.isEmpty;

  void add(String currency, double amount) =>
      byCurrency[currency] = (byCurrency[currency] ?? 0) + amount;

  void addAll(UsageCost other) {
    for (final MapEntry(:key, :value) in other.byCurrency.entries) {
      add(key, value);
    }
    unpriced += other.unpriced;
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

  /// [model]'s price on [upstream]: its own, else any upstream's.
  ModelPrice? of(String upstream, String model) =>
      _prices[key(upstream, model)] ?? _prices[key(null, model)];

  ModelPrice? priceOf(UsageCall call) => of(call.provider, call.model);

  /// What [calls] cost, by currency.
  UsageCost costOf(Iterable<UsageCall> calls) {
    final cost = UsageCost();
    for (final call in calls) {
      if (priceOf(call) case final price?) {
        cost.add(price.currency, price.cost(call));
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

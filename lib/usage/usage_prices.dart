import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../settings/user_settings.dart';
import 'usage_record.dart';

double? _number(Object? raw) => switch (raw) {
  final num n when n >= 0 => n.toDouble(),
  final String s => switch (double.tryParse(s.trim())) {
    final n? when n >= 0 => n,
    _ => null,
  },
  _ => null,
};

int? _count(Object? raw) => switch (_number(raw)) {
  final n? => n.round(),
  null => null,
};

String? _text(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? raw.trim() : null;

/// `{"name": factor}`, those that read.
Map<String, double> _factors(Object? raw) => {
  if (raw is Map)
    for (final MapEntry(:key, :value) in raw.entries)
      if (key is String && key.isNotEmpty) key: ?_number(value),
};

/// Ten thousand tokens as `10K`, a million as `1M`.
String _tokens(int n) => n >= 1000000 && n % 1000000 == 0
    ? '${n ~/ 1000000}M'
    : n >= 1000 && n % 1000 == 0
    ? '${n ~/ 1000}K'
    : '$n';

/// A price's band: the calls whose prompt (all their input, the cache's
/// too) and answer are within it pay its prices, all of their tokens (as
/// Qwen's, Doubao's, Gemini's and OpenAI's long prompts are priced: the
/// band the request is in, not tokens past a line).
@immutable
class PriceTier {
  const PriceTier({
    this.over,
    this.upTo,
    this.outputOver,
    this.outputUpTo,
    required this.input,
    required this.output,
    this.cacheRead,
    this.cacheWrite,
    this.cacheWriteLong,
  });

  /// The prompt's tokens: more than [over], at most [upTo].
  final int? over;
  final int? upTo;

  /// The answer's tokens: more than [outputOver], at most [outputUpTo].
  final int? outputOver;
  final int? outputUpTo;

  final double input;
  final double output;

  /// Where not given: the price's own, as the input's is to its.
  final double? cacheRead;
  final double? cacheWrite;
  final double? cacheWriteLong;

  bool matches(UsageCall call) =>
      (over == null || call.prompt > over!) &&
      (upTo == null || call.prompt <= upTo!) &&
      (outputOver == null || call.output > outputOver!) &&
      (outputUpTo == null || call.output <= outputUpTo!);

  /// `32K–128K`, `>256K`, `≤32K · out ≤200`.
  String get label {
    final prompt = switch ((over, upTo)) {
      (final over?, final upTo?) => '${_tokens(over)}–${_tokens(upTo)}',
      (final over?, null) => '>${_tokens(over)}',
      (null, final upTo?) => '≤${_tokens(upTo)}',
      _ => null,
    };
    final answer = switch ((outputOver, outputUpTo)) {
      (final over?, final upTo?) => 'out ${_tokens(over)}–${_tokens(upTo)}',
      (final over?, null) => 'out >${_tokens(over)}',
      (null, final upTo?) => 'out ≤${_tokens(upTo)}',
      _ => null,
    };
    return [?prompt, ?answer].join(' · ');
  }

  Map<String, Object?> toJson() => {
    'over': ?over,
    'upTo': ?upTo,
    'outputOver': ?outputOver,
    'outputUpTo': ?outputUpTo,
    'input': input,
    'output': output,
    'cacheRead': ?cacheRead,
    'cacheWrite': ?cacheWrite,
    'cacheWriteLong': ?cacheWriteLong,
  };

  static PriceTier? fromJson(Object? json) {
    if (json is! Map) return null;
    final input = _number(json['input']);
    final output = _number(json['output']);
    if (input == null || output == null) return null;
    return PriceTier(
      over: _count(json['over']),
      upTo: _count(json['upTo']),
      outputOver: _count(json['outputOver']),
      outputUpTo: _count(json['outputUpTo']),
      input: input,
      output: output,
      cacheRead: _number(json['cacheRead']),
      cacheWrite: _number(json['cacheWrite']),
      cacheWriteLong: _number(json['cacheWriteLong']),
    );
  }
}

/// Hours of the week priced at [factor] times: from [from] to [to] minutes
/// into the day, on [days] (1 Monday … 7 Sunday; every day when empty); one
/// whose [to] is not after [from] goes on past midnight.
@immutable
class PriceWindow {
  const PriceWindow({
    this.days = const {},
    required this.from,
    required this.to,
    required this.factor,
  });

  final Set<int> days;
  final int from;
  final int to;
  final double factor;

  bool _on(int day) => days.isEmpty || days.contains(day);

  /// Whether [minute] into [day] (1 Monday … 7 Sunday) is in it.
  bool contains(int day, int minute) {
    if (from < to) return _on(day) && minute >= from && minute < to;
    final before = day == 1 ? 7 : day - 1;
    return (_on(day) && minute >= from) || (_on(before) && minute < to);
  }

  static String _time(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  static int? _minutes(Object? raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$')
        .firstMatch(raw is String ? raw.trim() : '');
    if (match == null) return null;
    final hours = int.parse(match[1]!);
    final minutes = int.parse(match[2]!);
    if (minutes > 59 || hours > 24 || (hours == 24 && minutes > 0)) {
      return null;
    }
    return hours * 60 + minutes;
  }

  Map<String, Object?> toJson() => {
    if (days.isNotEmpty) 'days': [...days]..sort(),
    'from': _time(from),
    'to': _time(to),
    'factor': factor,
  };

  static PriceWindow? fromJson(Object? json) {
    if (json is! Map) return null;
    final from = _minutes(json['from']);
    final to = _minutes(json['to']);
    final factor = _number(json['factor']);
    if (from == null || to == null || factor == null) return null;
    return PriceWindow(
      days: {
        if (json['days'] case final List<Object?> days)
          for (final day in days)
            if (day is num && day >= 1 && day <= 7) day.toInt(),
      },
      from: from,
      to: to,
      factor: factor,
    );
  }
}

/// Prices by the time of the week, in [timezone]: a call in one of
/// [windows] (the first it is in) at its factor, any other at [otherwise];
/// on the dates of [except] (holidays, `2026-10-01`) at [otherwise] all
/// day. DeepSeek's off-peak hours, a plan's peak hours.
@immutable
class PriceSchedule {
  const PriceSchedule({
    required this.timezone,
    required this.offset,
    this.windows = const [],
    this.otherwise = 1,
    this.except = const {},
  });

  /// As given: `UTC`, `UTC+8`, `+08:00`, `Asia/Shanghai`.
  final String timezone;

  /// [timezone]'s from UTC.
  final Duration offset;
  final List<PriceWindow> windows;
  final double otherwise;
  final Set<String> except;

  /// The factor of a call made [at].
  double factorAt(DateTime at) => windowAt(at)?.factor ?? otherwise;

  /// The window [at] is in; null for none, or a date of [except].
  PriceWindow? windowAt(DateTime at) {
    final local = at.toUtc().add(offset);
    final date =
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    if (except.contains(date)) return null;
    final minute = local.hour * 60 + local.minute;
    for (final window in windows) {
      if (window.contains(local.weekday, minute)) return window;
    }
    return null;
  }

  /// Zones without summer time, by their names; others as an offset.
  static const _zones = {
    'ASIA/SHANGHAI': Duration(hours: 8),
    'ASIA/CHONGQING': Duration(hours: 8),
    'ASIA/HONG_KONG': Duration(hours: 8),
    'ASIA/TAIPEI': Duration(hours: 8),
    'ASIA/SINGAPORE': Duration(hours: 8),
    'ASIA/TOKYO': Duration(hours: 9),
    'ASIA/SEOUL': Duration(hours: 9),
    'ASIA/KOLKATA': Duration(hours: 5, minutes: 30),
    'ASIA/DUBAI': Duration(hours: 4),
    'UTC': Duration.zero,
    'GMT': Duration.zero,
    'Z': Duration.zero,
    'ETC/UTC': Duration.zero,
  };

  /// [timezone]'s offset from UTC: `UTC`, `UTC+8`, `GMT-05:00`, `+0530`,
  /// or a zone without summer time (`Asia/Shanghai`); null for others.
  static Duration? parseOffset(String timezone) {
    final text = timezone.trim().toUpperCase();
    if (_zones[text] case final offset?) return offset;
    final match = RegExp(r'^(?:UTC|GMT)?\s*([+-])(\d{1,2})(?::?(\d{2}))?$')
        .firstMatch(text);
    if (match == null) return null;
    final hours = int.parse(match[2]!);
    final minutes = int.parse(match[3] ?? '0');
    if (hours > 14 || minutes > 59) return null;
    final offset = Duration(hours: hours, minutes: minutes);
    return match[1] == '-' ? -offset : offset;
  }

  Map<String, Object?> toJson() => {
    'timezone': timezone,
    'windows': [for (final window in windows) window.toJson()],
    if (otherwise != 1) 'otherwise': otherwise,
    if (except.isNotEmpty) 'except': [...except]..sort(),
  };

  static PriceSchedule? fromJson(Object? json) {
    if (json is! Map) return null;
    final timezone = _text(json['timezone']) ?? 'UTC';
    final offset = parseOffset(timezone);
    if (offset == null) return null;
    return PriceSchedule(
      timezone: timezone,
      offset: offset,
      windows: [
        if (json['windows'] case final List<Object?> windows)
          for (final window in windows) ?PriceWindow.fromJson(window),
      ],
      otherwise: _number(json['otherwise']) ?? 1,
      except: {
        if (json['except'] case final List<Object?> dates)
          for (final date in dates)
            if (date is String &&
                RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date.trim()))
              date.trim(),
      },
    );
  }
}

/// What priced a call, besides its tokens' prices: the [tier] its prompt
/// is in (none: the price's own), the factors its tokens were multiplied
/// by, and its fees ([ModelPrice.perCall] and its tools').
typedef PriceApplied = ({
  PriceTier? tier,
  PriceWindow? window,
  double time,
  double fast,
  double service,
  double geo,
  double multiplier,
  double fees,
});

/// What a model's calls cost: a price a million tokens of each kind, in
/// [currency]. The cache's, where not given, are the input's.
///
/// Its prices may change with the call: by the prompt's length ([tiers]),
/// the time of the week ([schedule]), fast mode ([fast]), the service tier
/// and where the upstream answered it ([serviceTiers], [geo]), all times
/// [multiplier]; and a call may pay a fee ([perCall]) and its tools'
/// ([tools]). A price [from] a date prices the calls since then, until
/// another's.
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
    this.tiers = const [],
    this.schedule,
    this.serviceTiers = const {},
    this.geo = const {},
    this.multiplier = 1,
    this.perCall = 0,
    this.tools = const {},
    this.from,
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

  /// Its prices by the prompt's length (and the answer's): the last that a
  /// call [PriceTier.matches], else its own.
  final List<PriceTier> tiers;

  /// Its prices by the time of the week.
  final PriceSchedule? schedule;

  /// By the service tier a call was answered at ([UsageCall.serviceTier]:
  /// `priority`, `flex`…), its prices times.
  final Map<String, double> serviceTiers;

  /// By where a call was answered ([UsageCall.geo]: `us`), its prices
  /// times.
  final Map<String, double> geo;

  /// All of it times: a relay's discount, a group's rate.
  final double multiplier;

  /// What each call costs besides its tokens, answered or not.
  final double perCall;

  /// What each use of the upstream's tools costs ([UsageCall.serverTools]:
  /// `web_search`), besides the tokens.
  final Map<String, double> tools;

  /// ISO 4217: USD, CNY…
  final String currency;

  /// Where it was read: its page.
  final String? source;
  final DateTime? updated;

  /// The date it is the price from (the calls before it are another's);
  /// none: since ever.
  final DateTime? from;

  /// What [call] cost.
  double cost(UsageCall call) => parts(call).total;

  /// The tier, factors and fees [call] is priced with.
  PriceApplied applied(UsageCall call) {
    PriceTier? tier;
    for (final each in tiers) {
      if (each.matches(call)) tier = each;
    }
    final window = schedule?.windowAt(call.at);
    var fees = 0.0;
    if (!call.failed) {
      fees = perCall;
      for (final MapEntry(:key, :value) in call.serverTools.entries) {
        fees += (tools[key] ?? 0) * value;
      }
    }
    return (
      tier: tier,
      window: window,
      time: window?.factor ?? schedule?.otherwise ?? 1,
      fast: call.fast ? fast : 1,
      service: serviceTiers[call.serviceTier] ?? 1,
      geo: geo[call.geo] ?? 1,
      multiplier: multiplier,
      fees: fees * multiplier,
    );
  }

  /// What [call]'s tokens of each kind cost, and its fees; and what its
  /// cache reads saved, against paying the input's price for them.
  UsageCostParts parts(UsageCall call) {
    final applied = this.applied(call);
    final tier = applied.tier;
    final input = tier?.input ?? this.input;
    // A tier's cache prices, where it gives none: as its input is to this.
    double? derived(double? own, double? base) =>
        own ??
        (base == null || tier == null || this.input == 0
            ? base
            : base * input / this.input);
    final cacheRead = derived(tier?.cacheRead, this.cacheRead) ?? input;
    final written = derived(tier?.cacheWrite, cacheWrite) ?? input;
    final writtenLong =
        derived(tier?.cacheWriteLong, cacheWriteLong) ?? written;
    final output = tier?.output ?? this.output;
    final times =
        applied.time *
        applied.fast *
        applied.service *
        applied.geo *
        applied.multiplier /
        1e6;
    final long = call.cacheWriteLong.clamp(0, call.cacheWrite);
    return UsageCostParts()
      ..input = call.input * input * times
      ..cacheRead = call.cacheRead * cacheRead * times
      ..cacheWrite =
          ((call.cacheWrite - long) * written + long * writtenLong) * times
      ..output = call.output * output * times
      ..fees = applied.fees
      ..saved = call.cacheRead * (input - cacheRead) * times;
  }

  /// Whether more than its tokens' prices go into a call's cost.
  bool get hasRules =>
      tiers.isNotEmpty ||
      schedule != null ||
      serviceTiers.isNotEmpty ||
      geo.isNotEmpty ||
      multiplier != 1 ||
      perCall > 0 ||
      tools.isNotEmpty ||
      fast != 1;

  /// This, with its own prices (as typed in) [input]… and the rest as it is.
  ModelPrice withPrices({
    required double input,
    required double output,
    double? cacheRead,
    double? cacheWrite,
    required String currency,
    DateTime? updated,
  }) => ModelPrice(
    input: input,
    output: output,
    cacheRead: cacheRead,
    cacheWrite: cacheWrite,
    cacheWriteLong: cacheWriteLong,
    currency: currency,
    source: source,
    updated: updated ?? this.updated,
    fast: fast,
    tiers: tiers,
    schedule: schedule,
    serviceTiers: serviceTiers,
    geo: geo,
    multiplier: multiplier,
    perCall: perCall,
    tools: tools,
    from: from,
  );

  /// This at an upstream of [rate]: all of it times its multiplier, in
  /// its currency, its fee added.
  ModelPrice at(UpstreamRate rate) => ModelPrice(
    input: input,
    output: output,
    cacheRead: cacheRead,
    cacheWrite: cacheWrite,
    cacheWriteLong: cacheWriteLong,
    currency: rate.currency ?? currency,
    source: rate.source ?? source,
    updated: rate.updated ?? updated,
    fast: fast,
    tiers: tiers,
    schedule: schedule,
    serviceTiers: serviceTiers,
    geo: geo,
    multiplier: multiplier * rate.multiplier,
    // The rate's fee as it is: the price's fees are times the multiplier.
    perCall: multiplier == 0
        ? perCall
        : perCall + rate.perCall / (multiplier * rate.multiplier),
    tools: tools,
    from: from,
  );

  Map<String, Object?> toJson() => {
    'input': input,
    'output': output,
    'cacheRead': ?cacheRead,
    'cacheWrite': ?cacheWrite,
    'cacheWriteLong': ?cacheWriteLong,
    'currency': currency,
    if (fast != 1) 'fast': fast,
    if (tiers.isNotEmpty) 'tiers': [for (final tier in tiers) tier.toJson()],
    'schedule': ?schedule?.toJson(),
    if (serviceTiers.isNotEmpty) 'serviceTiers': serviceTiers,
    if (geo.isNotEmpty) 'geo': geo,
    if (multiplier != 1) 'multiplier': multiplier,
    if (perCall > 0) 'perCall': perCall,
    if (tools.isNotEmpty) 'tools': tools,
    'from': ?switch (from) {
      final from? => _date(from),
      null => null,
    },
    'source': ?source,
    'updated': ?updated?.toIso8601String(),
  };

  /// `2026-11-01`.
  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static ModelPrice? fromJson(Object? json) {
    if (json is! Map) return null;
    final input = _number(json['input']);
    final output = _number(json['output']);
    if (input == null || output == null) return null;
    final currency = _text(json['currency']);
    return ModelPrice(
      input: input,
      output: output,
      cacheRead: _number(json['cacheRead']),
      cacheWrite: _number(json['cacheWrite']),
      cacheWriteLong: _number(json['cacheWriteLong']),
      currency: currency?.toUpperCase() ?? 'USD',
      source: _text(json['source']),
      updated: switch (json['updated']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
      fast: _number(json['fast']) ?? 1,
      tiers: [
        if (json['tiers'] case final List<Object?> tiers)
          for (final tier in tiers) ?PriceTier.fromJson(tier),
      ],
      schedule: PriceSchedule.fromJson(json['schedule']),
      serviceTiers: _factors(json['serviceTiers']),
      geo: _factors(json['geo']),
      multiplier: _number(json['multiplier']) ?? 1,
      perCall: _number(json['perCall']) ?? 0,
      tools: _factors(json['tools']),
      // A date, as the calls' days are: local.
      from: switch (_text(json['from'])) {
        final from? => DateTime.tryParse(from),
        null => null,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ModelPrice &&
      other.fast == fast &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// What a relay (a new-api one, its group's rate) or any upstream asks
/// for every model it has no price of its own for: the model's price on
/// any upstream (or Anthropic's, for Claude's), times [multiplier], in
/// [currency] where it is another, [perCall] more a call.
@immutable
class UpstreamRate {
  const UpstreamRate({
    this.multiplier = 1,
    this.currency,
    this.perCall = 0,
    this.source,
    this.updated,
  });

  final double multiplier;
  final String? currency;

  /// In [currency] (else the model's price's).
  final double perCall;
  final String? source;
  final DateTime? updated;

  Map<String, Object?> toJson() => {
    'multiplier': multiplier,
    'currency': ?currency,
    if (perCall > 0) 'perCall': perCall,
    'source': ?source,
    'updated': ?updated?.toIso8601String(),
  };

  static UpstreamRate? fromJson(Object? json) {
    if (json is! Map) return null;
    final multiplier = _number(json['multiplier']);
    if (multiplier == null || multiplier == 0) return null;
    return UpstreamRate(
      multiplier: multiplier,
      currency: _text(json['currency'])?.toUpperCase(),
      perCall: _number(json['perCall']) ?? 0,
      source: _text(json['source']),
      updated: switch (json['updated']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UpstreamRate &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// What tokens of each kind cost, and the fees, in one currency.
class UsageCostParts {
  double input = 0;
  double cacheRead = 0;
  double cacheWrite = 0;
  double output = 0;

  /// The calls' own and their tools' ([ModelPrice.perCall],
  /// [ModelPrice.tools]).
  double fees = 0;

  /// What reading from the cache saved, against the input's price: not in
  /// [total].
  double saved = 0;

  double get total => input + cacheRead + cacheWrite + output + fees;

  void addAll(UsageCostParts other) {
    input += other.input;
    cacheRead += other.cacheRead;
    cacheWrite += other.cacheWrite;
    output += other.output;
    fees += other.fees;
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
/// model of any upstream as `*/<model>`, a price or a list of them each
/// [ModelPrice.from] a date; and `usage.upstreamRates`, an [UpstreamRate]
/// by upstream, `{"<upstream>": {...}}`. The calls' costs are worked out from them as
/// they are now: a price set later, without a date it is from, prices the
/// calls before it too.
class UsagePrices extends ChangeNotifier {
  UsagePrices([
    Map<String, ModelPrice>? prices,
    Map<String, UpstreamRate>? rates,
  ]) : _prices = {
         for (final MapEntry(:key, :value) in (prices ?? const {}).entries)
           key: [value],
       },
       _rates = {...?rates};

  static UsagePrices current = UsagePrices();

  static const settingKey = 'usage.prices';
  static const ratesKey = 'usage.upstreamRates';

  /// Any upstream's, in a key.
  static const anyUpstream = '*';

  /// Each key's prices, by the date they are from (none first).
  Map<String, List<ModelPrice>> _prices;
  Map<String, UpstreamRate> _rates;
  UserSettings? _settings;

  /// Each key's price now (its latest).
  Map<String, ModelPrice> get all => Map.unmodifiable({
    for (final MapEntry(:key, :value) in _prices.entries) key: value.last,
  });

  /// [key]'s prices, by the date they are from.
  List<ModelPrice> versions(String key) =>
      List.unmodifiable(_prices[key] ?? []);

  /// The upstreams' rates, by upstream.
  Map<String, UpstreamRate> get rates => Map.unmodifiable(_rates);

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

  /// Of [versions], the price of a call [at] (none: now): the latest
  /// from before it, else the first.
  static ModelPrice? _pick(List<ModelPrice>? versions, DateTime? at) {
    if (versions == null || versions.isEmpty) return null;
    if (at == null) return versions.last;
    for (final price in versions.reversed) {
      final from = price.from;
      if (from == null || !from.isAfter(at)) return price;
    }
    return versions.first;
  }

  /// [model]'s price on [upstream] for a call [at] (none: now): its own,
  /// else any upstream's (Claude's at Anthropic's, [ClaudePrices], on
  /// Claude Code's own and on an upstream of a rate) at the upstream's
  /// rate ([rates]).
  ModelPrice? of(String upstream, String model, {DateTime? at}) =>
      switch (basisOf(upstream, model, at: at)) {
        (:final price, rate: final rate?, key: _) => price.at(rate),
        (:final price, rate: null, key: _) => price,
        null => null,
      };

  /// What [of] works [model]'s price on [upstream] out from: its own, or
  /// another's with the upstream's [rate] (none: as it is); and the key it
  /// is kept by (none: Anthropic's, built in).
  ({ModelPrice price, UpstreamRate? rate, String? key})? basisOf(
    String upstream,
    String model, {
    DateTime? at,
  }) {
    final own = key(upstream, model);
    if (_pick(_prices[own], at) case final price?) {
      return (price: price, rate: null, key: own);
    }
    final rate = _rates[upstream];
    final any = key(null, model);
    if (_pick(_prices[any], at) case final price?) {
      return (price: price, rate: rate, key: any);
    }
    if (upstream == ClaudePrices.upstream || rate != null) {
      if (ClaudePrices.of(model) case final price?) {
        return (price: price, rate: rate, key: null);
      }
    }
    return null;
  }

  ModelPrice? priceOf(UsageCall call) =>
      of(call.provider, call.model, at: call.at);

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
    final prices = parseVersions(_settings?[settingKey]);
    final rates = parseRates(_settings?[ratesKey]);
    if (jsonEncode(_pricesJson(prices)) == jsonEncode(_pricesJson(_prices)) &&
        mapEquals(rates, _rates)) {
      return;
    }
    _prices = prices;
    _rates = rates;
    notifyListeners();
  }

  /// Each key's price now, as [parseVersions] reads them.
  static Map<String, ModelPrice> parse(Object? json) => {
    for (final MapEntry(:key, :value) in parseVersions(json).entries)
      key: value.last,
  };

  /// Each key's prices, a price or a list of them, by the date they are
  /// from.
  static Map<String, List<ModelPrice>> parseVersions(Object? json) {
    final prices = <String, List<ModelPrice>>{};
    if (json is! Map) return prices;
    for (final MapEntry(:key, :value) in json.entries) {
      if (key is! String || key.isEmpty) continue;
      final versions = _sorted([
        if (value is List)
          for (final price in value) ?ModelPrice.fromJson(price)
        else
          ?ModelPrice.fromJson(value),
      ]);
      if (versions.isNotEmpty) prices[key] = versions;
    }
    return prices;
  }

  static Map<String, UpstreamRate> parseRates(Object? json) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String && key.isNotEmpty) key: ?UpstreamRate.fromJson(value),
  };

  /// By the date they are from, none first; one a date.
  static List<ModelPrice> _sorted(List<ModelPrice> prices) {
    final byDate = <DateTime?, ModelPrice>{
      for (final price in prices) price.from: price,
    };
    return byDate.values.toList()..sort((a, b) {
      final (x, y) = (a.from, b.from);
      if (x == null || y == null) return x == null ? (y == null ? 0 : -1) : 1;
      return x.compareTo(y);
    });
  }

  static Map<String, Object?> _pricesJson(Map<String, List<ModelPrice>> all) =>
      {
        for (final MapEntry(:key, :value) in all.entries)
          key: value.length == 1 && value.single.from == null
              ? value.single.toJson()
              : [for (final price in value) price.toJson()],
      };

  /// Sets [prices] by key ([key]), each the key's only one, a null one
  /// removing it; kept in settings.json where it is followed.
  Future<void> update(Map<String, ModelPrice?> prices) {
    final next = {..._prices};
    for (final MapEntry(:key, :value) in prices.entries) {
      if (value == null) {
        next.remove(key);
      } else {
        next[key] = [value];
      }
    }
    return _set(next, _rates);
  }

  /// Sets [price] as [key]'s from its date ([ModelPrice.from]), in place of
  /// the one from the same date; the others kept.
  Future<void> put(String key, ModelPrice price) => _set({
    ..._prices,
    key: _sorted([
      ...?_prices[key]?.where((other) => other.from != price.from),
      price,
    ]),
  }, _rates);

  /// Removes [key]'s price from [from] (a date), the others kept.
  Future<void> removeVersion(String key, DateTime from) {
    final kept = [...?_prices[key]?.where((price) => price.from != from)];
    return _set({
      for (final MapEntry(key: other, :value) in _prices.entries)
        if (other != key) other: value,
      if (kept.isNotEmpty) key: kept,
    }, _rates);
  }

  /// Sets [rates] by upstream, a null one removing it.
  Future<void> updateRates(Map<String, UpstreamRate?> rates) {
    final next = {..._rates};
    for (final MapEntry(:key, :value) in rates.entries) {
      if (value == null) {
        next.remove(key);
      } else {
        next[key] = value;
      }
    }
    return _set(_prices, next);
  }

  Future<void> _set(
    Map<String, List<ModelPrice>> prices,
    Map<String, UpstreamRate> rates,
  ) async {
    final ratesChanged = !mapEquals(rates, _rates);
    _prices = prices;
    _rates = rates;
    notifyListeners();
    final settings = _settings;
    if (settings == null) return;
    try {
      await settings.update(
        settingKey,
        prices.isEmpty ? null : _pricesJson(prices),
      );
      if (ratesChanged) {
        await settings.update(
          ratesKey,
          rates.isEmpty
              ? null
              : {
                  for (final MapEntry(:key, :value) in rates.entries)
                    key: value.toJson(),
                },
        );
      }
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
/// the input, an hour at twice; US-only inference (`inference_geo: us`)
/// at 1.1 times, a priority tier at none other; a web search $10 a
/// thousand.
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
    List<PriceTier> tiers = const [],
  }) => ModelPrice(
    input: input,
    output: output,
    cacheRead: cacheRead,
    cacheWrite: input * 1.25,
    cacheWriteLong: input * 2,
    source: source,
    fast: fast,
    tiers: tiers,
    geo: const {'us': 1.1},
    tools: const {'web_search': 0.01},
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
    // A prompt of more than 100K tokens (its cache's too) at five times.
    'claude-haiku-5-5': _price(
      0.1,
      0.5,
      0.01,
      tiers: const [
        PriceTier(
          over: 100000,
          input: 0.5,
          output: 2.5,
          cacheRead: 0.05,
          cacheWrite: 0.625,
          cacheWriteLong: 1,
        ),
      ],
    ),
    'claude-haiku-4-5': _price(1, 5, 0.1),
  };

  /// [model]'s, by its name without what may follow it (`[1m]`, a date).
  static ModelPrice? of(String model) =>
      prices[model
          .replaceFirst(RegExp(r'\[[^\]]*\]$'), '')
          .replaceFirst(RegExp(r'-\d{8}$'), '')];
}

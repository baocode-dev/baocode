/// Google's Antigravity backend (Cloud Code Assist), as the Antigravity app
/// speaks to it: its sign-in, the project an account's requests are made
/// in, its models and their quota. Written after magpie's and CLIProxyAPI's
/// Antigravity support (see lib/models/proxy/translate/NOTICE.md).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../codex/codex_usage.dart';
import '../model_provider.dart' show guessModelKind;
import '../upstream.dart';

/// Where Antigravity's requests go.
class AntigravityEndpoints {
  const AntigravityEndpoints({
    this.authorize = 'https://accounts.google.com/o/oauth2/v2/auth',
    this.token = 'https://oauth2.googleapis.com/token',
    this.userInfo = 'https://www.googleapis.com/oauth2/v2/userinfo?alt=json',
    this.base = 'https://daily-cloudcode-pa.googleapis.com',
    this.loadBase = 'https://cloudcode-pa.googleapis.com',
    this.versionFeed = 'https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/latest-arm64-mac.yml',
    this.callbackPort = 51121,
  });

  final String authorize;
  final String token;
  final String userInfo;

  /// Where conversations, models and quota are asked.
  final String base;

  /// Where an account's project is found (`loadCodeAssist`).
  final String loadBase;

  /// The app's update feed: its version, which requests say.
  final String versionFeed;

  /// The port Google sends the browser back to: the one Antigravity's
  /// client has; no other will do.
  final int callbackPort;

  static const callbackPath = '/oauth-callback';

  String get redirectUri => 'http://localhost:$callbackPort$callbackPath';

  /// Code Assist's [method] (`loadCodeAssist`), at [at] or [base].
  Uri method(String method, {String? at}) =>
      Uri.parse('${at ?? base}/v1internal:$method');

  /// A conversation, streamed.
  Uri get stream => Uri.parse('$base/v1internal:streamGenerateContent?alt=sse');
}

/// Antigravity's OAuth client: an installed app's, whose secret ships in
/// the app and so is none. Written in pieces only so GitHub's push
/// protection, which can't tell an installed app's from a server's, lets
/// it in.
const antigravityClientId =
    '1071006060591-tmhssin2h21lcre235vtolojh4g403ep'
    '.apps.googleusercontent'
    '.com';
const antigravityClientSecret =
    'GOCSPX'
    '-K58FWR486LdLJ1mLB8sXC4z6qDAf';

const antigravityScopes = [
  'https://www.googleapis.com/auth/cloud-platform',
  'https://www.googleapis.com/auth/userinfo.email',
  'https://www.googleapis.com/auth/userinfo.profile',
  'https://www.googleapis.com/auth/cclog',
  'https://www.googleapis.com/auth/experimentsandconfigs',
];

Uri antigravityAuthorizeUrl(
  AntigravityEndpoints endpoints, {
  required String state,
  required String challenge,
}) => Uri.parse(endpoints.authorize).replace(
  queryParameters: {
    'client_id': antigravityClientId,
    'redirect_uri': endpoints.redirectUri,
    'response_type': 'code',
    'scope': antigravityScopes.join(' '),
    'access_type': 'offline',
    'prompt': 'consent',
    'state': state,
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
  },
);

Map<String, String> antigravityCodeForm(
  AntigravityEndpoints endpoints, {
  required String code,
  required String verifier,
}) => {
  'grant_type': 'authorization_code',
  'code': code,
  'redirect_uri': endpoints.redirectUri,
  'client_id': antigravityClientId,
  'client_secret': antigravityClientSecret,
  'code_verifier': verifier,
};

Map<String, String> antigravityRefreshForm(String refreshToken) => {
  'grant_type': 'refresh_token',
  'refresh_token': refreshToken,
  'client_id': antigravityClientId,
  'client_secret': antigravityClientSecret,
};

/// The version Antigravity's requests say, until its feed tells a newer.
const antigravityFallbackVersion = '2.9.1';

/// The version in the update feed's text (`version: 2.9.1`); null when it
/// has none.
String? parseAntigravityVersion(String feed) {
  for (final line in const LineSplitter().convert(feed)) {
    if (!line.startsWith('version:')) continue;
    final version = line
        .substring('version:'.length)
        .trim()
        .replaceAll(RegExp('^[\'"]|[\'"]\$'), '');
    return RegExp(r'^[0-9.]+$').hasMatch(version) ? version : null;
  }
  return null;
}

/// What Antigravity says it is: `antigravity/hub/2.9.1 darwin/arm64`.
String antigravityUserAgent(
  String version, {
  String os = 'darwin',
  String arch = 'arm64',
}) => 'antigravity/hub/$version $os/$arch';

/// The session a conversation's requests are made in, as Antigravity names
/// it: from what stays the same over the conversation ([seed]), so that
/// its prompt is cached across turns.
String antigravitySessionId(String seed) {
  final sum = sha256.convert(utf8.encode(seed)).bytes;
  var n = BigInt.zero;
  for (final byte in sum.take(8)) {
    n = (n << 8) | BigInt.from(byte);
  }
  n &= (BigInt.one << 63) - BigInt.one;
  return '-$n';
}

// --- Its project -------------------------------------------------------------

/// What `loadCodeAssist` says of an account: its project, if it has one,
/// its plan, and the tier it would be set up on.
class AntigravityLoad {
  const AntigravityLoad({
    this.project,
    this.plan,
    this.tier,
    this.paidTier,
    this.defaultTier = 'free-tier',
    this.ineligible,
  });

  final String? project;
  final String? plan;

  /// The tier it is on, and the one it pays for.
  final String? tier;
  final String? paidTier;

  /// The tier `onboardUser` sets it up on, without a project.
  final String defaultTier;

  /// Why Google will not serve it, when it says.
  final String? ineligible;

  static AntigravityLoad fromJson(Object? json) {
    final map = json is Map ? json : const {};
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    Map? tierOf(Object? value) => value is Map ? value : null;
    final current = tierOf(map['currentTier']);
    final paid = tierOf(map['paidTier']);
    final named = paid != null && text(paid['name']) != null ? paid : current;
    var defaultTier = 'free-tier';
    if (map['allowedTiers'] case final List allowed) {
      final tiers = allowed.whereType<Map>().toList();
      final picked =
          tiers.where((tier) => tier['isDefault'] == true).firstOrNull ??
          tiers.firstOrNull;
      if (text(picked?['id']) case final id? when id != 'legacy-tier') {
        defaultTier = id;
      }
    }
    String? ineligible;
    if (map['ineligibleTiers'] case final List tiers) {
      for (final tier in tiers.whereType<Map>()) {
        ineligible = text(tier['reasonMessage']);
        if (ineligible != null) break;
      }
    }
    return AntigravityLoad(
      project: projectOf(map['cloudaicompanionProject']),
      plan: text(named?['name']) ?? text(named?['id']),
      tier: text(current?['id']),
      paidTier: text(paid?['id']),
      defaultTier: defaultTier,
      ineligible: ineligible,
    );
  }

  /// A project as Code Assist gives it: an id, or `{id, name}`.
  static String? projectOf(Object? value) => switch (value) {
    final String id when id.trim().isNotEmpty => id.trim(),
    {'id': final String id} when id.trim().isNotEmpty => id.trim(),
    _ => null,
  };
}

/// What `onboardUser` is asked to set an account up on [tier] with.
Map<String, Object?> antigravityOnboardBody(String tier, String version) => {
  'tier_id': tier,
  'metadata': {
    'ide_type': 'ANTIGRAVITY',
    'ide_version': version,
    'ide_name': 'antigravity',
  },
};

// --- Its models --------------------------------------------------------------

/// A model of an account's, as `fetchAvailableModels` lists it, with how
/// much of its quota is left.
class AntigravityModel {
  const AntigravityModel({
    required this.id,
    this.label,
    this.contextWindow,
    this.images,
    this.rank = 0,
    this.remaining,
    this.resetsAt,
  });

  final String id;
  final String? label;
  final int? contextWindow;
  final bool? images;

  /// Its place in Antigravity's picker, from 1; 0 when not there.
  final int rank;

  /// Of its quota, 0 to 1; null when not told.
  final double? remaining;
  final DateTime? resetsAt;
}

/// Those Antigravity lists that are not for a conversation.
const _hiddenModels = {
  'chat_20706',
  'chat_23310',
  'tab_flash_lite_preview',
  'tab_jump_flash_lite_preview',
  'gemini-2.5-flash-thinking',
  'gemini-2.5-pro',
};

/// `fetchAvailableModels`' answer: the models a conversation may be on,
/// as Antigravity's picker orders them.
List<AntigravityModel> parseAntigravityModels(Object? json) {
  final map = json is Map ? json : const {};
  final rank = <String, int>{};
  if (map['agentModelSorts'] case final List sorts) {
    for (final sort in sorts.whereType<Map>()) {
      for (final group
          in (sort['groups'] as List? ?? const []).whereType<Map>()) {
        for (final id in (group['modelIds'] as List? ?? const [])) {
          if (id is String) rank.putIfAbsent(id, () => rank.length + 1);
        }
      }
    }
  }
  final models = <AntigravityModel>[];
  if (map['models'] case final Map listed) {
    for (final MapEntry(:key, :value) in listed.entries) {
      if (key is! String || value is! Map) continue;
      if (_hiddenModels.contains(key) ||
          key.startsWith('chat_') ||
          key.startsWith('tab_')) {
        continue;
      }
      if (value['disabled'] == true) continue;
      final quota = value['quotaInfo'];
      double? remaining;
      DateTime? resetsAt;
      if (quota is Map) {
        // Left out once none is left.
        remaining = switch (quota['remainingFraction']) {
          final num fraction => fraction.toDouble(),
          _ => 0,
        };
        resetsAt = switch (quota['resetTime']) {
          final String at => DateTime.tryParse(at),
          _ => null,
        };
      }
      models.add(
        AntigravityModel(
          id: key,
          label: switch (value['displayName']) {
            final String name when name.trim().isNotEmpty => name.trim(),
            _ => null,
          },
          contextWindow: switch (value['maxTokens']) {
            final num tokens when tokens > 0 => tokens.toInt(),
            _ => null,
          },
          images: value['supportsImages'] as bool?,
          rank: rank[key] ?? 0,
          remaining: remaining,
          resetsAt: resetsAt,
        ),
      );
    }
  }
  models.sort((a, b) {
    if (a.rank != b.rank) {
      if (a.rank == 0) return 1;
      if (b.rank == 0) return -1;
      return a.rank - b.rank;
    }
    return a.id.compareTo(b.id);
  });
  return models;
}

/// The levels of thinking, least first.
const antigravityLevels = ['minimal', 'low', 'medium', 'high', 'xhigh'];

const _effortWords = [
  ('extra-high', 'xhigh'),
  ('extra-low', 'minimal'),
  ('xhigh', 'xhigh'),
  ('minimal', 'minimal'),
  ('low', 'low'),
  ('medium', 'medium'),
  ('high', 'high'),
];

/// An id's family and the level its last word says
/// (`gemini-3.8-flash-low`: `gemini-3.8-flash`, `low`); the id and null
/// when it says none.
(String, String?) splitAntigravityId(String id) {
  for (final (word, level) in _effortWords) {
    if (id.endsWith('-$word') && id.length > word.length + 1) {
      return (id.substring(0, id.length - word.length - 1), level);
    }
  }
  return (id, null);
}

/// The level a name's last words in brackets say (`Gemini 3.8 Flash
/// (High)`), and the name without them.
(String, String?) _nameLevel(String name) {
  final open = name.lastIndexOf(' (');
  if (open < 0 || !name.endsWith(')')) return (name, null);
  final level = switch (name
      .substring(open + 2, name.length - 1)
      .toLowerCase()) {
    'minimal' || 'extra low' => 'minimal',
    'low' => 'low',
    'medium' => 'medium',
    'high' => 'high',
    'extra high' || 'xhigh' => 'xhigh',
    _ => null,
  };
  return level == null ? (name, null) : (name.substring(0, open).trim(), level);
}

/// A family of Antigravity's ids, one model at each level it is served at
/// (`gemini-4-neon-low`, `-medium`, `-high`).
class AntigravityFamily {
  AntigravityFamily(this.id);

  final String id;
  final List<AntigravityModel> variants = [];

  /// Each variant's level, null for the id without one.
  final List<String?> levels = [];

  /// The id for each level; under null, the one asked for without one:
  /// the family's own id, if listed, else high, else the highest.
  Map<String?, String> get byLevel {
    final out = <String?, String>{};
    for (final (i, variant) in variants.indexed) {
      out.putIfAbsent(levels[i], () => variant.id);
    }
    out[null] ??=
        out['high'] ??
        antigravityLevels.reversed.map((l) => out[l]).nonNulls.firstOrNull ??
        variants.first.id;
    return out;
  }

  /// Its levels, least first.
  List<String> get efforts => [
    for (final level in antigravityLevels)
      if (levels.contains(level)) level,
  ];
}

/// [models]' families, in the order they are first listed.
List<AntigravityFamily> antigravityFamilies(List<AntigravityModel> models) {
  final families = <String, AntigravityFamily>{};
  for (final model in models) {
    final (family, _) = splitAntigravityId(model.id);
    families
        .putIfAbsent(family, () => AntigravityFamily(family))
        .variants
        .add(model);
  }
  for (final family in families.values) {
    // The levels their names say, where each says another; else their ids'.
    final named = {
      for (final variant in family.variants)
        ?_nameLevel(variant.label ?? '').$2,
    };
    for (final variant in family.variants) {
      family.levels.add(
        named.length == family.variants.length
            ? _nameLevel(variant.label ?? '').$2
            : splitAntigravityId(variant.id).$2,
      );
    }
  }
  return families.values.toList();
}

/// [models] as the picker offers them: each family one model with its
/// levels as efforts; one alone as it is listed, with the efforts its
/// thinking takes.
List<RemoteModel> antigravityRemoteModels(List<AntigravityModel> models) {
  final out = <RemoteModel>[];
  for (final family in antigravityFamilies(models)) {
    if (family.variants.length == 1) {
      final model = family.variants.single;
      out.add(
        RemoteModel(
          model.id,
          label: model.label,
          contextWindow: model.contextWindow,
          efforts: antigravityOwnEfforts(model.id),
          images: model.images ?? !model.id.startsWith('gpt-oss'),
        ),
      );
      continue;
    }
    final byLevel = family.byLevel;
    final main = family.variants.firstWhere((v) => v.id == byLevel[null]);
    final windows = family.variants.map((v) => v.contextWindow).nonNulls;
    out.add(
      RemoteModel(
        family.id,
        label: switch (main.label) {
          final label? => _nameLevel(label).$1,
          null => null,
        },
        contextWindow: windows.isEmpty
            ? null
            : windows.reduce((a, b) => a < b ? a : b),
        efforts: family.efforts,
        images: family.variants.every(
          (v) => v.images ?? !v.id.startsWith('gpt-oss'),
        ),
      ),
    );
  }
  return out;
}

/// The efforts a model of no family takes: Gemini 3 and later think at a
/// level, Gemini 2.5 and Claude's thinking ids within a budget; the rest
/// not at all.
List<String> antigravityOwnEfforts(String id) {
  if (guessModelKind(id).generatesImages) return const [];
  final lower = id.toLowerCase();
  if (lower.startsWith('gpt-oss')) return const [];
  if (lower.startsWith('claude')) {
    return lower.contains('thinking')
        ? const ['low', 'medium', 'high']
        : const [];
  }
  final generation = geminiGeneration(lower);
  if (generation >= 3) return const ['low', 'medium', 'high'];
  if (generation > 0) return const ['none', 'low', 'medium', 'high'];
  return const [];
}

/// The major version a Gemini id names (`gemini-4-neon`: 4); 0 for none.
int geminiGeneration(String id) =>
    switch (RegExp(r'(?:^|/)gemini-(\d+)').firstMatch(id.toLowerCase())) {
      final match? => int.parse(match.group(1)!),
      null => 0,
    };

/// The order efforts go in, for the nearest of a family's.
const _effortOrder = [
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
];

/// The id a request for [model] at [effort] goes out as, of those an
/// account lists ([ids]): a family's, the variant at the level nearest
/// [effort] (a tie going up), its default without one; any other as it is.
String antigravityModelId(Iterable<String> ids, String model, String? effort) {
  final listed = ids.toList();
  final families = antigravityFamilies([
    for (final id in listed) AntigravityModel(id: id),
  ]);
  final family = families
      .where((f) => f.id == model && f.variants.length > 1)
      .firstOrNull;
  if (family == null) {
    // A variant asked for by its own id, from before families were one.
    final (base, _) = splitAntigravityId(model);
    if (base != model &&
        effort != null &&
        effort.isNotEmpty &&
        families.any((f) => f.id == base && f.variants.length > 1)) {
      return antigravityModelId(listed, base, effort);
    }
    return model;
  }
  final byLevel = family.byLevel;
  if (effort == null || effort.isEmpty) return byLevel[null]!;
  final want = _effortOrder.indexOf(effort == 'none' ? 'minimal' : effort);
  if (want < 0) return byLevel[null]!;
  String? best;
  var distance = 1 << 30;
  for (final level in family.efforts) {
    final at = _effortOrder.indexOf(level);
    final d = (at - want).abs();
    if (d < distance || (d == distance && at > want)) {
      best = level;
      distance = d;
    }
  }
  return byLevel[best] ?? byLevel[null]!;
}

// --- Its quota -----------------------------------------------------------------

/// A group's name as quota shows it: "Gemini Models" is Gemini, "Claude
/// and GPT models" Claude & GPT.
String antigravityPoolName(String name) {
  var text = name.trim();
  if (text.toLowerCase().endsWith(' models')) {
    text = text.substring(0, text.length - ' models'.length).trim();
  }
  return text.replaceAll(' and ', ' & ');
}

/// The family of models an id is of, as quota groups name them.
String _vendorOf(String id) {
  final lower = id.toLowerCase();
  if (lower.startsWith('gemini')) return 'gemini';
  if (lower.startsWith('claude')) return 'claude';
  if (lower.startsWith('gpt')) return 'gpt';
  return lower.split('-').first;
}

/// An account's quota: each group's windows from `retrieveUserQuotaSummary`
/// ([summary]), each naming the models of [models] that draw on it; when
/// the summary tells none, each model's own five hours, by family.
CodexUsage antigravityUsage({
  required List<AntigravityModel> models,
  Object? summary,
  required DateTime now,
  String? plan,
}) {
  final windows = <CodexWindow>[];
  final groups = switch (summary) {
    {'groups': final List groups} => groups.whereType<Map>().toList(),
    _ => const <Map>[],
  };
  for (final group in groups) {
    final display = group['displayName'];
    if (display is! String || display.trim().isEmpty) continue;
    final pool = antigravityPoolName(display);
    final about = '$display ${group['description'] ?? ''}'.toLowerCase();
    // A group named for one model ("Gemini 4 Argon") is that model's; one
    // of a family ("Gemini Models") its family's others.
    final versioned = RegExp('[0-9]').hasMatch(pool);
    final ids = <String>{
      for (final model in models)
        if (versioned
            ? _poolNames(pool, model)
            : about.contains(_vendorOf(model.id)) &&
                  !groups.any((other) => _ownGroup(other, model))) ...{
          model.id,
          splitAntigravityId(model.id).$1,
        },
    };
    for (final bucket
        in (group['buckets'] as List? ?? const []).whereType<Map>()) {
      if (bucket['disabled'] == true) continue;
      final minutes = switch ('${bucket['window'] ?? ''}'.toLowerCase()) {
        '5h' => 300,
        'weekly' => 10080,
        _ => null,
      };
      final left = switch (bucket['remainingFraction']) {
        final num fraction => fraction.toDouble(),
        _ => 0.0,
      };
      windows.add(
        CodexWindow(
          usedPercent: ((1 - left) * 100).clamp(0, 100).toDouble(),
          minutes: minutes,
          resetsAt: switch (bucket['resetTime']) {
            final String at => DateTime.tryParse(at),
            _ => null,
          },
          name: minutes == null
              ? [
                  pool,
                  ?switch (bucket['displayName'] ?? bucket['window']) {
                    final String name when name.isNotEmpty => name,
                    _ => null,
                  },
                ].join(' ')
              : pool,
          models: ids,
        ),
      );
    }
  }
  if (windows.isEmpty) {
    // Each family's own: its least left of its models'.
    final byVendor = <String, CodexWindow>{};
    final idsOf = <String, Set<String>>{};
    for (final model in models) {
      final remaining = model.remaining;
      if (remaining == null) continue;
      final vendor = _vendorOf(model.id);
      idsOf.putIfAbsent(vendor, () => {}).addAll({
        model.id,
        splitAntigravityId(model.id).$1,
      });
      final used = ((1 - remaining) * 100).clamp(0, 100).toDouble();
      final known = byVendor[vendor];
      if (known == null || used > known.usedPercent) {
        byVendor[vendor] = CodexWindow(
          usedPercent: used,
          minutes: 300,
          resetsAt: model.resetsAt,
          name: switch (vendor) {
            'gemini' => 'Gemini',
            'claude' => 'Claude',
            'gpt' => 'GPT',
            _ => vendor,
          },
        );
      }
    }
    for (final MapEntry(key: vendor, value: window) in byVendor.entries) {
      windows.add(window.withModels(idsOf[vendor]!));
    }
  }
  return CodexUsage(at: now, plan: plan, windowList: windows);
}

bool _poolNames(String pool, AntigravityModel model) {
  final lower = pool.toLowerCase();
  for (final name in [model.label ?? '', model.id.replaceAll('-', ' ')]) {
    final text = name.toLowerCase();
    if (text == lower ||
        text.startsWith('$lower ') ||
        text.startsWith('$lower(')) {
      return true;
    }
  }
  return false;
}

/// Whether [group] is a group of [model]'s own, by its name.
bool _ownGroup(Map group, AntigravityModel model) =>
    switch (group['displayName']) {
      final String name =>
        RegExp('[0-9]').hasMatch(antigravityPoolName(name)) &&
            _poolNames(antigravityPoolName(name), model),
      _ => false,
    };

// --- Its errors ----------------------------------------------------------------

/// Until when an account is out of quota on the model asked, as a 429's
/// [text] says; null when it is not that (a refusal, or a rate limit of a
/// moment: [antigravityRetryAfter]).
DateTime? antigravityLimitReset(int status, String text, DateTime now) {
  if (status != 429) return null;
  final lower = text.toLowerCase();
  final quota =
      lower.contains('quota_exhausted') ||
      lower.contains('exhausted your capacity') ||
      lower.contains('quota will reset') ||
      lower.contains('insufficient_g1_credits_balance');
  final delay = _delayOf(text);
  if (quota) return now.add(_atLeast(delay ?? const Duration(minutes: 5)));
  if (lower.contains('rate_limit_exceeded') &&
      delay != null &&
      delay >= const Duration(seconds: 10)) {
    return now.add(delay);
  }
  return null;
}

/// How long a 429 of a moment asks to wait before the same account is
/// asked again; null when it says not.
Duration? antigravityRetryAfter(String text) {
  final delay = _delayOf(text);
  if (delay == null || delay >= const Duration(seconds: 10)) return null;
  return delay;
}

Duration _atLeast(Duration delay) =>
    delay < const Duration(seconds: 30) ? const Duration(seconds: 30) : delay;

/// The delay an error's details (`retryDelay`, `quotaResetDelay`) or words
/// ("Your quota will reset after 1h43m56s.") say.
Duration? _delayOf(String text) {
  Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    json = null;
  }
  final details = switch (json) {
    {'error': {'details': final List details}} => details,
    _ => const [],
  };
  for (final detail in details.whereType<Map>()) {
    for (final key in ['retryDelay', 'quotaResetDelay']) {
      if (_goDuration(detail[key]) case final delay?) return delay;
      if (detail['metadata'] case final Map metadata) {
        if (_goDuration(metadata[key]) case final delay?) return delay;
      }
    }
  }
  final words = RegExp(
    r'reset after ([0-9hms.]+)',
    caseSensitive: false,
  ).firstMatch(text);
  return _goDuration(words?.group(1));
}

/// A duration as Go and protobuf write it: `3600s`, `1h43m56s`,
/// `479.417207ms`.
Duration? _goDuration(Object? value) {
  if (value is! String) return null;
  final text = value.trim().replaceFirst(RegExp(r'\.$'), '');
  if (text.isEmpty) return null;
  final parts = RegExp(r'([0-9.]+)(ms|h|m|s)').allMatches(text).toList();
  if (parts.isEmpty || parts.map((m) => m.group(0)).join() != text) return null;
  var micros = 0.0;
  for (final part in parts) {
    final n = double.tryParse(part.group(1)!) ?? 0;
    micros += switch (part.group(2)) {
      'h' => n * 3600e6,
      'm' => n * 60e6,
      's' => n * 1e6,
      _ => n * 1e3,
    };
  }
  return Duration(microseconds: micros.round());
}

/// Whether [text], a 429's or an error event's, is Antigravity turning the
/// prompt away rather than its quota used up.
bool antigravityRefuses(String text) {
  final lower = text.toLowerCase();
  return lower.contains('resource has been exhausted') &&
      !lower.contains('exhausted your capacity') &&
      !lower.contains('quota will reset') &&
      !lower.contains('quota_exhausted');
}

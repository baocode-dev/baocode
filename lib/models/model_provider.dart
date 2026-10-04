/// An upstream models are served from, as Settings → Models keeps it in
/// settings.json (`models.providers`): where it is, how it is spoken to,
/// its models, and which of them Claude Code uses for what. Its key is in
/// the system's keychain ([SecretStore]), under [ModelProvider.keyRef].
library;

/// How an upstream is spoken to.
enum ProviderProtocol {
  /// Anthropic's Messages API: Claude Code talks to it itself.
  anthropic('anthropic'),

  /// OpenAI's Chat Completions: through the local proxy, translated.
  openaiChat('openai-chat'),

  /// OpenAI's Responses API: through the local proxy, translated.
  openaiResponses('openai-responses');

  const ProviderProtocol(this.id);

  /// As settings.json has it.
  final String id;

  /// Spoken to through the proxy ([ModelProxy]).
  bool get proxied => this != anthropic;

  static ProviderProtocol parse(Object? id) =>
      values.where((value) => value.id == id).firstOrNull ?? anthropic;
}

/// How the key goes to an Anthropic-compatible upstream.
enum ProviderAuth {
  /// `x-api-key` for Anthropic's own API, else a bearer token: what
  /// compatible upstreams document.
  auto('auto'),

  /// `Authorization: Bearer` (Claude Code's `ANTHROPIC_AUTH_TOKEN`).
  bearer('bearer'),

  /// `x-api-key` (Claude Code's `ANTHROPIC_API_KEY`).
  apiKey('x-api-key');

  const ProviderAuth(this.id);

  final String id;

  static ProviderAuth parse(Object? id) =>
      values.where((value) => value.id == id).firstOrNull ?? auto;
}

/// One model of an upstream.
class ProviderModel {
  const ProviderModel({
    required this.id,
    this.label,
    this.contextWindow,
    this.efforts,
    this.contexts,
    this.images = true,
    this.enabled = true,
    this.custom = false,
    this.missing = false,
  });

  /// The efforts offered unless the model has its own: `none` turns its
  /// reasoning off.
  static const defaultEfforts = [
    'none',
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
  ];

  /// The effort a session starts with, when the model offers it.
  static const defaultEffort = 'medium';

  /// The contexts offered unless the model has its own.
  static const defaultContexts = [
    200000,
    256000,
    300000,
    400000,
    500000,
    800000,
    1000000,
  ];

  /// The context a session fills before compacting, unless the model
  /// says ([contextWindow]).
  static const defaultContext = 200000;

  /// As the upstream names it.
  final String id;

  /// As the picker shows it; [id] when unset.
  final String? label;

  /// The context a session fills before compacting, unless another is
  /// picked; [defaultContext] when null.
  final int? contextWindow;

  /// The efforts offered in the picker; [defaultEfforts] when null.
  final List<String>? efforts;

  /// The contexts offered in the picker; [defaultContexts] when null.
  final List<int>? contexts;

  /// Whether it takes images.
  final bool images;

  /// Offered in the picker.
  final bool enabled;

  /// Added by hand, not listed by the upstream.
  final bool custom;

  /// Listed once, but no longer by the upstream: kept, and marked.
  final bool missing;

  String get displayName => switch (label?.trim()) {
    final label? when label.isNotEmpty => label,
    _ => id,
  };

  /// The efforts offered in the picker.
  List<String> get effortLevels => efforts ?? defaultEfforts;

  /// The effort picked unless another is: [defaultEffort] if offered,
  /// else the first; null with none offered.
  String? get initialEffort {
    final levels = effortLevels;
    return levels.contains(defaultEffort) ? defaultEffort : levels.firstOrNull;
  }

  /// The context picked unless another is: [contextWindow], else
  /// [defaultContext] if offered, else the first offered.
  int get initialContext {
    if (contextWindow case final tokens?) return tokens;
    final offered = contexts ?? defaultContexts;
    return offered.contains(defaultContext)
        ? defaultContext
        : offered.firstOrNull ?? defaultContext;
  }

  /// The contexts offered in the picker, smallest first: [initialContext]
  /// among them.
  List<int> get contextOptions {
    final offered = {...(contexts ?? defaultContexts), initialContext}.toList()
      ..sort();
    return offered;
  }

  ProviderModel copyWith({
    String? id,
    String? Function()? label,
    int? Function()? contextWindow,
    List<String>? Function()? efforts,
    List<int>? Function()? contexts,
    bool? images,
    bool? enabled,
    bool? custom,
    bool? missing,
  }) => ProviderModel(
    id: id ?? this.id,
    label: label == null ? this.label : label(),
    contextWindow: contextWindow == null ? this.contextWindow : contextWindow(),
    efforts: efforts == null ? this.efforts : efforts(),
    contexts: contexts == null ? this.contexts : contexts(),
    images: images ?? this.images,
    enabled: enabled ?? this.enabled,
    custom: custom ?? this.custom,
    missing: missing ?? this.missing,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    if (label case final label? when label.trim().isNotEmpty) 'label': label,
    'contextWindow': ?contextWindow,
    'efforts': ?efforts,
    'contexts': ?contexts,
    if (!images) 'images': false,
    if (!enabled) 'enabled': false,
    if (custom) 'custom': true,
    if (missing) 'missing': true,
  };

  static ProviderModel? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) return null;
    return ProviderModel(
      id: id.trim(),
      label: json['label'] is String ? json['label'] as String : null,
      contextWindow: switch (json['contextWindow']) {
        final int tokens when tokens > 0 => tokens,
        _ => null,
      },
      efforts: switch (json['efforts']) {
        final List list => [
          for (final level in list)
            if (level is String && level.trim().isNotEmpty) level.trim(),
        ],
        _ => null,
      },
      contexts: switch (json['contexts']) {
        final List list => [
          for (final tokens in list)
            if (tokens is int && tokens > 0) tokens,
        ],
        _ => null,
      },
      images: json['images'] != false,
      enabled: json['enabled'] != false,
      custom: json['custom'] == true,
      missing: json['missing'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProviderModel &&
      other.id == id &&
      other.label == label &&
      other.contextWindow == contextWindow &&
      _sameList(other.efforts, efforts) &&
      _sameList(other.contexts, contexts) &&
      other.images == images &&
      other.enabled == enabled &&
      other.custom == custom &&
      other.missing == missing;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    contextWindow,
    efforts == null ? null : Object.hashAll(efforts!),
    contexts == null ? null : Object.hashAll(contexts!),
    images,
    enabled,
    custom,
    missing,
  );

  static bool _sameList<T>(List<T>? a, List<T>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// An effort as the picker shows it: `X-High`, `Disable` for `none`.
String effortLabel(String level) => switch (level) {
  'none' => 'Disable',
  'xhigh' => 'X-High',
  '' => level,
  _ => level[0].toUpperCase() + level.substring(1),
};

/// Which models Claude Code uses for what, by model id: unset, the model
/// picked stands in.
class ProviderRoles {
  const ProviderRoles({
    this.main,
    this.opus,
    this.sonnet,
    this.haiku,
    this.subagent,
  });

  /// Used when the model picked of the upstream is gone (removed since):
  /// a session's, or new sessions' default.
  final String? main;

  /// `ANTHROPIC_DEFAULT_OPUS_MODEL`: what "opus" means (e.g. in Plan).
  final String? opus;

  /// `ANTHROPIC_DEFAULT_SONNET_MODEL`.
  final String? sonnet;

  /// `ANTHROPIC_DEFAULT_HAIKU_MODEL`: Claude Code's background work, and
  /// the app's (agents' titles).
  final String? haiku;

  /// `CLAUDE_CODE_SUBAGENT_MODEL`.
  final String? subagent;

  static const _keys = ['main', 'opus', 'sonnet', 'haiku', 'subagent'];

  String? operator [](String role) => switch (role) {
    'main' => main,
    'opus' => opus,
    'sonnet' => sonnet,
    'haiku' => haiku,
    'subagent' => subagent,
    _ => null,
  };

  /// With [role] set to [model] (null unsets it).
  ProviderRoles copyWith(String role, String? model) {
    final values = {for (final key in _keys) key: this[key]};
    values[role] = model;
    return ProviderRoles(
      main: values['main'],
      opus: values['opus'],
      sonnet: values['sonnet'],
      haiku: values['haiku'],
      subagent: values['subagent'],
    );
  }

  Map<String, Object?> toJson() => {
    for (final key in _keys)
      if (this[key] case final model? when model.isNotEmpty) key: model,
  };

  static ProviderRoles fromJson(Object? json) {
    String? read(String key) => switch (json is Map ? json[key] : null) {
      final String model when model.trim().isNotEmpty => model.trim(),
      _ => null,
    };
    return ProviderRoles(
      main: read('main'),
      opus: read('opus'),
      sonnet: read('sonnet'),
      haiku: read('haiku'),
      subagent: read('subagent'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProviderRoles && _keys.every((key) => other[key] == this[key]);

  @override
  int get hashCode => Object.hashAll(_keys.map((key) => this[key]));
}

/// An upstream of models.
class ModelProvider {
  const ModelProvider({
    required this.id,
    required this.name,
    this.protocol = ProviderProtocol.anthropic,
    this.baseUrl = '',
    this.auth = ProviderAuth.auto,
    this.enabled = true,
    this.models = const [],
    this.roles = const ProviderRoles(),
    this.disableNonessentialTraffic = false,
    this.preserveThinking = false,
    this.promptCacheKey = true,
    this.env = const {},
  });

  /// Its own, made once; models are picked as `@<id>/<model>`.
  final String id;
  final String name;
  final ProviderProtocol protocol;
  final String baseUrl;
  final ProviderAuth auth;

  /// Offered in the picker.
  final bool enabled;
  final List<ProviderModel> models;
  final ProviderRoles roles;

  /// `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`: no telemetry, update
  /// checks or usage requests, which an upstream other than Anthropic's
  /// does not answer.
  final bool disableNonessentialTraffic;

  /// Chat Completions: replays the model's reasoning (`reasoning_content`)
  /// even unsigned, as DeepSeek and others want it back.
  final bool preserveThinking;

  /// Through the proxy: a `prompt_cache_key` of the conversation's own, so
  /// that an upstream (or a relay before several) sends its requests where
  /// the earlier ones are cached. Off for one that refuses the field.
  final bool promptCacheKey;

  /// More environment for Claude Code, after what is set from the above.
  final Map<String, String> env;

  /// Where its key is kept in the keychain.
  String get keyRef => keyRefFor(id);

  static String keyRefFor(String id) => 'provider.$id';

  /// The host its base URL names, for the list.
  String get host => Uri.tryParse(baseUrl.trim())?.host ?? '';

  List<ProviderModel> get enabledModels => [
    for (final model in models)
      if (model.enabled) model,
  ];

  ProviderModel? model(String id) =>
      models.where((model) => model.id == id).firstOrNull;

  ModelProvider copyWith({
    String? name,
    ProviderProtocol? protocol,
    String? baseUrl,
    ProviderAuth? auth,
    bool? enabled,
    List<ProviderModel>? models,
    ProviderRoles? roles,
    bool? disableNonessentialTraffic,
    bool? preserveThinking,
    bool? promptCacheKey,
    Map<String, String>? env,
  }) => ModelProvider(
    id: id,
    name: name ?? this.name,
    protocol: protocol ?? this.protocol,
    baseUrl: baseUrl ?? this.baseUrl,
    auth: auth ?? this.auth,
    enabled: enabled ?? this.enabled,
    models: models ?? this.models,
    roles: roles ?? this.roles,
    disableNonessentialTraffic:
        disableNonessentialTraffic ?? this.disableNonessentialTraffic,
    preserveThinking: preserveThinking ?? this.preserveThinking,
    promptCacheKey: promptCacheKey ?? this.promptCacheKey,
    env: env ?? this.env,
  );

  /// With [model] in place of the one of its id, or added.
  ModelProvider withModel(ProviderModel model) {
    final index = models.indexWhere((m) => m.id == model.id);
    return copyWith(
      models: index < 0
          ? [...models, model]
          : [...models.take(index), model, ...models.skip(index + 1)],
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.id,
    'baseUrl': baseUrl,
    if (auth != ProviderAuth.auto) 'auth': auth.id,
    if (!enabled) 'enabled': false,
    'models': [for (final model in models) model.toJson()],
    if (roles.toJson() case final roles when roles.isNotEmpty) 'roles': roles,
    if (disableNonessentialTraffic) 'disableNonessentialTraffic': true,
    if (preserveThinking) 'preserveThinking': true,
    if (!promptCacheKey) 'promptCacheKey': false,
    if (env.isNotEmpty) 'env': env,
  };

  static ModelProvider? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty || id.contains('/')) return null;
    return ModelProvider(
      id: id,
      name: switch (json['name']) {
        final String name when name.trim().isNotEmpty => name.trim(),
        _ => id,
      },
      protocol: ProviderProtocol.parse(json['protocol']),
      baseUrl: json['baseUrl'] is String ? json['baseUrl'] as String : '',
      auth: ProviderAuth.parse(json['auth']),
      enabled: json['enabled'] != false,
      models: [
        for (final model in json['models'] as List? ?? const [])
          ?ProviderModel.fromJson(model),
      ],
      roles: ProviderRoles.fromJson(json['roles']),
      disableNonessentialTraffic: json['disableNonessentialTraffic'] == true,
      preserveThinking: json['preserveThinking'] == true,
      promptCacheKey: json['promptCacheKey'] != false,
      env: {
        if (json['env'] case final Map env)
          for (final MapEntry(:key, :value) in env.entries)
            if (key is String && key.isNotEmpty && value != null) key: '$value',
      },
    );
  }

  /// What a session started on it depends on, other than its model: a
  /// session goes on the one it started with until it restarts.
  String get launchFingerprint => [
    protocol.id,
    baseUrl.trim(),
    auth.id,
    roles.toJson().toString(),
    disableNonessentialTraffic,
    preserveThinking,
    env.toString(),
  ].join('|');
}

/// The built-in provider: Claude Code as the user set it up, nothing
/// injected.
const builtinProviderId = 'claude-code';

/// How a model of [providerId] is picked: `@<provider>/<model>`. A model
/// of the built-in provider goes by the CLI's own name for it.
String modelRef(String providerId, String modelId) => '@$providerId/$modelId';

/// The provider and model [value] picks, if it is a [modelRef].
({String provider, String model})? parseModelRef(String? value) {
  if (value == null || !value.startsWith('@')) return null;
  final slash = value.indexOf('/');
  if (slash < 2 || slash == value.length - 1) return null;
  return (
    provider: value.substring(1, slash),
    model: value.substring(slash + 1),
  );
}

/// A context window as short as the picker shows it: `128K`, `1M`.
String formatTokens(int tokens) {
  if (tokens >= 1000000) {
    final millions = (tokens / 1000000).toStringAsFixed(1);
    return '${millions.endsWith('.0') ? millions.substring(0, millions.length - 2) : millions}M';
  }
  if (tokens >= 1000) return '${(tokens / 1000).round()}K';
  return '$tokens';
}

/// [text] as a number of tokens (`200000`, `200K`, `1M`, `1.5m`); null
/// when empty, -1 when it is not one.
int? parseTokens(String text) {
  final value = text.trim().replaceAll(RegExp(r'[,_\s]'), '').toLowerCase();
  if (value.isEmpty) return null;
  final match = RegExp(r'^(\d+(?:\.\d+)?)([km]?)$').firstMatch(value);
  if (match == null) return -1;
  final number = double.parse(match.group(1)!);
  final tokens = switch (match.group(2)) {
    'k' => number * 1000,
    'm' => number * 1000000,
    _ => number,
  }.round();
  return tokens > 0 ? tokens : -1;
}

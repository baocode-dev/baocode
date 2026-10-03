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
    this.thinking = false,
    this.images = false,
    this.enabled = true,
    this.custom = false,
    this.missing = false,
  });

  /// As the upstream names it.
  final String id;

  /// As the picker shows it; [id] when unset.
  final String? label;

  /// Tokens it holds; unknown when null.
  final int? contextWindow;

  /// Whether it reasons: its effort is offered, and reasoning asked for.
  final bool thinking;

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

  ProviderModel copyWith({
    String? id,
    String? Function()? label,
    int? Function()? contextWindow,
    bool? thinking,
    bool? images,
    bool? enabled,
    bool? custom,
    bool? missing,
  }) => ProviderModel(
    id: id ?? this.id,
    label: label == null ? this.label : label(),
    contextWindow: contextWindow == null ? this.contextWindow : contextWindow(),
    thinking: thinking ?? this.thinking,
    images: images ?? this.images,
    enabled: enabled ?? this.enabled,
    custom: custom ?? this.custom,
    missing: missing ?? this.missing,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    if (label case final label? when label.trim().isNotEmpty) 'label': label,
    'contextWindow': ?contextWindow,
    if (thinking) 'thinking': true,
    if (images) 'images': true,
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
      thinking: json['thinking'] == true,
      images: json['images'] == true,
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
      other.thinking == thinking &&
      other.images == images &&
      other.enabled == enabled &&
      other.custom == custom &&
      other.missing == missing;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    contextWindow,
    thinking,
    images,
    enabled,
    custom,
    missing,
  );
}

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

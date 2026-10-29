/// What a model can do and costs, as far as the agent needs to know.
class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.name,
    this.family = '',
    this.contextWindow = 200000,
    this.maxOutput = 32000,
    this.defaultMaxTokens = 32000,
    this.thinking = ThinkingStyle.none,
    this.effortLevels = const [],
    this.defaultEffort,
    this.canDisableThinking = true,
    this.inputPrice = 0,
    this.outputPrice = 0,
    this.cacheReadFactor = 0.1,
    this.known = true,
  });

  /// An unknown model's: nothing asked of it that it may refuse.
  factory ModelInfo.unknown(String id) =>
      ModelInfo(id: id, name: id, known: false);

  final String id;
  final String name;

  /// `opus`, `sonnet`, `haiku`, `fable`, or empty.
  final String family;
  final int contextWindow;
  final int maxOutput;

  /// The `max_tokens` asked for unless the environment says
  /// (`CLAUDE_CODE_MAX_OUTPUT_TOKENS`): [maxOutput] for the newest, less
  /// for those that would spend it slowly.
  final int defaultMaxTokens;
  final ThinkingStyle thinking;

  /// The `output_config.effort` levels it takes; none when it takes none.
  final List<String> effortLevels;

  /// What it does with no effort said.
  final String? defaultEffort;

  /// Whether `thinking: {type: "disabled"}` is taken (at `high` or below).
  final bool canDisableThinking;

  /// Dollars a million tokens.
  final double inputPrice;
  final double outputPrice;

  /// What a cached token read costs, as a share of [inputPrice].
  final double cacheReadFactor;

  /// Whether this table knows it, rather than guessed.
  final bool known;

  bool get supportsEffort => effortLevels.isNotEmpty;

  /// The cost of [usage] (an API usage object), in dollars.
  double cost(Map<String, Object?> usage) {
    int count(String key) => (usage[key] as num?)?.toInt() ?? 0;
    final input = count('input_tokens');
    final written = count('cache_creation_input_tokens');
    final read = count('cache_read_input_tokens');
    final output = count('output_tokens');
    final searches = switch (usage['server_tool_use']) {
      final Map<Object?, Object?> tools =>
        (tools['web_search_requests'] as num?)?.toInt() ?? 0,
      _ => 0,
    };
    return (input * inputPrice +
                written * inputPrice * 1.25 +
                read * inputPrice * cacheReadFactor +
                output * outputPrice) /
            1000000 +
        searches * 0.01;
  }
}

/// How a model is asked to think.
enum ThinkingStyle {
  /// `{type: "adaptive"}`: it decides, steered by the effort.
  adaptive,

  /// `{type: "enabled", budget_tokens: n}`: earlier models.
  budget,

  /// Not at all.
  none,
}

/// The models the agent knows, and the names they go by (`opus`, `sonnet`,
/// `haiku`, `default`), which the environment may point elsewhere
/// (`ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, …).
class ModelCatalog {
  ModelCatalog([Map<String, String> environment = const {}])
    : _env = environment;

  final Map<String, String> _env;

  static const _all5 = ['low', 'medium', 'high', 'xhigh', 'max'];

  static const known = <ModelInfo>[
    ModelInfo(
      id: 'claude-fable-5-1',
      name: 'Fable 5.1',
      family: 'fable',
      contextWindow: 1000000,
      maxOutput: 128000,
      defaultMaxTokens: 64000,
      thinking: ThinkingStyle.adaptive,
      effortLevels: _all5,
      defaultEffort: 'high',
      canDisableThinking: false,
      inputPrice: 10,
      outputPrice: 50,
      cacheReadFactor: 0.025,
    ),
    ModelInfo(
      id: 'claude-opus-5-5',
      name: 'Opus 5.5',
      family: 'opus',
      contextWindow: 1000000,
      maxOutput: 128000,
      defaultMaxTokens: 128000,
      thinking: ThinkingStyle.adaptive,
      effortLevels: _all5,
      defaultEffort: 'medium',
      canDisableThinking: false,
      inputPrice: 4,
      outputPrice: 20,
      cacheReadFactor: 0.05,
    ),
    ModelInfo(
      id: 'claude-sonnet-5-5',
      name: 'Sonnet 5.5',
      family: 'sonnet',
      contextWindow: 1000000,
      maxOutput: 128000,
      defaultMaxTokens: 128000,
      thinking: ThinkingStyle.adaptive,
      effortLevels: _all5,
      defaultEffort: 'medium',
      canDisableThinking: false,
      inputPrice: 2,
      outputPrice: 10,
      cacheReadFactor: 0.05,
    ),
    ModelInfo(
      id: 'claude-haiku-5-5',
      name: 'Haiku 5.5',
      family: 'haiku',
      contextWindow: 1000000,
      maxOutput: 128000,
      defaultMaxTokens: 128000,
      thinking: ThinkingStyle.adaptive,
      effortLevels: _all5,
      defaultEffort: 'medium',
      inputPrice: 0.1,
      outputPrice: 0.5,
    ),
    ModelInfo(
      id: 'claude-fable-5',
      name: 'Fable 5',
      family: 'fable',
      contextWindow: 1000000,
      maxOutput: 128000,
      defaultMaxTokens: 64000,
      thinking: ThinkingStyle.adaptive,
      effortLevels: _all5,
      defaultEffort: 'high',
      canDisableThinking: false,
      inputPrice: 10,
      outputPrice: 50,
    ),
    ModelInfo(
      id: 'claude-opus-5',
      name: 'Opus 5',
      family: 'opus',
      contextWindow: 1000000,
      maxOutput: 128000,
      defaultMaxTokens: 64000,
      thinking: ThinkingStyle.adaptive,
      effortLevels: _all5,
      defaultEffort: 'high',
      inputPrice: 5,
      outputPrice: 25,
    ),
    ModelInfo(
      id: 'claude-sonnet-5',
      name: 'Sonnet 5',
      family: 'sonnet',
      contextWindow: 1000000,
      maxOutput: 128000,
      defaultMaxTokens: 64000,
      thinking: ThinkingStyle.adaptive,
      effortLevels: _all5,
      defaultEffort: 'high',
      inputPrice: 3,
      outputPrice: 15,
    ),
    ModelInfo(
      id: 'claude-opus-4-8',
      name: 'Opus 4.8',
      family: 'opus',
      contextWindow: 1000000,
      maxOutput: 128000,
      defaultMaxTokens: 64000,
      thinking: ThinkingStyle.adaptive,
      effortLevels: _all5,
      defaultEffort: 'high',
      inputPrice: 5,
      outputPrice: 25,
    ),
    ModelInfo(
      id: 'claude-opus-4-7',
      name: 'Opus 4.7',
      family: 'opus',
      contextWindow: 1000000,
      maxOutput: 128000,
      defaultMaxTokens: 64000,
      thinking: ThinkingStyle.adaptive,
      effortLevels: _all5,
      defaultEffort: 'xhigh',
      inputPrice: 5,
      outputPrice: 25,
    ),
    ModelInfo(
      id: 'claude-opus-4-6',
      name: 'Opus 4.6',
      family: 'opus',
      contextWindow: 200000,
      maxOutput: 128000,
      defaultMaxTokens: 64000,
      thinking: ThinkingStyle.adaptive,
      effortLevels: ['low', 'medium', 'high', 'max'],
      defaultEffort: 'high',
      inputPrice: 5,
      outputPrice: 25,
    ),
    ModelInfo(
      id: 'claude-sonnet-4-6',
      name: 'Sonnet 4.6',
      family: 'sonnet',
      contextWindow: 200000,
      maxOutput: 64000,
      thinking: ThinkingStyle.adaptive,
      effortLevels: ['low', 'medium', 'high', 'max'],
      defaultEffort: 'high',
      inputPrice: 3,
      outputPrice: 15,
    ),
    ModelInfo(
      id: 'claude-opus-4-5-20251101',
      name: 'Opus 4.5',
      family: 'opus',
      contextWindow: 200000,
      maxOutput: 64000,
      thinking: ThinkingStyle.budget,
      effortLevels: ['low', 'medium', 'high'],
      defaultEffort: 'high',
      inputPrice: 5,
      outputPrice: 25,
    ),
    ModelInfo(
      id: 'claude-sonnet-4-5-20250929',
      name: 'Sonnet 4.5',
      family: 'sonnet',
      contextWindow: 200000,
      maxOutput: 64000,
      thinking: ThinkingStyle.budget,
      inputPrice: 3,
      outputPrice: 15,
    ),
    ModelInfo(
      id: 'claude-haiku-4-5-20251001',
      name: 'Haiku 4.5',
      family: 'haiku',
      contextWindow: 200000,
      maxOutput: 64000,
      thinking: ThinkingStyle.budget,
      inputPrice: 1,
      outputPrice: 5,
    ),
  ];

  /// What each family's name stands for, unless the environment says.
  static const _familyDefaults = {
    'opus': 'claude-opus-5-5',
    'sonnet': 'claude-sonnet-5-5',
    'haiku': 'claude-haiku-5-5',
    'fable': 'claude-fable-5-1',
  };

  static const defaultAlias = 'default';

  String? _envModel(String name) => switch (_env[name]?.trim()) {
    final value? when value.isNotEmpty => value,
    _ => null,
  };

  /// The model [alias] (or id) stands for: `opus` the newest Opus, `default`
  /// what the environment sets else Opus. A `[1m]` suffix is kept off: every
  /// current model holds a million tokens.
  String resolve(String? alias) {
    var name = (alias ?? defaultAlias).trim();
    if (name.toLowerCase().endsWith('[1m]')) {
      name = name.substring(0, name.length - 4);
    }
    switch (name.toLowerCase()) {
      case '' || defaultAlias:
        return _envModel('ANTHROPIC_MODEL') ?? resolve('opus');
      case 'opus' || 'opusplan':
        return _envModel('ANTHROPIC_DEFAULT_OPUS_MODEL') ??
            _familyDefaults['opus']!;
      case 'sonnet':
        return _envModel('ANTHROPIC_DEFAULT_SONNET_MODEL') ??
            _familyDefaults['sonnet']!;
      case 'haiku':
        return _envModel('ANTHROPIC_DEFAULT_HAIKU_MODEL') ??
            _familyDefaults['haiku']!;
      case 'fable':
        return _familyDefaults['fable']!;
    }
    return name;
  }

  /// The small, fast model for the agent's own errands (titles, checks,
  /// summaries of pages).
  String get smallFast =>
      _envModel('ANTHROPIC_SMALL_FAST_MODEL') ??
      _envModel('ANTHROPIC_DEFAULT_HAIKU_MODEL') ??
      _familyDefaults['haiku']!;

  /// What [id] can do: the table's entry for it (or for the snapshot it
  /// names), else an unknown model's.
  ModelInfo info(String id) {
    final bare = id.toLowerCase();
    for (final model in known) {
      if (bare == model.id || bare.startsWith('${model.id}-')) return model;
    }
    // A dated snapshot of one known by its alias, or a model on another
    // platform (`anthropic.claude-opus-5-5`, `claude-opus-5-5@…`).
    for (final model in known) {
      final alias = model.id.replaceFirst(RegExp(r'-\d{8}$'), '');
      if (bare.contains(alias)) return model;
    }
    return ModelInfo.unknown(id);
  }

  /// The models listed to the user (the `initialize` answer's `models`).
  List<Map<String, Object?>> listed() {
    String price(double dollars) => dollars == dollars.roundToDouble()
        ? '\$${dollars.round()}'
        : '\$${dollars.toStringAsFixed(2)}';

    Map<String, Object?> entry(String value, String? label, String role) {
      final resolved = resolve(value);
      final model = info(resolved);
      final name = model.known ? model.name : resolved;
      final cost = model.inputPrice > 0
          ? ' · ${price(model.inputPrice)}/${price(model.outputPrice)} '
                'per Mtok'
          : '';
      return {
        'value': value,
        'resolvedModel': resolved,
        'displayName':
            label ?? '${value[0].toUpperCase()}${value.substring(1)}',
        'description': label == null
            ? '$name · $role$cost'
            : '$role (now $name)$cost',
        'supportsEffort': model.supportsEffort,
        'supportedEffortLevels': model.effortLevels,
        if (model.thinking == ThinkingStyle.adaptive)
          'supportsAdaptiveThinking': true,
        'supportsAutoMode': true,
      };
    }

    return [
      entry(
        defaultAlias,
        'Default (recommended)',
        'The model to use unless told otherwise',
      ),
      entry('opus', null, 'The best fit for most complex work'),
      entry(
        'fable',
        null,
        'The deepest reasoning, for the longest and hardest work',
      ),
      entry('sonnet', null, 'Quick and able, for everyday work'),
      entry('haiku', null, 'The quickest, for short answers'),
    ];
  }
}

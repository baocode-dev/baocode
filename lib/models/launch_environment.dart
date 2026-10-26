import 'model_provider.dart';
import 'upstream.dart';

/// Where the local proxy takes a provider's requests, and the token it
/// asks for.
typedef ProxyEndpoint = ({String baseUrl, String token});

/// What Claude Code is given (its `--settings` `env`) to run a session on
/// [provider]'s [model]: the upstream, or the proxy in front of it, its
/// key, and the models it uses for each part of its work.
///
/// Both auth variables are always set, the one unused empty: a key of the
/// user's own (for Anthropic) must not go to another upstream.
///
/// Roles on another upstream's model ([ModelProvider.otherUpstreams]), and
/// models of an endpoint of their own ([ProviderModel.protocol]), take the
/// session through the proxy whatever [provider] speaks, a model elsewhere
/// named as its [modelRef]: the proxy sends it there.
Map<String, String> launchEnvironment({
  required ModelProvider provider,
  required String model,
  String? key,
  ProxyEndpoint? proxy,
  String? noProxy,
}) {
  final String baseUrl;
  final String token;
  var apiKey = '';
  final proxied = provider.throughProxy;
  if (proxied) {
    if (proxy == null) {
      throw StateError('${provider.name} needs the model proxy');
    }
    baseUrl = proxy.baseUrl;
    token = proxy.token;
  } else {
    baseUrl = UpstreamUrls.anthropicBase(provider.baseUrl) ?? provider.baseUrl;
    if (sendsApiKeyHeader(provider)) {
      token = '';
      apiKey = key ?? '';
    } else {
      token = key ?? '';
    }
  }
  final roles = provider.roles;
  // This upstream's own model by its id; another's as it is picked.
  String? role(String? value) => switch (parseModelRef(value)) {
    (provider: final id, :final model) when id == provider.id => model,
    _ => value,
  };
  return {
    // Whatever the user's own setup says: this session is this upstream's.
    for (final name in ClaudeModelVariables.cleared) name: '',
    ClaudeModelVariables.baseUrl: baseUrl,
    ClaudeModelVariables.authToken: token,
    ClaudeModelVariables.apiKey: apiKey,
    ClaudeModelVariables.model: model,
    ClaudeModelVariables.opus: role(roles.opus) ?? model,
    ClaudeModelVariables.sonnet: role(roles.sonnet) ?? model,
    // The background work: the model picked, unless one is set for it.
    ClaudeModelVariables.haiku: role(roles.haiku) ?? model,
    // Empty for none: not one the user's own settings name.
    ClaudeModelVariables.subagent: role(roles.subagent) ?? '',
    // Over the model a subagent's definition names, or the agent asks for
    // ("sonnet", "haiku": the model picked, here): else the one set for
    // subagents is used only where neither says.
    ClaudeModelVariables.subagentForce: roles.subagent != null ? '1' : '',
    // Unknown Anthropic-compatible models can still accept output_config.effort.
    if (provider.speaksAnthropic) ClaudeModelVariables.alwaysEnableEffort: '1',
    if (provider.disableNonessentialTraffic)
      ClaudeModelVariables.nonessentialTraffic: '1',
    // The proxy is on this machine: never through the user's HTTP proxy.
    if (proxied)
      'NO_PROXY': [
        if (noProxy case final list? when list.trim().isNotEmpty) list.trim(),
        '127.0.0.1',
        'localhost',
      ].join(','),
    // A provider spoken to directly carries its own headers in Claude
    // Code's variable (a proxied one goes through the proxy, which sets
    // them itself): `Name: Value` a line, only the names that may be set.
    // A `{{…}}` variable is not filled here (the CLI cannot): it stands
    // as written.
    if (!proxied)
      if (customHeadersEnvironment(provider.headers) case final custom
          when custom.isNotEmpty)
        ClaudeModelVariables.customHeadersVariable: custom,
    ...provider.env,
  };
}

/// [headers] as [ClaudeModelVariables.customHeaders] shows them: a
/// `Name: Value` a line, only the names that may be set ([sanitizeHeaders]).
String customHeadersEnvironment(Map<String, String> headers) => [
  for (final MapEntry(:key, :value) in sanitizeHeaders(headers).entries)
    '$key: $value',
].join('\n');

const fastModelSuffix = ';fast';

/// The model [model] of [provider] as Claude Code is told to ask for it:
/// for one spoken to through the proxy ([ModelProvider.protocolOf]), the
/// effort after it in parentheses (`gpt-5(high)`, `gpt-5(none)` for no
/// reasoning), which the proxy takes off and asks the upstream for. Fast
/// appends `;fast` inside those parentheses.
String requestedModel(
  ModelProvider provider,
  ProviderModel model, {
  String? effort,
  bool fast = false,
}) {
  final protocol = provider.protocolOf(model);
  final useFast =
      fast &&
      (protocol == ProviderProtocol.openaiResponses ||
          protocol == ProviderProtocol.codex);
  if (!protocol.proxied || (effort == null && !useFast)) {
    return model.id;
  }
  return '${model.id}(${effort ?? ''}${useFast ? fastModelSuffix : ''})';
}

/// What a provider's session lets through an `availableModels` of the
/// user's own settings, which Claude Code would otherwise swap for one of
/// Claude's, sent to the provider all the same (#219): [models], those
/// [env] (its [launchEnvironment]) names for each role, and the names
/// those stand for (a subagent may ask for `haiku`). An organization's
/// policy is over it: its list stands.
List<String> allowedModels(Map<String, String>? env, Iterable<String> models) =>
    {
      ...models,
      for (final name in const [
        ClaudeModelVariables.model,
        ClaudeModelVariables.opus,
        ClaudeModelVariables.sonnet,
        ClaudeModelVariables.haiku,
        ClaudeModelVariables.subagent,
      ])
        if (env?[name] case final value? when value.isNotEmpty) value,
      'opus',
      'sonnet',
      'haiku',
    }.toList();

/// The environment variables Claude Code takes its model setup from.
abstract final class ClaudeModelVariables {
  static const baseUrl = 'ANTHROPIC_BASE_URL';
  static const authToken = 'ANTHROPIC_AUTH_TOKEN';
  static const apiKey = 'ANTHROPIC_API_KEY';
  static const model = 'ANTHROPIC_MODEL';
  static const opus = 'ANTHROPIC_DEFAULT_OPUS_MODEL';
  static const sonnet = 'ANTHROPIC_DEFAULT_SONNET_MODEL';
  static const haiku = 'ANTHROPIC_DEFAULT_HAIKU_MODEL';
  static const subagent = 'CLAUDE_CODE_SUBAGENT_MODEL';

  /// [subagent] for every subagent, whatever its definition or the call
  /// names (but `inherit`).
  static const subagentForce = 'CLAUDE_CODE_SUBAGENT_MODEL_FORCE';
  static const alwaysEnableEffort = 'CLAUDE_CODE_ALWAYS_ENABLE_EFFORT';
  static const nonessentialTraffic = 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC';

  /// The provider's own request headers, an Anthropic-compatible one
  /// spoken to directly: `Name: Value` a line (Claude Code's own variable,
  /// [cleared] for every other session).
  static const customHeadersVariable = 'ANTHROPIC_CUSTOM_HEADERS';

  /// The window of a model not Claude's: the CLI takes 200K for one it
  /// does not know, and compacts within it whatever `--autocompact` says.
  static const maxContextTokens = 'CLAUDE_CODE_MAX_CONTEXT_TOKENS';

  /// Those that hold a secret: a settings file, not a command line.
  static const secrets = {authToken, apiKey};

  /// Set empty for a provider's session, over the user's own: other
  /// backends, and older names of the models.
  static const cleared = [
    'CLAUDE_CODE_USE_BEDROCK',
    'CLAUDE_CODE_USE_VERTEX',
    'CLAUDE_CODE_USE_FOUNDRY',
    'ANTHROPIC_SMALL_FAST_MODEL',
    'ANTHROPIC_CUSTOM_HEADERS',
  ];

  /// What a provider's session must not inherit from the app's
  /// environment.
  static const inherited = [
    baseUrl,
    authToken,
    apiKey,
    model,
    opus,
    sonnet,
    haiku,
    subagent,
    subagentForce,
    ...cleared,
  ];
}

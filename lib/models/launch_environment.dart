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
  if (provider.protocol.proxied) {
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
  return {
    // Whatever the user's own setup says: this session is this upstream's.
    for (final name in ClaudeModelVariables.cleared) name: '',
    ClaudeModelVariables.baseUrl: baseUrl,
    ClaudeModelVariables.authToken: token,
    ClaudeModelVariables.apiKey: apiKey,
    ClaudeModelVariables.model: model,
    ClaudeModelVariables.opus: roles.opus ?? model,
    ClaudeModelVariables.sonnet: roles.sonnet ?? model,
    // The background work: the model picked, unless one is set for it.
    ClaudeModelVariables.haiku: roles.haiku ?? model,
    ClaudeModelVariables.subagent: ?roles.subagent,
    // Unknown Anthropic-compatible models can still accept output_config.effort.
    if (!provider.protocol.proxied)
      ClaudeModelVariables.alwaysEnableEffort: '1',
    if (provider.disableNonessentialTraffic)
      ClaudeModelVariables.nonessentialTraffic: '1',
    // The proxy is on this machine: never through the user's HTTP proxy.
    if (provider.protocol.proxied)
      'NO_PROXY': [
        if (noProxy case final list? when list.trim().isNotEmpty) list.trim(),
        '127.0.0.1',
        'localhost',
      ].join(','),
    ...provider.env,
  };
}

/// The model [modelId] of [provider] as Claude Code is told to ask for it:
/// for a proxied model, the effort after it in parentheses (`gpt-5(high)`,
/// `gpt-5(none)` for no reasoning), which the proxy takes off and asks the
/// upstream for.
String requestedModel(
  ModelProvider provider,
  ProviderModel model, {
  String? effort,
}) {
  if (!provider.protocol.proxied || effort == null) {
    return model.id;
  }
  return '${model.id}($effort)';
}

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
  static const alwaysEnableEffort = 'CLAUDE_CODE_ALWAYS_ENABLE_EFFORT';
  static const nonessentialTraffic = 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC';

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
    ...cleared,
  ];
}

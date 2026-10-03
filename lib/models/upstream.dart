import 'dart:convert';

import 'model_provider.dart';

/// What an upstream lists of its models (`GET /v1/models`).
class RemoteModel {
  const RemoteModel(this.id, {this.label, this.contextWindow});

  final String id;
  final String? label;
  final int? contextWindow;
}

/// How [ModelProvider.baseUrl] is read, as each protocol's SDK has it:
/// Anthropic's without the version (`https://api.anthropic.com`, Claude
/// Code adds `/v1/messages`), OpenAI's with it
/// (`https://api.openai.com/v1`, `/chat/completions` added). An OpenAI
/// URL without a version in its path gets `/v1`: a bare host, or a
/// gateway's prefix (`https://x.example/provider`).
abstract final class UpstreamUrls {
  /// [baseUrl] without trailing slashes; null when it is not an http(s)
  /// URL.
  static Uri? parse(String baseUrl) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    if (uri.host.isEmpty) return null;
    return uri;
  }

  /// The base Claude Code is pointed at (`ANTHROPIC_BASE_URL`): without a
  /// trailing `/v1`, which it adds.
  static String? anthropicBase(String baseUrl) {
    final uri = parse(baseUrl);
    if (uri == null) return null;
    final text = uri.toString();
    return text.endsWith('/v1') ? text.substring(0, text.length - 3) : text;
  }

  /// The base OpenAI's paths go under: with its version (`v1`, `v4`,
  /// `v1beta`, anywhere in the path), `/v1` added if it has none.
  static String? openaiBase(String baseUrl) {
    final uri = parse(baseUrl);
    if (uri == null) return null;
    final versioned = uri.pathSegments.any(_version.hasMatch);
    return versioned ? '$uri' : '$uri/v1';
  }

  static final _version = RegExp(r'^v\d+[a-z0-9.]*$', caseSensitive: false);

  /// Where [provider] lists its models.
  static Uri? models(ModelProvider provider) => switch (provider.protocol) {
    ProviderProtocol.anthropic => switch (anthropicBase(provider.baseUrl)) {
      final base? => Uri.parse('$base/v1/models'),
      null => null,
    },
    _ => switch (openaiBase(provider.baseUrl)) {
      final base? => Uri.parse('$base/models'),
      null => null,
    },
  };

  /// Where [provider] takes a conversation: Chat Completions or
  /// Responses (Anthropic's is Claude Code's to call).
  static Uri? conversation(ModelProvider provider) =>
      switch (openaiBase(provider.baseUrl)) {
        final base? => switch (provider.protocol) {
          ProviderProtocol.openaiChat => Uri.parse('$base/chat/completions'),
          ProviderProtocol.openaiResponses => Uri.parse('$base/responses'),
          ProviderProtocol.anthropic => null,
        },
        null => null,
      };
}

/// Whether [provider]'s key goes as `x-api-key`: asked for, or left to
/// [ProviderAuth.auto] on Anthropic's own API.
bool sendsApiKeyHeader(ModelProvider provider) => switch (provider.auth) {
  ProviderAuth.apiKey => true,
  ProviderAuth.bearer => false,
  ProviderAuth.auto =>
    provider.protocol == ProviderProtocol.anthropic &&
        provider.host.endsWith('anthropic.com'),
};

/// The headers [provider] is asked with, [key] in them.
Map<String, String> upstreamHeaders(ModelProvider provider, String? key) => {
  if (provider.protocol == ProviderProtocol.anthropic)
    'anthropic-version': '2023-06-01',
  if (key != null && key.isNotEmpty)
    if (sendsApiKeyHeader(provider))
      'x-api-key': key
    else
      'authorization': 'Bearer $key',
};

/// The models in a `/v1/models` answer: OpenAI's `data` (or a bare list),
/// Anthropic's `data` with `display_name`; a context window where the
/// upstream says (OpenRouter's `context_length`, and others').
List<RemoteModel> parseModelList(Object? json) {
  final list = switch (json) {
    {'data': final List data} => data,
    {'models': final List models} => models,
    final List list => list,
    _ => const [],
  };
  final models = <RemoteModel>[];
  final seen = <String>{};
  for (final item in list) {
    if (item is! Map) continue;
    final id = switch (item['id'] ?? item['name']) {
      final String id when id.trim().isNotEmpty => id.trim(),
      _ => null,
    };
    if (id == null || !seen.add(id)) continue;
    final label = switch (item['display_name'] ?? item['displayName']) {
      final String label when label.trim().isNotEmpty && label != id =>
        label.trim(),
      _ => null,
    };
    int? window;
    for (final key in const [
      'context_window',
      'context_length',
      'max_input_tokens',
      'max_context_length',
      'max_model_len',
    ]) {
      if (item[key] case final num tokens when tokens > 0) {
        window = tokens.toInt();
        break;
      }
    }
    if (window == null) {
      if (item['top_provider'] case {'context_length': final num tokens}
          when tokens > 0) {
        window = tokens.toInt();
      }
    }
    models.add(RemoteModel(id, label: label, contextWindow: window));
  }
  return models;
}

/// [provider]'s models with [listed] merged in: new ones added, off
/// unless in [enable]; known ones kept as the user set them (on if in
/// [enable]); those no longer listed marked [ProviderModel.missing] (kept;
/// added by hand, left alone).
List<ProviderModel> mergeModelList(
  List<ProviderModel> models,
  List<RemoteModel> listed, {
  Set<String> enable = const {},
}) {
  final byId = {for (final model in listed) model.id: model};
  final merged = <ProviderModel>[
    for (final model in models)
      if (byId[model.id] case final remote?)
        model.copyWith(
          missing: false,
          contextWindow: model.contextWindow == null
              ? () => remote.contextWindow
              : null,
          label: (model.label ?? '').isEmpty ? () => remote.label : null,
          enabled: enable.contains(model.id) ? true : null,
        )
      else if (model.custom)
        model
      else
        model.copyWith(missing: true),
  ];
  final known = {for (final model in models) model.id};
  for (final remote in listed) {
    if (known.contains(remote.id)) continue;
    merged.add(
      ProviderModel(
        id: remote.id,
        label: remote.label,
        contextWindow: remote.contextWindow,
        enabled: enable.contains(remote.id),
      ),
    );
  }
  return merged;
}

/// An Anthropic error, for what Claude Code shows of a failed request.
Map<String, Object?> anthropicError(int status, String message) => {
  'type': 'error',
  'error': {
    'type': switch (status) {
      400 || 413 || 422 => 'invalid_request_error',
      401 => 'authentication_error',
      403 => 'permission_error',
      404 => 'not_found_error',
      429 => 'rate_limit_error',
      529 || 503 => 'overloaded_error',
      _ => 'api_error',
    },
    'message': message,
  },
};

/// The message in an upstream's error body: OpenAI's and Anthropic's
/// `error.message`, else the body itself, cut short.
String upstreamErrorMessage(int status, String body) {
  final trimmed = body.trim();
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    decoded = null;
  }
  final message = switch (decoded) {
    {'error': {'message': final String message}} => message,
    {'error': final String message} => message,
    {'message': final String message} => message,
    _ => null,
  };
  final text = message ?? trimmed;
  final short = text.length > 500 ? '${text.substring(0, 500)}…' : text;
  return short.isEmpty ? 'HTTP $status' : 'HTTP $status: $short';
}

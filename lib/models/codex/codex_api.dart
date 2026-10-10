// ChatGPT's Codex backend, as the Codex CLI speaks to it: where it is, how
// a request to it is made, and what it answers. After CLIProxyAPI's Codex
// executor (see proxy/translate/NOTICE.md).

import 'dart:convert';

import '../upstream.dart';

/// The Codex CLI's version this speaks as: the backend lists the models of
/// it ([CodexEndpoints.models]).
const codexClientVersion = '0.154.0';

/// What the requests go as, as the Codex CLI's: the backend's Cloudflare
/// turns away other clients.
const codexUserAgent =
    'codex-tui/$codexClientVersion (Mac OS 26.5.2; arm64) iTerm.app/3.6.11 '
    '(codex-tui; $codexClientVersion)';

const codexOriginator = 'codex-tui';

/// OpenAI's OAuth client of the Codex CLI.
const codexClientId = 'app_EMoamEEZ73f0CkXaXp7hrann';

/// Where sign-in and the backend are: OpenAI's own, unless under test.
class CodexEndpoints {
  const CodexEndpoints({
    this.auth = 'https://auth.openai.com',
    this.backend = 'https://chatgpt.com/backend-api',
    this.callbackPort = 1455,
  });

  /// OAuth's: `/oauth/authorize`, `/oauth/token`.
  final String auth;

  /// The backend's: `/codex/responses`, `/codex/models`, `/wham/usage`.
  final String backend;

  /// The port sign-in comes back to, on this machine: the one the client
  /// is registered with.
  final int callbackPort;

  Uri get authorize => Uri.parse('$auth/oauth/authorize');
  Uri get token => Uri.parse('$auth/oauth/token');
  Uri get responses => Uri.parse('$backend/codex/responses');
  Uri get models =>
      Uri.parse('$backend/codex/models?client_version=$codexClientVersion');
  Uri get usage => Uri.parse('$backend/wham/usage');
  String get redirectUri => 'http://localhost:$callbackPort/auth/callback';
}

/// The headers a request to the backend goes with: [token] the account's
/// access token, [accountId] its workspace; [session] the conversation's
/// (its `prompt_cache_key`).
Map<String, String> codexHeaders(
  String token, {
  String? accountId,
  String? session,
  bool events = false,
}) => {
  'authorization': 'Bearer $token',
  if (accountId != null && accountId.isNotEmpty)
    'chatgpt-account-id': accountId,
  'originator': codexOriginator,
  'user-agent': codexUserAgent,
  'accept': events ? 'text/event-stream' : 'application/json',
  if (session != null && session.isNotEmpty) 'session-id': session,
};

/// [request] (a Responses request) as the backend takes it: instructions
/// set, even empty (the system prompt is a developer message), streamed,
/// nothing stored, the reasoning encrypted to be replayed; without the
/// fields it refuses.
Map<String, Object?> prepareCodexRequest(Map<String, Object?> request) {
  request['instructions'] ??= '';
  request['stream'] = true;
  request['store'] = false;
  final webSearch = switch (request['tools']) {
    final List tools => tools.any(
      (tool) => tool is Map && tool['type'] == 'web_search',
    ),
    _ => false,
  };
  // Priority (fast) only: it knows no other tier.
  if (request['service_tier'] != 'priority') request.remove('service_tier');
  request['include'] = [
    'reasoning.encrypted_content',
    if (webSearch) 'web_search_call.action.sources',
  ];
  for (final field in const [
    'previous_response_id',
    'prompt_cache_retention',
    'safety_identifier',
    'stream_options',
    'max_output_tokens',
    'max_completion_tokens',
    'temperature',
    'top_p',
    'truncation',
    'user',
    'metadata',
  ]) {
    request.remove(field);
  }
  return request;
}

/// [request] without its reasoning items: for an account other than the
/// one that encrypted them, which cannot read them. Whether there were any.
bool stripReasoningItems(Map<String, Object?> request) {
  final input = request['input'];
  if (input is! List) return false;
  final before = input.length;
  input.removeWhere((item) => item is Map && item['type'] == 'reasoning');
  return input.length != before;
}

/// Whether [body], an error, says the reasoning replayed could not be
/// read: encrypted for another account.
bool isInvalidEncryptedContent(String body) =>
    body.contains('invalid_encrypted_content') ||
    body.toLowerCase().contains('encrypted content') &&
        body.toLowerCase().contains('could not be');

/// When an account that answered [status] with [body] has its quota again:
/// a usage limit reached (`usage_limit_reached`, with `resets_at` or
/// `resets_in_seconds`); null when it is not one. A limit without a time
/// is taken to last [fallback].
DateTime? codexLimitReset(
  int status,
  String body,
  DateTime now, {
  Duration fallback = const Duration(minutes: 5),
}) {
  Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return null;
  }
  return codexLimitResetOf(json, now, fallback: fallback);
}

/// [codexLimitReset] of a decoded error: an answer's, or an event's
/// (`error`, `response.failed`).
DateTime? codexLimitResetOf(
  Object? json,
  DateTime now, {
  Duration fallback = const Duration(minutes: 5),
}) {
  final candidates = [
    if (json case {'error': final Map error}) error,
    if (json case {'response': {'error': final Map error}}) error,
    if (json is Map) json,
  ];
  for (final error in candidates) {
    if ('${error['type'] ?? error['code'] ?? ''}'.trim().toLowerCase() !=
        'usage_limit_reached') {
      continue;
    }
    if (error['resets_at'] case final num at when at > 0) {
      final time = DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000);
      if (time.isAfter(now)) return time;
    }
    if (error['resets_in_seconds'] case final num seconds when seconds > 0) {
      return now.add(Duration(seconds: seconds.toInt()));
    }
    return now.add(fallback);
  }
  return null;
}

/// The models the backend lists (`/codex/models`): those it shows, with
/// their context and efforts.
List<RemoteModel> parseCodexModels(Object? json) {
  final list = switch (json) {
    {'models': final List models} => models,
    {'data': final List data} => data,
    final List list => list,
    _ => const [],
  };
  final models = <RemoteModel>[];
  final seen = <String>{};
  for (final item in list) {
    if (item is! Map) continue;
    final id = switch (item['slug'] ?? item['id']) {
      final String id when id.trim().isNotEmpty => id.trim(),
      _ => null,
    };
    if (id == null || !seen.add(id)) continue;
    if (item['visibility'] case final String visibility
        when visibility != 'list') {
      continue;
    }
    if (item['supported_in_api'] == false) continue;
    final label = switch (item['display_name']) {
      final String label when label.trim().isNotEmpty && label != id =>
        label.trim(),
      _ => null,
    };
    final efforts = switch (item['supported_reasoning_levels']) {
      final List levels => [
        for (final level in levels)
          if (switch (level) {
                {'effort': final String effort} => effort,
                final String effort => effort,
                _ => null,
              }
              case final effort? when effort.trim().isNotEmpty)
            effort.trim(),
      ],
      _ => null,
    };
    final images = switch (item['input_modalities']) {
      final List modalities => modalities.contains('image'),
      _ => null,
    };
    models.add(
      RemoteModel(
        id,
        label: label,
        contextWindow: switch (item['context_window']) {
          final num tokens when tokens > 0 => tokens.toInt(),
          _ => null,
        },
        efforts: efforts == null || efforts.isEmpty ? null : efforts,
        images: images,
      ),
    );
  }
  return models;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../util/cancel.dart';
import 'model_client.dart';
import 'sse.dart';

/// Where the API is and how to sign in to it.
class ApiConfig {
  const ApiConfig({
    this.baseUrl = defaultBaseUrl,
    this.apiKey,
    this.authToken,
    this.headers = const {},
    this.environment = const {},
    this.maxRetries = 10,
    this.idleTimeout = const Duration(minutes: 5),
    this.userAgent = 'baocode-agent',
    this.userId,
    this.deviceId,
  });

  static const defaultBaseUrl = 'https://api.anthropic.com';

  final String baseUrl;

  /// Sent as `x-api-key`.
  final String? apiKey;

  /// Sent as `Authorization: Bearer`.
  final String? authToken;

  /// More headers for every request (`ANTHROPIC_CUSTOM_HEADERS`).
  final Map<String, String> headers;

  /// The environment the proxy settings are read from (`HTTPS_PROXY`,
  /// `NO_PROXY`, …).
  final Map<String, String> environment;
  final int maxRetries;

  /// How long a streamed answer may go quiet before it is given up on and
  /// asked for again.
  final Duration idleTimeout;
  final String userAgent;

  /// Sent as every request's `metadata.user_id`: the session, by which a
  /// proxy or gateway keeps a conversation on the upstream (and the
  /// account) that has it cached.
  final String? userId;

  /// The machine, as Anthropic's own API is told it with [userId].
  final String? deviceId;

  bool get hasCredentials =>
      (apiKey?.isNotEmpty ?? false) || (authToken?.isNotEmpty ?? false);

  /// Whether this is Anthropic's own API (or, with
  /// `BAOCODE_FIRST_PARTY_API`, a server that speaks all of it).
  bool get firstParty => isFirstParty(baseUrl, environment);

  /// Whether requests to [baseUrl] go to Anthropic's own API (or the
  /// environment says to treat them so).
  static bool isFirstParty(String baseUrl, Map<String, String> environment) {
    final forced = environment['BAOCODE_FIRST_PARTY_API'];
    if (forced != null && forced.isNotEmpty) {
      return forced != '0' && forced != 'false';
    }
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    return host == 'api.anthropic.com';
  }

  /// `metadata.user_id`: for Anthropic's own API the machine, the account
  /// and the session; for others the session alone.
  String? get metadataUserId {
    final id = userId;
    if (id == null || !firstParty) return id;
    try {
      final session = jsonDecode(id);
      if (session is Map) {
        return jsonEncode({
          'device_id': deviceId ?? '',
          'account_uuid': '',
          'session_id': session['session_id'],
        });
      }
    } on FormatException {
      // As it is.
    }
    return id;
  }

  Uri endpoint(String path) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    // A base that already names the version (`…/v1`) is taken as it is.
    if (base.endsWith('/v1') && path.startsWith('/v1/')) {
      path = path.substring(3);
    }
    return Uri.parse('$base$path');
  }
}

/// The Messages API over HTTPS: streamed answers, retried as the API asks
/// (rate limits, overload, a dropped connection).
class AnthropicClient implements ModelClient {
  AnthropicClient(this.config, {HttpClient Function()? httpClient})
    : _newClient = httpClient ?? HttpClient.new;

  final ApiConfig config;
  final HttpClient Function() _newClient;

  static const apiVersion = '2023-06-01';

  @override
  bool get firstParty => config.firstParty;

  HttpClient _client() {
    final client = _newClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 15);
    if (config.environment.isNotEmpty) {
      client.findProxy = (uri) => HttpClient.findProxyFromEnvironment(
        uri,
        environment: _proxyEnvironment(config.environment),
      );
    }
    return client;
  }

  /// The proxy variables, in either case.
  static Map<String, String> _proxyEnvironment(Map<String, String> env) => {
    for (final name in const ['http_proxy', 'https_proxy', 'no_proxy'])
      if (env[name] ?? env[name.toUpperCase()] case final value?
          when value.isNotEmpty)
        name: value,
  };

  Map<String, String> _headers({List<String> betas = const []}) => {
    'content-type': 'application/json',
    'anthropic-version': apiVersion,
    'user-agent': config.userAgent,
    if (config.apiKey case final key? when key.isNotEmpty) 'x-api-key': key,
    if (config.authToken case final token? when token.isNotEmpty)
      'authorization': 'Bearer $token',
    if (betas.isNotEmpty) 'anthropic-beta': betas.join(','),
    ...config.headers,
  };

  @override
  Stream<Map<String, Object?>> stream(
    ModelRequest request, {
    CancelToken? cancel,
    void Function(RetryInfo info)? onRetry,
  }) async* {
    cancel ??= CancelToken();
    var attempt = 0;
    var started = false;
    while (true) {
      cancel.check();
      try {
        await for (final event in _once(request, cancel)) {
          if (!started) started = true;
          yield event;
        }
        return;
      } on Cancelled {
        rethrow;
      } on ApiError catch (error) {
        if (!error.retryable || attempt >= config.maxRetries) rethrow;
        attempt++;
        final delay = _delay(attempt, error.retryAfter);
        onRetry?.call(
          RetryInfo(
            attempt: attempt,
            maxRetries: config.maxRetries,
            delay: delay,
            status: error.status,
            message: error.message,
          ),
        );
        await cancel.guard(Future<void>.delayed(delay));
        if (started) {
          started = false;
          yield const {'type': 'stream_restart'};
        }
      }
    }
  }

  /// How long to wait before attempt [attempt]: what the API said, else
  /// doubling from half a second up to half a minute, with some jitter.
  static Duration _delay(int attempt, Duration? retryAfter) {
    if (retryAfter != null && retryAfter <= const Duration(minutes: 5)) {
      return retryAfter;
    }
    final base = 500 * math.pow(2, attempt - 1);
    final capped = math.min(base, 32000).toInt();
    final jitter = math.Random().nextInt(math.max(1, capped ~/ 4));
    return Duration(milliseconds: capped + jitter);
  }

  Stream<Map<String, Object?>> _once(
    ModelRequest request,
    CancelToken cancel,
  ) async* {
    final client = _client();
    HttpClientRequest? http;
    final aborted = cancel.whenCancelled.then((_) {
      http?.abort(const Cancelled());
      client.close(force: true);
    });
    try {
      final HttpClientResponse response;
      try {
        final endpoint = config.endpoint('/v1/messages');
        http = await client.postUrl(
          config.firstParty
              ? endpoint.replace(queryParameters: {'beta': 'true'})
              : endpoint,
        );
        _headers(betas: request.betas).forEach(http.headers.set);
        http.add(utf8.encode(jsonEncode(_body(request.body))));
        response = await http.close();
      } on Cancelled {
        rethrow;
      } on Object catch (error) {
        if (cancel.isCancelled) throw Cancelled(cancel.reason);
        throw ApiError(
          'Could not reach ${config.endpoint('/v1/messages').host}: $error',
          retryable: true,
        );
      }
      final requestId = response.headers.value('request-id');
      if (response.statusCode != 200) {
        final body = await _readBody(response);
        throw _error(response.statusCode, body, response.headers, requestId);
      }
      final events = response
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const SseDecoder())
          .timeout(
            config.idleTimeout,
            onTimeout: (sink) => sink.addError(
              const ApiError(
                'The answer stopped coming: no data for too long',
                retryable: true,
              ),
            ),
          );
      try {
        await for (final event in events) {
          final json = event.json;
          if (json == null) continue;
          final type = json['type'] ?? event.event;
          if (type == 'ping') continue;
          if (type == 'error') {
            final error = json['error'];
            final kind = error is Map ? '${error['type']}' : 'error';
            final message = error is Map ? '${error['message']}' : '$error';
            throw ApiError(
              message,
              type: kind,
              retryable: _retryableType(kind),
              requestId: requestId,
            );
          }
          if (type == 'message_start' && requestId != null) {
            final message = json['message'];
            if (message is Map) {
              yield {
                ...json,
                'message': {...message, '_request_id': requestId},
              };
              continue;
            }
          }
          yield json;
          if (type == 'message_stop') return;
        }
      } on ApiError {
        rethrow;
      } on Cancelled {
        rethrow;
      } on Object catch (error) {
        if (cancel.isCancelled) throw Cancelled(cancel.reason);
        throw ApiError('The connection broke: $error', retryable: true);
      }
      // Ended without `message_stop`: cut off.
      if (cancel.isCancelled) throw Cancelled(cancel.reason);
      throw const ApiError('The answer ended early', retryable: true);
    } finally {
      unawaited(aborted);
      client.close(force: true);
    }
  }

  /// [body] as sent: the conversation, the system prompt and the tools
  /// first, then who asks, then the rest.
  Map<String, Object?> _body(Map<String, Object?> body) {
    final out = <String, Object?>{
      for (final key in const ['model', 'messages', 'system', 'tools'])
        if (body.containsKey(key)) key: body[key],
      if (config.metadataUserId case final id?) 'metadata': {'user_id': id},
    };
    for (final MapEntry(:key, :value) in body.entries) {
      out.putIfAbsent(key, () => value);
    }
    out['stream'] = true;
    return out;
  }

  static bool _retryableType(String type) =>
      type == 'overloaded_error' ||
      type == 'api_error' ||
      type == 'rate_limit_error' ||
      type == 'timeout_error';

  static Future<String> _readBody(HttpClientResponse response) async {
    try {
      return await response
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 30));
    } on Object {
      return '';
    }
  }

  static ApiError _error(
    int status,
    String body,
    HttpHeaders headers,
    String? requestId,
  ) {
    String message = body.trim();
    String? type;
    try {
      final json = jsonDecode(body);
      if (json is Map && json['error'] is Map) {
        final error = json['error'] as Map;
        message = '${error['message'] ?? message}';
        type = error['type'] as String?;
      }
    } on FormatException {
      // Not JSON: the text as it came (a gateway's page, say).
    }
    if (message.isEmpty) message = 'HTTP $status';
    if (message.length > 2000) message = '${message.substring(0, 2000)}…';
    final retryAfter = switch (int.tryParse(
      headers.value('retry-after-ms') ?? '',
    )) {
      final ms? => Duration(milliseconds: ms),
      null => switch (int.tryParse(headers.value('retry-after') ?? '')) {
        final seconds? => Duration(seconds: seconds),
        null => null,
      },
    };
    final shouldRetry = headers.value('x-should-retry');
    final retryable = switch (shouldRetry) {
      'true' => true,
      'false' => false,
      _ =>
        status == 408 ||
            status == 409 ||
            status == 429 ||
            status >= 500 ||
            (type != null && _retryableType(type)),
    };
    return ApiError(
      message,
      status: status,
      type: type,
      retryable: retryable,
      retryAfter: retryAfter,
      requestId: requestId,
    );
  }

  @override
  Future<List<Map<String, Object?>>?> models() async {
    final client = _client();
    try {
      final models = <Map<String, Object?>>[];
      String? after;
      for (var page = 0; page < 5; page++) {
        final uri = config
            .endpoint('/v1/models')
            .replace(queryParameters: {'limit': '100', 'after_id': ?after});
        final request = await client.getUrl(uri);
        _headers().forEach(request.headers.set);
        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );
        if (response.statusCode != 200) {
          await response.drain<void>();
          return models.isEmpty ? null : models;
        }
        final json = jsonDecode(await _readBody(response));
        if (json is! Map) break;
        for (final model in json['data'] as List? ?? const []) {
          if (model is Map) models.add(model.cast<String, Object?>());
        }
        if (json['has_more'] != true) break;
        after = json['last_id'] as String?;
        if (after == null) break;
      }
      return models;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

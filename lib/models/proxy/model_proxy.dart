import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../launch_environment.dart';
import '../model_provider.dart';
import '../upstream.dart';
import 'translate/openai_chat_request.dart';
import 'translate/openai_chat_response.dart';
import 'translate/responses_request.dart';
import 'translate/responses_response.dart';
import 'translate/thinking.dart';

/// Anthropic's Messages API on this machine, in front of the upstreams
/// that speak OpenAI's: Claude Code is pointed at it
/// (`ANTHROPIC_BASE_URL`), and each request is translated for the
/// upstream, and its answer back, as it streams (see translate/).
///
/// Listens on 127.0.0.1 only, on a port of the system's choosing, and
/// answers only a request with its [token] (Claude Code's
/// `ANTHROPIC_AUTH_TOKEN`), made anew each run. The providers' keys stay
/// here: read as each request goes out, so a key changed applies at once.
///
/// `/p/<provider>/v1/messages` and `/p/<provider>/v1/messages/count_tokens`
/// (an estimate: the upstreams have none).
class ModelProxy {
  ModelProxy({
    required this._provider,
    required this._key,
    this._onError,
    this._findProxy,
    @visibleForTesting String? token,
  }) : token = token ?? _newToken();

  final ModelProvider? Function(String id) _provider;
  final Future<String?> Function(String id) _key;
  final void Function(String id, String? error)? _onError;

  /// The HTTP proxy to reach the upstreams through, a connection each
  /// (the app's `NetworkProxy`); straight to them without one.
  final String Function(Uri url)? _findProxy;

  /// What a request must carry, as a bearer token or `x-api-key`.
  final String token;

  static String _newToken() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 32; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  Future<HttpServer>? _server;
  HttpClient? _client;

  /// Where [providerId]'s requests go, the proxy started if not yet.
  Future<ProxyEndpoint> endpoint(String providerId) async {
    final server = await (_server ??= _bind());
    return (
      baseUrl:
          'http://127.0.0.1:${server.port}/p/${Uri.encodeComponent(providerId)}',
      token: token,
    );
  }

  Future<HttpServer> _bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => unawaited(_handle(request)));
    return server;
  }

  Future<HttpClient> _upstream() async {
    if (_client case final client?) return client;
    return _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 30)
      ..findProxy = _findProxy ?? (_) => 'DIRECT';
  }

  Future<void> close() async {
    final server = await _server;
    _server = null;
    await server?.close(force: true);
    _client?.close(force: true);
    _client = null;
  }

  // --- A request -----------------------------------------------------------

  bool _authorized(HttpRequest request) {
    final bearer = request.headers.value(HttpHeaders.authorizationHeader);
    final given = switch (bearer) {
      final value? when value.startsWith('Bearer ') => value.substring(7),
      _ => request.headers.value('x-api-key'),
    };
    return given != null && _same(given.trim(), token);
  }

  /// In time that does not say how much of it matched.
  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (!_authorized(request)) {
        return await _fail(response, 401, 'Not this proxy\'s token');
      }
      final segments = request.uri.pathSegments;
      if (request.method != 'POST' ||
          segments.length < 4 ||
          segments[0] != 'p' ||
          segments[2] != 'v1' ||
          segments[3] != 'messages') {
        return await _fail(
          response,
          404,
          'No such endpoint: ${request.uri.path}',
        );
      }
      final providerId = segments[1];
      final body = jsonDecode(await utf8.decodeStream(request));
      if (body is! Map<String, Object?>) {
        return await _fail(response, 400, 'The request is not a JSON object');
      }
      if (segments.length == 5 && segments[4] == 'count_tokens') {
        return await _json(response, 200, {
          'input_tokens': estimateInputTokens(body),
        });
      }
      if (segments.length != 4) {
        return await _fail(
          response,
          404,
          'No such endpoint: ${request.uri.path}',
        );
      }
      final provider = _provider(providerId);
      if (provider == null || !provider.protocol.proxied) {
        return await _fail(response, 404, 'No such provider: $providerId');
      }
      await _forward(provider, body, response);
    } on FormatException catch (error) {
      await _fail(response, 400, 'The request is not JSON: ${error.message}');
    } on Object catch (error) {
      debugPrint('Model proxy: $error');
      await _fail(response, 502, '$error');
    }
  }

  Future<void> _forward(
    ModelProvider provider,
    Map<String, Object?> body,
    HttpResponse response,
  ) async {
    final requested = parseSuffix('${body['model'] ?? ''}');
    final modelId = requested.modelName.trim();
    // The effort picked goes with the model's name: none, or `none`, and
    // reasoning is not asked for.
    final effort = requested.hasSuffix ? requested.rawSuffix.trim() : '';
    final thinking = effort.isNotEmpty && effort != ThinkingLevel.none;
    final stream = body['stream'] == true;
    final url = UpstreamUrls.conversation(provider);
    if (url == null) {
      return _fail(response, 400, '${provider.name} has no valid base URL');
    }
    final Map<String, Object?> outgoing;
    if (provider.protocol == ProviderProtocol.openaiChat) {
      outgoing = convertClaudeRequestToOpenAI(
        modelId,
        body,
        stream,
        preserveThinking: provider.preserveThinking,
      );
      if (thinking) {
        outgoing['reasoning_effort'] = effort;
      } else {
        outgoing.remove('reasoning_effort');
      }
      if (stream) outgoing['stream_options'] = {'include_usage': true};
    } else {
      outgoing = convertClaudeRequestToResponses(
        modelId,
        body,
        reasoning: thinking,
      );
      if (thinking) outgoing['reasoning'] = {'effort': effort};
    }
    if (provider.promptCacheKey) {
      if (promptCacheKey(body) case final key?) {
        outgoing['prompt_cache_key'] = key;
      }
    }

    final client = await _upstream();
    final upstreamRequest = await client.postUrl(url);
    final key = await _key(provider.id);
    upstreamHeaders(provider, key).forEach(upstreamRequest.headers.set);
    upstreamRequest.headers
      ..contentType = ContentType.json
      ..set(
        HttpHeaders.acceptHeader,
        stream || provider.protocol == ProviderProtocol.openaiResponses
            ? 'text/event-stream'
            : 'application/json',
      );
    upstreamRequest.add(utf8.encode(jsonEncode(outgoing)));
    // The client gone: so is the upstream's request.
    unawaited(
      response.done.then<void>((_) {}, onError: (_) => upstreamRequest.abort()),
    );
    final upstream = await upstreamRequest.close();
    if (upstream.statusCode >= 400) {
      final text = await utf8.decodeStream(upstream);
      final message = upstreamErrorMessage(upstream.statusCode, text);
      _onError?.call(provider.id, message);
      return _json(
        response,
        upstream.statusCode,
        anthropicError(upstream.statusCode, message),
      );
    }
    _onError?.call(provider.id, null);
    final lines = upstream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());

    if (provider.protocol == ProviderProtocol.openaiChat) {
      if (!stream) {
        final text = await utf8.decodeStream(upstream);
        return _json(
          response,
          200,
          convertOpenAIResponseToClaudeNonStream(body, text),
        );
      }
      _startEvents(response);
      final translator = OpenAIChatResponseTranslator(body);
      var done = false;
      await for (final line in lines) {
        if (line.trim() == 'data: [DONE]') done = true;
        for (final frame in translator.convert(line)) {
          response.write(frame);
        }
        await response.flush();
      }
      if (!done) translator.convert('data: [DONE]').forEach(response.write);
      return response.close();
    }

    // Responses: the upstream streams either way.
    if (!stream) {
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final message = convertResponsesResponseToClaudeNonStream(
          body,
          line.substring(5).trim(),
        );
        if (message != null) return _json(response, 200, message);
      }
      return _fail(response, 502, '${provider.name} ended without a reply');
    }
    _startEvents(response);
    final translator = ResponsesResponseTranslator(body);
    await for (final line in lines) {
      final events = translator.convert(line);
      if (events.isEmpty) continue;
      response.write(events);
      await response.flush();
    }
    return response.close();
  }

  static void _startEvents(HttpResponse response) {
    response
      ..statusCode = 200
      ..bufferOutput = false
      ..headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  }

  static Future<void> _json(
    HttpResponse response,
    int status,
    Object? body,
  ) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await response.close();
  }

  static Future<void> _fail(
    HttpResponse response,
    int status,
    String message,
  ) async {
    try {
      await _json(response, status, anthropicError(status, message));
    } on Object {
      // Already answered, or the client gone.
      await response.close().catchError((_) {});
    }
  }
}

/// About how many tokens [request]'s input comes to: a quarter of its
/// text, as no upstream counts them.
int estimateInputTokens(Map<String, Object?> request) {
  final text = jsonEncode({
    'system': request['system'],
    'messages': request['messages'],
    'tools': request['tools'],
  });
  return (utf8.encode(text).length / 4).ceil();
}

/// The `prompt_cache_key` of [request]'s conversation: Claude Code's
/// session (in `metadata.user_id`, as JSON, or as the older
/// `…_session_<id>`), hashed, so the upstream is not told it. Null without
/// one.
String? promptCacheKey(Map<String, Object?> request) {
  final userId = switch (request['metadata']) {
    {'user_id': final String id} => id.trim(),
    _ => '',
  };
  if (userId.isEmpty) return null;
  var session = '';
  try {
    if (jsonDecode(userId) case {'session_id': final String id}) {
      session = id.trim();
    }
  } on FormatException {
    final legacy = userId.lastIndexOf('_session_');
    if (legacy >= 0) session = userId.substring(legacy + 9).trim();
  }
  if (session.isEmpty) return null;
  final digest = sha256.convert(utf8.encode('baocode:$session'));
  return 'baocode-${'$digest'.substring(0, 32)}';
}

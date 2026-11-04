import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../bao_agent.dart';

import 'fake_model.dart';

/// What the server does with a request instead of answering it.
sealed class Trouble {
  const Trouble();
}

/// Answers with [status] and the API's error body.
class HttpTrouble extends Trouble {
  const HttpTrouble(
    this.status, {
    this.type = 'api_error',
    this.message = 'trouble',
    this.headers = const {},
  });

  final int status;
  final String type;
  final String message;
  final Map<String, String> headers;
}

/// Starts the answer, then sends an `error` event.
class StreamTrouble extends Trouble {
  const StreamTrouble(this.type);

  final String type;
}

/// Starts the answer, then ends it before its end.
class Cut extends Trouble {
  const Cut();
}

/// The Messages API on this machine: a [FakeModel]'s script answered over
/// HTTP, streamed as server-sent events, as `api.anthropic.com` would.
class FakeApi {
  FakeApi._(this._server, this.model);

  static Future<FakeApi> start({
    List<Reply>? script,
    Responder? errands,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = FakeApi._(server, FakeModel(script, errands));
    server.listen(api._handle);
    return api;
  }

  final HttpServer _server;

  /// Picks the reply to each request, as under the engine's own tests.
  final FakeModel model;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  /// Each request's headers, in order.
  final List<Map<String, String>> headers = [];

  /// What to do with the next requests, before answering them.
  final List<Trouble> troubles = [];

  /// The models `GET /v1/models` lists.
  List<Map<String, Object?>> models = [
    {
      'id': 'claude-opus-5-5',
      'display_name': 'Claude Opus 5.5',
      'type': 'model',
    },
  ];

  int _messages = 0;

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      headers.add({
        for (final name in const [
          'x-api-key',
          'authorization',
          'anthropic-version',
          'anthropic-beta',
          'user-agent',
          'x-custom',
          'x-claude-code-request-class',
          'x-claude-code-agent-id',
          'x-claude-code-agent-type',
        ])
          name: ?request.headers.value(name),
      });
      if (request.method == 'GET' && request.uri.path.endsWith('/v1/models')) {
        final after = request.uri.queryParameters['after_id'];
        final start = after == null
            ? 0
            : models.indexWhere((m) => m['id'] == after) + 1;
        final page = models.skip(start).take(1).toList();
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'data': page,
            'has_more': start + 1 < models.length,
            'last_id': page.isEmpty ? null : page.last['id'],
          }),
        );
        return;
      }
      if (request.method != 'POST' ||
          !request.uri.path.endsWith('/v1/messages')) {
        response.statusCode = 404;
        return;
      }
      final body = (jsonDecode(await utf8.decodeStream(request)) as Map)
          .cast<String, Object?>();
      final id = 'msg_api_${++_messages}';
      response.headers.set('request-id', 'req_$_messages');
      if (troubles.isNotEmpty) {
        switch (troubles.removeAt(0)) {
          case HttpTrouble(
            :final status,
            :final type,
            :final message,
            headers: final extra,
          ):
            response.statusCode = status;
            extra.forEach(response.headers.set);
            response.headers.contentType = ContentType.json;
            response.write(
              jsonEncode({
                'type': 'error',
                'error': {'type': type, 'message': message},
              }),
            );
            return;
          case StreamTrouble(:final type):
            _sse(response);
            _event(
              response,
              replyEvents(
                Reply.text(''),
                id: id,
                model: '${body['model']}',
              ).first,
            );
            _event(response, {
              'type': 'error',
              'error': {'type': type, 'message': 'Overloaded'},
            });
            return;
          case Cut():
            _sse(response);
            _event(
              response,
              replyEvents(
                Reply.text(''),
                id: id,
                model: '${body['model']}',
              ).first,
            );
            return;
        }
      }
      final events = <Map<String, Object?>>[];
      try {
        await for (final event in model.stream(ModelRequest(body))) {
          events.add(event);
        }
      } on ApiError catch (error) {
        response.statusCode = error.status ?? 500;
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'type': 'error',
            'error': {
              'type': error.type ?? 'api_error',
              'message': error.message,
            },
          }),
        );
        return;
      }
      _sse(response);
      response.write(': a comment\n\n');
      _event(response, {'type': 'ping'});
      for (final event in events) {
        _event(response, event);
      }
    } finally {
      try {
        await response.close();
      } on Object {
        // Dropped on purpose.
      }
    }
  }

  static void _sse(HttpResponse response) {
    response.headers.contentType = ContentType('text', 'event-stream');
  }

  static void _event(HttpResponse response, Map<String, Object?> event) {
    response.write('event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n');
  }

  Future<void> close() => _server.close(force: true);
}

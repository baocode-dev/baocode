import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model_provider.dart';
import 'codex_service.dart';

/// Binds this machine's loopback, IPv4 and IPv6, at [port]: none when
/// another program has it (the browser lands there all the same, and its
/// address is pasted).
Future<List<HttpServer>> bindLoopback(int port) async {
  final servers = <HttpServer>[];
  try {
    servers.add(await HttpServer.bind(InternetAddress.loopbackIPv4, port));
    // `localhost` may be ::1 first.
    try {
      servers.add(
        await HttpServer.bind(InternetAddress.loopbackIPv6, port, v6Only: true),
      );
    } on SocketException {
      // No IPv6 here.
    }
  } on SocketException {
    // Taken.
  }
  return servers;
}

/// A sign-in waiting for the browser to come back to this machine.
class LoopbackLogin implements CodexLogin {
  /// Waits on [servers] for the browser at [path], with [state]; the code
  /// it brings is given to [exchange] for the account.
  LoopbackLogin(
    this.url,
    this._servers,
    this._state,
    Duration timeout, {
    required this.path,
    required Future<ProviderAccount> Function(String code) exchange,
  }) {
    _result = _code.future.then(exchange);
    for (final server in _servers) {
      server.listen((request) => unawaited(_handle(request)));
    }
    _timer = Timer(timeout, () {
      _finish(const CodexException('Sign-in took too long.'));
    });
  }

  @override
  final Uri url;
  final List<HttpServer> _servers;
  final String _state;
  final Completer<String> _code = Completer();
  late final Timer _timer;
  late final Future<ProviderAccount> _result;

  /// Where the browser comes back to.
  final String path;

  @override
  Future<ProviderAccount> get result => _result;

  @override
  bool get listening => _servers.isNotEmpty;

  @override
  void submit(String callback) {
    final uri = Uri.tryParse(callback.trim());
    final query = uri?.queryParameters ?? const {};
    if (uri == null || !query.containsKey('state')) {
      throw const CodexException(
        'That is not the address sign-in came back to: it has no state.',
      );
    }
    if (query['state'] != _state) {
      throw const CodexException(
        'That address is of another sign-in: start again.',
      );
    }
    final code = query['code'];
    if (code == null || code.isEmpty) {
      final reason =
          query['error_description'] ?? query['error'] ?? 'No code was given.';
      _finish(CodexException('Sign-in failed: $reason'));
      return;
    }
    _finish(code);
  }

  @override
  void cancel() => _finish(const CodexCancelled());

  void _finish(Object outcome) {
    _timer.cancel();
    if (!_code.isCompleted) {
      if (outcome is String) {
        _code.complete(outcome);
      } else {
        _code.completeError(outcome);
      }
    }
    // After the page is answered.
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      for (final server in _servers) {
        unawaited(server.close(force: true));
      }
    });
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.uri.path != path) {
      response.statusCode = HttpStatus.notFound;
      return response.close();
    }
    final query = request.uri.queryParameters;
    final error = query['error'];
    final code = query['code'];
    final String page;
    if (query['state'] != _state) {
      response.statusCode = HttpStatus.badRequest;
      page = _page('Sign-in did not match', 'Start it again from BaoCode.');
    } else if (error != null || code == null || code.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      final reason =
          query['error_description'] ?? error ?? 'No code was given.';
      page = _page('Sign-in failed', reason);
      _finish(CodexException('Sign-in failed: $reason'));
    } else {
      page = _page(
        'Signed in',
        'You can close this page and go back to BaoCode.',
      );
      _finish(code);
    }
    response.headers.contentType = ContentType.html;
    response.write(page);
    await response.close();
  }

  static String _page(String title, String detail) {
    const escape = HtmlEscape();
    return '<!doctype html><meta charset="utf-8"><title>BaoCode</title>'
        '<body style="font-family:system-ui;text-align:center;margin-top:20vh">'
        '<h2>${escape.convert(title)}</h2><p>${escape.convert(detail)}</p>';
  }
}

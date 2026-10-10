import 'dart:convert';
import 'dart:io';

import '../network/network_proxy_io.dart';
import 'codex/codex_accounts_io.dart';
import 'codex/codex_api.dart';
import 'model_provider.dart';
import 'model_test.dart';
import 'model_test_stream.dart';
import 'upstream.dart';

/// Native streaming transport, independent of chat sessions and their proxy
/// translators (which may synthesize completion on an interrupted stream).
Future<void> runModelTest(
  ModelProvider provider,
  ProviderModel model,
  String prompt,
  ModelTestCancellation cancellation,
  void Function(ModelTestEvent) emit, {
  required Future<String?> Function(String providerId) keyOf,
  required CodexAccounts codex,
}) async {
  HttpClient? client;
  String? credential;
  try {
    final route = await NetworkProxy.instance.resolve();
    if (cancellation.cancelled) return;
    final http = client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..findProxy = route.findProxy;
    // Force-closing this run's client interrupts DNS/connect, headers and body;
    // cancelling one model never closes another model's connection.
    cancellation.whenCancelled.then((_) => http.close(force: true));
    final body = modelTestRequest(provider, model, prompt);
    Uri? url;
    Map<String, String> headers;
    ProviderAccount? account;
    if (provider.protocol == ProviderProtocol.codex) {
      account = codex.pick(provider);
      if (account == null) {
        throw const HttpException('No available ChatGPT account');
      }
      credential = await codex.accessToken(provider, account);
      prepareCodexRequest(body);
      url = codex.endpoints.responses;
      headers = codexHeaders(
        credential,
        accountId: account.accountId,
        events: true,
        version: codexVersionOf(provider),
      );
    } else {
      credential = await keyOf(provider.id);
      headers = upstreamHeaders(provider, credential);
      url = provider.protocol == ProviderProtocol.anthropic
          ? switch (UpstreamUrls.anthropicBase(provider.baseUrl)) {
              final base? => Uri.parse('$base/v1/messages'),
              null => null,
            }
          : UpstreamUrls.conversation(provider);
    }
    if (cancellation.cancelled) return;
    if (url == null) throw const HttpException('Invalid HTTP(S) base URL');
    final request = await http.postUrl(url);
    if (cancellation.cancelled) {
      request.abort();
      return;
    }
    headers.forEach(request.headers.set);
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'text/event-stream');
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    if (account != null) {
      codex.record(provider, account, response.headers.value);
    }
    if (response.statusCode >= 400) {
      // Error bodies are untrusted and may be arbitrarily large.
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk.take(8192 - bytes.length));
        if (bytes.length >= 8192) break;
      }
      throw HttpException(
        upstreamErrorMessage(
          response.statusCode,
          utf8.decode(bytes, allowMalformed: true),
        ),
      );
    }
    final parser = ModelTestStreamParser(provider.protocol);
    await for (final line
        in response
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())) {
      if (cancellation.cancelled) return;
      final event = parser.addLine(line);
      if (event != null) emit(event);
      if (parser.done) return;
    }
    final tail = parser.finish();
    if (tail != null) emit(tail);
  } on Object catch (error) {
    if (cancellation.cancelled) return;
    // Gateways occasionally echo submitted headers in errors. Those must not
    // enter the session result or a widget tooltip.
    var message = '$error';
    if (credential != null && credential.isNotEmpty) {
      message = message.replaceAll(credential, '[redacted]');
    }
    throw HttpException(message);
  } finally {
    client?.close(force: true);
  }
}

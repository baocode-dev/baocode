import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../network/network_proxy_io.dart';
import '../network/tls.dart';
import 'antigravity/antigravity_accounts_io.dart';
import 'codex/codex_accounts_io.dart';
import 'image_api.dart';
import 'model_provider.dart';
import 'model_runtime.dart' show UpstreamException;
import 'upstream.dart';

/// Asks image models for pictures (see image_api.dart): by the Images API,
/// a conversation's `modalities`, a ChatGPT account (Codex's), or an
/// Antigravity Google account.
class ImageGenerator {
  ImageGenerator({
    required this.codex,
    required this.antigravity,
    required this.key,
  });

  final CodexAccounts codex;
  final AntigravityAccounts antigravity;

  /// A provider's key, by its id.
  final Future<String?> Function(String providerId) key;

  /// How long a picture may take: GPT Image's take a minute or two.
  static const timeout = Duration(minutes: 5);

  /// Past this a picture linked to is not fetched.
  static const _maxBytes = 64 << 20;

  /// [request]'s pictures by [model] of [provider], each as its bytes.
  /// Throws [UpstreamException].
  Future<List<GeneratedImage>> generate(
    ModelProvider provider,
    ProviderModel model,
    ImageRequest request, {
    String? session,
  }) async {
    final route = await NetworkProxy.instance.resolve();
    final client = HttpClient(context: await upstreamSecurityContext())
      ..connectionTimeout = const Duration(seconds: 30)
      ..findProxy = route.findProxy;
    try {
      final speaking = provider.speakingFor(model.id);
      final images = switch ((speaking.protocol, model.kind)) {
        (ProviderProtocol.codex, _) => await _codex(
          speaking,
          model,
          request,
          session,
        ),
        (ProviderProtocol.antigravity, _) => await _antigravity(
          speaking,
          model,
          request,
          session,
        ),
        (ProviderProtocol.gemini, _) => await _gemini(
          client,
          speaking,
          model,
          request,
        ),
        (_, ModelKind.imageChat) => await _chat(
          client,
          speaking,
          model,
          request,
        ),
        _ => await _images(client, speaking, model, request),
      };
      return [for (final image in images) await _fetched(client, image)];
    } on SocketException catch (error) {
      throw UpstreamException('Could not connect: ${error.message}');
    } on HandshakeException catch (error) {
      throw UpstreamException('TLS failed: ${handshakeFailure(error)}');
    } on TimeoutException {
      throw const UpstreamException('No answer in time.');
    } on HttpException catch (error) {
      throw UpstreamException(error.message);
    } finally {
      client.close(force: true);
    }
  }

  /// By the Images API: a generation, or with pictures an edit (in the
  /// generation's body, where the upstream takes them so).
  Future<List<GeneratedImage>> _images(
    HttpClient client,
    ModelProvider provider,
    ProviderModel model,
    ImageRequest request,
  ) async {
    final base = imagesBase(provider);
    if (base == null) {
      throw const UpstreamException('The base URL is not an http(s) URL.');
    }
    final inBody = referencesInBody(Uri.parse(base).host);
    final Uri url;
    final List<int> body;
    final ContentType type;
    if (request.references.isEmpty || inBody) {
      url = Uri.parse('$base/images/generations');
      body = utf8.encode(
        jsonEncode(
          imageGenerationBody(model.id, request, referencesInBody: inBody),
        ),
      );
      type = ContentType.json;
    } else {
      url = Uri.parse('$base/images/edits');
      final form = _editForm(model.id, request);
      body = form.body;
      type = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': form.boundary},
      );
    }
    final text = await _post(client, provider, model, url, body, type);
    return parseImagesResponse(_decode(text, url));
  }

  /// In a conversation that answers with pictures.
  Future<List<GeneratedImage>> _chat(
    HttpClient client,
    ModelProvider provider,
    ProviderModel model,
    ImageRequest request,
  ) async {
    final base = imagesBase(provider);
    if (base == null) {
      throw const UpstreamException('The base URL is not an http(s) URL.');
    }
    final url = Uri.parse('$base/chat/completions');
    final text = await _post(
      client,
      provider,
      model,
      url,
      utf8.encode(jsonEncode(chatImageBody(model.id, request))),
      ContentType.json,
    );
    return parseChatImages(_decode(text, url));
  }

  /// As a ChatGPT account, as the Codex CLI does: its Images API; where
  /// the backend has none, the Responses API's `image_generation` tool, by
  /// one of the provider's conversation models.
  Future<List<GeneratedImage>> _codex(
    ModelProvider provider,
    ProviderModel model,
    ImageRequest request,
    String? session,
  ) async {
    final endpoints = codex.endpoints;
    final edit = request.references.isNotEmpty;
    final url = edit ? endpoints.imageEdits : endpoints.imageGenerations;
    final List<int> body;
    final ContentType type;
    if (edit) {
      final form = _editForm(model.id, request);
      body = form.body;
      type = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': form.boundary},
      );
    } else {
      body = utf8.encode(jsonEncode(imageGenerationBody(model.id, request)));
      type = ContentType.json;
    }
    final (status, text) = await codex.post(
      provider,
      url,
      body,
      contentType: type,
      session: session,
      timeout: timeout,
    );
    if (status < 400) return parseImagesResponse(_decode(text, url));
    if (status != 404 && status != 405) {
      throw UpstreamException(
        '${upstreamErrorMessage(status, text)} (POST $url)',
      );
    }
    final chat = switch (provider.roles.main) {
      final main? when provider.model(main) != null => main,
      _ => provider.enabledModels.firstOrNull?.id,
    };
    if (chat == null) {
      throw UpstreamException(
        '${upstreamErrorMessage(status, text)} (POST $url); no conversation '
        'model of ${provider.name} to make it with instead.',
      );
    }
    final responses = endpoints.responses;
    final (answered, events) = await codex.post(
      provider,
      responses,
      utf8.encode(jsonEncode(responsesImageBody(chat, request))),
      contentType: ContentType.json,
      session: session,
      events: true,
      timeout: timeout,
    );
    if (answered >= 400) {
      throw UpstreamException(
        '${upstreamErrorMessage(answered, events)} (POST $responses)',
      );
    }
    return parseResponsesImages(events);
  }

  /// As an Antigravity Google account, through Code Assist's
  /// `streamGenerateContent` with `requestType: image_gen`. Gemini image
  /// models draw one picture per call, so `count > 1` asks once per needed
  /// picture.
  Future<List<GeneratedImage>> _antigravity(
    ModelProvider provider,
    ProviderModel model,
    ImageRequest request,
    String? session,
  ) async {
    final body = antigravityImageRequest(request);
    final want = request.count < 1 ? 1 : request.count;
    final out = <GeneratedImage>[];
    for (var i = 0; i < want && out.length < want; i++) {
      final (status, events) = await antigravity.postImage(
        provider,
        model.id,
        body,
        session: session,
        timeout: timeout,
      );
      if (status >= 400) {
        throw UpstreamException(
          '${upstreamErrorMessage(status, events)} '
          '(POST ${antigravity.endpoints.stream})',
        );
      }
      out.addAll(parseAntigravityImages(events));
    }
    return out.length > want ? out.sublist(0, want) : out;
  }

  /// Through Gemini's `generateContent` endpoint with an API key.
  Future<List<GeneratedImage>> _gemini(
    HttpClient client,
    ModelProvider provider,
    ProviderModel model,
    ImageRequest request,
  ) async {
    final url = UpstreamUrls.geminiEndpoint(
      provider,
      model: model.id,
      stream: false,
    );
    if (url == null) {
      throw const UpstreamException('The base URL is not an http(s) URL.');
    }
    final payload = utf8.encode(jsonEncode(antigravityImageRequest(request)));
    final want = request.count < 1 ? 1 : request.count;
    final out = <GeneratedImage>[];
    for (var i = 0; i < want && out.length < want; i++) {
      final text = await _post(
        client,
        provider,
        model,
        url,
        payload,
        ContentType.json,
      );
      out.addAll(parseAntigravityImages(text));
    }
    return out.length > want ? out.sublist(0, want) : out;
  }

  ({Uint8List body, String boundary}) _editForm(
    String model,
    ImageRequest request,
  ) {
    final field = imageEditField(model);
    return multipartForm(imageEditFields(model, request), [
      // One picture where the model takes one.
      for (final image
          in field == 'image' ? request.references.take(1) : request.references)
        (field, image),
    ]);
  }

  /// POSTs [body] to [url] of [provider] with its key and headers: the
  /// text answered. Throws [UpstreamException] for an error.
  Future<String> _post(
    HttpClient client,
    ModelProvider provider,
    ProviderModel model,
    Uri url,
    List<int> body,
    ContentType type,
  ) async {
    final request = await client.postUrl(url);
    upstreamHeaders(
      provider,
      await key(provider.id),
    ).forEach(request.headers.set);
    customUpstreamHeaders(
      provider,
      model: model.id,
    ).forEach(request.headers.set);
    request.headers
      ..contentType = type
      ..set(HttpHeaders.acceptHeader, 'application/json');
    request.add(body);
    final response = await request.close().timeout(timeout);
    final text = await utf8.decodeStream(response).timeout(timeout);
    if (response.statusCode >= 400) {
      throw UpstreamException(
        '${upstreamErrorMessage(response.statusCode, text)} (POST $url)',
      );
    }
    return text;
  }

  /// [image] with its bytes: fetched, where it is a link.
  Future<GeneratedImage> _fetched(
    HttpClient client,
    GeneratedImage image,
  ) async {
    final url = image.url;
    if (image.bytes != null || url == null) return image;
    final request = await client.getUrl(url);
    final response = await request.close().timeout(timeout);
    if (response.statusCode >= 400) {
      await response.drain<void>();
      throw UpstreamException(
        'The picture could not be fetched: HTTP ${response.statusCode} '
        '(GET ${url.replace(query: '')})',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      bytes.add(chunk);
      if (bytes.length > _maxBytes) {
        throw const UpstreamException('The picture is too large to fetch.');
      }
    }
    return GeneratedImage(
      bytes: bytes.takeBytes(),
      revisedPrompt: image.revisedPrompt,
    );
  }

  static Object? _decode(String text, Uri url) {
    try {
      return jsonDecode(text);
    } on FormatException {
      final short = text.length > 200 ? '${text.substring(0, 200)}…' : text;
      throw UpstreamException('The answer is not JSON (POST $url): $short');
    }
  }
}

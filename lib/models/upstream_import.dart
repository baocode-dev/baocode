/// An upstream as a site hands it over to be added in one click: the link
/// on its key's page goes to baocode.dev/import (site/import.js), which
/// opens `baocode://provider/import?…` (see docs/upstream-import.md).
///
/// Only where it is, how it is spoken to, its name and the key come in
/// this way: nothing that changes what Claude Code runs with (an upstream's
/// environment), and not ChatGPT (Codex), which signs in with accounts.
library;

import 'model_provider.dart';
import 'upstream.dart';

class UpstreamImport {
  const UpstreamImport({
    required this.name,
    required this.protocol,
    required this.baseUrl,
    this.key = '',
  });

  /// What the link asks: `baocode://provider/import`, then `v` (1),
  /// `name`, `protocol` (`anthropic`, the default, `openai-chat`,
  /// `openai-responses` or `gemini`), `url` (the base URL, http or https)
  /// and `key`; null for any other URL, or one without a base URL to go to.
  static UpstreamImport? parse(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null ||
        !uri.isScheme(scheme) ||
        uri.host != 'provider' ||
        uri.path != '/import') {
      return null;
    }
    final query = uri.queryParameters;
    if (query['v'] case final version? when version != '1') return null;
    final protocol = switch (query['protocol']) {
      null || '' => ProviderProtocol.anthropic,
      final id => _protocols.where((p) => p.id == id).firstOrNull,
    };
    if (protocol == null) return null;
    final base = UpstreamUrls.parse(query['url'] ?? '');
    if (base == null) return null;
    final name = _clean(query['name'] ?? '', maxNameLength);
    return UpstreamImport(
      name: name.isEmpty ? base.host : name,
      protocol: protocol,
      baseUrl: '$base',
      key: _clean(query['key'] ?? '', maxKeyLength),
    );
  }

  /// The app's URL scheme (Info.plist, tool/baocode.iss).
  static const scheme = 'baocode';

  static const maxNameLength = 64;
  static const maxKeyLength = 512;

  /// Those an upstream can come in with.
  static const _protocols = [
    ProviderProtocol.anthropic,
    ProviderProtocol.openaiChat,
    ProviderProtocol.openaiResponses,
    ProviderProtocol.gemini,
  ];

  /// [text] on one line, without control characters, at most [max] long.
  static String _clean(String text, int max) {
    final line = text.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    return line.length > max ? line.substring(0, max).trim() : line;
  }

  final String name;
  final ProviderProtocol protocol;
  final String baseUrl;

  /// Empty when the link has none: one to paste after.
  final String key;

  String get host => Uri.parse(baseUrl).host;

  /// [key] as the confirmation shows it: its first and last few
  /// characters.
  String get maskedKey {
    if (key.length <= 12) return '•' * key.length.clamp(0, 8);
    return '${key.substring(0, 6)}…${key.substring(key.length - 4)}';
  }

  /// The upstream it makes, [id] its own; as one added by hand starts.
  ModelProvider toProvider(String id) => ModelProvider(
    id: id,
    name: name,
    protocol: protocol,
    baseUrl: baseUrl,
    disableNonessentialTraffic: true,
  );

  /// The upstream among [providers] it is already: the same protocol at
  /// the same base URL (as requests go to it: with or without `/v1`); the
  /// key is what an import changes then.
  ModelProvider? existingIn(Iterable<ModelProvider> providers) {
    final base = _requestBase(baseUrl);
    for (final provider in providers) {
      if (provider.protocol == protocol &&
          _requestBase(provider.baseUrl) == base) {
        return provider;
      }
    }
    return null;
  }

  String? _requestBase(String url) => switch (protocol) {
    ProviderProtocol.anthropic => UpstreamUrls.anthropicBase(url),
    ProviderProtocol.gemini => UpstreamUrls.geminiBase(url),
    _ => UpstreamUrls.openaiBase(url),
  };
}

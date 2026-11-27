import 'dart:convert';
import 'dart:io';

import 'package:baocode/models/featured_upstreams.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/upstream_import.dart';
import 'package:flutter_test/flutter_test.dart';

String _link(Map<String, String> query) => Uri(
  scheme: 'baocode',
  host: 'provider',
  path: '/import',
  queryParameters: query,
).toString();

void main() {
  group('UpstreamImport.parse', () {
    test('reads what a site hands over', () {
      final import = UpstreamImport.parse(
        _link({
          'v': '1',
          'name': 'Example API',
          'protocol': 'openai-chat',
          'url': 'https://api.example.com/v1/',
          'key': 'sk-abc+def/123',
        }),
      )!;
      expect(import.name, 'Example API');
      expect(import.protocol, ProviderProtocol.openaiChat);
      // Without the trailing slash, as an upstream keeps it.
      expect(import.baseUrl, 'https://api.example.com/v1');
      expect(import.key, 'sk-abc+def/123');
      expect(import.host, 'api.example.com');
    });

    test('Anthropic-compatible, named after its host, keyless by default', () {
      final import = UpstreamImport.parse(
        _link({'url': 'https://relay.example.com'}),
      )!;
      expect(import.protocol, ProviderProtocol.anthropic);
      expect(import.name, 'relay.example.com');
      expect(import.key, isEmpty);
    });

    test('refuses what it cannot add', () {
      // No base URL, or not http(s).
      expect(UpstreamImport.parse(_link({'name': 'x'})), isNull);
      expect(
        UpstreamImport.parse(_link({'url': 'file:///etc/passwd'})),
        isNull,
      );
      expect(
        UpstreamImport.parse(_link({'url': 'javascript:alert(1)'})),
        isNull,
      );
      // ChatGPT (Codex) signs in with accounts; unknown protocols.
      expect(
        UpstreamImport.parse(
          _link({'url': 'https://a.example.com', 'protocol': 'codex'}),
        ),
        isNull,
      );
      expect(
        UpstreamImport.parse(
          _link({'url': 'https://a.example.com', 'protocol': 'grpc'}),
        ),
        isNull,
      );
      // A version it does not know.
      expect(
        UpstreamImport.parse(_link({'url': 'https://a.example.com', 'v': '2'})),
        isNull,
      );
      // Other links of the scheme, and other schemes.
      expect(UpstreamImport.parse('baocode://agent?path=/tmp'), isNull);
      expect(
        UpstreamImport.parse('https://provider/import?url=https://a.com'),
        isNull,
      );
    });

    test('takes nothing else: an environment never comes in', () {
      final import = UpstreamImport.parse(
        _link({
          'url': 'https://a.example.com',
          'env': '{"NODE_OPTIONS":"--require /tmp/x.js"}',
          'NODE_OPTIONS': '--require /tmp/x.js',
        }),
      )!;
      final provider = import.toProvider('a');
      expect(provider.env, isEmpty);
      expect(provider.toJson().toString(), isNot(contains('NODE_OPTIONS')));
    });

    test('a name is one line, not too long', () {
      final import = UpstreamImport.parse(
        _link({'url': 'https://a.example.com', 'name': 'A\nB${'x' * 100}'}),
      )!;
      expect(import.name, isNot(contains('\n')));
      expect(import.name.length, lessThanOrEqualTo(64));
    });
  });

  test('the key shows masked', () {
    UpstreamImport key(String key) => UpstreamImport(
      name: 'a',
      protocol: ProviderProtocol.anthropic,
      baseUrl: 'https://a.example.com',
      key: key,
    );
    expect(key('sk-1234567890abcdef').maskedKey, 'sk-123…cdef');
    expect(key('short').maskedKey, '•••••');
    expect(key('').maskedKey, '');
  });

  test('an upstream there already: the same protocol at the same base', () {
    const anthropic = ModelProvider(
      id: 'a',
      name: 'A',
      baseUrl: 'https://a.example.com/v1/',
    );
    const openai = ModelProvider(
      id: 'b',
      name: 'B',
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://a.example.com',
    );
    final import = UpstreamImport.parse(
      _link({'url': 'https://a.example.com'}),
    )!;
    // `/v1` or not, Claude Code goes to the same place.
    expect(import.existingIn(const [openai, anthropic])?.id, 'a');
    final chat = UpstreamImport.parse(
      _link({'url': 'https://a.example.com/v1', 'protocol': 'openai-chat'}),
    )!;
    expect(chat.existingIn(const [anthropic, openai])?.id, 'b');
    expect(chat.existingIn(const [anthropic]), isNull);

    const gemini = ModelProvider(
      id: 'g',
      name: 'G',
      protocol: ProviderProtocol.gemini,
      baseUrl: 'https://g.example.com',
    );
    final geminiImport = UpstreamImport.parse(
      _link({'url': 'https://g.example.com/v1beta', 'protocol': 'gemini'}),
    )!;
    expect(geminiImport.protocol, ProviderProtocol.gemini);
    expect(geminiImport.existingIn(const [anthropic, gemini])?.id, 'g');
  });

  group('FeaturedUpstream', () {
    const json = '''
{
  "version": 1,
  "upstreams": [
    {
      "id": "example",
      "name": "Example",
      "url": "https://example.com/register?aff=abc",
      "logo": "example.svg",
      "description": {"en": "Cheap", "zh": "便宜"},
      "hosts": ["API.example.com"]
    },
    {"id": "no-url", "name": "No URL"},
    {"id": "bad-url", "name": "Bad", "url": "javascript:alert(1)"},
    {"name": "No id", "url": "https://x.com"}
  ]
}''';

    test('lists the entries it can show', () {
      final list = FeaturedUpstream.parseList(json, logoDirectory: '/cache');
      expect(list.map((u) => u.id), ['example']);
      final example = list.single;
      expect(example.url.queryParameters['aff'], 'abc');
      expect(example.logo, '/cache/example.svg');
      expect(example.describe('zh'), '便宜');
      expect(example.describe('fr'), 'Cheap');
      expect(FeaturedUpstream.at('api.EXAMPLE.com', list)?.id, 'example');
      expect(FeaturedUpstream.at('example.com', list), isNull);
    });

    test('a logo is a file beside the list, never a path', () {
      for (final name in [
        '../x.png',
        '/etc/x.png',
        'a/b.png',
        '.x.png',
        '..png',
        '',
      ]) {
        expect(FeaturedUpstream.isLogoName(name), isFalse, reason: name);
      }
      expect(FeaturedUpstream.isLogoName('site-1.logo.svg'), isTrue);
      final list = FeaturedUpstream.parseList(
        '{"upstreams": [{"id": "a", "name": "A", "url": "https://a.dev", '
        '"logo": "../../secret.png"}]}',
        logoDirectory: '/cache',
      );
      expect(list.single.logo, isNull);
    });

    test('the list baocode.dev serves is whole: each entry shown, its logo '
        'there, its id its own', () {
      final text = File('site/featured/upstreams.json').readAsStringSync();
      final raw = (jsonDecode(text) as Map)['upstreams'] as List;
      final list = FeaturedUpstream.parseList(
        text,
        logoDirectory: 'site/featured',
      );
      expect(list, hasLength(raw.length));
      expect(list.map((u) => u.id).toSet(), hasLength(list.length));
      for (final upstream in list) {
        if (upstream.logo case final logo?) {
          expect(File(logo).existsSync(), isTrue, reason: logo);
        }
        expect(upstream.hosts, isNotEmpty, reason: upstream.id);
      }
    });

    test('nothing from what is not a list', () {
      expect(FeaturedUpstream.parseList('not json'), isEmpty);
      expect(FeaturedUpstream.parseList('[]'), isEmpty);
      expect(FeaturedUpstream.parseList('{"upstreams": 3}'), isEmpty);
    });

    FeaturedUpstream site(String id) =>
        FeaturedUpstream(id: id, name: id, url: Uri.https('$id.example.com'));
    List<String> ids(List<FeaturedUpstream> list) => [
      for (final upstream in list) upstream.id,
    ];

    test('the list kept last time shows at once, the new one as it answers, '
        'and every load asks again', () async {
      var asked = 0;
      FeaturedUpstream.keptLoader = () async => [site('kept')];
      FeaturedUpstream.loader = () async {
        asked++;
        return [site('fresh')];
      };
      expect(ids(await FeaturedUpstream.load()), ['kept']);
      await pumpEventQueue();
      expect(ids(FeaturedUpstream.known.value), ['fresh']);
      // Asked every time, not once in an hour.
      expect(ids(await FeaturedUpstream.load()), ['fresh']);
      expect(asked, 2);
    });

    test('at the start, those known are those kept, with no asking', () async {
      var asked = 0;
      FeaturedUpstream.keptLoader = () async => [site('kept')];
      FeaturedUpstream.loader = () async {
        asked++;
        return const [];
      };
      await FeaturedUpstream.readKept();
      expect(ids(FeaturedUpstream.known.value), ['kept']);
      expect(FeaturedUpstream.knownAt('kept.example.com'), isNull);
      expect(asked, 0);
    });

    test('with none kept, the new list; none where it cannot be got, asked '
        'again the next time', () async {
      var answer = <FeaturedUpstream>[];
      FeaturedUpstream.loader = () async => answer;
      expect(await FeaturedUpstream.load(), isEmpty);
      await pumpEventQueue();
      answer = [site('fresh')];
      expect(ids(await FeaturedUpstream.load()), ['fresh']);
    });
  });
}

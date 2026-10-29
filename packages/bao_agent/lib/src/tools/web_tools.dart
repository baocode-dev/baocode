import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../api/message_accumulator.dart';
import '../api/model_client.dart';
import '../permissions/decision.dart';
import '../permissions/rules.dart';
import '../util/html_markdown.dart';
import '../util/json.dart';
import 'tool.dart';

/// Fetches a page and has the small model answer [prompt] from it.
class WebFetchTool extends Tool {
  WebFetchTool();

  static const maxBytes = 10 * 1024 * 1024;
  static const maxText = 100000;
  static const cacheFor = Duration(minutes: 15);

  /// Hosts of documentation fetched without asking.
  static const preapproved = {
    'docs.anthropic.com',
    'docs.claude.com',
    'code.claude.com',
    'developer.mozilla.org',
    'docs.python.org',
    'dart.dev',
    'api.dart.dev',
    'pub.dev',
    'flutter.dev',
    'api.flutter.dev',
    'docs.flutter.dev',
    'react.dev',
    'nodejs.org',
    'go.dev',
    'pkg.go.dev',
    'doc.rust-lang.org',
    'docs.rs',
    'kotlinlang.org',
    'developer.apple.com',
    'learn.microsoft.com',
    'docs.github.com',
    'www.typescriptlang.org',
    'docs.oracle.com',
    'cppreference.com',
    'en.cppreference.com',
    'docs.swift.org',
  };

  final Map<
    String,
    ({DateTime at, String text, int code, String codeText, int bytes})
  >
  _cache = {};

  @override
  String get name => 'WebFetch';

  @override
  String get description => '''Reads a web page for you: fetches the URL, makes its HTML Markdown, and has a small model answer your prompt from it. What comes back is that answer, not the page.

- If an MCP server offers a fetch tool of its own, use that instead: it may reach more.
- Give a whole URL; http is taken as https.
- Say in the prompt what you want from the page.
- A very long page is read a part at a time: the answer says where the part ended, and `offset` reads on from there.
- A page fetched in the last 15 minutes is answered from a copy.
- A redirect to another host is not followed: you are told where it goes, and can fetch that URL in a new call.
- For GitHub, `gh` through Bash (gh pr view, gh issue view, gh api) usually does better.
- It only reads: nothing on this machine changes.''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'url': {
        'type': 'string',
        'format': 'uri',
        'description': 'The page to read',
      },
      'prompt': {
        'type': 'string',
        'description': 'What you want to know from the page',
      },
      'offset': {
        'type': 'integer',
        'minimum': 0,
        'maximum': 9007199254740991,
        'description':
            'The character of the page\'s text to begin at. A page longer '
            'than one call returns is read in parts: pass the number the '
            'last part ended at',
      },
    },
    'required': ['url', 'prompt'],
    'additionalProperties': false,
  };

  @override
  bool isReadOnly(Map<String, Object?> input) => true;

  @override
  String? describe(Map<String, Object?> input) => asString(input['url']);

  @override
  String? ruleContent(Map<String, Object?> input) {
    final host = Uri.tryParse('${input['url']}')?.host;
    return host == null ? null : 'domain:$host';
  }

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final uri = Uri.tryParse('${input['url']}');
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'Not a URL that can be fetched: ${input['url']}';
    }
    if (uri.userInfo.isNotEmpty) {
      return 'URLs with a username or password are not fetched.';
    }
    return null;
  }

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final url = '${input['url']}';
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    final ruled = context.session.permissions.checkContent(
      'WebFetch',
      url,
      match: domainRuleMatches,
      suggestions: [
        addRulesSuggestion(['WebFetch(domain:$host)']),
      ],
    );
    if (ruled is! PermissionPassthrough) return ruled;
    if (preapproved.contains(host)) {
      return const PermissionAllow(reason: 'preapproved');
    }
    return ruled;
  }

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final started = DateTime.now();
    var uri = Uri.parse('${input['url']}');
    // Upgraded, but for a server on this machine (one in development).
    if (uri.scheme == 'http' && !_loopback(uri.host)) {
      uri = uri.replace(scheme: 'https');
    }
    final prompt = '${input['prompt']}';
    final key = uri.toString();
    final cached = _cache[key];
    ({DateTime at, String text, int code, String codeText, int bytes}) page;
    if (cached != null && DateTime.now().difference(cached.at) < cacheFor) {
      page = cached;
    } else {
      final fetched = await _fetch(uri, context);
      if (fetched case final String redirect) {
        return ToolOutput(
          redirect,
          result: {
            'code': 302,
            'codeText': 'Redirect',
            'url': key,
            'result': redirect,
            'bytes': 0,
            'durationMs': DateTime.now().difference(started).inMilliseconds,
          },
        );
      }
      page =
          fetched
              as ({
                DateTime at,
                String text,
                int code,
                String codeText,
                int bytes,
              });
      _cache[key] = page;
      _cache.removeWhere(
        (_, entry) => DateTime.now().difference(entry.at) > cacheFor,
      );
    }
    if (page.code >= 400) {
      return ToolOutput.error(
        'The server answered ${page.code} ${page.codeText}.',
      );
    }
    final offset = (asInt(input['offset']) ?? 0).clamp(0, page.text.length);
    final end = (offset + maxText).clamp(0, page.text.length);
    final content = page.text.substring(offset, end);
    final more = end < page.text.length;
    final answer = await context.session.quickQuery(
      system:
          'You answer questions about the content of a web page, from that '
          'content alone. Be concise and accurate. Quote exact text only '
          'briefly (no more than 125 characters at a time) and never '
          'reproduce song lyrics. If the page does not say, say so.',
      prompt:
          'Web page content:\n---\n$content\n---\n\n$prompt\n\n'
          'Answer from the content above only.',
      cancel: context.cancel,
      maxTokens: 4096,
    );
    final text = more
        ? '$answer\n\n[This was the page\'s text from character $offset to '
              '$end of ${page.text.length}. To read on, call WebFetch again '
              'with offset $end.]'
        : answer;
    return ToolOutput(
      text,
      result: {
        'bytes': page.bytes,
        'code': page.code,
        'codeText': page.codeText,
        'result': answer,
        'durationMs': DateTime.now().difference(started).inMilliseconds,
        'url': key,
      },
    );
  }

  static bool _loopback(String host) =>
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host == '::1' ||
      host == '[::1]' ||
      host.startsWith('127.');

  /// The page at [uri] as Markdown, or what to say of a redirect to
  /// another host.
  Future<Object> _fetch(Uri uri, ToolContext context) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..userAgent =
          'Mozilla/5.0 (compatible; BaoCode-Agent/1.0; +https://baocode.dev)'
      ..findProxy = (url) => HttpClient.findProxyFromEnvironment(
        url,
        environment: context.session.environment,
      );
    try {
      var current = uri;
      for (var hops = 0; hops < 10; hops++) {
        final request = await context.cancel.guard(client.getUrl(current));
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.acceptHeader,
          'text/markdown, text/html;q=0.9, */*;q=0.8',
        );
        final response = await context.cancel.guard(
          request.close().timeout(const Duration(seconds: 60)),
        );
        if (response.isRedirect ||
            (response.statusCode >= 300 && response.statusCode < 400)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null) break;
          final next = current.resolve(location);
          // Another host: the model is to fetch it itself, so the user is
          // asked about that host.
          if (_bareHost(next.host) != _bareHost(current.host)) {
            return '$uri sends you to another host '
                '(${response.statusCode} ${response.reasonPhrase}), which is '
                'not followed: $next\n\n'
                'To read it, call WebFetch again with that URL as url and the '
                'same prompt.';
          }
          current = next;
          continue;
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > maxBytes) break;
        }
        final type = response.headers.contentType;
        final charset = type?.charset?.toLowerCase();
        final body = charset == 'iso-8859-1' || charset == 'latin1'
            ? latin1.decode(bytes)
            : utf8.decode(bytes, allowMalformed: true);
        final isHtml =
            type?.subType == 'html' ||
            (type == null &&
                body.trimLeft().toLowerCase().startsWith('<!doctype html'));
        final text = isHtml ? htmlToMarkdown(body, base: current) : body;
        return (
          at: DateTime.now(),
          text: text,
          code: response.statusCode,
          codeText: response.reasonPhrase,
          bytes: bytes.length,
        );
      }
      throw const ToolFailure('The page redirects more than 10 times');
    } on SocketException catch (error) {
      throw ToolFailure('Could not fetch $uri: ${error.message}');
    } on HandshakeException catch (error) {
      throw ToolFailure('Could not fetch $uri: ${error.message}');
    } on TimeoutException {
      throw ToolFailure('Fetching $uri timed out');
    } on HttpException catch (error) {
      throw ToolFailure('Could not fetch $uri: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  static String _bareHost(String host) => host.toLowerCase().startsWith('www.')
      ? host.substring(4).toLowerCase()
      : host.toLowerCase();
}

/// Searches the web, by the API's own search tool.
class WebSearchTool extends Tool {
  const WebSearchTool();

  @override
  String get name => 'WebSearch';

  @override
  String get description => '''Searches the web and gives back what it found, with each result's title and link: for news, recent releases, or anything newer than what you know.

- allowed_domains keeps to some sites, blocked_domains leaves some out (one or the other).
- For something recent, put the year in the query, the current one from the date you were given.
- When you answer from a search, end the answer with a "Sources:" list of the links you drew on, as Markdown links: [Title](URL).''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'minLength': 2,
        'description': 'What to search for',
      },
      'allowed_domains': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Keep to results from these sites',
      },
      'blocked_domains': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Leave out results from these sites',
      },
    },
    'required': ['query'],
    'additionalProperties': false,
  };

  @override
  bool isReadOnly(Map<String, Object?> input) => true;

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAllow(reason: 'readOnly');

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    if ('${input['query'] ?? ''}'.trim().length < 2) {
      return 'The query needs at least 2 characters.';
    }
    if (asList(input['allowed_domains']).isNotEmpty &&
        asList(input['blocked_domains']).isNotEmpty) {
      return 'Give allowed_domains or blocked_domains, not both.';
    }
    return null;
  }

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final started = DateTime.now();
    final query = '${input['query']}'.trim();
    final session = context.session;
    final model = session.resolvedModel;
    final request = ModelRequest({
      'model': model,
      'max_tokens': 8192,
      'system': [
        {
          'type': 'text',
          'text':
              'Search the web for what you are asked, then say briefly '
              'what the results tell.',
        },
      ],
      'messages': [
        {'role': 'user', 'content': 'Search for: $query'},
      ],
      'tools': [
        {
          'type': 'web_search_20250305',
          'name': 'web_search',
          'max_uses': 8,
          if (asList(input['allowed_domains']).isNotEmpty)
            'allowed_domains': asList(input['allowed_domains']),
          if (asList(input['blocked_domains']).isNotEmpty)
            'blocked_domains': asList(input['blocked_domains']),
        },
      ],
      'stream': true,
    });
    var accumulator = MessageAccumulator();
    try {
      await for (final event in session.client.stream(
        request,
        cancel: context.cancel,
      )) {
        if (event['type'] == 'stream_restart') {
          accumulator = MessageAccumulator();
          continue;
        }
        accumulator.add(event);
      }
    } on ApiError catch (error) {
      return ToolOutput.error(
        'Web search is not available here: $error. The API or provider in '
        'use may not offer the web search tool.',
      );
    }
    final message = accumulator.message();
    session.addUsage(model, asMap(message['usage']));
    final parts = <String>[];
    final links = <Map<String, Object?>>[];
    final results = <Object?>[];
    for (final block in asList(message['content'])) {
      final b = asMap(block);
      switch (b['type']) {
        case 'text':
          final text = '${b['text'] ?? ''}'.trim();
          if (text.isNotEmpty) parts.add(text);
          results.add(text);
        case 'web_search_tool_result':
          final content = b['content'];
          if (content is List) {
            final found = [
              for (final item in content)
                if (item is Map)
                  {
                    'title': '${item['title'] ?? ''}',
                    'url': '${item['url'] ?? ''}',
                  },
            ];
            links.addAll(found);
            results.add({'tool_use_id': b['tool_use_id'], 'content': found});
          } else if (content is Map) {
            final code = content['error_code'];
            parts.add('Web search error: $code');
            results.add('Web search error: $code');
          }
      }
    }
    final text = StringBuffer('What a web search for "$query" found:\n\n');
    if (links.isNotEmpty) text.writeln('Results: ${jsonEncode(links)}\n');
    text.write(parts.join('\n\n'));
    text.write(
      '\n\nEnd your answer with a "Sources:" list of the links you drew '
      'on, as Markdown links.',
    );
    return ToolOutput(
      text.toString(),
      result: {
        'query': query,
        'results': results,
        'durationSeconds':
            DateTime.now().difference(started).inMilliseconds / 1000,
      },
    );
  }
}

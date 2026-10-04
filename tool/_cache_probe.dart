// Temporary probe: prompt caching over turns, through the translators, to
// the real upstream. Deleted after use.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:baocode/models/proxy/translate/json_value.dart';
import 'package:baocode/models/proxy/translate/openai_chat_request.dart';
import 'package:baocode/models/proxy/translate/openai_chat_response.dart';
import 'package:baocode/models/proxy/translate/responses_request.dart';
import 'package:baocode/models/proxy/translate/responses_response.dart';

final key = Platform.environment['ASTRA_KEY']!;
final random = Random();
String hex(int n) =>
    List.generate(n, (_) => random.nextInt(16).toRadixString(16)).join();

/// A Claude Code-like request: billing block (fresh each turn), a long
/// fixed system prompt, tools, the messages so far.
Map<String, Object?> claude(String seed, List<Map<String, Object?>> messages) {
  final system = StringBuffer('Session $seed. You are a coding assistant.\n');
  for (var i = 0; i < 700; i++) {
    system.writeln(
      'Rule $i: keep answers short, cite file paths, prefer edits over rewrites.',
    );
  }
  return {
    'model': 'gpt-6-astra(low)',
    'stream': true,
    'max_tokens': 2000,
    'metadata': {'user_id': 'user_abc_account__session_$seed'},
    'system': [
      {
        'type': 'text',
        'text':
            'x-anthropic-billing-header: cc_version=2.1.281; cc_entrypoint=sdk-cli; cch=${hex(5)};',
      },
      {
        'type': 'text',
        'text': '$system',
        'cache_control': {'type': 'ephemeral'},
      },
    ],
    'tools': [
      for (final name in ['Read', 'Edit', 'Bash', 'Grep'])
        {
          'name': name,
          'description': '$name tool. ' * 20,
          'input_schema': {
            'type': 'object',
            'properties': {
              'arg': {'type': 'string'},
            },
          },
        },
    ],
    'messages': messages,
  };
}

Future<({String text, Map usage})> send(
  String protocol,
  Map<String, Object?> request, {
  String? cacheKey,
}) async {
  final Map<String, Object?> out;
  final Uri url;
  if (protocol == 'chat') {
    out = convertClaudeRequestToOpenAI('gpt-6-astra', request, true)
      ..['reasoning_effort'] = 'low'
      ..['stream_options'] = {'include_usage': true};
    url = Uri.parse('https://api.aijws.com/v1/chat/completions');
  } else {
    out = convertClaudeRequestToResponses('gpt-6-astra', request)
      ..['reasoning'] = {'effort': 'low'};
    url = Uri.parse('https://api.aijws.com/v1/responses');
  }
  if (cacheKey != null) out['prompt_cache_key'] = cacheKey;
  final client = HttpClient();
  final req = await client.postUrl(url);
  req.headers
    ..set('Authorization', 'Bearer $key')
    ..contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode(out)));
  final res = await req.close();
  final text = StringBuffer();
  Map usage = {};
  final responses = ResponsesResponseTranslator(request);
  final chat = OpenAIChatResponseTranslator(request);
  await for (final line
      in res.transform(utf8.decoder).transform(const LineSplitter())) {
    if (res.statusCode >= 400) {
      text.write(line);
      continue;
    }
    final events = protocol == 'chat'
        ? chat.convert(line).join()
        : responses.convert(line);
    if (protocol == 'chat' && line.startsWith('data: {')) {
      final raw = JsonValue.parse(line.substring(6)).get('usage');
      if (raw.isObject) usage['upstream'] = raw.value;
    }
    if (protocol != 'chat' && line.contains('"response.completed"')) {
      usage['upstream'] = JsonValue.parse(
        line.substring(5),
      ).get('response.usage').value;
    }
    for (final e in events.split('\n')) {
      if (!e.startsWith('data: ')) continue;
      final d = JsonValue.parse(e.substring(6));
      if (d.get('delta.type').string == 'text_delta') {
        text.write(d.get('delta.text').string);
      }
      if (d.get('type').string == 'message_delta') {
        usage['claude'] = d.get('usage').value;
      }
    }
  }
  client.close();
  if (res.statusCode >= 400) usage['status'] = res.statusCode;
  return (text: '$text', usage: usage);
}

String brief(Map usage) {
  final c = usage['claude'] as Map? ?? {};
  final up = usage['upstream'] as Map? ?? {};
  final details = up['input_tokens_details'] ?? up['prompt_tokens_details'];
  final input = (c['input_tokens'] ?? 0) as int;
  final read = (c['cache_read_input_tokens'] ?? 0) as int;
  final total = input + read + ((c['cache_creation_input_tokens'] ?? 0) as int);
  final pct = total == 0 ? 0 : (read * 100 / total).round();
  final raw = {for (final k in ['input_tokens','prompt_tokens','total_tokens']) if (up[k] != null) k: up[k]};
  return 'raw=$raw claude: in=$input cache_read=$read ($pct%) | upstream details=$details'
      '${usage['status'] != null ? ' STATUS ${usage['status']}' : ''}';
}

Future<void> conversation(String label, String protocol, {bool key = false}) async {
  final seed = hex(12);
  final cacheKey = key ? 'session-$seed' : null;
  final messages = <Map<String, Object?>>[
    {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': 'Name one prime number. One word.'},
      ],
    },
  ];
  stdout.writeln('== $label');
  for (var turn = 1; turn <= 3; turn++) {
    final (:text, :usage) = await send(
      protocol,
      claude(seed, messages),
      cacheKey: cacheKey,
    );
    stdout.writeln('  turn $turn: ${brief(usage)}  reply=${jsonEncode(text.length > 60 ? text.substring(0, 60) : text)}');
    messages
      ..add({
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': text.isEmpty ? 'ok' : text},
        ],
      })
      ..add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Another one, different. One word.'},
        ],
      });
  }
}

Future<void> main(List<String> args) async {
  final which = args.isEmpty ? 'all' : args.first;
  if (which == 'all' || which == 'responses') {
    await conversation('responses, as sent today', 'responses');
  }
  if (which == 'all' || which == 'responses-key') {
    await conversation('responses + prompt_cache_key', 'responses', key: true);
  }
  if (which == 'all' || which == 'chat') {
    await conversation('chat, as sent today', 'chat');
  }
  if (which == 'all' || which == 'chat-key') {
    await conversation('chat + prompt_cache_key', 'chat', key: true);
  }
}

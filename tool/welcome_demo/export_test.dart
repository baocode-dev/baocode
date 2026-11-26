// Writes the welcome demo (assets/welcome/): the conversation a new user
// first sees, in English and in Chinese. Its turns are the showcase's own
// (tool/showcase/scripts.dart), played at once by [ShowTransport] and kept
// as Claude Code keeps a session, so the app reads and shows it as any
// other (see lib/workspace/welcome.dart).
//
// Run again once the showcase's scripts change:
//
//   flutter test tool/welcome_demo/export_test.dart
//
// Its folder is [WelcomeDemo.folder], put in place of the user's welcome
// folder as the demo is set up.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/workspace/welcome.dart';
import 'package:flutter_test/flutter_test.dart';

import '../showcase/scripts.dart';
import '../showcase/show_transport.dart';
import '../showcase/story.dart';

void main() {
  for (final locale in WelcomeDemo.locales) {
    test('the welcome demo, $locale', () async {
      Story.locale = locale;
      final lines = await _export();
      final file = File('assets/welcome/demo.$locale.jsonl')
        ..parent.createSync(recursive: true);
      file.writeAsStringSync('${lines.map(jsonEncode).join('\n')}\n');
    });
  }
}

/// Its turns, asked one after the other: the algorithms compared, then the
/// one picked written, by subagents and edits, and tested.
Future<List<Map<String, Object?>>> _export() async {
  ShowClock.dilation = 0;
  ShowScripts.clear();
  for (final hold in const ['agents', 'written', 'answer']) {
    ShowScripts.release(hold);
  }
  const root = WelcomeDemo.folder;
  ShowScripts.register(markdownPrompt, markdownScript);
  ShowScripts.register(rateLimitPrompt, (run) => rateLimitScript(run, root));

  final kept = _Kept(root);
  kept.notice(
    Story.t(
      'This is a demo conversation: nothing in it ran, and none of your files were touched. Send a message to start one of your own.',
      '这是一段演示对话：里面的操作都没有真的执行，也不会改动你的文件。发一条消息，开始你自己的对话。',
    ),
  );
  final transport = ShowTransport(const ClaudeLaunch(cwd: root));
  final results = StreamController<void>.broadcast();
  transport.messages.listen((message) {
    if (message['type'] == 'result') results.add(null);
    kept.take(message);
  });
  for (final prompt in [markdownPrompt, rateLimitPrompt]) {
    final done = results.stream.first;
    kept.ask(prompt);
    transport.write({
      'type': 'user',
      'message': {'role': 'user', 'content': prompt},
    });
    await done;
  }
  transport.close();
  kept.notice(
    Story.t(
      'That was the demo. Ask anything below: a new conversation starts, in this folder.',
      '演示到这里。在下面随便问点什么，会在这个文件夹里开始一段新的对话。',
    ),
  );
  return kept.lines;
}

/// The lines of the session, as Claude Code writes them: each the child of
/// the one before, a subagent's own left out (the CLI keeps those apart).
class _Kept {
  _Kept(this.cwd);

  final String cwd;
  final List<Map<String, Object?>> lines = [];
  String? _last;
  var _at = DateTime.utc(2026, 11, 20, 9);
  var _next = 0;

  static const _session = WelcomeDemo.sessionId;

  String _uuid() {
    final n = (++_next).toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-a000-$n';
  }

  void _add(Map<String, Object?> line, {int seconds = 2}) {
    final uuid = _uuid();
    _at = _at.add(Duration(seconds: seconds));
    lines.add({
      'parentUuid': _last,
      'isSidechain': false,
      'userType': 'external',
      'cwd': cwd,
      'sessionId': _session,
      'version': '2.1.0',
      ...line,
      'uuid': uuid,
      'timestamp': _at.toIso8601String(),
    });
    _last = uuid;
  }

  void ask(String prompt) => _add({
    'type': 'user',
    'message': {'role': 'user', 'content': prompt},
  }, seconds: 20);

  void notice(String text) => _add({
    'type': 'system',
    'subtype': 'informational',
    'level': 'notice',
    'content': text,
  });

  void take(Map<String, Object?> message) {
    if (message['parent_tool_use_id'] != null) return;
    switch (message['type']) {
      case 'assistant':
        _add({'type': 'assistant', 'message': message['message']});
      case 'user' when message['isReplay'] != true:
        _add({
          'type': 'user',
          'message': message['message'],
          'toolUseResult': ?message['tool_use_result'],
        });
    }
  }
}

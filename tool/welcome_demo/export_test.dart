// Writes the welcome demo (assets/welcome/): the conversation a new user
// first sees, in English and in Chinese. Its turns are script.dart's,
// played by the showcase's stand-in for Claude Code ([ShowTransport]) in
// the test's time, and what it printed kept with when, for the app to
// play again as it was (see lib/workspace/welcome.dart).
//
// Run again once the scripts change:
//
//   flutter test tool/welcome_demo/export_test.dart
//
// Its folder is [WelcomeDemo.folder], put in place of the user's welcome
// folder as the demo is set up.

import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/workspace/welcome.dart';
import 'package:flutter_test/flutter_test.dart';

import '../showcase/show_transport.dart';
import '../showcase/story.dart';
import 'script.dart';

void main() {
  for (final locale in WelcomeDemo.locales) {
    testWidgets('the welcome demo, $locale', (tester) async {
      Story.locale = locale;
      ShowClock.dilation = 1;
      ShowScripts.clear();
      const root = WelcomeDemo.folder;
      ShowScripts.register(comparePrompt, compareScript);
      ShowScripts.register(rewritePrompt, (run) => rewriteScript(run, root));

      final transport = ShowTransport(const ClaudeLaunch(cwd: root));
      DateTime now() => tester.binding.clock.now();
      var start = now();
      var lines = <List<Object?>>[];
      var ended = false;
      transport.messages.listen((message) {
        if (message['type'] case 'control_response' || 'control_request') {
          return;
        }
        lines.add([
          now().difference(start).inMilliseconds,
          {...message}..remove('session_id'),
        ]);
        if (message['type'] == 'result') ended = true;
      });
      final turns = <Map<String, Object?>>[];
      for (final (i, prompt) in [comparePrompt, rewritePrompt].indexed) {
        start = now();
        lines = [];
        ended = false;
        transport.write({
          'type': 'user',
          'uuid': 'welcome-$i',
          'message': {'role': 'user', 'content': prompt},
        });
        while (!ended) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        turns.add({'prompt': prompt, 'messages': lines});
      }
      transport.close();
      ShowScripts.clear();

      final file = File('assets/welcome/demo.$locale.json')
        ..parent.createSync(recursive: true);
      final notice = Story.t(
        'This is a demo: nothing in it really runs, and none of your files are touched. For a real conversation, click New Chat at the top left.',
        '这是一段演示：里面的操作都没有真的执行，也不会改动你的文件。要开始真正的对话，点左上角的「新对话」。',
      );
      final ending = Story.t(
        'That was the demo. Pick a suggestion or send anything below to watch it again; New Chat at the top left starts a real conversation.',
        '演示到这里。点下面的建议或随便发点什么，会再演示一遍；左上角的「新对话」会开始真正的对话。',
      );
      final demo = {'notice': notice, 'ending': ending, 'turns': turns};
      file.writeAsStringSync('${jsonEncode(demo)}\n');
    });
  }
}

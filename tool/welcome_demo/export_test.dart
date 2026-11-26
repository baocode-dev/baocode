// Writes the welcome demo (assets/welcome/): the conversation a new user
// first sees, in English and in Chinese: script.dart's reply, played by
// the showcase's stand-in for Claude Code ([ShowTransport]) in the test's
// time, and its stream-json kept with when each line came, for the app to
// play again as it was (see lib/workspace/welcome.dart).
//
// Run again once the script changes:
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
      ShowScripts.register(demoPrompt, (run) => demoScript(run, root));

      final transport = ShowTransport(const ClaudeLaunch(cwd: root));
      DateTime now() => tester.binding.clock.now();
      final start = now();
      final lines = <List<Object?>>[];
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
      transport.write({
        'type': 'user',
        'uuid': 'welcome',
        'message': {'role': 'user', 'content': demoPrompt},
      });
      while (!ended) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      transport.close();
      ShowScripts.clear();
      // Once it is over: that sending anything plays it again.
      lines.add([
        lines.last.first,
        {
          'type': 'system',
          'subtype': 'informational',
          'level': 'notice',
          'content': Story.t(
            'That was the demo. Send anything to watch it again; New Chat at the top left starts a real conversation.',
            '演示到这里。发任何消息都会再播放一遍；左上角的「新对话」会开始真正的对话。',
          ),
        },
      ]);

      final demo = {
        'notice': Story.t(
          'This is a demo: nothing in it really runs, and none of your files are touched. For a real conversation, click New Chat at the top left.',
          '这是一段演示：里面的操作都没有真的执行，也不会改动你的文件。要开始真正的对话，点左上角的「新对话」。',
        ),
        'prompt': demoPrompt,
        'messages': lines,
      };
      File('assets/welcome/demo.$locale.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('${jsonEncode(demo)}\n');
    });
  }
}

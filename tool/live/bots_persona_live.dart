// A bot knowing itself, with the real Claude Code (on OpenCode's model, see live_model.dart), without a phone: asked
// who it is and what it looks like, what it likes; then its profile
// changed (a new name and picture), for it to see; and what it noted of
// itself printed.
//
//   flutter test tool/live/bots_persona_live.dart
import 'dart:io';

import 'package:baocode/bots/bot.dart';
import 'package:baocode/bots/bot_folders_io.dart';
import 'package:baocode/bots/bots.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/link/chat_codec.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_model.dart';

void main() {
  test('live persona', () async {
    final root = await Directory.systemTemp.createTemp('bots-persona');
    final demo = Directory('${root.path}/demo')..createSync();
    ClaudeCore.current = () => ClaudeCore.cli;
    final model = await useOpenCode();
    KernelRegistry.use([KernelRegistry.claudeCode]);
    final workspace = Workspace(
      projects: [Project('demo', demo.path)],
      kernels: [KernelRegistry.claudeCode],
    );
    final bots = Bots(
      workspace: workspace,
      folders: DataBotFolders(),
      chinese: true,
    );
    await bots.start();
    onModel(bots, model);
    var bot = bots.save(
      id: bots.bots.single.id,
      name: '小宝',
      avatar: '🐼',
      gender: '女',
      identity: '我的朋友，在杭州长大，刚毕业，做设计的，有点毒舌但很温柔。',
      abilities: BotAbility.values.toSet(),
    );
    final session = bots.threadFor(bot).session;
    final started = DateTime.now();
    var printed = 0;

    void show() {
      final quiet = ChatCodec.botQuiet(session.itemCount, session.itemAt);
      for (; printed < session.itemCount; printed++) {
        final item = session.itemAt(printed);
        final at = DateTime.now().difference(started).inMilliseconds / 1000;
        final line = switch (item) {
          UserMessageItem(:final text) => 'USER  $text',
          AssistantTextItem() when quiet.contains(printed) => null,
          AssistantTextItem(:final text) => 'TEXT  $text',
          final ToolCallItem tool when ChatCodec.botSay(tool) != null =>
            'SAY   ${ChatCodec.botSay(tool)}',
          ToolCallItem(:final tool, :final input) =>
            'tool  ${tool ?? ''} ${input.isEmpty ? '' : input}',
          NoticeItem(:final text) => 'notice $text',
          _ => null,
        };
        if (line != null) stdout.writeln('${at.toStringAsFixed(1)}s $line');
      }
    }

    Future<void> idle() async {
      await Future<void>.delayed(const Duration(seconds: 2));
      while (session.isStreaming) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      show();
    }

    Future<void> send(String text) async {
      session.send(ComposerMessage(text: text));
      await idle();
    }

    await send('你叫啥，长啥样？');
    await send('平时下班都干嘛');
    await send('你最喜欢吃什么');
    // A new name and picture, for it to see.
    bot = bots.save(
      id: bot.id,
      name: '包包',
      gender: bot.gender,
      identity: bot.identity,
      abilities: bot.abilities,
      avatarImage: (
        bytes: File('site/brand/baocode-icon-256.png').readAsBytesSync(),
        type: 'image/png',
      ),
    );
    await idle();
    await send('你现在头像是啥');
    stdout.writeln('self notes:\n${bots.selfNotes(bots.bots.single)}');
    bots.dispose();
    workspace.dispose();
  }, timeout: const Timeout(Duration(minutes: 15)));
}

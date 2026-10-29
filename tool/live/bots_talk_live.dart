// A bot's chat with the real Claude Code, without a phone: messages sent
// to the assistant one after another (one while it is still talking), and
// what it does with them printed, to see how it talks (bot_say), when it
// says nothing, and whether it plans to come back (bot_later).
//
//   flutter test tool/live/bots_talk_live.dart
import 'dart:async';
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

void main() {
  test('live talk', () async {
    final root = await Directory.systemTemp.createTemp('bots-talk');
    final demo = Directory('${root.path}/demo')..createSync();
    ClaudeCore.current = () => ClaudeCore.cli;
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
    final bot = bots.bots.single;
    bots.save(
      id: bot.id,
      name: bot.name,
      identity: bot.identity,
      abilities: BotAbility.values.toSet(),
      proactive: const BotProactive(perDay: 6, quietFrom: 0, quietTo: 0),
    );
    final session = bots.threadFor(bots.bots.single).session;
    final started = DateTime.now();
    var printed = 0;

    void show() {
      final quiet = ChatCodec.botQuiet(session.itemCount, session.itemAt);
      for (; printed < session.itemCount; printed++) {
        final item = session.itemAt(printed);
        final at = DateTime.now().difference(started).inMilliseconds / 1000;
        final line = switch (item) {
          UserMessageItem(:final text) => 'USER  $text',
          AssistantTextItem(:final text) =>
            quiet.contains(printed) ? '(note) $text' : 'TEXT  $text',
          final ToolCallItem tool when ChatCodec.botSay(tool) != null =>
            'SAY   ${ChatCodec.botSay(tool)}',
          ToolCallItem(:final tool, :final target, :final input) =>
            'tool  ${tool ?? ''} $target ${input.isEmpty ? '' : input}',
          NoticeItem(:final text) => 'notice $text',
          _ => null,
        };
        if (line != null) stdout.writeln('${at.toStringAsFixed(1)}s $line');
      }
    }

    final ticker = Timer.periodic(const Duration(milliseconds: 300), (_) {
      // Items change as they come: printed once done with.
      if (!session.isStreaming) show();
    });

    Future<void> idle() async {
      await Future<void>.delayed(const Duration(seconds: 2));
      while (session.isStreaming) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      show();
    }

    Future<void> send(String text) async {
      session.send(ComposerMessage(text: text));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    await send('在吗');
    await idle();
    await send('终于把 relay 那个断线的 bug 修好了！！');
    await idle();
    await send('帮我看看现在有啥在跑');
    // Written while it talks: taken up as it does.
    await Future<void>.delayed(const Duration(seconds: 2));
    await send('算了不用了，我自己看吧');
    await idle();
    await send('明天下午三点我有个面试，有点紧张');
    await idle();
    await send('ok 我去睡了 晚安');
    await idle();
    ticker.cancel();
    stdout.writeln(
      'laters: ${[for (final l in bots.laters(bots.bots.single)) '${l.at} ${l.note}']}',
    );
    bots.dispose();
    workspace.dispose();
  }, timeout: const Timeout(Duration(minutes: 15)));
}

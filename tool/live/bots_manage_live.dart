// A bot's chat with the real Claude Code (on OpenCode's model, see live_model.dart), without a phone: how much it
// says to a line; a reminder called off (dropped, or let pass in
// silence); the web looked up; what the user writes while it talks, where
// they wrote it; and the assistant making a contact.
//
//   flutter test tool/live/bots_manage_live.dart
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
  test('live manage', () async {
    final root = await Directory.systemTemp.createTemp('bots-manage');
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
    bots.setMe(const BotUser(name: 'Leo', signature: '写代码的'), null);
    final bot = bots.bots.single;
    bots.save(
      id: bot.id,
      name: bot.name,
      identity: bot.identity,
      abilities: BotAbility.values.toSet(),
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
          UserMessageItem() when ChatCodec.botEvent(item) != null =>
            'APP   ${ChatCodec.botEvent(item)!.replaceAll('\n', ' / ')}',
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

    await send('在吗');
    await send('今天好累');
    await send('1分钟后提醒我喝水');
    await send('算了 不用提醒了');
    stdout.writeln(
      'laters: ${[for (final l in bots.laters(bots.bots.single)) l.note]}',
    );
    // Its time come, were it still there.
    await Future<void>.delayed(const Duration(seconds: 70));
    await idle();
    await send('杭州今天天气怎么样');
    // Written while it talks: where it was written.
    session.send(const ComposerMessage(text: '你最近在看什么书'));
    await Future<void>.delayed(const Duration(seconds: 4));
    session.send(const ComposerMessage(text: '对了 推荐一本'));
    await idle();
    await send('帮我建个联系人，叫阿猫，是一只很懒的橘猫，说话慢吞吞的');
    stdout.writeln(
      'bots: ${[for (final b in bots.bots) '${b.name} ${b.avatar ?? ''} ${b.signature}']}',
    );
    bots.dispose();
    workspace.dispose();
  }, timeout: const Timeout(Duration(minutes: 20)));
}

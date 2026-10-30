// A bot's own tools, with the real Claude Code (on OpenCode's model, see
// live_model.dart), without a phone: no files nor commands of its own (a
// project's file left to an agent), a picture the user sent taken for
// its avatar, what it remembers, its signature, a bot it makes, a
// reminder.
//
//   flutter test tool/live/bots_tools_live.dart
import 'dart:convert';
import 'dart:io';

import 'package:baocode/bots/bot.dart';
import 'package:baocode/bots/bot_folders_io.dart';
import 'package:baocode/bots/bots.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/link/chat_codec.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_model.dart';

void main() {
  test('live tools', () async {
    final root = await Directory.systemTemp.createTemp('bots-tools');
    final demo = Directory('${root.path}/demo')..createSync();
    File('${demo.path}/notes.txt').writeAsStringSync('周五前把 relay 的重连修好\n');
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
    var bot = bots.bots.single;
    bot = bots.save(
      id: bot.id,
      name: bot.name,
      identity: bot.identity,
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
          UserMessageItem() when ChatCodec.botEvent(item) != null =>
            'APP   ${ChatCodec.botEvent(item)!.replaceAll('\n', ' / ')}',
          UserMessageItem(:final text) => 'USER  $text',
          AssistantTextItem(:final text) =>
            quiet.contains(printed) ? '(note) $text' : 'TEXT  $text',
          final ToolCallItem tool when ChatCodec.botSay(tool) != null =>
            'SAY   ${ChatCodec.botSay(tool)}',
          ToolCallItem(:final tool, :final target, :final status) =>
            'tool  ${tool ?? ''} $target [${status.name}]',
          NoticeItem(:final text) => 'notice $text',
          _ => null,
        };
        if (line != null) stdout.writeln('${at.toStringAsFixed(1)}s $line');
      }
    }

    /// Until it is done; anything asked of the user, said (there should
    /// be none).
    Future<void> idle() async {
      await Future<void>.delayed(const Duration(seconds: 2));
      while (session.isStreaming) {
        if (session.pendingInteraction case final ApprovalRequest asked) {
          show();
          stdout.writeln('ASKED (should not be) ${asked.title}');
          session.answer(const ApprovalAnswer(ApprovalDecision.deny));
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      show();
    }

    Future<void> send(String text, {List<ImageAttachment> images = const []}) {
      session.send(ComposerMessage(text: text, images: images));
      return idle();
    }

    String file(String name) {
      final f = File('${bot.folder}/$name');
      return f.existsSync() ? f.readAsStringSync().trim() : '(none)';
    }

    await send('demo 项目的 notes.txt 里写了啥');
    // A small red square, as the phone sends it: numbered.
    final red = base64.decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CA'
      'FWEXHbQSACj/P8Fu7N9hAAAAAElFTkSuQmCC',
    );
    await send(
      '[Image #1] 用这张当你的头像吧',
      images: [ImageAttachment(bytes: red, mediaType: 'image/png', number: 1)],
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    stdout.writeln(
      'received: ${File('${bot.folder}/received/image-1.png').existsSync()} '
      'avatar: ${bots.byId(bot.id)!.avatar}',
    );
    await send('记住我喜欢喝乌龙茶，不加糖');
    stdout.writeln('MEMORY.md: ${file('MEMORY.md')}');
    await send('把你的签名改成「摸鱼中」');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    stdout.writeln('signature: ${bots.byId(bot.id)!.signature}');
    await send('帮我建一个叫阿猫的 bot，一只爱睡觉的懒猫，头像用 🐱');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    for (final b in bots.bots) {
      stdout.writeln(
        'bot: ${b.name} ${b.avatar} ${b.abilities} '
        '${b.identity.replaceAll('\n', ' / ')}',
      );
    }
    await send('一小时后提醒我站起来活动一下');
    stdout.writeln('LATER.md: ${file('LATER.md')}');
    stdout.writeln(
      'laters: ${bots.laters(bot).map((l) => '${l.at} ${l.note}')}',
    );
    bots.dispose();
    workspace.dispose();
  }, timeout: const Timeout(Duration(minutes: 15)));
}

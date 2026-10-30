// Bots changing their own profiles, with the real Claude Code, without a
// phone: one with the computer's files in its card, a picture by its path
// (taken, cut square); one without, with bot_edit_me. On OpenCode's
// model (see live_model.dart).
//
//   flutter test tool/live/bots_profile_live.dart
import 'dart:convert';
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
  test('live profile', () async {
    final root = await Directory.systemTemp.createTemp('bots-profile');
    final pictures = Directory('${root.path}/pictures')..createSync();
    File('${pictures.path}/cat.png').writeAsBytesSync(
      base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAYAAAB/qH1jAAAAEklEQVR4nGP4z8Dw'
        'HxkzoAsAAA8hD/EEN8afAAAAAElFTkSuQmCC',
      ),
    );
    ClaudeCore.current = () => ClaudeCore.cli;
    final model = await useOpenCode();
    KernelRegistry.use([KernelRegistry.claudeCode]);
    final workspace = Workspace(
      projects: [Project('pictures', pictures.path)],
      kernels: [KernelRegistry.claudeCode],
    );
    final bots = Bots(
      workspace: workspace,
      folders: DataBotFolders(),
      chinese: true,
    );
    await bots.start();
    onModel(bots, model);
    final started = DateTime.now();

    Future<void> talk(Bot bot, String text) async {
      final session = bots.threadFor(bot).session;
      var printed = session.itemCount;
      session.send(ComposerMessage(text: text));
      await Future<void>.delayed(const Duration(seconds: 2));
      while (session.isStreaming) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await Future<void>.delayed(const Duration(seconds: 1));
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
          _ => null,
        };
        if (line != null) {
          stdout.writeln('${at.toStringAsFixed(1)}s ${bot.name} $line');
        }
      }
      final now = bots.byId(bot.id)!;
      stdout.writeln('  -> avatar: ${now.avatar}  signature: ${now.signature}');
    }

    final bao = bots.bots.single;
    await talk(bao, '把你的签名改成「摸鱼中」，头像换成 🐼');
    await talk(bao, '头像换成 pictures 项目里的 cat.png');
    final mia = bots.save(name: 'Mia', identity: '你是我的朋友 Mia', abilities: {});
    await talk(mia, '你签名改成「在发呆」吧，头像换个 🐶');
    bots.dispose();
    workspace.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}

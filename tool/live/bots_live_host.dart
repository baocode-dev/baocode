// A desktop for the phone to pair with and talk to its bots: the real
// Claude Code, in a folder of its own (never the user's data). It writes
// the pairing link there, a line of what happens, and runs two agents to
// watch: one done at once, one at work a while. The phone's integration
// test drives it (mobile's integration_test/bots_live_test.dart).
//
//   flutter test tool/live/bots_live_host.dart \
//     [--dart-define=BAOCODE_LIVE_DIR=/tmp/bots] [--dart-define=LIVE_MINUTES=2]
//
// It writes <dir>/offer.txt (a temporary folder unless set), its log in
// <dir>/live.log, and listens until LIVE_MINUTES have passed.
import 'dart:async';
import 'dart:io';

import 'package:baocode/bots/bot.dart';
import 'package:baocode/bots/bot_folders_io.dart';
import 'package:baocode/bots/bot_prompt.dart';
import 'package:baocode/bots/bots.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/link/link_host.dart';
import 'package:baocode/link/link_platform_io.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live desktop', () async {
    const asked = String.fromEnvironment('BAOCODE_LIVE_DIR');
    final dir = asked.isEmpty
        ? await Directory.systemTemp.createTemp('baocode-live')
        : (Directory(asked)..createSync(recursive: true));
    final log = File('${dir.path}/live.log')..writeAsStringSync('');
    stdout.writeln('live host: logs in ${dir.path}');
    void say(String line) {
      log.writeAsStringSync(
        '${DateTime.now().toIso8601String().substring(11, 19)} $line\n',
        mode: FileMode.append,
      );
    }

    final root = await Directory.systemTemp.createTemp('bots-live');
    final demo = Directory('${root.path}/demo')..createSync();
    File('${demo.path}/README.md')
        .writeAsStringSync('# demo\n\nA tiny project for trying the bots.\n');
    // The real Claude Code, not the scripted one tests run on; the CLI,
    // as main() reads it from the settings.
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
      // The app's own: half an hour.
    );
    await bots.start();
    final assistant = bots.bots.single;
    bots.save(
      id: assistant.id,
      name: assistant.name,
      identity: assistantDefaults(chinese: true).identity,
      abilities: BotAbility.values.toSet(),
      // Any hour: not to wait for the morning.
      proactive: const BotProactive(perDay: 6, quietFrom: 0, quietTo: 0),
    );

    final host = LinkHost(
      workspace: workspace,
      platform: IoLinkPlatform(path: '${root.path}/mobile.json'),
      bots: bots,
    );
    await host.load();
    await host.setPort(47199);
    final offer = (await host.beginPairing())!;
    File('${dir.path}/offer.txt').writeAsStringSync(offer.uri);
    say('offer ${offer.endpoints}');
    host.addListener(() {
      if (host.pending case final pending?) {
        say('pairing ${pending.code}');
        host.approvePending();
      }
    });

    // What the bot says, as it comes: each item once, as it ends up.
    final logged = <String>{};
    final watches = <Timer>[];
    watches.add(
      Timer.periodic(const Duration(seconds: 2), (_) {
        final thread = bots.threadOf(bots.bots.single);
        if (thread == null || !thread.isOpen) return;
        final session = thread.session;
        if (session.isStreaming) return;
        for (var i = 0; i < session.itemCount; i++) {
          final line = switch (session.itemAt(i)) {
            UserMessageItem(:final text) => 'user: $text',
            AssistantTextItem(:final text) => 'bot: $text',
            ToolCallItem(:final tool, :final target, :final kind) =>
              'tool: ${tool ?? kind.name} $target',
            NoticeItem(:final text) => 'notice: $text',
            _ => null,
          };
          if (line != null && logged.add('$i $line')) say(line);
        }
      }),
    );

    // Agents to look after: one done soon, one at work a while.
    final quick = workspace.startAgent(workspace.projects.single);
    quick.session.send(
      const ComposerMessage(text: 'Reply with one word: hello.'),
    );
    final long = workspace.startAgent(workspace.projects.single);
    final permissions = long.session.permissions;
    if (permissions != null) {
      permissions.onSelected(
        permissions.options.firstWhere(
          (o) => o.id == 'bypassPermissions',
          orElse: () => permissions.selected,
        ),
      );
    }
    long.session.send(
      const ComposerMessage(
        text:
            'Run `sleep 590` with the Bash tool (timeout 600000 ms) four '
            'times, one after another, not in the background; then reply '
            'with one word: done.',
      ),
    );
    watches.add(
      Timer.periodic(const Duration(minutes: 1), (_) {
        say(
          'agents: ${[for (final t in workspace.threads) '${t.title}=${t.status.name}'].join(', ')}',
        );
      }),
    );

    const minutes = int.fromEnvironment('LIVE_MINUTES', defaultValue: 4);
    await Future<void>.delayed(const Duration(minutes: minutes));
    for (final watch in watches) {
      watch.cancel();
    }
  }, timeout: const Timeout(Duration(minutes: 240)));
}

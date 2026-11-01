// Runs the real CLI on the model of a settings file of the app's (one it
// wrote for an upstream: BAOCODE_LIVE_SETTINGS), for a person to start.
@Tags(['e2e'])
library;

import 'dart:io';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/review/change_review.dart';
import 'package:baocode/chat/review/review_store_io.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/process_transport.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'e2e_claude_real_test.dart' show tempProject;

void main() {
  final settings = Platform.environment['BAOCODE_LIVE_SETTINGS'];

  test(
    "real Claude Code: each conversation's edits and its subagent's are "
    'its own to undo',
    () async {
      final cwd = await tempProject();
      final checkpoints = p.join(
        (await Directory.systemTemp.createTemp('baocode-e2e-review-')).path,
        'checkpoints',
      );
      String read(String name) => File(p.join(cwd, name)).readAsStringSync();
      File(p.join(cwd, 'b.txt')).writeAsStringSync('alpha\nbeta\ngamma\n');

      late final KernelDescriptor descriptor;
      descriptor = KernelDescriptor(
        id: 'claude-code',
        label: 'Claude Code',
        icon: Icons.abc,
        description: '',
        create: (context) => ClaudeCodeKernel(
          descriptor,
          context,
          start: (launch) =>
              startClaudeProcess(launch.copyWith(settingsPath: settings)),
        ),
      );
      ChatSession conversation() {
        final session = ChatSession(
          kernel: descriptor,
          kernels: [descriptor],
          kernelContext: KernelContext(
            cwd: cwd,
            settings: const {'mode': 'acceptEdits'},
          ),
          historyCount: 0,
          openReview: (root, {session}) async =>
              ChangeReview(BlobReviewStore.open(checkpoints), root: root),
        );
        addTearDown(session.dispose);
        return session..attach();
      }

      Future<void> run(ChatSession session, String text) async {
        session.send(ComposerMessage(text: text));
        final deadline = DateTime.now().add(const Duration(minutes: 4));
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          switch (session.pendingInteraction) {
            case ApprovalRequest():
              session.answer(const ApprovalAnswer(ApprovalDecision.allowOnce));
            case QuestionRequest():
              session.answer(const QuestionAnswer([], skipped: true));
            default:
          }
          if (!session.isStreaming && session.itemCount > 1) break;
        }
        // The review takes in the turn's end.
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      Map<String, (int, int, FileChangeKind)> listed(ChatSession session) => {
        for (final change in session.fileChanges)
          p.relative(change.path, from: cwd): (
            change.added,
            change.removed,
            change.kind,
          ),
      };

      final first = conversation();
      await run(
        first,
        'Do exactly these two steps and nothing else. 1) Use the Write tool '
        "to create a.txt containing the single line 'one'. 2) Then use the "
        'Agent tool with subagent_type general-purpose and ask the subagent '
        "to use the Edit tool to change 'beta' to 'BETA' in b.txt in the "
        "current directory. Then reply 'done'.",
      );
      expect(read('b.txt'), 'alpha\nBETA\ngamma\n');
      expect(listed(first), {
        'a.txt': (1, 0, FileChangeKind.added),
        'b.txt': (1, 1, FileChangeKind.modified),
      });

      final second = conversation();
      await run(
        second,
        "Use the Edit tool to change 'gamma' to 'GAMMA' in b.txt, then "
        "reply 'done'. Do nothing else.",
      );
      expect(read('b.txt'), 'alpha\nBETA\nGAMMA\n');
      expect(listed(second), {'b.txt': (1, 1, FileChangeKind.modified)});
      // The first's is still its own alone.
      expect(listed(first)['b.txt'], (1, 1, FileChangeKind.modified));

      first.undoAllChanges!();
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(File(p.join(cwd, 'a.txt')).existsSync(), isFalse);
      expect(read('b.txt'), 'alpha\nbeta\nGAMMA\n');
      expect(first.fileChanges, isEmpty);
      expect(listed(second), {'b.txt': (1, 1, FileChangeKind.modified)});
    },
    skip: settings == null ? 'BAOCODE_LIVE_SETTINGS is not set' : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

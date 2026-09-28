// Reports what the real CLI did, for a person to read.
// ignore_for_file: avoid_print
@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/kernel/agent_kernel.dart';
import 'package:monad/kernel/claude_code/claude_code_kernel.dart';
import 'package:monad/kernel/claude_code/claude_storage_io.dart';
import 'package:monad/kernel/claude_code/process_transport.dart';
import 'package:monad/kernel/kernel_event.dart';
import 'package:monad/kernel/kernel_types.dart';
import 'package:monad/kernel/mock/mock_kernels.dart';
import 'package:monad/kernel/transcript.dart';

import 'kernel_test.dart' show shown;

/// A new git repository to run in. Removed after the test, pass or fail,
/// with what Claude Code kept of it: its sessions, and task output.
Future<String> tempProject() async {
  final dir = await Directory.systemTemp.createTemp('monad-e2e-');
  final cwd = dir.resolveSymbolicLinksSync();
  await Process.run('git', ['init', '-q'], workingDirectory: cwd);
  final dashed = cwd.replaceAll(RegExp('[^a-zA-Z0-9]'), '-');
  addTearDown(() async {
    final kept = [
      dir,
      Directory('${Platform.environment['HOME']}/.claude/projects/$dashed'),
      for (final entry in Directory('/tmp').listSync())
        if (entry.path.startsWith('/tmp/claude-'))
          Directory('${entry.path}/$dashed'),
    ];
    for (final directory in kept) {
      if (directory.existsSync()) await directory.delete(recursive: true);
    }
  });
  return cwd;
}

void main() {
  test('real Claude Code, end to end', () async {
    final cwd = await tempProject();
    File('$cwd/README.md').writeAsStringSync('# demo\n');
    final kernel = ClaudeCodeKernel(
      MockKernels.claudeCode,
      KernelContext(
        cwd: cwd,
        settings: const {'mode': 'default', 'model': 'haiku'},
      ),
      start: startClaudeProcess,
      readHistory: ClaudeStorage.read,
    );
    final transcript = Transcript();
    final asked = <String>[];
    kernel.events.listen((event) {
      transcript.apply(event);
      if (event is InteractionRequested) {
        final request = event.request;
        asked.add('${request.runtimeType}: ${request.title}');
        scheduleMicrotask(
          () => kernel.answer(request.id, switch (request) {
            QuestionRequest(:final questions) => QuestionAnswer([
              for (final q in questions) [q.options.last.label],
            ]),
            ApprovalRequest() => const ApprovalAnswer(
              ApprovalDecision.allowOnce,
            ),
            PlanReviewRequest() => const PlanAnswer(PlanDecision.approve),
          }),
        );
      }
    });
    kernel.send(
      const KernelTurn(
        id: '22222222-2222-4222-8222-222222222222',
        text:
            'Use the AskUserQuestion tool once to ask whether I prefer red or '
            'blue. Then create the file color.txt containing just my answer. '
            'Then run `cat color.txt` with Bash. Then reply "done".',
      ),
    );
    for (
      var i = 0;
      i < 240 &&
          (transcript.activeTurn != null || transcript.lastTurnEndSeq == 0);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    print('HEALTH ${kernel.health.status} ${kernel.health.message ?? ''}');
    print('ASKED $asked');
    print('ITEMS\n  ${shown(transcript).join('\n  ')}');
    print(
      'MODEL ${kernel.model.selected} of ${kernel.model.options.map((o) => o.id).toList()}',
    );
    print('MODE ${kernel.mode.selected}  EFFORT ${kernel.effort.selected}');
    print('COMMANDS ${kernel.commands.length}');
    print(
      'USAGE ${transcript.usage?.used}/${transcript.usage?.window} ${transcript.usage?.segments.map((s) => '${s.label}:${s.kind.name}').toList()}',
    );
    print(
      'STATS \$${transcript.stats?.costUsd} ${transcript.stats?.limits.map((l) => '${l.label} ${(l.utilization * 100).round()}%').toList()}',
    );
    print(
      'EDITS ${transcript.edits.map((e) => '${e.change.path} +${e.change.added} turn ${e.turnId}').toList()}',
    );
    final files = await kernel.suggestFiles('READ');
    print('FILES ${files.map((f) => f.path).toList()}');
    print('COLOR exists: ${File('$cwd/color.txt').existsSync()}');

    kernel.revertChanges(sinceTurn: '22222222-2222-4222-8222-222222222222');
    await Future<void>.delayed(const Duration(seconds: 3));
    print(
      'AFTER UNDO color exists: ${File('$cwd/color.txt').existsSync()} reverted ${transcript.revertedSeq > 0}',
    );
    kernel.dispose();

    final projects = await const ClaudeStorage().projects();
    final project = projects.firstWhere((p) => p.path == cwd);
    final session = project.sessions.first;
    print(
      'CATALOG ${project.path} ${project.sessions.length} session(s): "${session.title}"',
    );
    final resumed = ClaudeCodeKernel(
      MockKernels.claudeCode,
      KernelContext(resume: session),
      start: startClaudeProcess,
      readHistory: ClaudeStorage.read,
    );
    final replay = Transcript();
    resumed.events.listen(replay.apply);
    await Future<void>.delayed(const Duration(seconds: 2));
    print('REPLAY\n  ${shown(replay).join('\n  ')}');
    expect(shown(replay), shown(transcript));
    expect(asked, hasLength(2));
    resumed.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('real Claude Code: an image, MCP servers, background, suggestions', () async {
    final cwd = await tempProject();
    final kernel = ClaudeCodeKernel(
      MockKernels.claudeCode,
      KernelContext(
        cwd: cwd,
        settings: const {'mode': 'bypassPermissions', 'model': 'haiku'},
      ),
      start: startClaudeProcess,
    );
    final transcript = Transcript();
    kernel.events.listen(transcript.apply);
    Future<void> until(bool Function() done, {int seconds = 120}) async {
      for (var i = 0; i < seconds * 4 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    bool idle() =>
        transcript.activeTurn == null && transcript.lastTurnEndSeq > 0;

    // A 16×16 red square.
    final red = ImageAttachment(
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAF0lEQVR4nGP4z8BAEiJN9a'
        'iGUQ1DSgMAkPn/Afnh+ngAAAAASUVORK5CYII=',
      ),
      mediaType: 'image/png',
    );
    kernel.send(
      KernelTurn(
        id: '33333333-3333-4333-8333-333333333333',
        text: 'What single color is this image? One word.',
        images: [red],
      ),
    );
    await until(idle);
    final answer = shown(transcript).lastWhere((l) => l.startsWith('text:'));
    print('IMAGE ${shown(transcript)}');
    expect(answer.toLowerCase(), contains('red'));
    expect(
      (transcript.itemAt(0) as UserMessageItem).images.single.bytes,
      red.bytes,
    );

    kernel.refreshMcpServers();
    await until(() => kernel.mcpServers != null, seconds: 20);
    print(
      'MCP ${kernel.mcpServers?.map((s) => '${s.name}: ${s.status.name} '
          '${s.tools.length} tools').toList()}',
    );
    expect(kernel.mcpServers, isNotNull);

    final ended = transcript.lastTurnEndSeq;
    final started = DateTime.now();
    kernel.send(
      const KernelTurn(
        id: '44444444-4444-4444-8444-444444444444',
        text:
            'Run exactly this bash command in the foreground, not in the '
            'background: sleep 25 && echo fg-done. Then reply "ok".',
      ),
    );
    KernelTask? foreground() => transcript.tasks
        .where((t) => !t.background && t.toolUseId != null)
        .firstOrNull;
    await until(() => foreground() != null, seconds: 60);
    final task = foreground();
    print('FOREGROUND $task ${task?.toolUseId}');
    expect(task, isNotNull);
    kernel.moveToBackground(task!.toolUseId!);
    await until(() => transcript.lastTurnEndSeq > ended);
    final took = DateTime.now().difference(started);
    // The turn goes on at once; the model may still choose to wait.
    print('BACKGROUNDED turn took ${took.inSeconds}s: ${shown(transcript)}');
    expect(
      shown(transcript),
      contains('terminal: sleep 25 && echo fg-done (background)'),
    );
    expect(
      transcript.tasks.firstWhere((t) => t.id == task.id).background,
      isTrue,
    );

    await until(() => kernel.promptSuggestion != null, seconds: 30);
    print('SUGGESTION ${kernel.promptSuggestion}');
    kernel.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));
}

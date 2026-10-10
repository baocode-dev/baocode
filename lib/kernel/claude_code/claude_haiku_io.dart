import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/launch_environment.dart';
import '../../network/network_proxy_io.dart';
import 'claude_environment.dart';
import 'claude_haiku.dart';
import 'claude_settings_file.dart';
import 'cli_locator.dart';

/// `claude -p --model haiku`: the prompt on stdin, one JSON result on
/// stdout. No tools, MCP servers or slash commands, and no session kept;
/// run outside the project so that its CLAUDE.md is not read.
///
/// On a provider: [model] of it, [env] its environment, given as flag
/// settings in a file (it holds the key), as a session's are.
Future<String> askClaudeHaiku(
  String system,
  String prompt, {
  Future<void>? cancel,
  String? model,
  Map<String, String>? env,
}) async {
  final stdout = StringBuffer();
  final (stderr, code) = await _run(
    system,
    prompt,
    cancel: cancel,
    model: model,
    env: env,
    stream: false,
    onLine: stdout.writeln,
  );
  return claudeHaikuAnswer(stdout.toString(), stderr, code);
}

/// As [askClaudeHaiku], its answer streamed and timed.
Future<ClaudeTimedAnswer> timeClaudeAnswer(
  String system,
  String prompt, {
  Future<void>? cancel,
  String? model,
  Map<String, String>? env,
}) async {
  final timer = ClaudeAnswerTimer();
  final clock = Stopwatch();
  final (stderr, code) = await _run(
    system,
    prompt,
    cancel: cancel,
    model: model,
    env: env,
    stream: true,
    onStart: clock.start,
    onLine: (line) => timer.add(line, clock.elapsed),
  );
  return timer.answer(stderr, code);
}

/// Runs Claude Code, giving each line it prints to [onLine]: what it
/// wrote to stderr and exited with.
Future<(String, int)> _run(
  String system,
  String prompt, {
  required Future<void>? cancel,
  required String? model,
  required Map<String, String>? env,
  required bool stream,
  required void Function(String line) onLine,
  void Function()? onStart,
}) async {
  final cli = await CliLocator.locate();
  final settingsFile = env == null
      ? null
      : await ClaudeSettingsFile.write({'env': env});
  final proxy = await NetworkProxy.instance.environment();
  final Process process;
  try {
    process = await Process.start(
      cli.executable,
      claudeHaikuArguments(
        system,
        model: model,
        settingsFile: settingsFile,
        stream: stream,
      ),
      workingDirectory: Directory.systemTemp.path,
      environment: {
        ...cli.environment,
        ...proxy,
        if (env != null)
          for (final name in ClaudeModelVariables.inherited) name: '',
        ...ClaudeEnvironment.stateDirectory(cli.environment),
      },
      includeParentEnvironment: Platform.isWindows,
      runInShell: cli.throughShell,
    );
  } on ProcessException catch (error) {
    if (settingsFile != null) await ClaudeSettingsFile.delete(settingsFile);
    throw ClaudeHaikuException('Claude Code could not start: ${error.message}');
  }
  onStart?.call();
  if (settingsFile != null) {
    unawaited(
      process.exitCode.then((_) => ClaudeSettingsFile.delete(settingsFile)),
    );
  }
  var cancelled = false;
  unawaited(
    cancel?.then((_) {
      cancelled = true;
      process.kill();
    }),
  );
  final stdout = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach(onLine);
  final stderr = process.stderr.transform(utf8.decoder).join();
  process.stdin.add(utf8.encode(prompt));
  unawaited(process.stdin.close().catchError((Object _) {}));
  final code = await process.exitCode.timeout(
    const Duration(minutes: 2),
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      throw const ClaudeHaikuException('Claude Code took too long to answer.');
    },
  );
  if (cancelled) throw const ClaudeHaikuCancelled();
  await stdout;
  return (await stderr, code);
}

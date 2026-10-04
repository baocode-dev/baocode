import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/launch_environment.dart';
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
  final cli = await CliLocator.locate();
  final settingsFile = env == null
      ? null
      : await ClaudeSettingsFile.write({'env': env});
  final Process process;
  try {
    process = await Process.start(
      cli.executable,
      claudeHaikuArguments(system, model: model, settingsFile: settingsFile),
      workingDirectory: Directory.systemTemp.path,
      environment: {
        ...cli.environment,
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
  final stdout = process.stdout.transform(utf8.decoder).join();
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
  return claudeHaikuAnswer(await stdout, await stderr, code);
}
